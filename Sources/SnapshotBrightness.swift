import CoreGraphics

struct SnapshotBrightness {
    let mean: Double
    let brightPixels: Int

    // A lock screen with a clock still has visible content on a black wallpaper.
    // Ignore the near-empty frames returned while the display is waking.
    var isBlank: Bool { brightPixels < 8 }

    init(_ image: CGImage) {
        let side = 64
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                    bitsPerComponent: 8, bytesPerRow: side * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        var total = 0, bright = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let r = Int(bytes[index]), g = Int(bytes[index + 1]), b = Int(bytes[index + 2])
            total += r + g + b
            if max(r, g, b) > 8 { bright += 1 }
        }
        mean = Double(total) / Double(side * side * 3)
        brightPixels = bright
    }
}
