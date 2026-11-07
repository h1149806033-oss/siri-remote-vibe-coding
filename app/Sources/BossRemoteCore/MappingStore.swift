import Combine
import Foundation

public struct AppProfile: Identifiable, Equatable, Sendable {
    public var bundleID: String
    public var displayName: String
    public var actions: [RemoteControl: ButtonAction]
    public var holdActions: [RemoteControl: ButtonAction]

    public var id: String { bundleID }
    public var overrideCount: Int { actions.count + holdActions.count }

    public init(
        bundleID: String,
        displayName: String,
        actions: [RemoteControl: ButtonAction] = [:],
        holdActions: [RemoteControl: ButtonAction] = [:]
    ) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.actions = actions
        self.holdActions = holdActions
    }
}

public final class MappingStore: ObservableObject {
    @Published public private(set) var actions: [RemoteControl: ButtonAction]
    @Published public private(set) var holdActions: [RemoteControl: ButtonAction]
    @Published public private(set) var appProfiles: [String: AppProfile]

    public var onMappingChange: ((RemoteControl, ButtonAction, String?) -> Void)?

    private let defaults: UserDefaults
    private let storageKey: String
    private let holdKey: String
    private let profilesKey: String
    private static let defaultsVersionKey =
        "bossRemote.mappings.defaultsVersion"
    private static let currentDefaultsVersion = 3

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "bossRemote.mappings.v1",
        holdKey: String = "bossRemote.mappings.hold.v1",
        profilesKey: String = "bossRemote.appProfiles.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.holdKey = holdKey
        self.profilesKey = profilesKey
        self.actions = Self.loadActions(
            from: defaults,
            key: storageKey,
            base: RemoteControl.defaultActions
        )
        self.holdActions = Self.loadActions(
            from: defaults,
            key: holdKey,
            base: [:]
        )
        self.appProfiles = Self.loadProfiles(from: defaults, key: profilesKey)
        migrateDefaultActionsIfNeeded()
    }

    private func migrateDefaultActionsIfNeeded() {
        guard defaults.integer(forKey: Self.defaultsVersionKey)
            < Self.currentDefaultsVersion
        else { return }
        var migrated = actions
        if migrated[.back] == .key(.escape) {
            migrated[.back] = .key(.delete)
        }
        if migrated[.playPause] == .key(.space) {
            migrated[.playPause] = .key(.mediaPlayPause)
        }
        if migrated[.select] == .key(.mediaPlayPause) {
            migrated[.select] = .key(.returnKey)
        }
        actions = migrated
        saveActions()
        defaults.set(
            Self.currentDefaultsVersion,
            forKey: Self.defaultsVersionKey
        )
    }

    public var profileList: [AppProfile] {
        appProfiles.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public func profile(for bundleID: String?) -> AppProfile? {
        guard let bundleID else { return nil }
        return appProfiles[bundleID]
    }

    @discardableResult
    public func ensureProfile(bundleID: String, displayName: String) -> AppProfile {
        if var existing = appProfiles[bundleID] {
            if existing.displayName != displayName {
                existing.displayName = displayName
                appProfiles[bundleID] = existing
                saveProfiles()
            }
            return existing
        }
        let profile = AppProfile(bundleID: bundleID, displayName: displayName)
        appProfiles[bundleID] = profile
        saveProfiles()
        return profile
    }

    public func removeProfile(bundleID: String) {
        guard appProfiles.removeValue(forKey: bundleID) != nil else { return }
        saveProfiles()
    }

    public func resetProfiles() {
        guard !appProfiles.isEmpty else { return }
        appProfiles.removeAll()
        saveProfiles()
    }

    public func updateDisplayName(_ displayName: String, bundleID: String) {
        guard var profile = appProfiles[bundleID], profile.displayName != displayName else {
            return
        }
        profile.displayName = displayName
        appProfiles[bundleID] = profile
        saveProfiles()
    }

    public func action(for control: RemoteControl) -> ButtonAction {
        actions[control] ?? control.defaultAction
    }

    public func action(for control: RemoteControl, bundleID: String?) -> ButtonAction {
        if let bundleID, let override = appProfiles[bundleID]?.actions[control] {
            return override
        }
        return action(for: control)
    }

    public func isOverride(for control: RemoteControl, bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return appProfiles[bundleID]?.actions[control] != nil
    }

    public func holdAction(for control: RemoteControl) -> ButtonAction {
        holdActions[control] ?? .none
    }

    public func holdAction(
        for control: RemoteControl,
        bundleID: String?
    ) -> ButtonAction {
        if let bundleID, let override = appProfiles[bundleID]?.holdActions[control] {
            return override
        }
        return holdAction(for: control)
    }

    public func isHoldOverride(
        for control: RemoteControl,
        bundleID: String?
    ) -> Bool {
        guard let bundleID else { return false }
        return appProfiles[bundleID]?.holdActions[control] != nil
    }

    public func setHoldAction(
        _ action: ButtonAction,
        for control: RemoteControl,
        bundleID: String? = nil
    ) {
        if let bundleID {
            var profile = appProfiles[bundleID]
                ?? AppProfile(bundleID: bundleID, displayName: bundleID)
            profile.holdActions[control] = action
            appProfiles[bundleID] = profile
            saveProfiles()
        } else {
            holdActions[control] = action
            saveActions()
        }
    }

    public func clearHoldOverride(
        for control: RemoteControl,
        bundleID: String
    ) {
        guard var profile = appProfiles[bundleID],
              profile.holdActions.removeValue(forKey: control) != nil
        else { return }
        appProfiles[bundleID] = profile
        saveProfiles()
    }

    public func setAction(
        _ action: ButtonAction,
        for control: RemoteControl,
        bundleID: String? = nil
    ) {
        if let bundleID {
            var profile = appProfiles[bundleID]
                ?? AppProfile(bundleID: bundleID, displayName: bundleID)
            profile.actions[control] = action
            appProfiles[bundleID] = profile
            saveProfiles()
            onMappingChange?(control, action, bundleID)
        } else {
            actions[control] = action
            saveActions()
            onMappingChange?(control, action, nil)
        }
    }

    public func clearOverride(for control: RemoteControl, bundleID: String) {
        guard var profile = appProfiles[bundleID],
              profile.actions.removeValue(forKey: control) != nil
        else { return }
        appProfiles[bundleID] = profile
        saveProfiles()
        onMappingChange?(control, action(for: control), bundleID)
    }

    public func reset() {
        actions = RemoteControl.defaultActions
        holdActions = [:]
        saveActions()
    }

    private func saveActions() {
        Self.save(actions, defaults: defaults, key: storageKey)
        Self.save(holdActions, defaults: defaults, key: holdKey)
    }

    private static func save(
        _ map: [RemoteControl: ButtonAction],
        defaults: UserDefaults,
        key: String
    ) {
        let encoded = Dictionary(
            uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) }
        )
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        defaults.set(data, forKey: key)
    }

    private func saveProfiles() {
        let stored = appProfiles.values.map { profile in
            StoredProfile(
                bundleID: profile.bundleID,
                displayName: profile.displayName,
                actions: Dictionary(
                    uniqueKeysWithValues: profile.actions.map { ($0.key.rawValue, $0.value) }
                ),
                holdActions: Dictionary(
                    uniqueKeysWithValues: profile.holdActions.map { ($0.key.rawValue, $0.value) }
                )
            )
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: profilesKey)
    }

    private static func loadActions(
        from defaults: UserDefaults,
        key: String,
        base: [RemoteControl: ButtonAction]
    ) -> [RemoteControl: ButtonAction] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ButtonAction].self, from: data)
        else {
            return base
        }
        var result = base
        for (rawValue, action) in decoded {
            guard let control = RemoteControl(rawValue: rawValue) else { continue }
            result[control] = action
        }
        return result
    }

    private static func loadProfiles(
        from defaults: UserDefaults,
        key: String
    ) -> [String: AppProfile] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([StoredProfile].self, from: data)
        else {
            return [:]
        }
        var result: [String: AppProfile] = [:]
        for item in stored {
            var actions: [RemoteControl: ButtonAction] = [:]
            for (rawValue, action) in item.actions {
                guard let control = RemoteControl(rawValue: rawValue) else { continue }
                actions[control] = action
            }
            var holds: [RemoteControl: ButtonAction] = [:]
            for (rawValue, action) in item.holdActions ?? [:] {
                guard let control = RemoteControl(rawValue: rawValue) else { continue }
                holds[control] = action
            }
            result[item.bundleID] = AppProfile(
                bundleID: item.bundleID,
                displayName: item.displayName,
                actions: actions,
                holdActions: holds
            )
        }
        return result
    }
}

private struct StoredProfile: Codable {
    var bundleID: String
    var displayName: String
    var actions: [String: ButtonAction]
    var holdActions: [String: ButtonAction]?
}
