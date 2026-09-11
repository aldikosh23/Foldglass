import AppKit
import QuartzCore

@MainActor
final class FrameClock: NSObject {
    private var link: CADisplayLink?
    private var update: ((Double) -> Void)?

    func start(on screen: NSScreen, update: @escaping (Double) -> Void) {
        stop()
        self.update = update
        // Use the screen's clock even for the overlay in a private lock screen space.
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        let maximum = Float(screen.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum),
                                                       maximum: maximum, preferred: maximum)
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    func pause() { link?.isPaused = true }
    @discardableResult func resume() -> Bool {
        guard let link, link.isPaused else { return false }
        link.isPaused = false
        return true
    }
    func stop() {
        link?.invalidate()
        link = nil
        update = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        update?(link.targetTimestamp)
    }
}
