import AppKit

// Space placement based on SkyLightWindow by Lakr Aream (MIT).
// See THIRD_PARTY_NOTICES.md.
@MainActor final class LockScreenSpace {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Level = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Show = @convention(c) (Int32, CFArray) -> Void
    private typealias Move = @convention(c) (Int32, Int32, CFArray, Int32) -> Void
    private typealias Destroy = @convention(c) (Int32, Int32) -> Void

    private let handle: UnsafeMutableRawPointer
    private let connection: Int32
    private let space: Int32
    private let move: Move
    private let destroy: Destroy

    init() throws {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW) else {
            throw AppMessage(key: "lock_overlay_unavailable", detail: "SkyLight could not be loaded")
        }
        var initialized = false
        defer { if !initialized { dlclose(handle) } }
        func symbol<T>(_ name: String, as type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else { throw AppMessage(key: "lock_overlay_unavailable", detail: name) }
            return unsafeBitCast(pointer, to: T.self)
        }
        let getConnection = try symbol("SLSMainConnectionID", as: Connection.self)
        let create = try symbol("SLSSpaceCreate", as: Create.self)
        let setLevel = try symbol("SLSSpaceSetAbsoluteLevel", as: Level.self)
        let show = try symbol("SLSShowSpaces", as: Show.self)
        let move = try symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: Move.self)
        let destroy = try symbol("SLSSpaceDestroy", as: Destroy.self)
        let connection = getConnection()
        let space = create(connection, 1, 0)
        guard space != 0 else { throw AppMessage(key: "lock_overlay_unavailable", detail: "SLSSpaceCreate") }
        // Notification Center's lock-screen space level sits above the lock surface.
        let result = setLevel(connection, space, 400)
        guard result == 0 else {
            destroy(connection, space)
            throw AppMessage(key: "lock_overlay_unavailable", detail: "SLSSpaceSetAbsoluteLevel: \(result)")
        }
        show(connection, [space] as CFArray)
        self.handle = handle
        self.connection = connection
        self.space = space
        self.move = move
        self.destroy = destroy
        initialized = true
    }

    func attach(_ window: NSWindow) {
        move(connection, space, [window.windowNumber] as CFArray, 7)
    }

    deinit { destroy(connection, space); dlclose(handle) }
}
