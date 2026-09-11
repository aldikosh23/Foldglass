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
        func render(_ angle: Double, textures: FoldTextures) throws -> (Data, Double) {
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
        let open = try render(90, textures: textures).0
        let inactive = try render(120, textures: textures).0
        precondition(inactive == open, "open screen must be pixel identical across inactive angles")
        var previousMean = Double.infinity
        for angle in [90.0, 75, 60, 45, 30, 20, 12] {
            let (bytes, ms) = try render(angle, textures: textures)
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
        // A uniform source isolates the moving shade from wallpaper and perspective.
        let white = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                              bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        white.setFillColor(gray: 1, alpha: 1)
        white.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let whiteTextures = try gpu.textures(for: white.makeImage()!)
        let halfway = try render(51, textures: whiteTextures).0
        func brightness(_ bytes: Data, y: Double) -> Double {
            let index = (Int(Double(height - 1) * y) * width + width / 2) * 4
            return Double(bytes[index]) / 255
        }
        let freeEdge = brightness(halfway, y: 0.1)
        precondition(freeEdge > 0.3 && freeEdge < 0.7,
                     "the free edge should shade without disappearing halfway through the fold")
        precondition(brightness(halfway, y: 0.9) > 0.9,
                     "the hinge should stay lit while the free edge shades")
        let transition = [0.1, 0.3, 0.5, 0.7, 0.9].map { brightness(halfway, y: $0) }
        precondition(zip(transition, transition.dropFirst()).allSatisfy { $0 < $1 },
                     "the shade must be gradual across the panel")
        print("render checks passed: identity, gradual shading, lit hinge, black endpoint")
    }
}
