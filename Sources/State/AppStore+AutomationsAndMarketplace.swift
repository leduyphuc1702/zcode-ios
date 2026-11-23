import Foundation

/// Host-backed Automations page (`zcode-agent` automation RPCs) and Plugin Marketplace
/// (`plugin-management`). Every success is reported only after the RPC returned.
extension AppStore {

    // MARK: - Automation scoping

    /// The workspace the Automations page reads/writes, matching the desktop page's active project.
    public var automationWorkspacePath: String {
        activeProject?.rootPath ?? projects.first?.rootPath ?? ""
    }

    private var automationWorkspaceIdentity: String? {
        let path = automationWorkspacePath
        guard !path.isEmpty else { return nil }
        return workspaceIdentityByPath[path]
    }

    public var canManageAutomations: Bool {
        if isUITestSeededMode { return true }
        return isRemoteRPCReady && !automationWorkspacePath.isEmpty
    }

    // MARK: - Load

    public func loadAutomations() async {
        if isUITestSeededMode { return }
        guard isRemoteRPCReady else {
            automations = []
            automationHostRows = []
            automationsError = "Connect to your computer to manage scheduled tasks."
            return
        }
        let path = automationWorkspacePath
        guard !path.isEmpty else {
            automations = []
            automationHostRows = []
            automationsError = "Open a workspace to manage its scheduled tasks."
            return
        }
        isLoadingAutomations = true
        defer { isLoadingAutomations = false }

        var req: [String: Any] = ["workspacePath": path]
        if let identity = automationWorkspaceIdentity, !identity.isEmpty {
            req["workspaceIdentity"] = identity
        }
        do {
            let value = try await rpcClient.call(
                channel: "zcode-agent",
                method: "listAutomations",
                args: [.fromJSONObject(req)],
                timeoutSec: 12
            )
            let array = (value.decodeJSONValue() as? [[String: Any]])
                ?? ((value.decodeJSONDictionary()?["automations"] as? [[String: Any]]) ?? [])
            automationHostRows = array
            automations = array.compactMap { Self.mapAutomation($0, fallbackWorkspacePath: path, identity: automationWorkspaceIdentity) }
            automationsError = nil
        } catch {
            automationsError = error.localizedDescription
        }
    }

