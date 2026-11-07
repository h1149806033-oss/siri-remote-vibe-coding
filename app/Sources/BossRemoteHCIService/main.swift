import BossRemoteHCIProtocol
import Darwin
import Foundation
import Security

private enum HCIError: Error {
    case notRoot
    case stateCorrupt
    case missingTeamIdentifier
    case authorizationCreate(OSStatus)
    case authorizationRightLookup(OSStatus)
    case authorizationRightWrite(OSStatus)
    case bluetoothReload(Int32)
}

private let helperTeamIdentifier: String? = {
    var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(getpid(), &pathBuffer, UInt32(pathBuffer.count)) > 0 else {
        return nil
    }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(
        URL(fileURLWithPath: String(cString: pathBuffer)) as CFURL,
        [],
        &code
    ) == errSecSuccess, let code else { return nil }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(
        code,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &information
    ) == errSecSuccess,
        let values = information as? [String: Any]
    else { return nil }
    return values[kSecCodeInfoTeamIdentifier as String] as? String
}()

private struct PersistedState: Codable {
    var active: Bool
    var originalPlistPresent: Bool
    var originalPlist: Data?
    var originalRightPresent: Bool?
    var originalRight: Data?

    static let inactive = PersistedState(
        active: false,
        originalPlistPresent: false,
        originalPlist: nil,
        originalRightPresent: nil,
        originalRight: nil
    )
}

private final class ConfigurationStore {
    private let preferences = URL(
        fileURLWithPath: "/Library/Preferences/com.apple.MobileBluetooth.debug.plist"
    )
    private let stateDirectory = URL(
        fileURLWithPath: "/Library/Application Support/BossRemote/HCI",
        isDirectory: true
    )
    private let rightName = "com.apple.PacketLogger.HCI"
    private let traceKeys = [
        "StackDebugEnabled",
        "HCILiveTraces",
        "HCIFileTraces",
        "RawAudioTrace",
        "HIDTrace",
        "HCISkipAuth",
    ]

    private var stateURL: URL { stateDirectory.appendingPathComponent("state.plist") }

    func recoverAtStartup() {
        do {
            guard try readState().active else { return }
            try restore()
            log("recovery restored previous HCI state")
        } catch {
            log("recovery failed: \(error)")
        }
    }

    func enable() throws {
        guard geteuid() == 0 else { throw HCIError.notRoot }
        let existing = try readState()
        if existing.active {
            try restore()
        }

        let originalPlist = try? Data(contentsOf: preferences)
        let originalRight = try readRight()
        try writeState(PersistedState(
            active: true,
            originalPlistPresent: originalPlist != nil,
            originalPlist: originalPlist,
            originalRightPresent: originalRight != nil,
            originalRight: originalRight
        ))

        do {
            try writeTraces(enabled: true, original: originalPlist)
            try writeClientRight()
            try reloadBluetooth()
        } catch {
            try? restore()
            throw error
        }
    }

    func restore() throws {
        guard geteuid() == 0 else { throw HCIError.notRoot }
        let state = try readState()
        guard state.active else { return }

        if state.originalPlistPresent, let data = state.originalPlist {
            try writePreferences(data)
        }
        // HCITraces are owned by this app: never leave them enabled after a
        // restore, even if a stale captured plist already contained them.
        try removeTraces()
        try restoreRight(state)
        try reloadBluetooth()
        try writeState(.inactive)
    }

    private func writeTraces(enabled: Bool, original: Data?) throws {
        guard enabled else { return }
        var root: [String: Any] = [:]
        if let original,
           let object = try? PropertyListSerialization.propertyList(
               from: original,
               options: [],
               format: nil
           ) as? [String: Any] {
            root = object
        }
        root["HCITraces"] = Dictionary(
            uniqueKeysWithValues: traceKeys.map { ($0, true) }
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try writePreferences(data)
    }

    private func removeTraces() throws {
        guard FileManager.default.fileExists(atPath: preferences.path) else { return }
        guard let data = try? Data(contentsOf: preferences),
              var root = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any]
        else {
            try FileManager.default.removeItem(at: preferences)
            return
        }
        root.removeValue(forKey: "HCITraces")
        if root.isEmpty {
            try FileManager.default.removeItem(at: preferences)
            return
        }
        let output = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try writePreferences(output)
    }

    private func writePreferences(_ data: Data) throws {
        try data.write(to: preferences, options: .atomic)
        try FileManager.default.setAttributes([
            .ownerAccountID: NSNumber(value: 0),
            .groupOwnerAccountID: NSNumber(value: 0),
            .posixPermissions: NSNumber(value: 0o644),
        ], ofItemAtPath: preferences.path)
    }

    private func readRight() throws -> Data? {
        var definition: CFDictionary?
        let status = rightName.withCString { AuthorizationRightGet($0, &definition) }
        if status == errAuthorizationDenied { return nil }
        guard status == errAuthorizationSuccess, let definition else {
            throw HCIError.authorizationRightLookup(status)
        }
        return try PropertyListSerialization.data(
            fromPropertyList: definition,
            format: .binary,
            options: 0
        )
    }

