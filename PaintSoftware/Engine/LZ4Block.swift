import Compression

/// The lossless raw block used by derived frames and process-local source checkpoints.
/// Storage owners supply and charge their own buffers; this value codec retains nothing.
enum LZ4Block {
    static let algorithm = COMPRESSION_LZ4_RAW
    static var encodingScratchBytes: Int { compression_encode_scratch_buffer_size(algorithm) }
    static var decodingScratchBytes: Int { compression_decode_scratch_buffer_size(algorithm) }

    /// Tiny payloads are stored raw: a fixed compressor workspace must not make their existing
    /// checkpoint reservation grow larger than the pixels. Larger blocks use explicit scratch.
    static func compressesWithinCheckpoint(_ count: Int) -> Bool { encodingScratchBytes <= count }
    static func checkpointWorkingBytes(_ count: Int) -> Int? {
        let (total, overflow) = count.multipliedReportingOverflow(by: 2)
        return count >= 0 && !overflow ? total : nil
    }

    static func encode(_ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawBufferPointer,
                       scratch: UnsafeMutableRawPointer? = nil) -> Int {
        guard let source = input.baseAddress, let destination = output.baseAddress else { return 0 }
        return compression_encode_buffer(destination.assumingMemoryBound(to: UInt8.self), output.count,
            source.assumingMemoryBound(to: UInt8.self), input.count, scratch, algorithm)
    }

    static func decode(_ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawBufferPointer,
                       scratch: UnsafeMutableRawPointer? = nil) -> Bool {
        guard let source = input.baseAddress, let destination = output.baseAddress else { return false }
        return compression_decode_buffer(destination.assumingMemoryBound(to: UInt8.self), output.count,
            source.assumingMemoryBound(to: UInt8.self), input.count, scratch, algorithm) == output.count
    }
}
