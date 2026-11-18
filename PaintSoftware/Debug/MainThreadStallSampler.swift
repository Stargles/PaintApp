import Darwin
import Foundation
import QuartzCore

/// **Names the main-thread time no span names: while one run-loop pass runs long, a watcher thread
/// takes the main thread's call stack every few milliseconds, and the pass is reported with the code
/// those stacks were in.**
///
/// ## Why this exists
///
/// The owner's recording of 2026-11-17 showed run-loop passes of 113–796 ms with every named span
/// under 33 ms: the whole of each stall was `sourcePhase`, which says *when* the main thread was busy
/// and nothing about *what with*. A span names only code someone thought to wrap, and the costs that
/// keep reaching the owner's iPad are exactly the ones nobody thought to wrap — work inside UIKit's
/// update cycle, Core Animation's commit (which since iOS 26 runs inside the update-cycle *source*,
/// not at the `beforeWaiting` observer `PlaybackTrace.caCommit` brackets), a touch handler's inner
/// loop. A stack does not need anyone to have guessed.
///
/// ## How
///
/// `PlaybackTrace`'s run-loop observers tell this class when a pass begins and ends. A thread of its
/// own wakes every `interval`; once the current pass is older than `samplingFloor` it suspends the
/// main thread, reads its registers, walks the frame-pointer chain into a preallocated buffer, and
/// resumes it — nothing allocates while the main thread is stopped, because the main thread may be
/// holding the allocator's lock. A pass that ends at or over `reportFloor` is symbolicated (on this
/// thread, after the fact) and queued for `ActionRecorder` to write as one `mainStall` line.
///
/// ## Cost
///
/// Nothing until `PlaybackTrace` is armed. Armed, one thread wake every 10 ms that reads a lock-held
/// timestamp; a stack walk only inside a pass already past 40 ms — a pass the artist already felt.
final class MainThreadStallSampler: @unchecked Sendable {

    static let shared = MainThreadStallSampler()

    /// How often the watcher looks, and so how many stacks a stall of a given length gets.
    nonisolated(unsafe) static var interval: TimeInterval = 0.010
    /// A pass older than this starts being sampled. Below a 60 Hz frame and a half nothing is wanted.
    nonisolated(unsafe) static var samplingFloor: CFTimeInterval = 0.040
    /// A pass at least this long is reported.
    nonisolated(unsafe) static var reportFloor: CFTimeInterval = 0.080
    /// Stacks kept per pass — two seconds at the device `interval`; a longer stall keeps its first ones.
    static let maxSamplesPerPass = 200
    static let maxDepth = 96
    /// Reports kept between drains, so a recorder that never drains cannot grow this.
    static let maxPendingStalls = 64

    /// One long pass, as the recorder writes it.
    struct Stall {
        let start: CFTimeInterval
        let ms: Double
        let cpuMs: Double
        let samples: Int
        /// The innermost frame of this app's own code in each stack, counted, most frequent first —
        /// the line that says whose code it was.
        let appFrames: [(frame: String, count: Int)]
        /// The innermost frame of each stack, whatever library it is in, counted.
        let leafFrames: [(frame: String, count: Int)]
        /// The commonest stack, innermost first, with the run loop's own frames dropped.
        let stack: [String]
    }

    private let lock = NSLock()
    // Guarded by `lock`.
    private var passStart: CFTimeInterval = 0
    private var pending: [Stall] = []
    private var running = false
    /// Bumped by every `start`, so a watcher left over from an earlier start exits instead of
    /// sharing the stack buffer with the new one.
    private var generation = 0
    /// Long passes that ended, waiting for the watcher to symbolicate them.
    private var ended: [(start: CFTimeInterval, end: CFTimeInterval, cpu: Double)] = []

    // Owned by the watcher thread.
    private var buffer = UnsafeMutablePointer<UInt>.allocate(capacity: maxSamplesPerPass * maxDepth)
    private var depths = [Int](repeating: 0, count: maxSamplesPerPass)
    private var sampleCount = 0
    private var sampledPassStart: CFTimeInterval = 0

    private var mainPort: thread_act_t = 0
    private static let armThreadState64: thread_state_flavor_t = 6
    private static let stateWords = 34
    private let registers = UnsafeMutablePointer<natural_t>.allocate(capacity: stateWords * 2)
    private var stackLow: UInt = 0
    private var stackHigh: UInt = 0
    private var watcher: Thread?

    // MARK: - Lifecycle

