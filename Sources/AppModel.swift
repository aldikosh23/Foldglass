import AppKit
import SwiftUI
import ScreenCaptureKit
import Combine

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
            if error != nil { self.dismissEffect(); self.wakeState.cancelOpening() }
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
            MainActor.assumeIsolated { self?.dismissEffect(); self?.armed = false }
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
                    let active = self.effectVisible || self.fullscreenDemo || self.capturePurpose == .physical || self.capturePurpose == .opening
                    self.escape()
                    return active
                }
                if cancelled { return nil }
            }
            return event
        }
        // This monitor works when macOS allows global key observation. Mouse movement
        // and the normal system menu remain available without Accessibility access.
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type != .keyDown || event.keyCode == 53 { MainActor.assumeIsolated { self?.escape() } }
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
            guard desktopSessionAvailable else { return }
            if wakeState.consumeOpening(at: newAngle, startAngle: settings.startAngle) && permission && !capturing && !effectVisible {
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

    private func captureDesktop() async throws -> (CGImage, NSScreen) {
        guard !suspended, desktopSessionAvailable else { throw CancellationError() }
        guard CGPreflightScreenCaptureAccess() else { throw AppMessage(key: "grant_permission") }
        let (screen, id) = try builtInScreen()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard !suspended, desktopSessionAvailable else { throw CancellationError() }
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
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        guard !suspended, desktopSessionAvailable else { throw CancellationError() }
        return (image, screen)
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
                let (image, _) = try await captureDesktop()
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
        guard enabled, !suspended, desktopSessionAvailable else { return }
        let demo = purpose == .demo
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
                let (image, screen) = try await captureDesktop()
                guard ticket == generation, enabled, !suspended, desktopSessionAvailable else { return }
                if !demo && (angle ?? settings.startAngle) >= settings.startAngle { return }
                let textures = try gpu.textures(for: image)
                overlayRenderer.textures = textures
                displayAngle = purpose == .opening ? (angle ?? settings.startAngle) : settings.startAngle
                targetAngle = demo ? settings.startAngle : (angle ?? settings.startAngle)
                overlayRenderer.firstFrameReady = { [weak self] in
                    guard let self, ticket == self.generation, self.effectVisible else { return }
                    guard !self.suspended, self.desktopSessionAvailable else { self.dismissEffect(); return }
                    // The lid may finish opening while the first frame is rendering.
                    if !demo && (self.angle ?? self.settings.startAngle) >= self.settings.startAngle {
                        self.dismissEffect(); return
                    }
                    self.beginAnimation(purpose: purpose)
                }
                showOverlay(on: screen)
            } catch is CancellationError { }
            catch {
                guard ticket == generation else { return }
                message = AppMessage.preserving(error)
                armed = false
                fullscreenDemo = false
                refreshPermission()
            }
        }
    }

    private func showOverlay(on screen: NSScreen) {
        let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.alphaValue = 0
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.sharingType = .none
        let view = overlayRenderer.makeView()
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        overlayRenderer.update(angle: displayAngle, settings: settings)
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
        overlay = window
        effectVisible = true
        // Finish the first GPU frame while hidden, then blend into the desktop.
        // Closing starts at identity; reopening uses the current physical angle.
        view.draw()
    }

    private func beginAnimation(purpose: CapturePurpose) {
        animation?.invalidate()
        let start = CACurrentMediaTime()
        lastFrame = start
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
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
                self.overlay?.alphaValue = FoldState.overlayOpacity(progress: progress, elapsed: now - start)
                self.overlayRenderer.update(angle: self.displayAngle, settings: self.settings)
            }
        }
        animation = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func dismissEffect() {
        generation += 1
        captureTask?.cancel(); captureTask = nil
        capturing = false
        capturePurpose = nil
        animation?.invalidate(); animation = nil
        overlay?.orderOut(nil); overlay?.close(); overlay = nil
        overlayRenderer.textures = nil
        overlayRenderer.firstFrameReady = nil
        effectVisible = false
        fullscreenDemo = false
    }

    func escape() {
        guard effectVisible || fullscreenDemo || capturePurpose == .physical || capturePurpose == .opening else { return }
        dismissEffect()
        wakeState.cancelOpening()
        armed = false
    }
    private var desktopSessionAvailable: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session[kCGSessionOnConsoleKey as String] as? Bool == true
            && session[kCGSessionLoginDoneKey as String] as? Bool == true
            && session["CGSSessionScreenIsLocked"] as? Bool != true
    }

    private func pause(_ reason: WakeState.Pause) {
        let physicalEffect = armed || effectVisible || capturePurpose == .physical || capturePurpose == .opening
        let wasClosing = enabled && physicalEffect && !fullscreenDemo && (angle ?? settings.startAngle) < settings.startAngle
        wakeState.pause(reason, wasClosing: wasClosing)
        suspendRuntime()
    }

    private func suspendRuntime() {
        dismissEffect()
        stopPreview()
        sensor.stop()
        armed = false
    }
    private func resume(_ reason: WakeState.Pause) {
        wakeState.resume(reason)
        guard !suspended else { return }
        refreshPermission()
        sensor.start()
    }
    func shutdown() { wakeState.cancelOpening(); suspendRuntime() }
}
