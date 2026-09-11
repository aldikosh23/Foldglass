import AppKit
import Combine
import ServiceManagement

enum LaunchContext {
    static func isLoginItem(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == AEEventID(kAEOpenApplication) else { return false }
        let reason = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))
        return reason?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}

@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error: AppMessage?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) {
        error = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = AppMessage(key: "login_failed", detail: error.localizedDescription)
        }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
