import CoreGraphics
import Foundation
import UIKit

/// Source pixels have one budget, including versions retained by undo or an asynchronous reader.
/// Derived composites keep their existing compositor/cache budgets.
final class RasterResidency {
    // Includes both source buffers and the workspace needed to checkpoint dirty versions.
    /// **Source pixels may hold up to the one budget** (SCHEDULER.md rule 5, `MemoryBudget`) — no
    /// number of their own — and what they hold is charged there as one `.shown` entry, so every
    /// other admission sees it: this owner already evicts its own candidates least recently used
    /// first, and its checkpoint bookkeeping is what makes an eviction safe, so the one budget counts
    /// it and leaves the choice here. (Its old figure, twice `CompositorBudget`'s, was a sixteenth of
    /// the *Mac's* memory on the simulator — 1.5 GiB — which is the only reason three 5000² rasters
    /// ever fitted in a test.)
    static let shared = RasterResidency(budgetBytes: MemoryBudget.deviceTotalBytes,
                                        charge: MemoryBudget.shared.entry("RasterResidency", priority: .shown) {})

    enum Failure: Error, Equatable {
        case invalidSize
        case budgetExceeded
        case allocationRefused
        case unreadableBacking
        case checkpointFailed
        case checkpointPending
        case writeRequiresCopy
        case writeNotAdmitted
    }

    struct Usage: Equatable {
        let pixelBytes: Int
        let workingBytes: Int
        let pixelBufferCount: Int
        let highWaterBytes: Int
        let allocations: Int
        let evictions: Int
        let reservedCheckpointBytes: Int
        let registeredCandidateCount: Int

        var chargedBytes: Int { pixelBytes + workingBytes }
        var admittedBytes: Int { chargedBytes + reservedCheckpointBytes }
    }

    /// A reservation becomes the allocation's lifetime owner. In particular, a returned CGImage
    /// retains this through its data provider, even after its UIImage and source handle disappear.
    final class Allocation {
        fileprivate enum Kind { case pixels, working, checkpoint }
        fileprivate let id = UUID()
        fileprivate let owner: RasterResidency
        fileprivate let kind: Kind
        let byteCount: Int

        fileprivate init(owner: RasterResidency, kind: Kind, byteCount: Int) {
            self.owner = owner
            self.kind = kind
            self.byteCount = byteCount
        }

        var isDirty: Bool { owner.isDirty(id) }
        func markDurable() { owner.markDurable(id) }
        deinit { owner.release(byteCount, kind: kind, id: id) }
    }

    private struct Candidate {
        weak var value: (any RasterResidencyCandidate)?
        var touched: UInt64
    }

    let budgetBytes: Int
    let storage: ProjectStore.RasterStorage
    private let makeRoom: (Int) -> Bool
    /// What this owner holds, in the one budget — `shared`'s only.
    private let charge: MemoryBudget.Entry?
    private let lock = NSLock()
    private var pixelBytes = 0
    private var workingBytes = 0
    private var checkpointWorkingBytes = 0
    private var dirtyAllocations: [UUID: Int] = [:]
    private var pixelBufferCount = 0
    private var highWaterBytes = 0
    private var allocations = 0
    private var evictions = 0
    private var clock: UInt64 = 0
    private var candidates: [UUID: Candidate] = [:]

    init(budgetBytes: Int, storage: ProjectStore.RasterStorage = ProjectStore.RasterStorage(),
         makeRoom: @escaping (Int) -> Bool = { MemoryBudget.shared.makeRoom(for: $0) },
         charge: MemoryBudget.Entry? = nil) {
        self.charge = charge
        self.budgetBytes = max(0, budgetBytes)
        self.storage = storage
        self.makeRoom = makeRoom
    }

    var usage: Usage {
        lock.lock(); defer { lock.unlock() }
        return Usage(pixelBytes: pixelBytes, workingBytes: workingBytes,
                     pixelBufferCount: pixelBufferCount, highWaterBytes: highWaterBytes,
                     allocations: allocations, evictions: evictions,
                     reservedCheckpointBytes: reservedCheckpointBytes,
                     registeredCandidateCount: candidates.count)
    }

    private var reservedCheckpointBytes: Int {
        max(0, (dirtyAllocations.values.max() ?? 0) - checkpointWorkingBytes)
    }

    func register(_ candidate: any RasterResidencyCandidate) {
        lock.lock(); defer { lock.unlock() }
        clock &+= 1
        candidates[candidate.residencyID] = Candidate(value: candidate, touched: clock)
    }

    /// A live cold owner stays eligible; only its death retires its weak registration.
    func unregister(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        candidates[id] = nil
    }

    func touch(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        clock &+= 1
        candidates[id]?.touched = clock
    }

    /// Admission precedes I/O/allocation and precedes a texture's mutation lock. Eviction callbacks
    /// run without this owner's lock and must decline rather than wait for a busy texture.
    func admitPixels(_ bytes: Int, durable: Bool = false, excluding: Set<UUID> = []) -> Result<Allocation, Failure> {
        admit(bytes, kind: .pixels, excluding: excluding, durable: durable)
    }

