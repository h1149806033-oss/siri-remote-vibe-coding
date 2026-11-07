import BossRemoteCore
import CoreBluetooth
import Foundation

final class BLEBatteryMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum State: Equatable {
        case unknown
        case poweredOn
        case poweredOff
        case unauthorized
        case unsupported
        case resetting
    }

    var onBattery: ((Int?) -> Void)?
    var onChargeState: ((BatteryChargeState?) -> Void)?
    var onState: ((State) -> Void)?
    var onLog: ((String) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var levelCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var pollTimer: Timer?
    private var reconnectTimer: Timer?
    private var lastLevel: Int?
    private var started = false
    private var attached: [UUID: CBPeripheral] = [:]
    private(set) var state: State = .unknown

    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")
    private let batteryStatusUUID = CBUUID(string: "2BED")
    private let hidServiceUUID = CBUUID(string: "1812")

    func start() {
        guard !started else { return }
        started = true
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
            [weak self] _ in
            guard let self, self.started, self.peripheral == nil,
                  let central = self.central, central.state == .poweredOn
            else { return }
            self.discoverConnectedRemotes(central, quiet: true)
        }
    }

    func refresh() {
        if let peripheral, let levelCharacteristic {
            log("manual refresh")
            peripheral.readValue(for: levelCharacteristic)
            if let statusCharacteristic {
                peripheral.readValue(for: statusCharacteristic)
            }
            return
        }
        guard let central else {
            start()
            return
        }
        guard central.state == .poweredOn else {
            log("refresh unavailable state=\(stateName(central.state))")
            let mapped = Self.mapState(central.state)
            state = mapped
            onState?(mapped)
            return
        }
        log("manual refresh rediscover")
        discoverConnectedRemotes(central)
    }

    func stop() {
        started = false
        pollTimer?.invalidate()
        pollTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        central?.stopScan()
        if let peripheral, let central, central.state == .poweredOn {
            central.cancelPeripheralConnection(peripheral)
        }
        central = nil
        peripheral = nil
        levelCharacteristic = nil
        statusCharacteristic = nil
        attached.removeAll()
        lastLevel = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = Self.mapState(central.state)
        log("state=\(stateName(central.state))")
        onState?(state)
        guard central.state == .poweredOn else {
            switch central.state {
            case .poweredOff, .unauthorized, .unsupported:
                pollTimer?.invalidate()
                pollTimer = nil
                attached.removeAll()
                peripheral = nil
                levelCharacteristic = nil
                statusCharacteristic = nil
                onBattery?(nil)
                onChargeState?(nil)
            case .unknown, .resetting, .poweredOn:
                break
            @unknown default:
                break
            }
            return
        }
        discoverConnectedRemotes(central)
    }

    private func discoverConnectedRemotes(
        _ central: CBCentralManager,
        quiet: Bool = false
    ) {
        let candidates = central.retrieveConnectedPeripherals(
            withServices: [batteryServiceUUID, hidServiceUUID]
        )
        if !quiet {
            let names = candidates.compactMap(\.name).joined(separator: ", ")
            log("connected candidates=\(candidates.count) [\(names)]")
        }

        let remotes = candidates.filter {
            let name = ($0.name ?? "").lowercased()
            return name.contains("siri") || name.contains("remote")
        }
        let targets = remotes.isEmpty ? candidates : remotes
        guard !targets.isEmpty else {
            if !quiet {
                log("no connected BLE remote; scanning")
            }
            central.scanForPeripherals(
                withServices: [batteryServiceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak central] in
                central?.stopScan()
            }
            return
        }
        for candidate in targets {
            attach(candidate)
        }
    }

    private func attach(_ candidate: CBPeripheral) {
        guard attached[candidate.identifier] == nil else { return }
        attached[candidate.identifier] = candidate
        candidate.delegate = self
        log("discover services for \(candidate.name ?? candidate.identifier.uuidString)")
        central?.connect(candidate)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = (peripheral.name ?? "").lowercased()
        guard name.contains("siri") || name.contains("remote") else { return }
        central.stopScan()
        log("scan found \(peripheral.name ?? "unknown"); connecting")
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("connected \(peripheral.name ?? "unknown")")
        peripheral.discoverServices([batteryServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        attached.removeValue(forKey: peripheral.identifier)
        log("connect failed: \(error?.localizedDescription ?? "unknown")")
        if self.peripheral?.identifier == peripheral.identifier {
            self.peripheral = nil
            levelCharacteristic = nil
            statusCharacteristic = nil
            pollTimer?.invalidate()
            pollTimer = nil
            onBattery?(nil)
            onChargeState?(nil)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        attached.removeValue(forKey: peripheral.identifier)
        log("disconnected: \(error?.localizedDescription ?? "no error")")
        if self.peripheral?.identifier == peripheral.identifier {
            self.peripheral = nil
            levelCharacteristic = nil
            statusCharacteristic = nil
            pollTimer?.invalidate()
            pollTimer = nil
            onBattery?(nil)
            onChargeState?(nil)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            log("service discovery failed: \(error.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: {
            $0.uuid == batteryServiceUUID
        }) else {
            log("battery service missing on \(peripheral.name ?? "unknown")")
            return
        }
        peripheral.discoverCharacteristics(
            [batteryLevelUUID, batteryStatusUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            log("characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        guard service.uuid == batteryServiceUUID else { return }
        let ids = service.characteristics?.map {
            "\($0.uuid.uuidString)(\($0.properties.contains(.notify) ? "n" : "-"))"
        }.joined(separator: ",") ?? ""
        log("battery characteristics [\(ids)]")
        if let level = service.characteristics?.first(where: {
            $0.uuid == batteryLevelUUID
        }) {
            self.peripheral = peripheral
            levelCharacteristic = level
            peripheral.readValue(for: level)
            if level.properties.contains(.notify) || level.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: level)
            }
            schedulePollingIfNeeded(
                supportsNotifications: level.properties.contains(.notify)
                    || level.properties.contains(.indicate),
                isNotifying: level.isNotifying
            )
            log("battery level characteristic ready")
        } else {
            log("battery level characteristic missing")
            onBattery?(nil)
        }
        if let status = service.characteristics?.first(where: {
            $0.uuid == batteryStatusUUID
        }) {
            statusCharacteristic = status
            log("battery status characteristic ready")
            peripheral.readValue(for: status)
            if status.properties.contains(.notify) || status.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: status)
            }
        } else {
            statusCharacteristic = nil
            log("battery status characteristic missing (charge inferred from level)")
            onChargeState?(nil)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == batteryLevelUUID else { return }
        if let error {
            log("battery notify failed: \(error.localizedDescription)")
        }
        schedulePollingIfNeeded(
            supportsNotifications: characteristic.properties.contains(.notify)
                || characteristic.properties.contains(.indicate),
            isNotifying: characteristic.isNotifying
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            log("battery read failed: \(error.localizedDescription)")
            if characteristic.uuid == batteryStatusUUID {
                onChargeState?(nil)
            }
            return
        }
        if characteristic.uuid == batteryStatusUUID,
           let data = characteristic.value {
            let raw = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            let state = decodeChargeState(data)
            log("charge=\(state.rawValue) raw=[\(raw)]")
            onChargeState?(state)
            return
        }
        guard characteristic.uuid == batteryLevelUUID,
              let data = characteristic.value,
              let first = data.first
        else { return }
        let level = min(100, max(0, Int(first)))
        let changed = level != lastLevel
        lastLevel = level
        if changed {
            log("level=\(level)")
        }
        onBattery?(level)
    }

    private func decodeChargeState(_ data: Data) -> BatteryChargeState {
        guard data.count >= 3 else { return .unknown }
        let powerState = UInt16(data[data.startIndex + 1]) |
            UInt16(data[data.startIndex + 2]) << 8
        guard powerState & 0x0001 == 0x0001 else { return .unknown }
        let wired = (powerState >> 1) & 0x0003
        let wireless = (powerState >> 3) & 0x0003
        let charge = (powerState >> 5) & 0x0003
        if charge == 0x0001 { return .charging }
        if wired == 0x0001 || wireless == 0x0001 { return .externalPower }
        if wired == 0x0000, wireless == 0x0000 {
            return .onBattery
        }
        return .unknown
    }

    private func schedulePollingIfNeeded(
        supportsNotifications: Bool,
        isNotifying: Bool
    ) {
        pollTimer?.invalidate()
        pollTimer = nil
        if supportsNotifications, isNotifying {
            log("battery notifications active; polling disabled")
            return
        }
        let interval: TimeInterval = 60
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            guard let self, let peripheral = self.peripheral,
                  let characteristic = self.levelCharacteristic
            else { return }
            peripheral.readValue(for: characteristic)
            if let status = self.statusCharacteristic {
                peripheral.readValue(for: status)
            }
        }
        pollTimer = timer
        log("polling scheduled every \(Int(interval))s")
    }

    private func log(_ message: String) {
        onLog?(message)
    }

    private static func mapState(_ state: CBManagerState) -> State {
        switch state {
        case .unknown: return .unknown
        case .resetting: return .resetting
        case .unsupported: return .unsupported
        case .unauthorized: return .unauthorized
        case .poweredOff: return .poweredOff
        case .poweredOn: return .poweredOn
        @unknown default: return .unknown
        }
    }

    private func stateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "other"
        }
    }
}