    /// Called on the main thread by `PlaybackTrace.start()`.
    func start() {
        precondition(Thread.isMainThread)
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        running = true
        generation += 1
        passStart = 0
        if mainPort == 0 {
            mainPort = mach_thread_self()
            let main = pthread_self()
            stackHigh = UInt(bitPattern: pthread_get_stackaddr_np(main))
            stackLow = stackHigh - UInt(pthread_get_stacksize_np(main))
        }
        let mine = generation
        let thread = Thread { [weak self] in self?.watch(generation: mine) }
        thread.name = "MainThreadStallSampler"
        thread.qualityOfService = .userInteractive
        watcher = thread
        thread.start()
    }

    func stop() {
        lock.lock()
        running = false
        passStart = 0
        lock.unlock()
        watcher = nil
    }

    // MARK: - The pass, as `PlaybackTrace`'s observers see it

    func passBegan(at time: CFTimeInterval) {
        lock.lock()
        passStart = time
        lock.unlock()
    }

    /// `cpu` is the main thread's own CPU seconds across the pass, from the same `thread_info` read
    /// `PlaybackTrace.mainBusy` carries — so a stall can say whether it was work or waiting.
    func passEnded(at time: CFTimeInterval, cpu: Double) {
        lock.lock()
        let start = passStart
        passStart = 0
        lock.unlock()
        guard start > 0, time - start >= Self.reportFloor else { return }
        // The watcher owns the stacks; it finalizes the report on its own thread, so the main thread
        // pays two stores here and nothing else.
        lock.lock()
        ended.append((start, time, cpu))
        lock.unlock()
    }

    /// Every report since the last drain, oldest first.
    func drain() -> [Stall] {
        lock.lock()
        defer { lock.unlock() }
        let out = pending
        pending.removeAll(keepingCapacity: true)
        return out
    }

    // MARK: - The watcher

    private func watch(generation mine: Int) {
        while true {
            lock.lock()
            let alive = running && generation == mine
            let start = passStart
            let finished = ended
            ended.removeAll()
            lock.unlock()
            guard alive else { return }
            for done in finished { report(start: done.start, end: done.end, cpu: done.cpu) }

            if start > 0, CACurrentMediaTime() - start >= Self.samplingFloor {
                if sampledPassStart != start {
                    sampledPassStart = start
                    sampleCount = 0
                }
                if sampleCount < Self.maxSamplesPerPass { sampleMain() }
            }
            Thread.sleep(forTimeInterval: Self.interval)
        }
    }

    /// One stack of the main thread into `buffer`'s next row. **Allocates nothing between the
    /// suspend and the resume.**
    private func sampleMain() {
        let row = buffer + sampleCount * Self.maxDepth
        guard thread_suspend(mainPort) == KERN_SUCCESS else { return }
        // `arm_thread_state64_t` does not import into Swift, so its layout is spelled here: 29
        // general registers, then fp, lr, sp, pc as 64-bit words, then cpsr and padding — 68
        // `natural_t`s, which is `ARM_THREAD_STATE64_COUNT`. Flavor 6 is `ARM_THREAD_STATE64`.
        var count = mach_msg_type_number_t(Self.stateWords * 2)
        let result = thread_get_state(mainPort, Self.armThreadState64, registers, &count)
        var depth = 0
        if result == KERN_SUCCESS {
            let words = UnsafeRawPointer(registers).assumingMemoryBound(to: UInt64.self)
            row[depth] = Self.strip(UInt(words[32])); depth += 1
            row[depth] = Self.strip(UInt(words[30])); depth += 1
            var fp = UInt(words[29])
            while depth < Self.maxDepth, fp >= stackLow, fp + 16 <= stackHigh, fp & 0xF == 0 {
                let frame = UnsafePointer<UInt>(bitPattern: fp)!
                let next = frame[0]
                let ret = Self.strip(frame[1])
                guard ret != 0 else { break }
                row[depth] = ret; depth += 1
                guard next > fp else { break }
                fp = next
            }
        }
        thread_resume(mainPort)
        guard depth > 0 else { return }
        depths[sampleCount] = depth
        sampleCount += 1
    }

    /// Return addresses with any pointer-authentication bits cleared.
    private static func strip(_ address: UInt) -> UInt { address & 0x0000_000F_FFFF_FFFF }