    func admitWorking(_ bytes: Int, excluding: Set<UUID> = []) -> Result<Allocation, Failure> {
        admit(bytes, kind: .working, excluding: excluding)
    }

    func admitCheckpointWorking(_ bytes: Int, excluding: Set<UUID> = []) -> Result<Allocation, Failure> {
        admit(bytes, kind: .checkpoint, excluding: excluding)
    }

    private func admit(_ bytes: Int, kind: Allocation.Kind, excluding: Set<UUID>, durable: Bool = false) -> Result<Allocation, Failure> {
        guard bytes >= 0 else { return .failure(.invalidSize) }
        guard bytes <= budgetBytes else { return .failure(.budgetExceeded) }
        let required = LZ4Block.checkpointWorkingBytes(bytes)
        guard kind != .pixels || required != nil else { return .failure(.invalidSize) }
        let checkpointBytes = durable ? 0 : required ?? 0
        guard makeRoom(bytes) else { return .failure(.allocationRefused) }
        return withEvictionPass(excluding: excluding) {
            let dirtyNeed = max(dirtyAllocations.values.max() ?? 0, kind == .pixels ? checkpointBytes : 0)
            let fitsActualBytes = bytes <= budgetBytes - pixelBytes - workingBytes
            let checkpointWorking = fitsActualBytes && kind == .checkpoint ? checkpointWorkingBytes + bytes : checkpointWorkingBytes
            let reserve = max(0, dirtyNeed - checkpointWorking)
            if fitsActualBytes && bytes <= budgetBytes - pixelBytes - workingBytes - reserve {
                let allocation = Allocation(owner: self, kind: kind, byteCount: bytes)
                switch kind {
                case .pixels:
                    pixelBytes += bytes; pixelBufferCount += 1; allocations += 1
                    if checkpointBytes > 0 { dirtyAllocations[allocation.id] = checkpointBytes }
                case .working: workingBytes += bytes
                case .checkpoint: workingBytes += bytes; checkpointWorkingBytes += bytes
                }
                highWaterBytes = max(highWaterBytes, pixelBytes + workingBytes)
                charge?.update(bytes: pixelBytes + workingBytes)
                return allocation
            }
            return nil
        }
    }

    private func isDirty(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return dirtyAllocations[id] != nil
    }

    private func markDurable(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        dirtyAllocations[id] = nil
    }

    func prepareMutation(of allocation: Allocation, excluding: Set<UUID> = []) -> Result<Void, Failure> {
        guard let checkpointBytes = LZ4Block.checkpointWorkingBytes(allocation.byteCount) else { return .failure(.invalidSize) }
        return withEvictionPass(excluding: excluding) {
            if dirtyAllocations[allocation.id] != nil { return () }
            let need = max(dirtyAllocations.values.max() ?? 0, checkpointBytes)
            if max(0, need - checkpointWorkingBytes) <= budgetBytes - pixelBytes - workingBytes {
                if checkpointBytes > 0 { dirtyAllocations[allocation.id] = checkpointBytes }
                return ()
            }
            return nil
        }
    }

    /// The operation reads/commits accounting under lock; candidate work never holds that lock.
    /// One weak snapshot bounds a pass even when callbacks register sources or refresh recency.
    private func withEvictionPass<Value>(excluding: Set<UUID>, attempt: () -> Value?) -> Result<Value, Failure> {
        lock.lock()
        if let value = attempt() { lock.unlock(); return .success(value) }
        let snapshot = candidates.filter { !excluding.contains($0.key) }
        lock.unlock()
        let ordered = snapshot.sorted { $0.value.touched < $1.value.touched }
        for (id, captured) in ordered {
            lock.lock()
            if let value = attempt() { lock.unlock(); return .success(value) }
            let unchanged = candidates[id]?.touched == captured.touched
            lock.unlock()
            guard unchanged else { continue }
            // Promote and finally release the weak target outside the owner lock: its final
            // provider/allocation release can call back into this owner's accounting.
            let released = autoreleasepool { captured.value?.releaseResidentPixels() }
            lock.lock()
            if let released {
                if released { evictions += 1 }
            } else if candidates[id]?.touched == captured.touched {
                candidates[id] = nil
            }
            lock.unlock()
        }
        lock.lock()
        let value = attempt()
        lock.unlock()
        return value.map { .success($0) } ?? .failure(.budgetExceeded)
    }

    private func release(_ bytes: Int, kind: Allocation.Kind, id: UUID) {
        lock.lock(); defer { lock.unlock() }
        switch kind {
        case .pixels: pixelBytes -= bytes; pixelBufferCount -= 1; dirtyAllocations[id] = nil
        case .working: workingBytes -= bytes
        case .checkpoint: workingBytes -= bytes; checkpointWorkingBytes -= bytes
        }
        precondition(pixelBytes >= 0 && workingBytes >= 0 && pixelBufferCount >= 0)
        charge?.update(bytes: pixelBytes + workingBytes)
    }
}

