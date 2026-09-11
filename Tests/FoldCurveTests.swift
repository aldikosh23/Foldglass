import Foundation

@main
struct FoldCurveTests {
    static func main() {
        let settings = FoldSettings()
        precondition(settings.startAngle == 90, "standard start angle must remain 90 degrees")
        precondition(FoldSettings.startAngle(forComfortAngle: 80) == 70, "lap position needs ten degrees of movement before activation")
        precondition(FoldSettings.startAngle(forComfortAngle: 35) == 30)
        precondition(FoldSettings.startAngle(forComfortAngle: 140) == 115)
        let lowStart = FoldSettings(startAngle: FoldSettings.startAngleRange.lowerBound)
        precondition(FoldState.at(angle: 30, settings: lowStart).progress == 0)
        precondition(FoldState.at(angle: 12, settings: lowStart).progress == 1)
        let open = FoldState.at(angle: settings.startAngle + 15, settings: settings)
        precondition(open.progress == 0 && open.projection == 1, "open screen must stay unchanged")

        let angles = stride(from: settings.startAngle, through: settings.endAngle, by: -1.0)
        var previous = open
        for angle in angles {
            let state = FoldState.at(angle: angle, settings: settings)
            precondition(state.progress >= previous.progress && state.progress <= 1, "closing must increase progress")
            precondition(state.projection <= previous.projection && state.projection > 0, "closing must shorten projected screen")
            previous = state
        }

        for boundary in [settings.startAngle, settings.endAngle] {
            let before = FoldState.at(angle: boundary + 0.0001, settings: settings)
            let after = FoldState.at(angle: boundary - 0.0001, settings: settings)
            precondition(abs(before.progress - after.progress) < 0.0001, "progress must remain continuous")
            precondition(abs(before.projection - after.projection) < 0.0001, "projection must remain continuous")
        }

        let closed = FoldState.at(angle: 0, settings: settings)
        precondition(closed.progress == 1, "closed lid must reach full darkening progress")
        precondition(abs(closed.projection - 0.04) < 0.00001, "closed projection must reach its lower limit")
        precondition(FoldState.overlayOpacity(progress: 0, elapsed: 1) == 0, "threshold must blend into the live desktop")
        precondition(FoldState.overlayOpacity(progress: 1, elapsed: 0) == 0, "first frame must stay hidden")
        precondition(FoldState.overlayOpacity(progress: 1, elapsed: 0.22) == 1, "ready overlay must become fully visible")
        precondition(FoldState.overlayOpacity(progress: 1, elapsed: 0, fadeDuration: 0.045) == 0)
        precondition(FoldState.overlayOpacity(progress: 1, elapsed: 0.045, fadeDuration: 0.045) == 1,
                     "opening should show its ready frame within 45 ms")
        precondition(FoldState.overlayOpacity(progress: 1, elapsed: 0.045) < 0.2,
                     "closing must retain the gradual entry")
        let entry = FoldState.overlayOpacity(progress: 0.001, elapsed: 0.1)
        precondition(entry < 0.001, "small hinge movement must not pop in the snapshot")
        var at60 = FoldMotion(angle: 90)
        var at120 = FoldMotion(angle: 90)
        for _ in 0..<60 {
            at60.advance(toward: 30, dt: 1.0 / 60)
            at120.advance(toward: 30, dt: 1.0 / 120)
            at120.advance(toward: 30, dt: 1.0 / 120)
            precondition(abs(at60.angle - at120.angle) < 0.000001,
                         "smoothing must follow the same motion at 60 and 120 Hz")
            precondition(at60.angle >= 30 && at60.angle <= 90,
                         "closing toward a stationary target must not overshoot")
        }
        precondition(abs(at60.angle - 30) < 0.001 && abs(at60.velocity) < 0.01,
                     "stationary motion must converge so drawing can pause")
        var reversing = FoldMotion(angle: 90)
        for _ in 0..<6 { reversing.advance(toward: 30, dt: 1.0 / 60) }
        reversing.advance(toward: 90, dt: 1.0 / 120)
        precondition(reversing.velocity < 0, "a reversed sensor target must decelerate rather than instantly flip velocity")
        print("motion passed: refresh-rate independence, convergence, smooth reversal")
        print("fold curve passed: identity, monotonic closing, continuity, closed endpoint")
    }
}