    private func report(start: CFTimeInterval, end: CFTimeInterval, cpu: Double) {
        let taken = sampledPassStart == start ? sampleCount : 0
        if sampledPassStart == start { sampledPassStart = 0; sampleCount = 0 }
        var symbols: [UInt: Frame] = [:]
        func frame(_ address: UInt, isReturn: Bool) -> Frame {
            if let known = symbols[address] { return known }
            let made = Frame(address: isReturn ? address &- 1 : address)
            symbols[address] = made
            return made
        }
        var appCounts: [String: Int] = [:], leafCounts: [String: Int] = [:], stackCounts: [[String]: Int] = [:]
        for index in 0..<taken {
            let row = buffer + index * Self.maxDepth
            var names: [String] = []
            var innermostApp: String?
            for level in 0..<depths[index] where row[level] >= 0x1000 {
                let f = frame(row[level], isReturn: level > 0)
                if innermostApp == nil, f.isApp { innermostApp = f.name }
                if !Self.boilerplate.contains(where: { f.name.hasPrefix($0) }) { names.append(f.name) }
            }
            if let first = names.first { leafCounts[first, default: 0] += 1 }
            appCounts[innermostApp ?? "(no app frame)", default: 0] += 1
            stackCounts[Array(names.prefix(24)), default: 0] += 1
        }
        func ranked(_ counts: [String: Int]) -> [(frame: String, count: Int)] {
            counts.sorted { $0.value > $1.value }.prefix(5).map { (frame: $0.key, count: $0.value) }
        }
        let stall = Stall(start: start, ms: (end - start) * 1000, cpuMs: cpu * 1000, samples: taken,
                          appFrames: ranked(appCounts), leafFrames: ranked(leafCounts),
                          stack: stackCounts.max { $0.value < $1.value }?.key ?? [])
        lock.lock()
        if pending.count < Self.maxPendingStalls { pending.append(stall) }
        lock.unlock()
    }

    /// Frames every main-thread stack shares, which say nothing about whose work it was.
    private static let boilerplate = ["start", "main", "UIApplicationMain", "GSEventRunModal", "-[UIApplication _run]",
                                      "_CFRunLoopRun", "__CFRunLoopRun", "static App.main", "runApp",
                                      "closure #1 in KitRendererCommon"]

    /// One symbolicated address: the function's name, demangled and cut at its parameter list, or
    /// `image+offset` when the image carries no symbol for it.
    private struct Frame {
        let name: String
        let isApp: Bool

        init(address: UInt) {
            var info = Dl_info()
            guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0 else {
                name = String(format: "0x%lx", address); isApp = false; return
            }
            let image = info.dli_fname.map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
            isApp = image == Frame.appImage || image == Frame.appImage + ".debug.dylib"
            if let symbol = info.dli_sname {
                name = Frame.readable(String(cString: symbol))
            } else {
                let base = UInt(bitPattern: info.dli_fbase)
                name = "\(image)+0x\(String(address &- base, radix: 16))"
            }
        }

        static let appImage: String = (Bundle.main.executablePath as NSString?)?.lastPathComponent ?? "PaintSoftware"

        static func readable(_ symbol: String) -> String {
            var text = symbol
            if let demangled = demangle(symbol) { text = demangled }
            // `Module.Type.method(label: Type, …) -> Result` → `Type.method`; the argument list is
            // noise in a one-line report and the module prefix is the same on every frame.
            if let paren = text.firstIndex(of: "(") { text = String(text[..<paren]) }
            for prefix in ["PaintSoftware.", "(extension in PaintSoftware):PaintSoftware."] {
                text = text.replacingOccurrences(of: prefix, with: "")
            }
            return text
        }

        private static func demangle(_ symbol: String) -> String? {
            let name = symbol.hasPrefix("_$") ? String(symbol.dropFirst()) : symbol
            guard name.hasPrefix("$s") || name.hasPrefix("$S") else { return nil }
            return name.withCString { pointer -> String? in
                guard let out = _swiftDemangle(pointer, UInt(strlen(pointer)), nil, nil, 0) else { return nil }
                defer { free(out) }
                return String(cString: out)
            }
        }
    }
}

@_silgen_name("swift_demangle")
private func _swiftDemangle(_ mangledName: UnsafePointer<CChar>?, _ mangledNameLength: UInt,
                            _ outputBuffer: UnsafeMutablePointer<CChar>?,
                            _ outputBufferSize: UnsafeMutablePointer<UInt>?,
                            _ flags: UInt32) -> UnsafeMutablePointer<CChar>?
