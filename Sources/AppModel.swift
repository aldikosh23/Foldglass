import AppKit
import SwiftUI
import ScreenCaptureKit
import Combine
import OSLog

final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var language = AppLanguage.load() {
        didSet {
            language.save()
            if !previewIsDesktop {
                do { previewRenderer.textures = try gpu.textures(for: DemoImage.make(language: language)) }
                catch { message = AppMessage.preserving(error) }
                refreshPreview()
            }
        }
    }
    @Published var settings: FoldSettings {
        didSet {
            if settings.startAngle != oldValue.startAngle { dismissEffect(); wakeState.cancelOpening(); armed = false }
            saveSettings(); refreshPreview()
        }
    }
    @Published var enabled = true { didSet { if !enabled { dismissEffect() }; wakeState.cancelOpening(); armed = false } }
    @Published private(set) var angle: Double?
    @Published private(set) var sensorError: AppMessage?
    @Published private(set) var permission = CGPreflightScreenCaptureAccess()
    @Published private(set) var message: AppMessage?
    @Published private(set) var effectVisible = false
    @Published private(set) var capturing = false
    @Published var previewAngle: Double = 90 { didSet { refreshPreview() } }
    @Published var previewIsDesktop = false
    @Published private(set) var playing = false
    @Published private(set) var fullscreenDemo = false
    let sensor = LidSensor()
    let loginItem = LoginItem()
    let gpu: FoldGPU
    let previewRenderer: FoldRenderer
    let overlayRenderer: FoldRenderer
    private var overlay: OverlayWindow?
    private enum CaptureSurface: String { case desktop, lockScreen }
    private var overlaySurface: CaptureSurface?
    private var lockScreenSpace: LockScreenSpace?
    private let logger = Logger(subsystem: "local.foldglass", category: "effect")
    private var captureTask: Task<Void, Never>?
    private enum CapturePurpose { case preview, physical, opening, demo }
    private var capturePurpose: CapturePurpose?
    private var animation: Timer?
    private var previewTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var generation = 0
    @Published private var armed = false
    private var wakeState = WakeState()
    private var suspended: Bool { wakeState.isSuspended }
    private var displayAngle: Double = 90
    private var targetAngle: Double = 90
    private var lastFrame = CACurrentMediaTime()
    private var firstSubmittedFrame = 0
    private var escapeMonitor: Any?
    private var localEscapeMonitor: Any?
    private var observationTokens: [NSObjectProtocol] = []
    var onShowSettings: (() -> Void)?

    init(gpu: FoldGPU, demo: FoldTextures) {
        self.gpu = gpu
        previewRenderer = FoldRenderer(gpu: gpu)
        overlayRenderer = FoldRenderer(gpu: gpu)
        previewRenderer.textures = demo
        let defaults = UserDefaults.standard
        settings = FoldSettings(
            startAngle: defaults.object(forKey: "startAngle") as? Double ?? 90,
            endAngle: 12,
            blur: defaults.object(forKey: "blur") as? Double ?? 72,
            darkness: defaults.object(forKey: "darkness") as? Double ?? 1.05,
            projection: defaults.object(forKey: "projection") as? Double ?? 1)
        previewAngle = settings.startAngle
        sensor.onAngle = { [weak self] angle in self?.receive(angle) }
        sensor.$error.sink { [weak self] error in
            guard let self else { return }
            if self.sensorError != error { self.sensorError = error }
            if let error {
                self.logger.error("sensor failure: \(error.text(in: .english), privacy: .public)")
                self.dismissEffect("sensor failure"); self.wakeState.cancelOpening()
            }
        }.store(in: &cancellables)
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, WakeState.Pause.systemSleep),
                               (NSWorkspace.screensDidSleepNotification, .displaySleep),
                               (NSWorkspace.sessionDidResignActiveNotification, .inactiveSession)] {
            observationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause(reason) }
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, WakeState.Pause.systemSleep),
                               (NSWorkspace.screensDidWakeNotification, .displaySleep),
                               (NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession)] {
            observationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume(reason) }
            })
        }
        observationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissEffect("screen parameters changed") }
        })
        observationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission(); self?.loginItem.refresh() }
        })
        for (name, lock) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observationTokens.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if lock { self?.pause(.locked) } else { self?.resume(.locked) } }
            })
        }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type != .keyDown || event.keyCode == 53 {
                let cancelled = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.escape()
                }
                if cancelled { return nil }
            }
            return event
        }
        // This monitor works when macOS allows global key observation. Mouse movement
        // and the normal system menu remain available without Accessibility access.
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type != .keyDown || event.keyCode == 53 { _ = MainActor.assumeIsolated { self?.escape() } }
        }
        refreshPreview()
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            if session["CGSSessionScreenIsLocked"] as? Bool == true { pause(.locked) }
            if session[kCGSessionOnConsoleKey as String] as? Bool != true { pause(.inactiveSession) }
        }
        if !suspended { sensor.start() }
    }

    func text(_ key: String) -> String { language.text(key) }

    var status: String {
        if let sensorError { return sensorError.text(in: language) }
        if let message { return message.text(in: language) }
        if !enabled { return text("paused") }
        if suspended { return text("screen_asleep") }
        if !permission { return text("permission_needed") }
        if capturing { return text("preparing_snapshot") }
        if effectVisible { return fullscreenDemo ? text("demo_active") : text("following_lid") }
        if angle == nil { return text("connecting_sensor") }
        if !armed { return language.text("raise_lid", arguments: [String(Int(settings.startAngle + 2))]) }
        return text("ready")
    }

    private func saveSettings() {
        UserDefaults.standard.set(settings.startAngle, forKey: "startAngle")
        UserDefaults.standard.set(settings.blur, forKey: "blur")
        UserDefaults.standard.set(settings.darkness, forKey: "darkness")
        UserDefaults.standard.set(settings.projection, forKey: "projection")
    }

    func resetSettings() { settings = FoldSettings(); previewAngle = settings.startAngle }
    func calibrateStartAngle() {
        guard let angle else { return }
        settings.startAngle = FoldSettings.startAngle(forComfortAngle: angle)
        previewAngle = settings.startAngle
    }
    func refreshPermission() { permission = CGPreflightScreenCaptureAccess() }
    func requestPermission() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        refreshPermission()
        if !permission {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    private func receive(_ newAngle: Double) {
        if angle != newAngle { angle = newAngle }
        guard !suspended, enabled, !fullscreenDemo else { return }
        if newAngle >= settings.startAngle + 2 {
            if !armed { armed = true }
            if message != nil { message = nil }
        }
        targetAngle = newAngle
        if wakeState.openingPending {
            guard captureSurface != nil else { return }
            if wakeState.needsOpening(at: newAngle, startAngle: settings.startAngle) && permission && !capturing && !effectVisible {
                captureAndShow(purpose: .opening)
            }
            return
        }
        if newAngle >= settings.startAngle {
            if capturePurpose == .physical || capturePurpose == .opening { dismissEffect() }
            if !effectVisible { return }
        } else if armed && permission && !capturing && !effectVisible {
            captureAndShow(purpose: .physical)
        }
    }

    private func builtInScreen() throws -> (NSScreen, CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }), let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            throw AppMessage(key: "screen_unavailable")
        }
        return (screen, id)
    }

    private func captureScreen(surface: CaptureSurface) async throws -> (CGImage, NSScreen) {
        guard !suspended, captureSurface == surface else { throw CancellationError() }
        guard CGPreflightScreenCaptureAccess() else { throw AppMessage(key: "grant_permission") }
        let (screen, id) = try builtInScreen()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard !suspended, captureSurface == surface else { throw CancellationError() }
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw AppMessage(key: "capture_display_missing") }
        let overlayWindows = content.windows.filter { $0.windowID == CGWindowID(overlay?.windowNumber ?? 0) }
        let filter = SCContentFilter(display: display, excludingWindows: overlayWindows)
        let config = SCStreamConfiguration()
        config.width = CGDisplayPixelsWide(id)
        config.height = CGDisplayPixelsHigh(id)
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        let deadline = CACurrentMediaTime() + 0.6
        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            guard !suspended, captureSurface == surface else { throw CancellationError() }
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try Task.checkCancellation()
            guard !suspended, captureSurface == surface else { throw CancellationError() }
            if surface == .desktop { return (image, screen) }
            guard (angle ?? settings.startAngle) < settings.startAngle else { throw CancellationError() }
            let brightness = SnapshotBrightness(image)
            logger.notice("lock capture attempt=\(attempt) mean=\(brightness.mean) lit=\(brightness.brightPixels) angle=\(self.angle ?? -1)")
            if !brightness.isBlank { return (image, screen) }
            // Poll blank wake frames at display cadence, within a bounded window.
            // No overlay is visible while the lock screen image is unavailable.
            guard CACurrentMediaTime() < deadline else { throw AppMessage(key: "lock_snapshot_blank") }
            try await Task.sleep(nanoseconds: 16_666_667)
        }
    }

    func capturePreview() {
        guard !capturing, !suspended else { return }
        if !permission { requestPermission(); return }
        capturing = true
        capturePurpose = .preview
        message = nil
        generation += 1
        let ticket = generation
        captureTask = Task {
            defer { if ticket == generation { capturing = false; captureTask = nil; capturePurpose = nil } }
            do {
                let (image, _) = try await captureScreen(surface: .desktop)
                guard ticket == generation else { return }
                previewRenderer.textures = try gpu.textures(for: image)
                previewIsDesktop = true
                refreshPreview()
            } catch is CancellationError { }
            catch { if ticket == generation { message = AppMessage.preserving(error) } }
        }
    }

    func playPreview() {
        stopPreview()
        playing = true
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let elapsed = CACurrentMediaTime() - start
                let phase = min(1, elapsed / 6)
                let amount = pow(sin(phase * .pi), 2)
                self.previewAngle = self.settings.startAngle - (self.settings.startAngle - self.settings.endAngle) * amount
                if phase >= 1 { self.stopPreview() }
            }
        }
        previewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stopPreview() { previewTimer?.invalidate(); previewTimer = nil; playing = false }
    func refreshPreview() { previewRenderer.update(angle: previewAngle, settings: settings) }

    func demoDesktop() {
        guard enabled, !suspended else { message = AppMessage(key: "enable_first"); return }
        if !permission { requestPermission(); return }
        dismissEffect()
        wakeState.cancelOpening()
        captureAndShow(purpose: .demo)
    }

    private func captureAndShow(purpose: CapturePurpose) {
        guard enabled, !suspended, let surface = captureSurface else { return }
        let demo = purpose == .demo
        guard !demo || surface == .desktop else { return }
        logger.debug("capture begin source=\(surface.rawValue, privacy: .public) angle=\(self.angle ?? -1)")
        capturing = true
        capturePurpose = purpose
        fullscreenDemo = demo
        message = nil
        generation += 1
        let ticket = generation
        captureTask = Task {
            defer {
                if ticket == generation {
                    capturing = false; captureTask = nil; capturePurpose = nil
                    if !effectVisible { fullscreenDemo = false }
                }
            }
            do {
                let (image, screen) = try await captureScreen(surface: surface)
                guard ticket == generation, enabled, !suspended, captureSurface == surface else { return }
                if !demo && (angle ?? settings.startAngle) >= settings.startAngle { return }
                let textures = try gpu.textures(for: image)
                overlayRenderer.textures = textures
                displayAngle = purpose == .opening ? (angle ?? settings.startAngle) : settings.startAngle
                targetAngle = demo ? settings.startAngle : (angle ?? settings.startAngle)
                overlayRenderer.firstFrameReady = { [weak self] in
                    guard let self, ticket == self.generation, self.effectVisible else { return }
                    guard !self.suspended, self.captureSurface == surface else { self.dismissEffect("surface changed before first frame"); return }
                    // The lid may finish opening while the first frame is rendering.
                    if !demo && (self.angle ?? self.settings.startAngle) >= self.settings.startAngle {
                        self.dismissEffect("lid already open before first frame"); return
                    }
                    if purpose == .opening {
                        self.wakeState.openingStarted()
                        self.armed = true
                    }
                    self.beginAnimation(purpose: purpose)
                }
                try showOverlay(on: screen, surface: surface)
            } catch is CancellationError { }
            catch {
                guard ticket == generation else { return }
                logger.error("capture failed: \(error.localizedDescription, privacy: .public)")
                dismissEffect()
                wakeState.cancelOpening()
                message = AppMessage.preserving(error)
                armed = false
                fullscreenDemo = false
                refreshPermission()
            }
        }
    }

    private func showOverlay(on screen: NSScreen, surface: CaptureSurface) throws {
        firstSubmittedFrame = overlayRenderer.submittedFrames
        if surface == .lockScreen && lockScreenSpace == nil { lockScreenSpace = try LockScreenSpace() }
        let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.alphaValue = 0
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = surface == .lockScreen
        window.hidesOnDeactivate = false
        window.canBecomeVisibleWithoutLogin = surface == .lockScreen
        window.level = NSWindow.Level(rawValue: surface == .lockScreen ? Int(Int32.max - 2) : Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.sharingType = .none
        let view = overlayRenderer.makeView()
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        overlayRenderer.update(angle: displayAngle, settings: settings)
        window.setFrame(screen.frame, display: false)
        if surface == .lockScreen { lockScreenSpace!.attach(window) }
        window.orderFrontRegardless()
        overlay = window
        overlaySurface = surface
        effectVisible = true
        // Finish the first GPU frame while hidden, then blend into the desktop.
        // Closing starts at identity; reopening uses the current physical angle.
        view.draw()
    }

    private func beginAnimation(purpose: CapturePurpose) {
        logger.debug("animation begin source=\(self.overlaySurface?.rawValue ?? "none", privacy: .public) angle=\(self.angle ?? -1)")
        animation?.invalidate()
        let start = CACurrentMediaTime()
        let fadeDuration = purpose == .opening ? 0.045 : 0.22
        lastFrame = start
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !self.suspended, self.overlaySurface == self.captureSurface else { self.dismissEffect(); return }
                let now = CACurrentMediaTime()
                let dt = min(0.05, now - self.lastFrame)
                self.lastFrame = now
                if purpose == .demo {
                    let phase = min(1, (now - start) / 6)
                    self.displayAngle = self.settings.startAngle - (self.settings.startAngle - self.settings.endAngle) * pow(sin(phase * .pi), 2)
                    if phase >= 1 { self.dismissEffect(); return }
                } else {
                    self.displayAngle += (self.targetAngle - self.displayAngle) * (1 - exp(-dt / 0.09))
                    if self.targetAngle >= self.settings.startAngle && self.displayAngle >= self.settings.startAngle - 0.08 {
                        self.dismissEffect(); return
                    }
                }
                let progress = FoldState.at(angle: self.displayAngle, settings: self.settings).progress
                self.overlay?.alphaValue = FoldState.overlayOpacity(progress: progress, elapsed: now - start, fadeDuration: fadeDuration)
                self.overlayRenderer.update(angle: self.displayAngle, settings: self.settings)
            }
        }
        animation = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func dismissEffect(_ reason: String = #function) {
        if effectVisible || capturing {
            logger.notice("dismiss reason=\(reason, privacy: .public) angle=\(self.angle ?? -1) frames=\(self.overlayRenderer.submittedFrames - self.firstSubmittedFrame) visible=\(self.overlay?.isVisible ?? false) occluded=\(!(self.overlay?.occlusionState.contains(.visible) ?? false))")
        }
        generation += 1
        captureTask?.cancel(); captureTask = nil
        capturing = false
        capturePurpose = nil
        animation?.invalidate(); animation = nil
        overlay?.orderOut(nil); overlay?.close(); overlay = nil
        overlaySurface = nil
        overlayRenderer.textures = nil
        overlayRenderer.firstFrameReady = nil
        effectVisible = false
        fullscreenDemo = false
    }

    @discardableResult func escape() -> Bool {
        // Authentication input belongs to macOS; never consume or react to it on the lock screen.
        guard captureSurface == .desktop,
              effectVisible || fullscreenDemo || capturePurpose == .physical || capturePurpose == .opening else { return false }
        dismissEffect("desktop input cancellation")
        wakeState.cancelOpening()
        armed = false
        return true
    }
    private var captureSurface: CaptureSurface? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true else { return nil }
        return session["CGSSessionScreenIsLocked"] as? Bool == true ? .lockScreen : .desktop
    }


    private func pause(_ reason: WakeState.Pause) {
        // Resigning app/session focus at screen lock need not mean another user owns the display.
        if reason == .inactiveSession && captureSurface != nil { return }
        logger.debug("pause \(String(describing: reason), privacy: .public) angle=\(self.angle ?? -1)")
        let physicalEffect = armed || effectVisible || capturePurpose == .physical || capturePurpose == .opening
        let wasClosing = enabled && physicalEffect && !fullscreenDemo && (angle ?? settings.startAngle) < settings.startAngle
        wakeState.pause(reason, wasClosing: wasClosing)
        if reason == .locked { dismissEffect(); stopPreview(); return }
        suspendRuntime()
    }

    private func suspendRuntime() {
        dismissEffect()
        stopPreview()
        sensor.stop()
        armed = false
    }
    private func resume(_ reason: WakeState.Pause) {
        logger.debug("resume \(String(describing: reason), privacy: .public) angle=\(self.angle ?? -1)")
        if reason == .locked { dismissEffect() }
        wakeState.resume(reason)
        guard !suspended else { return }
        refreshPermission()
        sensor.start()
    }
    func shutdown() { wakeState.cancelOpening(); suspendRuntime(); lockScreenSpace = nil }
}
