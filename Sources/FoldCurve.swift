import Foundation

struct FoldSettings {
    static let startAngleRange: ClosedRange<Double> = 30...115

    static func startAngle(forComfortAngle angle: Double) -> Double {
        min(startAngleRange.upperBound, max(startAngleRange.lowerBound, angle - 10))
    }

    var startAngle: Double = 90
    var endAngle: Double = 12
    var blur: Double = 72
    var darkness: Double = 1.05
    var projection: Double = 1
}

struct FoldState {
    let progress: Float
    let projection: Float

    static func overlayOpacity(progress: Float, elapsed: Double, fadeDuration: Double = 0.22) -> Double {
        func smooth(_ value: Double) -> Double {
            let x = min(1, max(0, value))
            return x * x * (3 - 2 * x)
        }
        return smooth(Double(progress) / 0.065) * smooth(elapsed / fadeDuration)
    }

    static func at(angle: Double, settings: FoldSettings) -> FoldState {
        let t = min(1, max(0, (settings.startAngle - angle) / (settings.startAngle - settings.endAngle)))
        let p = pow(t, 0.85)
        // Project onto the fully open screen plane, anchored at the physical hinge.
        let relativeAngle = (1 - t) * .pi / 2
        let projectedHeight = max(0.04, sin(relativeAngle))
        return FoldState(progress: Float(p), projection: Float(1 + (projectedHeight - 1) * settings.projection))
    }
}

// Keep a fast opening from dropping the captured image in a single frame.
// Entry follows the existing fade; only revealing the live screen is smoothed.
struct FoldOpacity {
    private(set) var value = 0.0

    mutating func advance(toward target: Double, dt: Double) {
        if target >= value {
            value = target
        } else {
            value = target + (value - target) * exp(-dt / 0.04)
            if value - target < 0.001 { value = target }
        }
    }
}

// Preserve velocity between integer-degree sensor reports, including reversals.
// The analytic critically damped step behaves equally at 60 and 120 Hz.
struct FoldMotion {
    var angle: Double
    private(set) var velocity: Double = 0

    mutating func advance(toward target: Double, dt: Double) {
        let frequency = 24.0
        let offset = angle - target
        let change = (velocity + frequency * offset) * dt
        let decay = exp(-frequency * dt)
        angle = target + (offset + change) * decay
        velocity = (velocity - frequency * change) * decay
    }
}
