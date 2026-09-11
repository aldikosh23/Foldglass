import AppKit

@main
struct LaunchContextTests {
    static func main() {
        func event(_ reason: OSType?) -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            if let reason { event.setParam(NSAppleEventDescriptor(enumCode: reason), forKeyword: AEKeyword(keyAEPropData)) }
            return event
        }
        precondition(!LaunchContext.isLoginItem(nil))
        precondition(!LaunchContext.isLoginItem(event(nil)), "normal open must show settings")
        precondition(LaunchContext.isLoginItem(event(OSType(keyAELaunchedAsLogInItem))), "login open must stay in the menu bar")
        precondition(!LaunchContext.isLoginItem(event(OSType(keyAELaunchedAsServiceItem))), "other event reasons are not login launches")
        print("launch context passed: manual launch and login Apple events")
    }
}
