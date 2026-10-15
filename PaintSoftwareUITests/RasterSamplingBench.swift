import XCTest
import UIKit

/// Opt-in native Release measurement, including source normalization, upload, readback and tile
/// handoff. TEST_RUNNER_PAINTAPP_RASTER_SAMPLING_COST=1. Footprint includes the runner and driver;
/// the sampler's byte charge and pixel counts are reported separately. No time-based assertion.
final class RasterSamplingBench: XCTestCase {
    func testWindowAndWholeFrameCostAndOneHundredWindowRetentions() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_RASTER_SAMPLING_COST"] == "1")
        let size = CGSize(width: 2048, height: 1024)
        let source = try XCTUnwrap(makeSource(size: size))
        let transform = CGAffineTransform(translationX: 1024, y: 512).rotated(by: 0.22)
            .scaledBy(x: 0.73, y: 0.73).translatedBy(x: -1024, y: -512)
        let matrix = try XCTUnwrap(Homography(transform).inverse)
        var check: UInt64 = 0
        func draw(_ output: CGRect) -> (Int, Int, Int) {
            var tiles = 0, requestedPixels = 0, peakBytes = 0
            var success = false
            let rendered = UIGraphicsImageRenderer(size: output.size, format: PixelOps.transparentFormat()).image { context in
                context.cgContext.translateBy(x: -output.minX, y: -output.minY)
                success = ImageWarp.drawRaster(sourceSize: size, destination: output, inverseTexelMap: matrix,
                source: { rect in
                    requestedPixels += Int(rect.width*rect.height)
                    return source.cropping(to: rect)
                }, consume: { image, rect in
                    tiles += 1
                    peakBytes = max(peakBytes, ImageWarp.RasterPlan(sourceSize: size, destination: rect, inverseTexelMap: matrix)!.workingBytes)
                    UIImage(cgImage: image).draw(in: rect)
                })
            }
            check &+= UInt64(rendered.cgImage!.width*rendered.cgImage!.height)
            XCTAssertTrue(success)
            return (tiles, requestedPixels, peakBytes)
        }
        let window = CGRect(x: 768, y: 256, width: 512, height: 512)
        for output in [window, CGRect(origin: .zero, size: size)] {
            for take in 0..<5 {
                autoreleasepool {
                    let start = CACurrentMediaTime(), counts = draw(output)
                    print("RASTER_SAMPLER take=\(take) output=\(output) ms=\((CACurrentMediaTime()-start)*1000) tiles=\(counts.0) sourcePixels=\(counts.1) peakCountedBytes=\(counts.2)")
                }
            }
        }
        let before = footprint()
        var peak = before
        for index in 1...100 {
            autoreleasepool { _ = draw(window); peak = max(peak, footprint()) }
            if index % 10 == 0 { print("RASTER_RETENTION draw=\(index) footprint=\(footprint()) peak=\(peak)") }
        }
        print("RASTER_RETENTION baseline=\(before) final=\(footprint()) peak=\(peak) check=\(check)")
        // Current high's full-source raster transform is the appearance/cost baseline only. It is
        // measured after retention so its process-global resampling cache cannot contaminate that.
        for output in [window, CGRect(origin: .zero, size: size)] {
            for take in 0..<5 { autoreleasepool {
                let start = CACurrentMediaTime()
                let image = UIGraphicsImageRenderer(size: output.size, format: PixelOps.transparentFormat()).image { context in
                    context.cgContext.translateBy(x: -output.minX, y: -output.minY)
                    context.cgContext.concatenate(transform)
                    context.cgContext.interpolationQuality = .high
                    UIImage(cgImage: source).draw(in: CGRect(origin: .zero, size: size))
                }
                check &+= UInt64(image.cgImage!.width)
                print("RASTER_HIGH_BASELINE take=\(take) output=\(output) ms=\((CACurrentMediaTime()-start)*1000) check=\(check)")
            } }
        }
    }

    private func makeSource(size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: w*h*4)
        for y in 0..<h { for x in 0..<w {
            let k = (y*w+x)*4, a = [1, 63, 127, 191, 255][(x/13+y/17)%5]
            bytes[k] = UInt8((x*17+y*3)%256*a/255)
            bytes[k+1] = UInt8((x*3+y*11)%256*a/255)
            bytes[k+2] = UInt8((x*7+y*5)%256*a/255)
            bytes[k+3] = UInt8(a)
        } }
        return CoreGraphicsCompositor.makeImage(fromPremultiplied: bytes, width: w, height: h)
    }

    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
}
