import Foundation
import Security
import XPC

public final class BTPacketLoggerClient {
    public enum Status: Equatable, Sendable {
        case connecting
        case requiresAuthorization
        case authorized
        case failed(String)
        case stopped
    }

    public var onPacket: ((Data) -> Void)?
    public var onStatus: ((Status) -> Void)?
    public var onLog: ((String) -> Void)?

    private let serviceName = "com.apple.bluetooth.BTPacketLogger"
    private let rightName = "com.apple.PacketLogger.HCI"
    private let queue = DispatchQueue(label: "com.bossremote.packetlogger")
    private var connection: xpc_connection_t?
    private var authorization: AuthorizationRef?
    private var authorized = false
    private var authorizationAttempted = false
    private var generation: UInt64 = 0

    public init() {}

    deinit {
        stopSynchronously()
    }

    public func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopSynchronously() {
        queue.sync { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func startOnQueue() {
        guard connection == nil else { return }
        generation &+= 1
        let activeGeneration = generation
        authorized = false
        authorizationAttempted = false
        onStatus?(.connecting)

        let connection = serviceName.withCString { name in
            xpc_connection_create_mach_service(
                name,
                queue,
                UInt64(XPC_CONNECTION_MACH_SERVICE_PRIVILEGED)
            )
        }
        self.connection = connection
        xpc_connection_set_event_handler(connection) { [weak self] object in
            self?.handle(object, generation: activeGeneration)
        }
        xpc_connection_activate(connection)
        onLog?("packet logger connecting")

        let message = xpc_dictionary_create_empty()
        xpc_connection_send_message_with_reply(connection, message, queue) { [weak self] reply in
            self?.handle(reply, generation: activeGeneration)
        }

        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self,
                  self.generation == activeGeneration,
                  !self.authorized,
                  !self.authorizationAttempted
            else { return }
            self.fail("connection_timeout")
        }
    }

    private func handle(_ object: xpc_object_t, generation: UInt64) {
        guard generation == self.generation else { return }
        let type = xpc_get_type(object)
        if type == XPC_TYPE_ERROR {
            if xpc_equal(object, XPC_ERROR_CONNECTION_INTERRUPTED) {
                fail("connection_interrupted")
            } else if xpc_equal(object, XPC_ERROR_CONNECTION_INVALID) {
                fail("connection_invalid")
            } else {
                fail("xpc_error")
            }
            return
        }
        guard type == XPC_TYPE_DICTIONARY else { return }

        if let requires = xpc_dictionary_get_value(object, "RequiresAuth") {
            guard xpc_get_type(requires) == XPC_TYPE_BOOL else {
                fail("malformed_auth")
                return
            }
            if xpc_bool_get_value(requires) {
                guard !authorizationAttempted else { return }
                onStatus?(.requiresAuthorization)
                requestAuthorization()
            } else {
                markAuthorized()
            }
            return
        }

        var length = 0
        guard let bytes = xpc_dictionary_get_data(object, "packet", &length),
              length > 0,
              length <= Int(UInt16.max) + 64
        else { return }
        if !authorized {
            markAuthorized()
        }
        onPacket?(Data(bytes: bytes, count: length))
    }

    private func markAuthorized() {
        guard !authorized else { return }
        authorized = true
        onStatus?(.authorized)
        onLog?("packet logger authorized")
    }

    private func requestAuthorization() {
        guard !authorizationAttempted else { return }
        authorizationAttempted = true
        var authorization: AuthorizationRef?
        let create = AuthorizationCreate(nil, nil, [], &authorization)
        guard create == errAuthorizationSuccess, let authorization else {
            fail("authorization_create_\(create)")
            return
        }
        self.authorization = authorization
        let status = rightName.withCString { name -> OSStatus in
            var item = AuthorizationItem(
                name: name,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    [.interactionAllowed, .extendRights, .preAuthorize],
                    nil
                )
            }
        }
        guard status == errAuthorizationSuccess else {
            fail("authorization_denied_\(status)")
            return
        }
        sendAuthorizationForm(authorization)
    }

    private func sendAuthorizationForm(_ authorization: AuthorizationRef) {
        var form = AuthorizationExternalForm()
        let status = AuthorizationMakeExternalForm(authorization, &form)
        guard status == errAuthorizationSuccess, let connection else {
            fail("authorization_form_\(status)")
            return
        }
        let message = xpc_dictionary_create_empty()
        withUnsafeBytes(of: &form) { bytes in
            xpc_dictionary_set_data(
                message,
                "Authentication",
                bytes.baseAddress,
                bytes.count
            )
        }
        xpc_connection_send_message(connection, message)
        onLog?("packet logger authorization submitted")
    }

    private func fail(_ reason: String) {
        onStatus?(.failed(reason))
        onLog?("packet logger failed: \(reason)")
        stopOnQueue()
    }

    private func stopOnQueue() {
        generation &+= 1
        if let connection {
            xpc_connection_cancel(connection)
            self.connection = nil
        }
        if let authorization {
            AuthorizationFree(authorization, [.destroyRights])
            self.authorization = nil
        }
        authorized = false
        onStatus?(.stopped)
    }
}
