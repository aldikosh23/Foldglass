import CoreGraphics

@main struct SnapshotBrightnessTests {
    static func main() {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                                bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        precondition(SnapshotBrightness(context.makeImage()!).isBlank, "transparent frame is blank")
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        precondition(SnapshotBrightness(context.makeImage()!).isBlank, "black wake frame must not cover the screen")
        context.setFillColor(gray: 0.1, alpha: 1)
        context.fill(CGRect(x: 31, y: 31, width: 1, height: 1))
        precondition(SnapshotBrightness(context.makeImage()!).isBlank, "one faint pixel is still a blank capture")
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 24, y: 48, width: 16, height: 3))
        precondition(!SnapshotBrightness(context.makeImage()!).isBlank, "clock on a black wallpaper is valid")
        print("snapshot brightness passed: transparent, black, near-black wake frame, clock on black")
    }
}