    private static func mapAutomation(
        _ row: [String: Any],
        fallbackWorkspacePath: String,
        identity: String?
    ) -> AutomationScheduleItem? {
        guard let id = row["automationId"] as? String, !id.isEmpty else { return nil }
        let title = ((row["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lifecycle = (row["lifecycleStatus"] as? String) ?? "active"
        let runCount = ZCodeV4.int(row["runCount"]) ?? 0
        var status = lifecycle.capitalized
        if runCount > 0 { status += " · Ran \(runCount) \(runCount == 1 ? "time" : "times")" }
        if let error = row["lastError"] as? String, !error.isEmpty {
            status += " · \(error)"
        }
        let schedule = (row["cronExpr"] as? String) ?? Self.scheduleSummary(row["scheduleRule"]) ?? "Scheduled"
        return AutomationScheduleItem(
            id: id,
            name: title.isEmpty ? "Untitled Automation" : title,
            cronExpression: schedule,
            workspacePath: (row["workspacePath"] as? String) ?? fallbackWorkspacePath,
            prompt: (row["prompt"] as? String) ?? "",
            enabled: (row["enabled"] as? Bool) ?? (lifecycle == "active"),
            lastRunStatus: status,
            lastRunAt: Self.automationDate(row["lastRunAt"])
        )
    }

    private static func scheduleSummary(_ raw: Any?) -> String? {
        guard let rule = raw as? [String: Any] else { return nil }
        if let summary = rule["summary"] as? String, !summary.isEmpty { return summary }
        if let label = rule["label"] as? String, !label.isEmpty { return label }
        return nil
    }

    private static func automationDate(_ raw: Any?) -> Date? {
        if let number = raw as? Double {
            return Date(timeIntervalSince1970: number > 9_999_999_999 ? number / 1000 : number)
        }
        if let number = raw as? Int {
            let value = Double(number)
            return Date(timeIntervalSince1970: value > 9_999_999_999 ? value / 1000 : value)
        }
        if let text = raw as? String, !text.isEmpty {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: text)
        }
        return nil
    }

    // MARK: - Mutations

    @discardableResult
    public func createAutomation(title: String, cronExpr: String, prompt: String) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCron = cronExpr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedPrompt.isEmpty, !trimmedCron.isEmpty else {
            automationsError = "A title, an instruction, and a schedule are required."
            return false
        }
        if isUITestSeededMode {
            automations.insert(
                AutomationScheduleItem(
                    id: "auto-\(UUID().uuidString.prefix(8))",
                    name: trimmedTitle,
                    cronExpression: trimmedCron,
                    workspacePath: automationWorkspacePath,
                    prompt: trimmedPrompt,
                    enabled: true,
                    lastRunStatus: "Active",
                    lastRunAt: nil
                ),
                at: 0
            )
            return true
        }
        guard canManageAutomations else {
            automationsError = isRemoteRPCReady
                ? "Open a workspace to manage its scheduled tasks."
                : "Connect to your computer to manage scheduled tasks."
            return false
        }
        var req: [String: Any] = [
            "title": trimmedTitle,
            "cronExpr": trimmedCron,
            "prompt": trimmedPrompt,
            "workspacePath": automationWorkspacePath,
            "recurring": true
        ]
        if let identity = automationWorkspaceIdentity, !identity.isEmpty {
            req["workspaceIdentity"] = identity
        }
        do {
            _ = try await rpcClient.call(
                channel: "zcode-agent",
                method: "createAutomation",
                args: [.fromJSONObject(req)],
                timeoutSec: 20
            )
            await loadAutomations()
            showToast("Created scheduled task")
            return true
        } catch {
            automationsError = error.localizedDescription
            showToast("Could not create the task. \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    public func updateAutomation(id: String, title: String, cronExpr: String, prompt: String) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCron = cronExpr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedPrompt.isEmpty, !trimmedCron.isEmpty else {
            automationsError = "A title, an instruction, and a schedule are required."
            return false
        }
        if isUITestSeededMode {
            if let idx = automations.firstIndex(where: { $0.id == id }) {
                automations[idx].name = trimmedTitle
                automations[idx].prompt = trimmedPrompt
                automations[idx].cronExpression = trimmedCron
            }
            return true
        }
        guard canManageAutomations else {
            automationsError = "Connect to your computer to manage scheduled tasks."
            return false
        }
        let previous = automationHostRows.first(where: { ($0["automationId"] as? String) == id })
        var req: [String: Any] = [
            "automationId": id,
            "title": trimmedTitle,
            "prompt": trimmedPrompt,
            "workspacePath": (previous?["workspacePath"] as? String) ?? automationWorkspacePath,
            "scheduleEditedByUser": true
        ]
        if let identity = (previous?["workspaceIdentity"] as? String) ?? automationWorkspaceIdentity, !identity.isEmpty {
            req["workspaceIdentity"] = identity
        }
        let previousCron = (previous?["cronExpr"] as? String) ?? ""
        let hadCustomRule = previous?["scheduleRule"] != nil
        if !previousCron.isEmpty {
            req["cronExpr"] = trimmedCron
            if trimmedCron != previousCron, hadCustomRule {
                // The user replaced the schedule; drop the stale custom repeat rule.
                req["scheduleRule"] = NSNull()
            }
        } else if hadCustomRule {
            if trimmedCron != Self.mapAutomation(previous ?? [:], fallbackWorkspacePath: automationWorkspacePath, identity: automationWorkspaceIdentity)?.cronExpression {
                req["cronExpr"] = trimmedCron
                req["scheduleRule"] = NSNull()
            }
        } else {
            req["cronExpr"] = trimmedCron
        }
        do {
            _ = try await rpcClient.call(
                channel: "zcode-agent",
                method: "updateAutomation",
                args: [.fromJSONObject(req)],
                timeoutSec: 20
            )
            await loadAutomations()
            return true
        } catch {
            automationsError = error.localizedDescription
            showToast("Could not save changes. \(error.localizedDescription)")
            return false
        }
    }

    public func setAutomationEnabled(id: String, enabled: Bool) async {
        if isUITestSeededMode {
            if let idx = automations.firstIndex(where: { $0.id == id }) {
                automations[idx].enabled = enabled
                automations[idx].lastRunStatus = enabled ? "Active" : "Paused"
            }
            return
        }
        let previous = automationHostRows.first(where: { ($0["automationId"] as? String) == id })
        var req: [String: Any] = [
            "automationId": id,
            "enabled": enabled,
            "workspacePath": (previous?["workspacePath"] as? String) ?? automationWorkspacePath
        ]
        if let identity = (previous?["workspaceIdentity"] as? String) ?? automationWorkspaceIdentity, !identity.isEmpty {
            req["workspaceIdentity"] = identity
        }
        do {
            _ = try await rpcClient.call(
                channel: "zcode-agent",
                method: "setAutomationEnabled",
                args: [.fromJSONObject(req)],
                timeoutSec: 15
            )
            await loadAutomations()
        } catch {
            automationsError = error.localizedDescription
            showToast("Could not update the task status. \(error.localizedDescription)")
        }
    }

    public func runAutomationNow(id: String) async {
        if isUITestSeededMode {
            if let automation = automations.first(where: { $0.id == id }) {
                createNewSession(initialPrompt: automation.prompt)
            }
            return
        }
        let previous = automationHostRows.first(where: { ($0["automationId"] as? String) == id })
        var req: [String: Any] = [
            "automationId": id,
            "workspacePath": (previous?["workspacePath"] as? String) ?? automationWorkspacePath
        ]
        if let identity = (previous?["workspaceIdentity"] as? String) ?? automationWorkspaceIdentity, !identity.isEmpty {
            req["workspaceIdentity"] = identity
        }
        do {
            let value = try await rpcClient.call(
                channel: "zcode-agent",
                method: "runAutomationNow",
                args: [.fromJSONObject(req)],
                timeoutSec: 20
            )
            let status = (value.decodeJSONDictionary()?["status"] as? String) ?? "queued"
            showToast(status == "duplicate" ? "A run is already in progress" : "Triggered — starting soon")
            await loadAutomations()
        } catch {
            automationsError = error.localizedDescription
            showToast("Could not trigger run. \(error.localizedDescription)")
        }
    }

    public func deleteAutomation(id: String) async {
        if isUITestSeededMode {
            automations.removeAll { $0.id == id }
            return
        }
        let previous = automationHostRows.first(where: { ($0["automationId"] as? String) == id })
        var req: [String: Any] = [
            "automationId": id,
            "workspacePath": (previous?["workspacePath"] as? String) ?? automationWorkspacePath
        ]
        if let identity = (previous?["workspaceIdentity"] as? String) ?? automationWorkspaceIdentity, !identity.isEmpty {
            req["workspaceIdentity"] = identity
        }
        do {
            _ = try await rpcClient.call(
                channel: "zcode-agent",
                method: "deleteAutomation",
                args: [.fromJSONObject(req)],
                timeoutSec: 15
            )
            await loadAutomations()
        } catch {
            automationsError = error.localizedDescription
            showToast("Could not delete the task. \(error.localizedDescription)")
        }
    }

    // MARK: - Plugin Marketplace (`plugin-management`)

    @discardableResult
    public func refreshPluginMarketplace() async -> Bool {
        if isUITestSeededMode { return true }
        guard isRemoteRPCReady else {
            pluginMarketplaceError = "Connect to your computer to load plugins."
            return false
        }
        let path = activeProject?.rootPath ?? projects.first?.rootPath ?? ""
        guard !path.isEmpty else {
            pluginMarketplaceError = "Open a workspace to load plugins."
            return false
        }
        isRefreshingPluginMarketplace = true
        defer { isRefreshingPluginMarketplace = false }

        var req: [String: Any] = ["workspacePath": path]
        if let identity = workspaceIdentityByPath[path], !identity.isEmpty {
            req["workspaceIdentity"] = identity
        }
        do {
            let value = try await rpcClient.call(
                channel: "plugin-management",
                method: "getPluginsOverview",
                args: [.fromJSONObject(req)],
                timeoutSec: 20
            )
            guard let dict = value.decodeJSONDictionary() else {
                pluginMarketplaceError = "The host returned an empty plugin catalog."
                return false
            }
            applyPluginsOverview(dict)
            pluginMarketplaceError = nil
            return true
        } catch {
            pluginMarketplaceError = error.localizedDescription
            return false
        }
    }

    private func applyPluginsOverview(_ dict: [String: Any]) {
        if let mks = dict["marketplaces"] as? [[String: Any]] {
            let names = mks.compactMap { $0["name"] as? String }
            if !names.isEmpty { pluginMarketplaces = names }
        }
        var merged: [PluginCatalogItem] = []
        if let installed = dict["installedPlugins"] as? [[String: Any]] {
            for p in installed {
                guard let id = p["id"] as? String, let name = p["name"] as? String else { continue }
                merged.append(
                    PluginCatalogItem(
                        id: id,
                        name: name,
                        version: (p["version"] as? String) ?? "1.0.0",
                        marketplace: (p["marketplace"] as? String) ?? "zcode-plugins-official",
                        scope: (p["scope"] as? String) ?? "user",
                        summary: (p["description"] as? String) ?? "",
                        componentBadges: ((p["componentTypes"] as? [String]) ?? []).map { $0.capitalized },
                        updateAvailableVersion: p["latestVersion"] as? String,
                        installed: true,
                        enabled: (p["enabled"] as? Bool) ?? true
                    )
                )
            }
        }
        if let available = dict["availablePlugins"] as? [[String: Any]] {
            for p in available where (p["installed"] as? Bool) != true {
                guard let id = p["id"] as? String, let name = p["name"] as? String else { continue }
                merged.append(
                    PluginCatalogItem(
                        id: id,
                        name: name,
                        version: (p["version"] as? String) ?? "1.0.0",
                        marketplace: (p["marketplace"] as? String) ?? "zcode-plugins-official",
                        summary: (p["description"] as? String) ?? "",
                        componentBadges: ((p["componentTypes"] as? [String]) ?? []).map { $0.capitalized },
                        installed: false,
                        enabled: false
                    )
                )
            }
        }
        plugins = merged
    }

    /// Toggle a plugin through `plugin-management.setPluginEnabled`; local state changes only on success.
    @discardableResult
    public func setMarketplacePluginEnabled(id: String, enabled: Bool) async -> Bool {
        guard let item = plugins.first(where: { $0.id == id }) else { return false }
        if isUITestSeededMode {
            if let idx = plugins.firstIndex(where: { $0.id == id }) { plugins[idx].enabled = enabled }
            return true
        }
        guard isRemoteRPCReady else {
            pluginMarketplaceError = "Connect to your computer to change plugins."
            return false
        }
        let path = activeProject?.rootPath ?? projects.first?.rootPath ?? ""
        guard !path.isEmpty else {
            pluginMarketplaceError = "Open a workspace to change plugins."
            return false
        }
        var req: [String: Any] = ["workspacePath": path, "pluginId": item.id, "enabled": enabled]
        if let identity = workspaceIdentityByPath[path], !identity.isEmpty {
            req["workspaceIdentity"] = identity
        }
        do {
            _ = try await rpcClient.call(
                channel: "plugin-management",
                method: "setPluginEnabled",
                args: [.fromJSONObject(req)],
                timeoutSec: 15
            )
            if let idx = plugins.firstIndex(where: { $0.id == id }) { plugins[idx].enabled = enabled }
            pluginMarketplaceError = nil
            return true
        } catch {
            pluginMarketplaceError = error.localizedDescription
            showToast("Could not update \(item.name). \(error.localizedDescription)")
            return false
        }
    }

    /// Install a marketplace plugin through `plugin-management.installPlugin`.
    @discardableResult
    public func installMarketplacePlugin(id: String) async -> Bool {
        guard let item = plugins.first(where: { $0.id == id }) else { return false }
        if isUITestSeededMode {
            if let idx = plugins.firstIndex(where: { $0.id == id }) {
                plugins[idx].installed = true
                plugins[idx].enabled = true
            }
            return true
        }
        guard isRemoteRPCReady else {
            pluginMarketplaceError = "Connect to your computer to install plugins."
            return false
        }
        let path = activeProject?.rootPath ?? projects.first?.rootPath ?? ""
        guard !path.isEmpty else {
            pluginMarketplaceError = "Open a workspace to install plugins."
            return false
        }
        var req: [String: Any] = [
            "workspacePath": path,
            "pluginName": item.name,
            "marketplace": item.marketplace
        ]
        if let identity = workspaceIdentityByPath[path], !identity.isEmpty {
            req["workspaceIdentity"] = identity
        }
        do {
            _ = try await rpcClient.call(
                channel: "plugin-management",
                method: "installPlugin",
                args: [.fromJSONObject(req)],
                timeoutSec: 120
            )
            await refreshPluginMarketplace()
            showToast("Installed \(item.name)")
            return true
        } catch {
            pluginMarketplaceError = error.localizedDescription
            showToast("Could not install \(item.name). \(error.localizedDescription)")
            return false
        }
    }
}
