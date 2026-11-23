import Foundation

/// Two-way sync of the host app settings that ZCode Remote exposes (`setting` channel + `broadcast` pushes).
/// The host has no RPC change event for `setting`, so it is refetched on connect, foreground,
/// Settings open, and whenever a `broadcast` message says preferences changed.
final class HostSettingsSyncState {
    var lastHost: [String: Any] = [:]
    var applying = false
    var broadcastSubId: Int32?
    var providerSubId: Int32?
    var refreshTask: Task<Void, Never>?
    var pushTask: Task<Void, Never>?
    /// Host `zcodeInteractionBehavior`: follow-ups typed while a turn runs are queued or used to guide it.
    var interactionBehavior = "queue"
}

extension AppStore {
    private static let uiStateKeys: Set<String> = ["theme", "locale", "uiFontSizePx", "interfaceMode", "notificationEnabled"]

    func subscribeHostSettings() async {
        hostSettings.broadcastSubId = try? await rpcClient.listen(channel: "broadcast", event: "onMessage") { [weak self] value in
            Task { @MainActor in
                guard let message = value.decodeJSONValue() as? [String: Any] else { return }
                self?.handleHostBroadcast(message)
            }
        }
        hostSettings.providerSubId = try? await rpcClient.listen(channel: "provider-settings", event: "onDidChange") { [weak self] _ in
            Task { @MainActor in await self?.refreshLiveModelView() }
        }
        await refreshHostSettings()
    }

    func resetHostSettingsSubscriptions() {
        hostSettings.broadcastSubId = nil
        hostSettings.providerSubId = nil
    }

    func refreshHostSettings() async {
        guard isLiveHostConnected,
              let value = try? await rpcClient.call(channel: "setting", method: "get", args: [], timeoutSec: 8),
              let dict = value.decodeJSONDictionary() else { return }
        applyHostSettings(dict)
    }

    func scheduleHostSettingsRefresh() {
        hostSettings.refreshTask?.cancel()
        hostSettings.refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self.refreshHostSettings()
        }
    }

    private func handleHostBroadcast(_ message: [String: Any]) {
        guard let channel = message["channel"] as? String else { return }
        let payload = message["payload"]
        switch channel {
        case "settings:app-runtime-preferences":
            scheduleHostSettingsRefresh()
        case "state:theme":
            if let theme = payload as? String { applyHostSettings(["theme": theme]) }
        case "state:locale":
            if let locale = payload as? String { applyHostSettings(["localePreference": locale]) }
        case "state:notificationEnabled":
            if let enabled = payload as? Bool { applyHostSettings(["notificationEnabled": enabled]) }
        case "state:projects", "state:task-groups":
            Task { @MainActor in await self.loadAllWorkspaceTasks(preferredActiveTaskId: self.activeSessionId) }
        default:
            break
        }
    }

    func applyHostSettings(_ dict: [String: Any]) {
        hostSettings.applying = true
        defer { hostSettings.applying = false }
        for (key, value) in dict { hostSettings.lastHost[key] = value }

        if let theme = dict["theme"] as? String {
            let mode: ZCodeThemeMode? = {
                switch theme {
                case "zai-dark": return themeMode == .graphite ? .graphite : .dark
                case "zai-light": return .light
                case "system": return .system
                default: return nil
                }
            }()
            if let mode, mode != themeMode { themeMode = mode }
        }
        // Vietnamese is an app-only language the host cannot express, so it is never overridden.
        if let locale = dict["localePreference"] as? String, language != .vietnamese {
            switch locale {
            case "zh-CN": if language != .chineseSimplified { language = .chineseSimplified }
            case "en-US": if language != .english { language = .english }
            default: break
            }
        }
        if let enabled = dict["notificationEnabled"] as? Bool, enabled != notificationsEnabled { notificationsEnabled = enabled }
        if let show = dict["messageStreamShowReasoning"] as? Bool, show != showReasoningBlocks { showReasoningBlocks = show }
        if let show = dict["messageStreamShowTodos"] as? Bool, show != showTodoTracker { showTodoTracker = show }
        if let behavior = dict["zcodeInteractionBehavior"] as? String { hostSettings.interactionBehavior = behavior }
    }

    /// Local values in host vocabulary; only keys the host already reported are ever written back.
    private var localHostSettings: [String: Any] {
        var out: [String: Any] = [
            "theme": themeMode == .light ? "zai-light" : (themeMode == .system ? "system" : "zai-dark"),
            "notificationEnabled": notificationsEnabled,
            "messageStreamShowReasoning": showReasoningBlocks,
            "messageStreamShowTodos": showTodoTracker
        ]
        switch language {
        case .english: out["localePreference"] = "en-US"
        case .chineseSimplified: out["localePreference"] = "zh-CN"
        case .vietnamese: break
        }
        return out
    }

    /// Called after any local preference change; pushes the differing host keys via `setting.update`.
    func pushHostSettingsIfNeeded() {
        guard !hostSettings.applying, isLiveHostConnected, !hostSettings.lastHost.isEmpty else { return }
        var patch: [String: Any] = [:]
        for (key, value) in localHostSettings {
            guard let host = hostSettings.lastHost[key] else { continue }
            if !Self.jsonEqual(host, value) { patch[key] = value }
        }
        guard !patch.isEmpty else { return }
        for (key, value) in patch { hostSettings.lastHost[key] = value }
        hostSettings.pushTask?.cancel()
        hostSettings.pushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                _ = try await self.rpcClient.call(channel: "setting", method: "update", args: [.fromJSONObject(patch)], timeoutSec: 10)
                for (key, value) in patch {
                    let stateKey = key == "localePreference" ? "locale" : key
                    guard Self.uiStateKeys.contains(stateKey) else { continue }
                    _ = try? await self.rpcClient.call(
                        channel: "broadcast",
                        method: "send",
                        args: [.fromJSONObject(["channel": "state:\(stateKey)", "payload": value])],
                        timeoutSec: 6
                    )
                }
            } catch {
                self.showToast("Couldn't save setting on your computer: \(error.localizedDescription)")
                await self.refreshHostSettings()
            }
        }
    }

    private static func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case let (l as Bool, r as Bool): return l == r
        case let (l as String, r as String): return l == r
        case let (l as NSNumber, r as NSNumber): return l == r
        default: return false
        }
    }
}
