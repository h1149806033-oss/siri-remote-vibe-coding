import Foundation
import Network
import BossRemoteCore
import BossRemoteHID

/// Sends real remote buttons and touch frames to 127.0.0.1 only.
/// The line format matches BossRemote.Relay.RelayCodec.
final class RelayClient {
    private let queue = DispatchQueue(label: "com.bossremote.relay")
    private let token: String
    private let port: UInt16
    private let onLog: (String) -> Void
    private var connection: NWConnection?
    private var buffer = Data()
    private var authed = false
    private var stopped = false
    private var held = Set<String>()
    private var reconnect: DispatchWorkItem?

    static func makeIfConfigured(
        settingsEnabled: Bool,
        log: @escaping (String) -> Void
    ) -> RelayClient? {
        let env = ProcessInfo.processInfo.environment
        let enabled = env["BOSS_REMOTE_RELAY"] == "1" || settingsEnabled
        guard enabled else { return nil }
        guard let path = env["BOSS_REMOTE_RELAY_TOKEN_FILE"], !path.isEmpty else {
            log("转发未启动：请设置 BOSS_REMOTE_RELAY_TOKEN_FILE，指向仅本人可读的 token 文件")
            return nil
        }
        guard let token = loadToken(at: path, log: log) else { return nil }
        let portValue = Int(env["BOSS_REMOTE_RELAY_PORT"] ?? "") ?? 4777
        guard (1...65535).contains(portValue) else {
            log("转发未启动：端口无效")
            return nil
        }
        let client = RelayClient(token: token, port: UInt16(portValue), onLog: log)
        client.start()
        return client
    }

    private init(token: String, port: UInt16, onLog: @escaping (String) -> Void) {
        self.token = token
        self.port = port
        self.onLog = onLog
    }

    func sendButton(_ control: RemoteControl, down: Bool) {
        guard !control.isGesture else { return }
        let id = control.rawValue
        queue.async { [weak self] in
            self?.writeButton(id, down: down)
        }
    }

    func sendTouch(_ contacts: [TouchSurface.Contact]) {
        let encoded = contacts.prefix(2).map { contact -> String? in
            guard contact.x.isFinite, contact.y.isFinite, contact.size.isFinite else { return nil }
            guard contact.x >= -0.05, contact.x <= 1.05, contact.y >= -0.05, contact.y <= 1.05 else {
                return nil
            }
            let x = min(max(contact.x, 0), 1)
            let y = min(max(contact.y, 0), 1)
            let size = min(max(contact.size, 0), 64)
            let id = min(max(contact.id, 0), 15)
            return String(format: "%d %.4f %.4f %.4f", id, x, y, size)
        }
        guard !encoded.contains(where: { $0 == nil }) else { return }
        let parts = encoded.compactMap { $0 }
        let line = "TOUCH \(parts.count)" + parts.map { " " + $0 }.joined()
        queue.async { [weak self] in
            self?.write(line)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.stopped = true
            self.reconnect?.cancel()
            for id in self.held {
                self.sendRaw("BTN \(id) 0")
            }
            self.held.removeAll()
            self.sendRaw("BYE")
            self.connection?.cancel()
            self.connection = nil
            self.authed = false
        }
    }

    private func start() {
        queue.async { [weak self] in
            self?.connect()
        }
    }

    private func connect() {
        guard !stopped else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: endpointPort,
            using: .tcp
        )
        self.connection = connection
        authed = false
        buffer.removeAll(keepingCapacity: true)
        connection.stateUpdateHandler = { [weak self] state in
            self?.queue.async {
                self?.handle(state)
            }
        }
        onLog("转发正在连接 127.0.0.1:\(port)")
        connection.start(queue: queue)
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            sendRaw("AUTH \(token)")
            receive()
        case .failed, .cancelled:
            authed = false
            held.removeAll()
            scheduleReconnect()
        default:
            break
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self] data, _, isComplete, error in
            self?.queue.async {
                guard let self, !self.stopped else { return }
                if let data {
                    self.buffer.append(data)
                    self.consumeLines()
                }
                if error != nil || isComplete {
                    self.authed = false
                    self.held.removeAll()
                    self.connection?.cancel()
                    self.scheduleReconnect()
                    return
                }
                self.receive()
            }
        }
    }

    private func consumeLines() {
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let chunk = Data(buffer.prefix(upTo: newline))
            buffer.removeSubrange(...newline)
            guard let line = String(data: chunk, encoding: .utf8)?.trimmingCharacters(in: .init(charactersIn: "\r")) else {
                continue
            }
            if line == "OK" {
                authed = true
                onLog("转发已通过认证")
            } else if line.hasPrefix("ERR") {
                onLog("转发被拒绝")
                stopped = true
                connection?.cancel()
            }
        }
    }

    private func writeButton(_ id: String, down: Bool) {
        guard authed, !stopped else { return }
        if down {
            held.insert(id)
        } else {
            held.remove(id)
        }
        sendRaw("BTN \(id) \(down ? 1 : 0)")
    }

    private func write(_ line: String) {
        guard authed, !stopped else { return }
        sendRaw(line)
    }

    private func sendRaw(_ line: String) {
        guard let connection else { return }
        var data = Data(line.utf8)
        data.append(UInt8(ascii: "\n"))
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        reconnect?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.connect()
        }
        reconnect = work
        queue.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private static func loadToken(at path: String, log: (String) -> Void) -> String? {
        guard FileManager.default.fileExists(atPath: path) else {
            log("转发未启动：找不到 token 文件")
            return nil
        }
        let mode = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?
            .uint16Value ?? 0
        if mode & 0o077 != 0 {
            log("转发未启动：token 文件不能对同组或其他用户可读")
            return nil
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            log("转发未启动：token 文件无法读取")
            return nil
        }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics
        guard token.count >= 16, token.count <= 128, token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            log("转发未启动：token 须为 16 到 128 位字母或数字")
            return nil
        }
        return token
    }
}
