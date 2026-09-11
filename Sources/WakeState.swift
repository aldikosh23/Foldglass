struct WakeState {
    enum Pause: Hashable { case systemSleep, displaySleep, locked, inactiveSession }

    private var pauses = Set<Pause>()
    private var closingBeforePause = false
    private(set) var openingPending = false
    var isSuspended: Bool { !pauses.isEmpty }

    mutating func pause(_ reason: Pause, wasClosing: Bool) {
        // Locking can arrive before the sleep notification and stop the sensor.
        if pauses.isEmpty { closingBeforePause = wasClosing }
        pauses.insert(reason)
        if reason == .systemSleep || reason == .displaySleep {
            openingPending = openingPending || closingBeforePause
        }
    }

    mutating func resume(_ reason: Pause) {
        pauses.remove(reason)
        if !isSuspended { closingBeforePause = false }
    }

    mutating func consumeOpening(at angle: Double, startAngle: Double) -> Bool {
        guard !isSuspended else { return false }
        let pending = openingPending
        openingPending = false
        return pending && angle < startAngle
    }

    mutating func cancelOpening() {
        closingBeforePause = false
        openingPending = false
    }
}
