import AppKit
import Foundation

// Run from the repository root: swift Tools/MakeIcon.swift
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("build/icon/Foldglass.iconset", isDirectory: true)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

func shade(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func makeIcon(pixels: Int) -> CGImage {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    let plate = NSBezierPath(roundedRect: CGRect(x: 70, y: 76, width: 884, height: 884), xRadius: 198, yRadius: 198)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = shade(0x050B16, 0.5)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = CGSize(width: 0, height: -18)
    shadow.set()
    shade(0x172333).setFill()
    plate.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [shade(0x101A29), shade(0x273D53)])!.draw(in: plate, angle: 83)

    NSGraphicsContext.saveGraphicsState()
    plate.addClip()
    NSGradient(starting: shade(0x82B3CB, 0.25), ending: shade(0x82B3CB, 0))!
        .draw(in: NSBezierPath(ovalIn: CGRect(x: 50, y: 488, width: 950, height: 720)), relativeCenterPosition: .zero)
    NSGradient(starting: shade(0x97B7BF, 0.16), ending: shade(0x97B7BF, 0))!
        .draw(in: NSBezierPath(ovalIn: CGRect(x: 42, y: 16, width: 950, height: 690)), relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()
    shade(0xA9C5D8, 0.26).setStroke()
    plate.lineWidth = 2
    plate.stroke()

    let upper = NSBezierPath()
    upper.move(to: CGPoint(x: 274, y: 510))
    upper.line(to: CGPoint(x: 750, y: 510))
    upper.curve(to: CGPoint(x: 765, y: 531), controlPoint1: CGPoint(x: 766, y: 510), controlPoint2: CGPoint(x: 770, y: 517))
    upper.line(to: CGPoint(x: 707, y: 743))
    upper.curve(to: CGPoint(x: 687, y: 761), controlPoint1: CGPoint(x: 704, y: 755), controlPoint2: CGPoint(x: 699, y: 761))
    upper.line(to: CGPoint(x: 337, y: 761))
    upper.curve(to: CGPoint(x: 317, y: 743), controlPoint1: CGPoint(x: 325, y: 761), controlPoint2: CGPoint(x: 320, y: 755))
    upper.line(to: CGPoint(x: 259, y: 531))
    upper.curve(to: CGPoint(x: 274, y: 510), controlPoint1: CGPoint(x: 254, y: 517), controlPoint2: CGPoint(x: 258, y: 510))
    upper.close()

    let lower = NSBezierPath()
    lower.move(to: CGPoint(x: 274, y: 495))
    lower.line(to: CGPoint(x: 750, y: 495))
    lower.curve(to: CGPoint(x: 767, y: 472), controlPoint1: CGPoint(x: 768, y: 495), controlPoint2: CGPoint(x: 774, y: 486))
    lower.line(to: CGPoint(x: 692, y: 275))
    lower.curve(to: CGPoint(x: 667, y: 256), controlPoint1: CGPoint(x: 687, y: 262), controlPoint2: CGPoint(x: 680, y: 256))
    lower.line(to: CGPoint(x: 357, y: 256))
    lower.curve(to: CGPoint(x: 332, y: 275), controlPoint1: CGPoint(x: 344, y: 256), controlPoint2: CGPoint(x: 337, y: 262))
    lower.line(to: CGPoint(x: 257, y: 472))
    lower.curve(to: CGPoint(x: 274, y: 495), controlPoint1: CGPoint(x: 250, y: 486), controlPoint2: CGPoint(x: 256, y: 495))
    lower.close()

    for path in [upper, lower] {
        NSGraphicsContext.saveGraphicsState()
        let panelShadow = NSShadow()
        panelShadow.shadowColor = shade(0x000812, 0.7)
        panelShadow.shadowBlurRadius = 26
        panelShadow.shadowOffset = CGSize(width: 0, height: -15)
        panelShadow.set()
        shade(0x070F18).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGradient(colors: [shade(0x829EA8), shade(0xE7ECE4), shade(0xC7DFE1)])!.draw(in: upper, angle: 64)
    NSGraphicsContext.saveGraphicsState()
    upper.addClip()
    let wave = NSBezierPath()
    wave.move(to: CGPoint(x: 240, y: 532))
    wave.curve(to: CGPoint(x: 735, y: 790), controlPoint1: CGPoint(x: 593, y: 466), controlPoint2: CGPoint(x: 466, y: 784))
    wave.line(to: CGPoint(x: 801, y: 793))
    wave.line(to: CGPoint(x: 801, y: 476))
    wave.line(to: CGPoint(x: 240, y: 476))
    wave.close()
    NSGradient(starting: shade(0x557E99, 0.8), ending: shade(0xC0D9DF, 0.3))!.draw(in: wave, angle: 90)
    NSGradient(starting: shade(0xFFFFFF, 0.78), ending: shade(0xFFFFFF, 0))!
        .draw(in: NSBezierPath(ovalIn: CGRect(x: 222, y: 637, width: 516, height: 297)), relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [shade(0xA8C7D3), shade(0xE4EADF), shade(0xFCF6E6)])!.draw(in: lower, angle: -74)
    NSGraphicsContext.saveGraphicsState()
    lower.addClip()
    NSGradient(starting: shade(0xA9D4E8, 0.75), ending: shade(0xA9D4E8, 0))!
        .draw(in: NSBezierPath(ovalIn: CGRect(x: 230, y: 235, width: 665, height: 411)), relativeCenterPosition: .zero)
    NSGradient(starting: shade(0xFFF2D6, 0.95), ending: shade(0xFFF2D6, 0))!
        .draw(in: NSBezierPath(ovalIn: CGRect(x: 119, y: 108, width: 639, height: 456)), relativeCenterPosition: .zero)
    let reflection = NSBezierPath()
    reflection.move(to: CGPoint(x: 245, y: 468))
    reflection.curve(to: CGPoint(x: 703, y: 273), controlPoint1: CGPoint(x: 407, y: 493), controlPoint2: CGPoint(x: 604, y: 390))
    reflection.line(to: CGPoint(x: 799, y: 256))
    reflection.line(to: CGPoint(x: 799, y: 510))
    reflection.line(to: CGPoint(x: 245, y: 510))
    reflection.close()
    shade(0xFFFFFF, 0.19).setFill()
    reflection.fill()
    NSGraphicsContext.restoreGraphicsState()

    for path in [upper, lower] {
        path.lineWidth = 3.5
        shade(0xE9F5F8, 0.82).setStroke()
        path.stroke()
    }
    let hinge = NSBezierPath()
    hinge.move(to: CGPoint(x: 274, y: 503))
    hinge.line(to: CGPoint(x: 750, y: 503))
    hinge.lineWidth = 3
    shade(0xC2D9E5, 0.7).setStroke()
    hinge.stroke()
    let edge = NSBezierPath()
    edge.move(to: CGPoint(x: 361, y: 260))
    edge.line(to: CGPoint(x: 663, y: 260))
    edge.lineWidth = 2
    shade(0xFFFFFF, 0.7).setStroke()
    edge.stroke()

    return context.makeImage()!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(cgImage: makeIcon(pixels: pixels))
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(size)x\(size)\(suffix).png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let preview = NSBitmapImageRep(cgImage: makeIcon(pixels: 1024))
try preview.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("build/icon/preview.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed: \(process.terminationStatus)") }
print("created AppIcon.icns with 10 raster representations")
