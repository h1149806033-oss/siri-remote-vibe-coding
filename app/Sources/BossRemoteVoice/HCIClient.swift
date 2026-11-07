import BossRemoteHCIProtocol
import Foundation
import Security

public final class HCIClient {
    public var onLog: ((String) -> Void)?

    private var connection: NSXPCConnection?
    private var prepared = false

    public init() {}

    deinit {
        stop()
    }

    public func prepare(completion: @escaping (Bool, String) -> Void) {
        guard connection == nil else {
            completion(false, prepared ? "already_prepared" : "preparing")
            return
        }
        let connection = NSXPCConnection(
            machServiceName: BossRemoteHCIConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: BossRemoteHCIServiceProtocol.self
        )
        connection.invalidationHandler = { [weak self] in
            self?.prepared = false
            self?.connection = nil
            self?.onLog?("HCI XPC invalidated")
        }
        connection.interruptionHandler = { [weak self] in
            self?.prepared = false
            self?.connection = nil
            self?.onLog?("HCI XPC interrupted")
        }
        connection.resume()
        self.connection = connection

        let latch = CompletionLatch()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            guard latch.claim() else { return }
            self?.onLog?("HCI XPC error: \(error.localizedDescription)")
            completion(false, "helper_unreachable")
        }) as? BossRemoteHCIServiceProtocol else {
            if latch.claim() {
                completion(false, "helper_interface_unavailable")
            }
            return
        }
        proxy.prepareConfiguration { [weak self] ok, status in
            guard latch.claim() else { return }
            self?.prepared = ok
            self?.onLog?("HCI prepare status=\(status)")
            completion(ok, status)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
            guard latch.claim() else { return }
            completion(false, "helper_timeout")
        }
    }

    public func release() {
        guard let connection else { return }
        if prepared,
           let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in })
            as? BossRemoteHCIServiceProtocol {
            proxy.releaseConfiguration { _, _ in }
        }
        prepared = false
        self.connection = nil
        connection.invalidate()
    }

    /// Sends the restore request and pumps the run loop until the helper
    /// replies, so the Bluetooth debug state is restored before the app exits.
    public func releaseForTermination(timeout: TimeInterval = 2) {
        guard let connection, prepared else { return }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.onLog?("HCI termination release failed: \(error.localizedDescription)")
        }) as? BossRemoteHCIServiceProtocol
        else { return }
        let latch = DispatchSemaphore(value: 0)
        proxy.releaseConfiguration { _, _ in
            latch.signal()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if latch.wait(timeout: .now()) == .success { break }
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.02)
            )
        }
        prepared = false
    }

    public func stop() {
        release()
    }

    private final class CompletionLatch {
        private let lock = NSLock()
        private var completed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return false }
            completed = true
            return true
        }
    }
}