/// A weak eviction registration cannot keep a cel, document or background snapshot alive.
protocol RasterResidencyCandidate: AnyObject {
    var residencyID: UUID { get }
    /// Give back eligible resident pixels, preserving an immutable backing first if needed.
    /// A busy source declines immediately. A failed checkpoint must retain its original pixels.
    func releaseResidentPixels() -> Bool
}

/// A native RGBA8 buffer whose charge lasts as long as any CGContext or CGImage can read its bytes.
/// A provider reads this allocation directly; retained source images never use makeImage's hidden COW.
nonisolated final class RasterSurface {
    typealias ReadLease = RasterPixelBuffer.ReadLease

    let width: Int
    let height: Int
    let bytesPerRow: Int
    let residency: RasterResidency
    private let buffer: RasterPixelBuffer
    /// Mutate only after preparedForWrite succeeds, with the texture's own lock held. A read provider
    /// can escape the texture, so directly writing this context without that admission is forbidden.
    private let context: CGContext

    var byteCount: Int { buffer.allocation.byteCount }
    var allocation: RasterResidency.Allocation { buffer.allocation }
    var readLeaseCount: Int { buffer.readLeaseCount }

    /// Exact blank proof for private storage or an immutable lease. No downsampling can discard
    /// a single painted pixel; normal nonblank pictures return at their first nonzero alpha.
    var isFullyTransparent: Bool { buffer.isFullyTransparent(.rgba8(width: width, height: height)) }

    private init(width: Int, height: Int, bytesPerRow: Int, residency: RasterResidency,
                 buffer: RasterPixelBuffer, context: CGContext) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.residency = residency
        self.buffer = buffer
        self.context = context
    }

    static func byteCount(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let (row, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (bytes, bytesOverflow) = row.multipliedReportingOverflow(by: height)
        return rowOverflow || bytesOverflow ? nil : bytes
    }

    static func allocate(width: Int, height: Int, using residency: RasterResidency,
                         excluding: Set<UUID> = []) -> Result<RasterSurface, RasterResidency.Failure> {
        guard let bytes = byteCount(width: width, height: height) else { return .failure(.invalidSize) }
        return residency.admitPixels(bytes, excluding: excluding).flatMap { allocation in
            guard let buffer = RasterPixelBuffer(allocation: allocation) else { return .failure(.allocationRefused) }
            let retained = Unmanaged.passRetained(buffer)
            guard let context = CGContext(data: buffer.address, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                    releaseCallback: { info, _ in
                        if let info { Unmanaged<RasterPixelBuffer>.fromOpaque(info).release() }
                    }, releaseInfo: retained.toOpaque()) else {
                retained.release()
                return .failure(.allocationRefused)
            }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            return .success(RasterSurface(width: width, height: height, bytesPerRow: width * 4,
                                          residency: residency, buffer: buffer, context: context))
        }
    }

    static func render(size: CGSize, using residency: RasterResidency,
                       drawing: (CGContext) -> Bool) -> Result<RasterSurface, RasterResidency.Failure> {
        guard let width = Int(exactly: size.width.rounded()), let height = Int(exactly: size.height.rounded()) else {
            return .failure(.invalidSize)
        }
        return allocate(width: width, height: height, using: residency).flatMap { surface in
            surface.mutate { context in
                UIGraphicsPushContext(context)
                defer { UIGraphicsPopContext() }
                return drawing(context)
            }.flatMap { $0 ? .success(surface) : .failure(.unreadableBacking) }
        }
    }

    /// Explicit COW: old providers continue reading the old charged buffer. No write occurs until
    /// admission and allocation both succeed, so a refusal preserves the complete previous version.
    func preparedForWrite(excluding: Set<UUID> = []) -> Result<RasterSurface, RasterResidency.Failure> {
        guard readLeaseCount > 0 else {
            return residency.prepareMutation(of: buffer.allocation, excluding: excluding).map { self }
        }
        return Self.allocate(width: width, height: height, using: residency, excluding: excluding).map { copy in
            memcpy(copy.buffer.address, buffer.address, byteCount)
            return copy
        }
    }

    /// The surface cannot be written while an image provider can still read it. Callers first
    /// replace it with preparedForWrite's admitted result, then enter here under their own lock.
    func mutate<T>(_ body: (CGContext) -> T) -> Result<T, RasterResidency.Failure> {
        guard readLeaseCount == 0 else { return .failure(.writeRequiresCopy) }
        guard buffer.allocation.isDirty else { return .failure(.writeNotAdmitted) }
        return .success(body(context))
    }

    func readLease() -> ReadLease { ReadLease(buffer: buffer, descriptor: .rgba8(width: width, height: height), residency: residency) }
    func image() -> Result<UIImage, RasterResidency.Failure> { readLease().image() }

    /// Warpers already produce normalized RGBA8 bytes. Install them directly into admitted native
    /// storage rather than creating an unowned CGImage whose array could escape its working charge.
    func replacePixels(with bytes: [UInt8]) -> Result<Void, RasterResidency.Failure> {
        guard bytes.count == byteCount else { return .failure(.invalidSize) }
        return mutate { _ in
            bytes.withUnsafeBytes { input in
                buffer.address.copyMemory(from: input.baseAddress!, byteCount: byteCount)
            }
        }
    }
}
