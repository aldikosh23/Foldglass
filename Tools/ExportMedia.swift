import AppKit
import MetalKit

// Exports the application's actual Metal shader using the synthetic DemoImage.
// This utility never reads, captures, or records the user's display.
@main
struct ExportMedia {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw FoldError.message("usage: export-media <project-directory> <frame-directory>")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let frames = URL(fileURLWithPath: CommandLine.arguments[2])
        let assets = root.appendingPathComponent("docs/assets")
        for directory in [frames, assets] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let gpu = try FoldGPU(shaderURL: root.appendingPathComponent("Resources/Fold.metal"))
        let textures = try gpu.textures(for: DemoImage.make())
        let renderer = ShaderFrames(gpu: gpu, textures: textures)

        func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                    green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: alpha)
        }
        func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat,
                  tint: NSColor, weight: NSFont.Weight = .regular, mono: Bool = false) {
            let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                : NSFont.systemFont(ofSize: size, weight: weight)
            (string as NSString).draw(at: CGPoint(x: x, y: y),
                                     withAttributes: [.font: font, .foregroundColor: tint])
        }
        func line(_ rect: CGRect, tint: NSColor) {
            tint.setFill()
            rect.fill()
        }
        func screen(_ image: CGImage, in rect: CGRect, radius: CGFloat) {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = color(0x000000, alpha: 0.4)
            shadow.shadowBlurRadius = 26
            shadow.shadowOffset = CGSize(width: 0, height: -14)
            shadow.set()
            color(0x0A0E14).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            path.addClip()
            NSGraphicsContext.current!.cgContext.draw(image, in: rect)
            NSGraphicsContext.restoreGraphicsState()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: radius, yRadius: radius)
            color(0xCBDCEB, alpha: 0.24).setStroke()
            border.lineWidth = 1
            border.stroke()
        }
        func canvas(width: Int, height: Int, draw: () throws -> Void) rethrows -> CGImage {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            try draw()
            return context.makeImage()!
        }
        func save(_ image: CGImage, to url: URL) throws {
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: url)
        }

        let phases = try [90.0, 60, 30].map { try renderer.render(angle: $0, width: 928, height: 604) }
        let hero = canvas(width: 1600, height: 900) {
            let bounds = CGRect(x: 0, y: 0, width: 1600, height: 900)
            NSGradient(starting: color(0x090D13), ending: color(0x182630))!.draw(in: bounds, angle: 38)
            NSGradient(starting: color(0x597B85, alpha: 0.24), ending: color(0x597B85, alpha: 0))!
                .draw(in: NSBezierPath(ovalIn: CGRect(x: 820, y: 320, width: 1080, height: 950)), relativeCenterPosition: .zero)
            text("native lid animation for macos", x: 76, y: 803, size: 17,
                 tint: color(0x92B2BC), weight: .medium, mono: true)
            text("foldglass", x: 70, y: 688, size: 92, tint: color(0xEFF3F1), weight: .semibold)
            text("a softer close. a seamless return.", x: 76, y: 651, size: 29, tint: color(0xA7B6BF))
            if let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns")) {
                icon.draw(in: CGRect(x: 1312, y: 649, width: 224, height: 224))
            }
            line(CGRect(x: 76, y: 601, width: 1448, height: 1), tint: color(0xAEC7D2, alpha: 0.14))
            let names = ["01 / open", "02 / folding", "03 / almost closed"]
            let captions = ["your desktop, untouched", "perspective meets frosted glass", "light fades toward the hinge"]
            for index in 0..<3 {
                let x = CGFloat(72 + index * 496)
                text(names[index], x: x + 3, y: 566, size: 15, tint: color(0x9BB0BC), mono: true)
                screen(phases[index], in: CGRect(x: x, y: 243, width: 464, height: 302), radius: 12)
                text(["90°", "60°", "30°"][index], x: x + 2, y: 186, size: 32,
                     tint: color(0xE1EAE9), weight: .medium)
                text(captions[index], x: x + 3, y: 156, size: 18, tint: color(0x92A5B1))
            }
            line(CGRect(x: 76, y: 113, width: 1448, height: 1), tint: color(0xAEC7D2, alpha: 0.14))
            text("native metal shader / synthetic desktop", x: 76, y: 65, size: 15,
                 tint: color(0x7C939F), mono: true)
            text("open source / made for mac", x: 1250, y: 65, size: 15,
                 tint: color(0x7C939F), mono: true)
        }
        try save(hero, to: assets.appendingPathComponent("hero.png"))

        let frameCount = 120
        func eased(_ value: Double) -> Double { value * value * (3 - 2 * value) }
        for frame in 0..<frameCount {
            let time = Double(frame) / 20
            let amount: Double
            if time < 0.5 { amount = 0 }
            else if time < 2.6 { amount = eased((time - 0.5) / 2.1) }
            else if time < 3.15 { amount = 1 }
            else if time < 5.5 { amount = 1 - eased((time - 3.15) / 2.35) }
            else { amount = 0 }
            let angle = 90 - 78 * amount
            let shader = try renderer.render(angle: angle, width: 660, height: 429)
            let preview = canvas(width: 720, height: 468) {
                color(0x0C131A).setFill()
                CGRect(x: 0, y: 0, width: 720, height: 468).fill()
                screen(shader, in: CGRect(x: 30, y: 30, width: 660, height: 429), radius: 8)
                text("native shader demo / synthetic desktop", x: 31, y: 7, size: 11,
                     tint: color(0x90A7B4), mono: true)
                text(String(format: "%02.0f°", angle), x: 656, y: 6, size: 13,
                     tint: color(0xCDDCE0), weight: .medium, mono: true)
            }
            try save(preview, to: frames.appendingPathComponent(String(format: "frame-%03d.png", frame)))
        }
        print("exported hero.png and \(frameCount) synthetic desktop frames at 20 fps")
    }
}

private final class ShaderFrames {
    let gpu: FoldGPU
    let textures: FoldTextures
    var target: MTLTexture?

    init(gpu: FoldGPU, textures: FoldTextures) {
        self.gpu = gpu
        self.textures = textures
    }

    func render(angle: Double, width: Int, height: Int) throws -> CGImage {
        if target?.width != width || target?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.renderTarget]
            target = gpu.device.makeTexture(descriptor: descriptor)
        }
        guard let target, let command = gpu.queue.makeCommandBuffer() else {
            throw FoldError.message("metal could not allocate a preview frame")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        gpu.encode(command, pass: pass, textures: textures, angle: angle, settings: FoldSettings())
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                        .union(.byteOrder32Little),
                       provider: CGDataProvider(data: bytes as CFData)!, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)!
    }
}
