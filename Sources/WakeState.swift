struct WakeState {
    enum Pause: Hashable { case systemSleep, displaySleep, locked, inactiveSession }

    private var pauses = Set<Pause>()
    private var closingBeforePause = false
    private(set) var openingPending = false
    // Screen lock changes the capture source; only sleep or another session pauses rendering.
    var isSuspended: Bool { pauses.contains(where: { $0 != .locked }) }

    mutating func pause(_ reason: Pause, wasClosing: Bool) {
        // Locking can arrive before sleep; retain the closing intent across both events.
        if !isSuspended { closingBeforePause = wasClosing }
        pauses.insert(reason)
        if reason == .systemSleep || reason == .displaySleep {
            openingPending = openingPending || closingBeforePause
        }
    }

    mutating func resume(_ reason: Pause) {
        pauses.remove(reason)
        if !isSuspended { closingBeforePause = false }
    }

    mutating func needsOpening(at angle: Double, startAngle: Double) -> Bool {
        guard !isSuspended else { return false }
        if angle >= startAngle { openingPending = false }
        return openingPending
    }

    mutating func openingStarted() { openingPending = false }

    mutating func cancelOpening() {
        closingBeforePause = false
        openingPending = false
    }
}
