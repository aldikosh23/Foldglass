import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: AppModel!
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let backgroundLaunch = LaunchContext.isLoginItem(NSAppleEventManager.shared().currentAppleEvent)
        do {
            let gpu = try FoldGPU()
            let demo = try gpu.textures(for: DemoImage.make())
            model = AppModel(gpu: gpu, demo: demo)
            let host = NSHostingController(rootView: SettingsView(model: model))
            window = NSWindow(contentViewController: host)
            window.title = "foldglass"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.backgroundColor = NSColor(red: 0.105, green: 0.12, blue: 0.145, alpha: 1)
            window.center()
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "foldglass")
            statusItem.button?.toolTip = "foldglass"
            model.$enabled.sink { [weak self] _ in DispatchQueue.main.async { self?.updateMenu() } }.store(in: &subscriptions)
            updateMenu()
            if !backgroundLaunch { showSettings() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "foldglass не запустился"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    func updateMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "foldglass", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(NSMenuItem.separator())
        let toggle = NSMenuItem(title: model.enabled ? "приостановить эффект" : "включить эффект", action: #selector(toggleEffect), keyEquivalent: "")
        toggle.target = self; menu.addItem(toggle)
        let settings = NSMenuItem(title: "настройки...", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let demo = NSMenuItem(title: "демо на экране", action: #selector(demo), keyEquivalent: "d")
        demo.target = self; menu.addItem(demo)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "завершить foldglass", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        let main = NSMenu()
        let item = NSMenuItem(title: "foldglass", action: nil, keyEquivalent: "")
        item.submenu = menu.copy() as? NSMenu
        main.addItem(item)
        NSApp.mainMenu = main
    }
    @objc func toggleEffect() { model.enabled.toggle() }
    @objc func demo() { model.demoDesktop() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showSettings() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); model.refreshPermission() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
    func windowWillClose(_ notification: Notification) { model.stopPreview() }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
