@main
struct WakeStateTests {
    static func main() {
        var lockedFirst = WakeState()
        lockedFirst.pause(.locked, wasClosing: true)
        lockedFirst.pause(.systemSleep, wasClosing: false)
        lockedFirst.pause(.displaySleep, wasClosing: false)
        lockedFirst.resume(.systemSleep)
        lockedFirst.resume(.displaySleep)
        precondition(lockedFirst.isSuspended && !lockedFirst.consumeOpening(), "wake must wait for unlock")
        lockedFirst.resume(.locked)
        precondition(lockedFirst.consumeOpening(), "lock-before-sleep must preserve the opening")
        lockedFirst.resume(.systemSleep)
        lockedFirst.resume(.displaySleep)
        precondition(!lockedFirst.consumeOpening(), "duplicate wake must not replay the opening")

        var sleepingFirst = WakeState()
        sleepingFirst.pause(.systemSleep, wasClosing: true)
        sleepingFirst.pause(.displaySleep, wasClosing: false)
        sleepingFirst.pause(.locked, wasClosing: false)
        sleepingFirst.resume(.locked)
        sleepingFirst.resume(.systemSleep)
        precondition(!sleepingFirst.consumeOpening(), "unlock must wait for the display to wake")
        sleepingFirst.pause(.inactiveSession, wasClosing: false)
        sleepingFirst.resume(.displaySleep)
        precondition(!sleepingFirst.consumeOpening(), "opening must stay hidden in another user's session")
        sleepingFirst.resume(.inactiveSession)
        precondition(sleepingFirst.consumeOpening(), "active unlocked desktop must receive one opening")

        var idle = WakeState()
        idle.pause(.systemSleep, wasClosing: false)
        idle.resume(.systemSleep)
        precondition(!idle.consumeOpening(), "idle sleep with an open lid must not animate")
        idle.pause(.locked, wasClosing: true)
        idle.resume(.locked)
        precondition(!idle.consumeOpening(), "locking without sleep must not animate")

        var cancelled = WakeState()
        cancelled.pause(.locked, wasClosing: true)
        cancelled.cancelOpening()
        cancelled.pause(.systemSleep, wasClosing: false)
        cancelled.resume(.locked)
        cancelled.resume(.systemSleep)
        precondition(!cancelled.consumeOpening(), "disabling or cancelling must clear the pending opening")

        let angle = { (time: Double) in WakeState.openingAngle(target: 130, start: 90, end: 12, elapsed: time) }
        precondition(angle(0) == 12, "wake reveal must start closed")
        precondition(angle(0.5) < 90, "an already open lid must still reveal gradually")
        precondition(angle(WakeState.openingDuration) == 90, "opening must reach the clear desktop")
        precondition(WakeState.openingAngle(target: 45, start: 90, end: 12, elapsed: 1) == 45,
                     "a partly opened lid must retain its physical angle")
        print("wake state passed: sleep and lock ordering, active session, one-shot reveal, cancellation, opening timing")
    }
}
