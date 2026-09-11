import Foundation

struct FoldSettings {
    var startAngle: Double = 90
    var endAngle: Double = 12
    var blur: Double = 72
    var darkness: Double = 1.05
    var projection: Double = 1
}

struct FoldState {
    let progress: Float
    let projection: Float

    static func overlayOpacity(progress: Float, elapsed: Double) -> Double {
        func smooth(_ value: Double) -> Double {
            let x = min(1, max(0, value))
            return x * x * (3 - 2 * x)
        }
        return smooth(Double(progress) / 0.065) * smooth(elapsed / 0.22)
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
