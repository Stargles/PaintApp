import CoreGraphics
import Foundation
import UIKit

/// Source pixels have one budget, including versions retained by undo or an asynchronous reader.
/// Derived composites keep their existing compositor/cache budgets.
final class RasterResidency {
    // Includes both source buffers and the workspace needed to checkpoint dirty versions.
    static let shared = RasterResidency(budgetBytes: CompositorBudget.textureBudgetBytes(
        physicalMemory: ProcessInfo.processInfo.physicalMemory) * 2)

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
    private let hasHeadroom: (Int) -> Bool
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
         hasHeadroom: @escaping (Int) -> Bool = CompositorBudget.hasHeadroom(for:)) {
        self.budgetBytes = max(0, budgetBytes)
        self.storage = storage
        self.hasHeadroom = hasHeadroom
    }

    var usage: Usage {
        lock.lock(); defer { lock.unlock() }
        return Usage(pixelBytes: pixelBytes, workingBytes: workingBytes,
                     pixelBufferCount: pixelBufferCount, highWaterBytes: highWaterBytes,
                     allocations: allocations, evictions: evictions,
                     reservedCheckpointBytes: reservedCheckpointBytes)
    }

    private var reservedCheckpointBytes: Int {
        max(0, (dirtyAllocations.values.max() ?? 0) - checkpointWorkingBytes)
    }

    func register(_ candidate: any RasterResidencyCandidate) {
        lock.lock(); defer { lock.unlock() }
        clock &+= 1
        candidates[candidate.residencyID] = Candidate(value: candidate, touched: clock)
    }

    func touch(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        clock &+= 1
        candidates[id]?.touched = clock
    }

    /// Admission precedes I/O/allocation and precedes a texture's mutation lock. Eviction callbacks
    /// run without this owner's lock and must decline rather than wait for a busy texture.
    func admitPixels(_ bytes: Int, excluding: Set<UUID> = []) -> Result<Allocation, Failure> {
        admit(bytes, kind: .pixels, excluding: excluding)
    }

    func admitWorking(_ bytes: Int, excluding: Set<UUID> = []) -> Result<Allocation, Failure> {
        admit(bytes, kind: .working, excluding: excluding)
    }

    func admitCheckpointWorking(_ bytes: Int, excluding: Set<UUID> = []) -> Result<Allocation, Failure> {
        admit(bytes, kind: .checkpoint, excluding: excluding)
    }

    private func admit(_ bytes: Int, kind: Allocation.Kind, excluding: Set<UUID>) -> Result<Allocation, Failure> {
        guard bytes >= 0 else { return .failure(.invalidSize) }
        guard bytes <= budgetBytes else { return .failure(.budgetExceeded) }
        let (checkpointBytes, checkpointOverflow) = bytes.multipliedReportingOverflow(by: 2)
        guard kind != .pixels || !checkpointOverflow else { return .failure(.invalidSize) }
        guard hasHeadroom(bytes) else { return .failure(.allocationRefused) }
        var attempted = excluding
        while true {
            lock.lock()
            let dirtyNeed = max(dirtyAllocations.values.max() ?? 0, kind == .pixels ? checkpointBytes : 0)
            let fitsActualBytes = bytes <= budgetBytes - pixelBytes - workingBytes
            let checkpointWorking = fitsActualBytes && kind == .checkpoint ? checkpointWorkingBytes + bytes : checkpointWorkingBytes
            let reserve = max(0, dirtyNeed - checkpointWorking)
            if fitsActualBytes && bytes <= budgetBytes - pixelBytes - workingBytes - reserve {
                let allocation = Allocation(owner: self, kind: kind, byteCount: bytes)
                switch kind {
                case .pixels:
                    pixelBytes += bytes; pixelBufferCount += 1; allocations += 1
                    dirtyAllocations[allocation.id] = checkpointBytes
                case .working: workingBytes += bytes
                case .checkpoint: workingBytes += bytes; checkpointWorkingBytes += bytes
                }
                highWaterBytes = max(highWaterBytes, pixelBytes + workingBytes)
                lock.unlock()
                return .success(allocation)
            }
            candidates = candidates.filter { $0.value.value != nil }
            let next = candidates.filter { !attempted.contains($0.key) }
                .min { $0.value.touched < $1.value.touched }
                .flatMap { entry in entry.value.value.map { (entry.key, $0) } }
            lock.unlock()
            guard let (id, candidate) = next else { return .failure(.budgetExceeded) }
            attempted.insert(id)
            if candidate.releaseResidentPixels() {
                lock.lock(); evictions += 1; lock.unlock()
            }
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
        let (checkpointBytes, overflow) = allocation.byteCount.multipliedReportingOverflow(by: 2)
        guard !overflow else { return .failure(.invalidSize) }
        var attempted = excluding
        while true {
            lock.lock()
            if dirtyAllocations[allocation.id] != nil { lock.unlock(); return .success(()) }
            let need = max(dirtyAllocations.values.max() ?? 0, checkpointBytes)
            if max(0, need - checkpointWorkingBytes) <= budgetBytes - pixelBytes - workingBytes {
                dirtyAllocations[allocation.id] = checkpointBytes
                lock.unlock()
                return .success(())
            }
            let next = candidates.filter { !attempted.contains($0.key) }
                .min { $0.value.touched < $1.value.touched }
                .flatMap { entry in entry.value.value.map { (entry.key, $0) } }
            lock.unlock()
            guard let (id, candidate) = next else { return .failure(.budgetExceeded) }
            attempted.insert(id)
            if candidate.releaseResidentPixels() { lock.lock(); evictions += 1; lock.unlock() }
        }
    }

    private func release(_ bytes: Int, kind: Allocation.Kind, id: UUID) {
        lock.lock(); defer { lock.unlock() }
        switch kind {
        case .pixels: pixelBytes -= bytes; pixelBufferCount -= 1; dirtyAllocations[id] = nil
        case .working: workingBytes -= bytes
        case .checkpoint: workingBytes -= bytes; checkpointWorkingBytes -= bytes
        }
        precondition(pixelBytes >= 0 && workingBytes >= 0 && pixelBufferCount >= 0)
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
final class RasterSurface {
    private final class Buffer {
        let allocation: RasterResidency.Allocation
        let address: UnsafeMutableRawPointer
        private let lock = NSLock()
        private var readers = 0

        init?(allocation: RasterResidency.Allocation) {
            guard allocation.byteCount > 0, let address = calloc(1, allocation.byteCount) else { return nil }
            self.allocation = allocation
            self.address = address
        }

        var readProviderCount: Int {
            lock.lock(); defer { lock.unlock() }
            return readers
        }

        func beginReading() { lock.lock(); readers += 1; lock.unlock() }
        func endReading() { lock.lock(); readers -= 1; precondition(readers >= 0); lock.unlock() }
        deinit { free(address) }
    }

    /// The data-provider release callback owns this, rather than a UIImage wrapper. CGImage aliases
    /// and CALayer.contents therefore keep both the pixels and their budget charge alive.
    private final class Reader {
        let buffer: Buffer
        init(_ buffer: Buffer) { self.buffer = buffer; buffer.beginReading() }
        deinit { buffer.endReading() }
    }

    let width: Int
    let height: Int
    let bytesPerRow: Int
    let residency: RasterResidency
    private let buffer: Buffer
    /// Mutate only after preparedForWrite succeeds, with the texture's own lock held. A read provider
    /// can escape the texture, so directly writing this context without that admission is forbidden.
    private let context: CGContext

    var byteCount: Int { buffer.allocation.byteCount }
    var allocation: RasterResidency.Allocation { buffer.allocation }
    var readProviderCount: Int { buffer.readProviderCount }

    private init(width: Int, height: Int, bytesPerRow: Int, residency: RasterResidency,
                 buffer: Buffer, context: CGContext) {
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
            guard let buffer = Buffer(allocation: allocation) else { return .failure(.allocationRefused) }
            let retained = Unmanaged.passRetained(buffer)
            guard let context = CGContext(data: buffer.address, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                    releaseCallback: { info, _ in
                        if let info { Unmanaged<Buffer>.fromOpaque(info).release() }
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

    /// Explicit COW: old providers continue reading the old charged buffer. No write occurs until
    /// admission and allocation both succeed, so a refusal preserves the complete previous version.
    func preparedForWrite(excluding: Set<UUID> = []) -> Result<RasterSurface, RasterResidency.Failure> {
        guard readProviderCount > 0 else {
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
        guard readProviderCount == 0 else { return .failure(.writeRequiresCopy) }
        guard buffer.allocation.isDirty else { return .failure(.writeNotAdmitted) }
        return .success(body(context))
    }

    func image() -> Result<UIImage, RasterResidency.Failure> {
        let reader = Unmanaged.passRetained(Reader(buffer))
        guard let provider = CGDataProvider(dataInfo: reader.toOpaque(), data: buffer.address,
                size: byteCount, releaseData: { info, _, _ in
                    if let info { Unmanaged<Reader>.fromOpaque(info).release() }
                }) else {
            reader.release()
            return .failure(.allocationRefused)
        }
        guard let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow, space: PixelOps.deviceRGBColorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return .failure(.allocationRefused)
        }
        return .success(UIImage(cgImage: image, scale: 1, orientation: .up))
    }
}