    private func writeClientRight() throws {
        let client = BossRemoteHCIConstants.expectedClientIdentifier
        guard let team = helperTeamIdentifier else {
            throw HCIError.missingTeamIdentifier
        }
        let requirement = "identifier \"\(client)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        let definition: [String: Any] = [
            "class": "user",
            "group": "admin",
            "authenticate-user": true,
            "allow-root": true,
            "shared": false,
            "timeout": 0,
            "identifier": client,
            "requirement": requirement,
        ]
        let description = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
            ? "允许 Boss Remote 接收 Siri Remote 蓝牙音频。"
            : "Allow Boss Remote to receive Bluetooth audio from the Siri Remote."
        try setRight(definition as CFDictionary, description: description)
    }

    private func restoreRight(_ state: PersistedState) throws {
        guard let originalPresent = state.originalRightPresent else { return }
        if originalPresent, let data = state.originalRight,
           let definition = try PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) as? [String: Any] {
            try setRight(definition as CFDictionary, description: nil)
            return
        }
        guard !originalPresent else { throw HCIError.stateCorrupt }
        var authorization: AuthorizationRef?
        let create = AuthorizationCreate(nil, nil, [], &authorization)
        guard create == errAuthorizationSuccess, let authorization else {
            throw HCIError.authorizationCreate(create)
        }
        defer { AuthorizationFree(authorization, [.destroyRights]) }
        let status = rightName.withCString {
            AuthorizationRightRemove(authorization, $0)
        }
        guard status == errAuthorizationSuccess || status == errAuthorizationDenied else {
            throw HCIError.authorizationRightWrite(status)
        }
    }

    private func setRight(_ definition: CFDictionary, description: String?) throws {
        var authorization: AuthorizationRef?
        let create = AuthorizationCreate(nil, nil, [], &authorization)
        guard create == errAuthorizationSuccess, let authorization else {
            throw HCIError.authorizationCreate(create)
        }
        defer { AuthorizationFree(authorization, [.destroyRights]) }
        let status = rightName.withCString {
            AuthorizationRightSet(
                authorization,
                $0,
                definition,
                description as CFString?,
                nil,
                nil
            )
        }
        guard status == errAuthorizationSuccess else {
            throw HCIError.authorizationRightWrite(status)
        }
    }

    private func reloadBluetooth() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-30", "bluetoothd"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HCIError.bluetoothReload(process.terminationStatus)
        }
    }

    private func readState() throws -> PersistedState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return .inactive
        }
        do {
            return try PropertyListDecoder().decode(
                PersistedState.self,
                from: Data(contentsOf: stateURL)
            )
        } catch {
            throw HCIError.stateCorrupt
        }
    }

    private func writeState(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o755)]
        )
        let data = try PropertyListEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([
            .ownerAccountID: NSNumber(value: 0),
            .groupOwnerAccountID: NSNumber(value: 0),
            .posixPermissions: NSNumber(value: 0o600),
        ], ofItemAtPath: stateURL.path)
    }
}

private final class RequestHandler: NSObject, BossRemoteHCIServiceProtocol {
    private let store = ConfigurationStore()
    private let lock = NSLock()
    private var prepared = false

    func prepareConfiguration(reply: @escaping (Bool, String) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if prepared {
            reply(true, "ready")
            return
        }
        do {
            try store.enable()
            prepared = true
            reply(true, "ready")
        } catch {
            reply(false, "configuration_enable_failed")
        }
    }

    func releaseConfiguration(reply: @escaping (Bool, String) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard prepared else {
            reply(true, "not_prepared")
            return
        }
        do {
            try store.restore()
            prepared = false
            reply(true, "released")
        } catch {
            reply(false, "configuration_restore_failed")
        }
    }
}

private func clientRequirement() -> String? {
    guard let team = helperTeamIdentifier else { return nil }
    let identifier = BossRemoteHCIConstants.expectedClientIdentifier
    return "identifier \"\(identifier)\" and anchor apple generic " +
        "and certificate leaf[subject.OU] = \"\(team)\""
}

private final class Service: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard let requirement = clientRequirement() else {
            log("rejected client: missing helper team identifier")
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        let handler = RequestHandler()
        connection.exportedInterface = NSXPCInterface(
            with: BossRemoteHCIServiceProtocol.self
        )
        connection.exportedObject = handler
        connection.invalidationHandler = {
            handler.releaseConfiguration { _, _ in }
        }
        connection.resume()
        log("accepted client pid=\(connection.processIdentifier)")
        return true
    }
}

private func log(_ message: String) {
    print("BOSS_REMOTE_HCI \(message)")
    fflush(stdout)
}

private let store = ConfigurationStore()
if CommandLine.arguments.contains("--restore") {
    do {
        try store.restore()
        log("restore command completed")
        exit(0)
    } catch {
        log("restore command failed: \(error)")
        exit(1)
    }
}

store.recoverAtStartup()
log("startup version=\(BossRemoteHCIConstants.serviceVersion)")
private let service = Service()
let listener = NSXPCListener(
    machServiceName: BossRemoteHCIConstants.machServiceName
)
listener.delegate = service
listener.resume()
RunLoop.main.run()
