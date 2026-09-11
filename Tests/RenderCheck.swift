import AppKit
import MetalKit

@main
struct RenderCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let gpu = try FoldGPU(shaderURL: root.appendingPathComponent("Resources/Fold.metal"))
        let begin = CACurrentMediaTime()
        let textures = try gpu.textures(for: DemoImage.make(bundle: Bundle(path: root.appendingPathComponent("Resources").path)!))
        print(String(format: "snapshot preparation: %.1f ms", (CACurrentMediaTime() - begin) * 1000))
        let width = 2560, height = 1664
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared
        desc.usage = [.renderTarget]
        let target = gpu.device.makeTexture(descriptor: desc)!
        func render(_ angle: Double) throws -> (Data, Double) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let command = gpu.queue.makeCommandBuffer()!
            gpu.encode(command, pass: pass, textures: textures, angle: angle, settings: FoldSettings())
            command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            var bytes = Data(count: width * height * 4)
            bytes.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
            return (bytes, (command.gpuEndTime - command.gpuStartTime) * 1000)
        }
        let open = try render(90).0
        let inactive = try render(120).0
        precondition(inactive == open, "open screen must be pixel identical across inactive angles")
        var previousMean = Double.infinity
        for angle in [90.0, 75, 60, 40, 12] {
            let (bytes, ms) = try render(angle)
            let mean = bytes.withUnsafeBytes { buffer -> Double in
                let b = buffer.bindMemory(to: UInt8.self)
                var sum: UInt64 = 0
                for i in stride(from: 0, to: b.count, by: 4) { sum += UInt64(b[i]) + UInt64(b[i+1]) + UInt64(b[i+2]) }
                return Double(sum) / Double(width * height * 3)
            }
            precondition(mean < previousMean, "brightness should fall as the lid closes")
            if angle == 12 { precondition(mean == 0, "closed frame must be black") }
            if angle == 90 { precondition(mean > 30, "open frame must contain the source image") }
            previousMean = mean
            let provider = CGDataProvider(data: bytes as CFData)!
            let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: output.appendingPathComponent("angle-\(Int(angle)).png"))
            print(String(format: "angle %.0f: mean %.2f, GPU %.3f ms", angle, mean, ms))
        }
        print("render checks passed: identity, ordered dimming, fully black endpoint, five actual GPU frames")
    }
}
