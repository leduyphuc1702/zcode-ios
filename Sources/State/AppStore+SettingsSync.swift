import Foundation
import SwiftUI

extension AppStore {

    // MARK: - Live ZCode Desktop v3.16.3 Settings Hydration & Bidirectional RPC

    public var isRemoteRPCReady: Bool {
        guard !isUITestSeededMode,
              let conn = activeConnection,
              conn.state == .connected,
              conn.transport != .enterpriseSandbox else {
            return false
        }
        return true
    }

    var currentWorkspaceContext: (path: String, identity: String?) {
        let path = activeProject?.rootPath ?? projects.first?.rootPath ?? ""
        let identity = path.isEmpty ? nil : workspaceIdentityByPath[path]
        return (path, identity)
    }

    public func syncAllSettingsFromRemoteDesktop() async {
        guard isRemoteRPCReady else { return }
        isSyncingSettings = true
        defer {
            isSyncingSettings = false
            lastSettingsSyncedAt = Date()
        }

        let ctx = currentWorkspaceContext

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.syncGeneralSettingsRPC() }
            group.addTask { await self.syncProvidersAndModelsRPC() }
            group.addTask { await self.syncSubagentsRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity) }
            group.addTask { await self.syncMCPServersRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity) }
            group.addTask { await self.syncSkillsRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity) }
            group.addTask { await self.syncPluginsRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity) }
            group.addTask { await self.syncCommandsRPC(workspacePath: ctx.path) }
            group.addTask { await self.syncHooksRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity) }
            group.addTask { await self.syncMemoriesRPC() }
            group.addTask { await self.syncUsageStatsRPC() }
        }
    }

    /// Fire-and-forget helper kept for non-UI call sites. Settings UI uses `updateDesktopSetting`.
    public func pushDesktopSettingPatch(_ patch: [String: Any]) {
        guard isRemoteRPCReady else { return }
        Task { _ = await self.updateDesktopSetting(patch) }
    }

    /// Writes `setting.update(patch)` and only reports success after the host accepts it.
    @discardableResult
    public func updateDesktopSetting(_ patch: [String: Any], successMessage: String? = nil) async -> Bool {
        guard isRemoteRPCReady else {
            showToast("Connect to your computer to change this setting")
            return false
        }
        do {
            _ = try await rpcClient.call(
                channel: "setting",
                method: "update",
                args: [.fromJSONObject(patch)],
                timeoutSec: 8.0
            )
            for (key, value) in patch { hostSettings.lastHost[key] = value }
            if let successMessage { showToast(successMessage) }
            await mirrorUiStateBroadcasts(patch)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    private func mirrorUiStateBroadcasts(_ patch: [String: Any]) async {
        let uiKeys: Set<String> = ["theme", "locale", "uiFontSizePx", "interfaceMode", "notificationEnabled"]
        for (key, value) in patch {
            let stateKey = key == "localePreference" ? "locale" : key
            guard uiKeys.contains(stateKey) else { continue }
            _ = try? await rpcClient.call(
                channel: "broadcast",
                method: "send",
                args: [.fromJSONObject(["channel": "state:\(stateKey)", "payload": value])],
                timeoutSec: 4.0
            )
        }
    }

    private func syncGeneralSettingsRPC() async {
        guard let val = try? await rpcClient.call(channel: "setting", method: "get", args: [], timeoutSec: 3.5),
              let d = val.decodeJSONDictionary() else { return }

        if let mode = d["interfaceMode"] as? String { interfaceMode = mode }
        if let inherit = d["terminalInheritSystemProfile"] as? Bool { terminalInheritSystemProfile = inherit }
        if let font = d["terminalFontFamily"] as? String, !font.isEmpty { terminalFontFamily = font }
        if let tsm = d["toolSearchMode"] as? String { toolSearchMode = tsm }
        if let nse = d["nativeSearchEnhancementsEnabled"] as? Bool { nativeSearchEnhancementsEnabled = nse }
        if let proxy = d["httpProxy"] as? String { httpProxyURL = proxy }
        if let noProxy = d["httpProxyNoProxy"] as? String { httpProxyNoProxy = noProxy }
        if let ca = d["httpProxyCaCertPath"] as? String { httpProxyCaCertPath = ca }
        if let sr = d["messageStreamShowReasoning"] as? Bool { showReasoningBlocks = sr }
        if let st = d["messageStreamShowTodos"] as? Bool { messageStreamShowTodos = st }
        if let ge = d["toolGroupingExploreEnabled"] as? Bool { toolGroupingExploreEnabled = ge }
        if let gt = d["toolGroupingTerminalEnabled"] as? Bool { toolGroupingTerminalEnabled = gt }
        if let gc = d["toolGroupingChangesEnabled"] as? Bool { toolGroupingChangesEnabled = gc }
        if let ib = d["zcodeInteractionBehavior"] as? String { zcodeInteractionBehavior = ib }
        if let autoQ = d["askUserQuestionAutoResolutionEnabled"] as? Bool { askUserQuestionAutoResolutionEnabled = autoQ }
        if let dw = d["dynamicWorkflowMode"] as? String { dynamicWorkflowMode = dw }
        if let fullIo = d["modelIoFullRetentionEnabled"] as? Bool { modelIoFullRetentionEnabled = fullIo }
        if let mem = d["memoryEnabled"] as? Bool { memoryEnabled = mem }
        if let aa = d["taskAutoArchiveEnabled"] as? Bool { taskAutoArchiveEnabled = aa }
        if let days = d["taskAutoArchiveOlderThanDays"] as? Int { taskAutoArchiveOlderThanDays = days }
        if let insec = d["embeddedBrowserAllowInsecureCertificates"] as? Bool { embeddedBrowserAllowInsecureCertificates = insec }
        if let cuaHide = d["computerUseComposerEntryHidden"] as? Bool { computerUseComposerEntryHidden = cuaHide }
        if let awake = d["keepAwakeWhileRunning"] as? Bool { keepAwakeWhileRunning = awake }
        if let prev = d["receivePreviewUpdates"] as? Bool { receivePreviewUpdates = prev }
        if let autoUpd = d["autoDownloadAndInstallUpdates"] as? Bool { autoDownloadAndInstallUpdates = autoUpd }
        if let dir = d["dataBaseDir"] as? String, !dir.isEmpty { dataBaseDir = dir }
        if let rawShortcuts = d["shortcutBindings"] as? [String: Any] {
            let bindings = rawShortcuts.compactMapValues { value -> [String]? in
                if let list = value as? [String] { return list }
                if let single = value as? String, !single.isEmpty { return [single] }
                return nil
            }
            applyHostShortcutBindings(bindings)
        }
    }

    private func applyHostShortcutBindings(_ bindings: [String: [String]]) {
        let known = Dictionary(uniqueKeysWithValues: ShortcutBindingItem.officialDefaults.map { ($0.id, $0) })
        var parsed: [ShortcutBindingItem] = []
        for (id, keys) in bindings {
            let joined = keys.joined(separator: " / ")
            guard !joined.isEmpty else { continue }
            if var item = known[id] {
                item.customBinding = joined
                parsed.append(item)
            } else {
                parsed.append(
                    ShortcutBindingItem(
                        id: id,
                        title: id,
                        category: "Desktop",
                        defaultBinding: joined,
                        customBinding: nil
                    )
                )
            }
        }
        parsed.sort { lhs, rhs in
            let order = ["Global", "Window", "Workspace", "Composer", "Desktop"]
            let l = order.firstIndex(of: lhs.category) ?? 99
            let r = order.firstIndex(of: rhs.category) ?? 99
            return l == r ? lhs.title < rhs.title : l < r
        }
        shortcutBindings = parsed
    }

    // MARK: - 1. Models & Providers (1:1 `provider-settings` RPC)

    public func syncProvidersAndModelsRPC() async {
        guard let val = try? await rpcClient.call(channel: "provider-settings", method: "getView", args: [], timeoutSec: 4.5),
              let dict = val.decodeJSONDictionary() else { return }
        applyProviderSettingsViewDictionary(dict)
    }

    /// Applies the authoritative `ProviderSettingsView`. An empty host list clears local state.
    func applyProviderSettingsViewDictionary(_ dict: [String: Any]) {
        providerSettingsRevision = (dict["revision"] as? String) ?? ""
        providerTemplates = ((dict["providerTemplates"] as? [[String: Any]]) ?? [])
            .compactMap(ProviderTemplateDescriptor.init(json:))
        let order = (dict["providerOrder"] as? [String]) ?? []
        providerOrder = order

        let templateNames = Dictionary(uniqueKeysWithValues: providerTemplates.map { ($0.id, $0.displayName()) })
        let rawProviders = (dict["providers"] as? [[String: Any]]) ?? []
        var parsed: [ModelProviderConfig] = rawProviders.compactMap { raw in
            parseProvider(raw, templateNames: templateNames)
        }

        // Host `providerOrder` only lists standard-personal providers; account presets keep registry order.
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let account = parsed.filter(\.isAccountProvider)
        let personal = parsed.filter { !$0.isAccountProvider }.enumerated().sorted { lhs, rhs in
            let l = rank[lhs.element.id] ?? Int.max
            let r = rank[rhs.element.id] ?? Int.max
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)
        parsed = account + personal
        providers = parsed
    }

    private func parseProvider(_ raw: [String: Any], templateNames: [String: String]) -> ModelProviderConfig? {
        guard let pid = raw["providerId"] as? String, !pid.isEmpty else { return nil }
        let pname = (raw["providerName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? pid
        let enabled = (raw["enabled"] as? Bool) ?? true
        let executable = (raw["executable"] as? Bool) ?? false
        let templateId = (raw["templateId"] as? String)
        let effectiveCfg = (raw["effectiveConfig"] as? [String: Any]) ?? [:]
        let personalCfg = raw["personalConfig"] as? [String: Any]
        let templateCfg = raw["templateConfig"] as? [String: Any]
        let apiDict = (effectiveCfg["api"] as? [String: Any]) ?? [:]
        let accessDict = (effectiveCfg["access"] as? [String: Any]) ?? [:]
        let personalAccess = (personalCfg?["access"] as? [String: Any]) ?? [:]
        let accessType = (accessDict["type"] as? String) ?? (personalAccess["type"] as? String) ?? "api-key"
        let apiKey = (accessDict["apiKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (personalAccess["apiKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? ""
        let apiKeyMgmt = (accessDict["apiKeyManagementUrl"] as? String)
            ?? (personalAccess["apiKeyManagementUrl"] as? String)
        let apiType = (apiDict["type"] as? String)
            ?? ((templateCfg?["api"] as? [String: Any])?["type"] as? String)
            ?? ProviderAPIFormat.openaiChatCompletions.rawValue
        let baseURL = (apiDict["baseUrl"] as? String)
            ?? ((templateCfg?["api"] as? [String: Any])?["baseUrl"] as? String)
            ?? ""
        let group = (effectiveCfg["group"] as? String)
            ?? (templateCfg?["group"] as? String)
            ?? (accessType == "zhipu-account" ? "zai-family" : "standard-personal")
        let logoKey = ((effectiveCfg["logo"] as? [String: Any])?["key"] as? String)
            ?? ((templateCfg?["logo"] as? [String: Any])?["key"] as? String)
            ?? templateId
            ?? "custom"
        let accountState = (raw["accountState"] as? [String: Any]) ?? [:]
        let availability = (accountState["availability"] as? String) ?? "unknown"
        let entitled = (accountState["entitled"] as? Bool) ?? (accessDict["entitled"] as? Bool) ?? false
        let unavailableReason = accountState["unavailableReason"] as? String
        let issues = ((raw["issues"] as? [[String: Any]]) ?? []).compactMap(ProviderConfigIssue.init(json:))
        let isAccount = accessType == "zhipu-account" || (group != "standard-personal" && !group.isEmpty)
        let statusText: String = {
            if !enabled { return "Disabled" }
            if executable { return "Ready" }
            return "Not ready"
        }()

        var models: [ModelDescriptor] = []
        for m in (raw["models"] as? [[String: Any]]) ?? [] {
            guard let mid = m["modelId"] as? String, !mid.isEmpty else { continue }
            let mEnabled = (m["enabled"] as? Bool) ?? true
            let kind = (m["kind"] as? String) ?? "builtin"
            let mBuiltin = (m["builtin"] as? Bool) ?? (kind == "builtin")
            let useRec = (m["useRecommendedConfig"] as? Bool) ?? false
            let mEff = (m["effectiveConfig"] as? [String: Any]) ?? [:]
            let props = (mEff["properties"] as? [String: Any]) ?? [:]
            let ctxTokens = (props["contextWindow"] as? Int) ?? 0
            let inFmt = (props["inputFormat"] as? [String: Any]) ?? [:]
            let optSpecs = (mEff["optionSpecs"] as? [String: Any]) ?? [:]
            let rSpec = (optSpecs["reasoningLevel"] as? [String: Any]) ?? [:]
            let rValues = (rSpec["values"] as? [String]) ?? []
            let rMap = (rSpec["map"] as? String) ?? ""
            let maxSpec = (optSpecs["maxOutputTokens"] as? [String: Any]) ?? [:]
            let maxOut = (maxSpec["max"] as? Int) ?? 0
            let maxMap = (maxSpec["map"] as? String) ?? ""

            models.append(
                ModelDescriptor(
                    id: "\(pid)/\(mid)",
                    modelId: mid,
                    name: mid,
                    providerId: pid,
                    providerName: pname,
                    enabled: mEnabled,
                    builtin: mBuiltin,
                    useRecommendedConfig: useRec,
                    contextWindowTokens: ctxTokens,
                    maxOutputTokens: maxOut,
                    supportsVision: (inFmt["supportsImage"] as? Bool) ?? false,
                    supportsVideo: (inFmt["supportsVideo"] as? Bool) ?? false,
                    supportsAudio: (inFmt["supportsAudio"] as? Bool) ?? false,
                    supportsPdf: (inFmt["supportsPdf"] as? Bool) ?? false,
                    supportsToolCall: (props["supportsToolCall"] as? Bool) ?? false,
                    supportsReasoning: !rValues.isEmpty,
                    supportsJsonSchemaOutput: (props["supportsJsonSchemaOutput"] as? Bool) ?? false,
                    supportsNativeWebSearch: (props["supportsNativeWebSearch"] as? Bool) ?? false,
                    supportsMidConversationSystem: (props["supportsMidConversationSystem"] as? Bool) ?? false,
                    reasoningLevels: rValues,
                    reasoningMap: rMap,
                    maxOutputTokensMap: maxMap,
                    requiresMfjsToolSchema: (props["requiresMfjsToolSchema"] as? Bool) ?? false,
                    kind: kind,
                    selectable: (m["selectable"] as? Bool) ?? false,
                    executable: (m["executable"] as? Bool) ?? false,
                    personalConfigJSON: Self.jsonString(m["personalExactConfig"] as? [String: Any]),
                    effectiveConfigJSON: Self.jsonString(mEff),
                    issues: ((m["issues"] as? [[String: Any]]) ?? []).compactMap(ProviderConfigIssue.init(json:)),
                    badge: nil
                )
            )
        }

        return ModelProviderConfig(
            id: pid,
            name: pname,
            baseURL: baseURL,
            protocolKind: apiType,
            group: group,
            templateId: templateId,
            templateName: templateNames[templateId ?? ""],
            apiKeyManagementURL: apiKeyMgmt,
            apiKey: apiKey,
            hasConfiguredAPIKey: !apiKey.isEmpty,
            accessType: accessType,
            enabled: enabled,
            isBuiltin: isAccount,
            executable: executable,
            entitled: entitled,
            accountAvailability: availability,
            accountUnavailableReason: unavailableReason,
            statusText: statusText,
            logoKey: logoKey,
            revision: providerSettingsRevision,
            personalConfigJSON: Self.jsonString(personalCfg),
            effectiveConfigJSON: Self.jsonString(effectiveCfg),
            issues: issues,
            models: models
        )
    }

    static func jsonString(_ dict: [String: Any]?) -> String {
        guard let dict, JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    private func applyProviderMutationReply(_ reply: VQLValue) -> Bool {
        guard let dict = reply.decodeJSONDictionary() else { return false }
        if let view = dict["view"] as? [String: Any] {
            applyProviderSettingsViewDictionary(view)
            return true
        }
        if dict["providers"] != nil || dict["revision"] != nil || dict["providerTemplates"] != nil {
            applyProviderSettingsViewDictionary(dict)
            return true
        }
        return false
    }

    private func requireRemoteForSettingsChange() -> Bool {
        guard isRemoteRPCReady else {
            showToast("Connect to your computer to change these settings")
            return false
        }
        return true
    }

    private func personalOverlay(for provider: ModelProviderConfig) -> [String: Any] {
        var overlay = provider.personalConfigDictionary
        // Renderer strips membership arrays before every overlay write (spec §66-69).
        overlay.removeValue(forKey: "builtinModelIds")
        overlay.removeValue(forKey: "personalModelIds")
        return overlay
    }

    /// Creates a provider from a host template (or a blank custom provider) and returns the real `providerId`.
    @discardableResult
    public func createProvider(
        template: ProviderTemplateDescriptor?,
        customName: String,
        apiKey: String = ""
    ) async -> String? {
        guard requireRemoteForSettingsChange() else { return nil }
        let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        var req: [String: Any] = ["locale": preferredHostLocale]
        if let template, !template.id.isEmpty {
            req["templateId"] = template.id
        }
        if !trimmedName.isEmpty {
            req["providerName"] = trimmedName
        }
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanKey.isEmpty {
            req["initialConfig"] = ["access": ["type": "api-key", "apiKey": cleanKey]]
        }
        do {
            let reply = try await rpcClient.call(
                channel: "provider-settings",
                method: "createPersonalProvider",
                args: [.fromJSONObject(req)],
                timeoutSec: 8.0
            )
            guard let dict = reply.decodeJSONDictionary(),
                  let view = dict["view"] as? [String: Any],
                  let providerId = dict["providerId"] as? String else {
                showToast("Provider creation did not return a provider")
                return nil
            }
            applyProviderSettingsViewDictionary(view)
            showToast("Added provider \(providers.first(where: { $0.id == providerId })?.name ?? providerId)")
            return providerId
        } catch {
            showToast(error.localizedDescription)
            return nil
        }
    }

    /// Rename and/or enable/disable via `savePersonalProviderOverlay(providerId, overlay, meta)`.
    @discardableResult
    public func saveProviderMeta(providerId: String, name: String? = nil, enabled: Bool? = nil) async -> Bool {
        guard requireRemoteForSettingsChange(),
              let provider = providers.first(where: { $0.id == providerId }),
              !provider.isAccountProvider else {
            if providers.first(where: { $0.id == providerId })?.isAccountProvider == true {
                showToast("Account providers cannot be changed here")
            }
            return false
        }
        var meta: [String: Any] = [:]
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != provider.name { meta["providerName"] = trimmed }
        }
        if let enabled, enabled != provider.enabled { meta["enabled"] = enabled }
        guard !meta.isEmpty else { return true }
        do {
            let reply = try await rpcClient.call(
                channel: "provider-settings",
                method: "savePersonalProviderOverlay",
                args: [.string(providerId), .fromJSONObject(personalOverlay(for: provider)), .fromJSONObject(meta)],
                timeoutSec: 8.0
            )
            guard applyProviderMutationReply(reply) else {
                await syncProvidersAndModelsRPC()
                return true
            }
            showToast("Provider settings saved")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    /// Saves endpoint, API format and (optionally) the API key. `apiKey == nil` keeps the host value.
    @discardableResult
    public func saveProviderConnection(
        providerId: String,
        name: String,
        baseURL: String,
        apiFormat: ProviderAPIFormat,
        apiKey: String?
    ) async -> Bool {
        guard requireRemoteForSettingsChange(),
              let provider = providers.first(where: { $0.id == providerId }),
              !provider.isAccountProvider else {
            if providers.first(where: { $0.id == providerId })?.isAccountProvider == true {
                showToast("Account providers are managed by your Z.AI login")
            }
            return false
        }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            showToast("Base URL is required")
            return false
        }
        var overlay = personalOverlay(for: provider)
        overlay["api"] = ["type": apiFormat.rawValue, "baseUrl": trimmedURL]
        if let apiKey {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            var access = (overlay["access"] as? [String: Any]) ?? [:]
            access["type"] = (access["type"] as? String) ?? "api-key"
            access["apiKey"] = trimmedKey
            overlay["access"] = access
        }
        var meta: [String: Any] = [:]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != provider.name { meta["providerName"] = trimmedName }
        do {
            var args: [VQLValue] = [.string(providerId), .fromJSONObject(overlay)]
            if !meta.isEmpty { args.append(.fromJSONObject(meta)) }
            let reply = try await rpcClient.call(
                channel: "provider-settings",
                method: "savePersonalProviderOverlay",
                args: args,
                timeoutSec: 8.0
            )
            guard applyProviderMutationReply(reply) else {
                await syncProvidersAndModelsRPC()
                return true
            }
            showToast("Provider settings saved")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func deleteProvider(_ providerId: String) async -> Bool {
        guard requireRemoteForSettingsChange(),
              let provider = providers.first(where: { $0.id == providerId }),
              !provider.isAccountProvider else {
            if providers.first(where: { $0.id == providerId })?.isAccountProvider == true {
                showToast("Account providers cannot be deleted")
            }
            return false
        }
        do {
            let reply = try await rpcClient.call(
                channel: "provider-settings",
                method: "deletePersonalProvider",
                args: [.string(providerId)],
                timeoutSec: 6.0
            )
            guard applyProviderMutationReply(reply) else {
                await syncProvidersAndModelsRPC()
                return true
            }
            showToast("Deleted \(provider.name)")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    public func movePersonalProvider(providerId: String, direction: Int) async {
        guard requireRemoteForSettingsChange() else { return }
        var ids = providers.filter { !$0.isAccountProvider }.map(\.id)
        guard let current = ids.firstIndex(of: providerId) else { return }
        let target = current + direction
        guard target >= 0 && target < ids.count else { return }
        ids.swapAt(current, target)
        do {
            let reply = try await rpcClient.call(
                channel: "provider-settings",
                method: "reorderPersonalProviders",
                args: [.array(ids.map { .string($0) })],
                timeoutSec: 6.0
            )
            if !applyProviderMutationReply(reply) { await syncProvidersAndModelsRPC() }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func modelConfigOverlay(_ model: ModelDescriptor) -> [String: Any] {
        var props: [String: Any] = [
            "requiresMfjsToolSchema": model.requiresMfjsToolSchema,
            "contextWindow": model.contextWindowTokens,
            "inputFormat": [
                "supportsText": true,
                "supportsImage": model.supportsVision,
                "supportsVideo": model.supportsVideo,
                "supportsAudio": model.supportsAudio,
                "supportsPdf": model.supportsPdf
            ],
            "outputFormat": ["supportsText": true],
            "supportsToolCall": model.supportsToolCall,
            "supportsJsonSchemaOutput": model.supportsJsonSchemaOutput,
            "supportsNativeWebSearch": model.supportsNativeWebSearch,
            "supportsMidConversationSystem": model.supportsMidConversationSystem
        ]
        if model.contextWindowTokens <= 0 { props.removeValue(forKey: "contextWindow") }
        var optionSpecs: [String: Any] = [:]
        if model.reasoningLevels.isEmpty {
            optionSpecs["reasoningLevel"] = NSNull()
        } else {
            optionSpecs["reasoningLevel"] = ["values": model.reasoningLevels, "map": model.reasoningMap]
        }
        if model.maxOutputTokens > 0 {
            var maxSpec: [String: Any] = ["max": model.maxOutputTokens]
            if !model.maxOutputTokensMap.isEmpty { maxSpec["map"] = model.maxOutputTokensMap }
            optionSpecs["maxOutputTokens"] = maxSpec
        }
        return ["enabled": model.enabled, "properties": props, "optionSpecs": optionSpecs]
    }

    /// Adds (`originalModelId == nil`) or saves a model draft. Only reports success after the host rebuilds the view.
    @discardableResult
    public func upsertModel(providerId: String, originalModelId: String?, draft: ModelDescriptor) async -> Bool {
        guard requireRemoteForSettingsChange(),
              let provider = providers.first(where: { $0.id == providerId }),
              !provider.isAccountProvider else {
            if providers.first(where: { $0.id == providerId })?.isAccountProvider == true {
                showToast("Built-in account models are read-only")
            }
            return false
        }
        let cleanId = draft.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else {
            showToast("Model ID is required")
            return false
        }
        if !draft.reasoningLevels.isEmpty {
            guard !draft.reasoningMap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showToast("Reasoning level mapping is required when levels are configured")
                return false
            }
        }
        let overlay = modelConfigOverlay(draft)
        do {
            let reply: VQLValue
            if let originalModelId {
                let req: [String: Any] = [
                    "providerId": providerId,
                    "originalModelId": originalModelId,
                    "nextModelId": cleanId,
                    "personalConfig": overlay,
                    "basedOnRevision": provider.revision,
                    "useRecommendedConfig": draft.useRecommendedConfig
                ]
                reply = try await rpcClient.call(
                    channel: "provider-settings",
                    method: "savePersonalModelDraft",
                    args: [.fromJSONObject(req)],
                    timeoutSec: 8.0
                )
            } else {
                reply = try await rpcClient.call(
                    channel: "provider-settings",
                    method: "addPersonalModel",
                    args: [.string(providerId), .string(cleanId), .fromJSONObject(overlay), .bool(draft.useRecommendedConfig)],
                    timeoutSec: 8.0
                )
            }
            guard applyProviderMutationReply(reply) else {
                await syncProvidersAndModelsRPC()
                return true
            }
            showToast("Saved model \(cleanId)")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func setModelEnabled(providerId: String, modelId: String, enabled: Bool) async -> Bool {
        guard requireRemoteForSettingsChange(),
              let provider = providers.first(where: { $0.id == providerId }),
              let model = provider.models.first(where: { $0.modelId == modelId || $0.id == modelId }) else { return false }
        do {
            let reply = try await rpcClient.call(
                channel: "provider-settings",
                method: "setPersonalModelEnabled",
                args: [.string(providerId), .string(model.modelId), .bool(enabled)],
                timeoutSec: 6.0
            )
            if !applyProviderMutationReply(reply) { await syncProvidersAndModelsRPC() }
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func deleteModel(providerId: String, modelId: String) async -> Bool {
        guard requireRemoteForSettingsChange(),
              let provider = providers.first(where: { $0.id == providerId }),
              let model = provider.models.first(where: { $0.modelId == modelId || $0.id == modelId }),
              !model.builtin else {
            if providers.first(where: { $0.id == providerId })?.models.contains(where: { ($0.modelId == modelId || $0.id == modelId) && $0.builtin }) == true {
                showToast("Built-in models cannot be deleted; disable them instead")
            }
            return false
        }
        do {
            let reply = try await rpcClient.call(
                channel: "provider-settings",
                method: "deletePersonalModel",
                args: [.string(providerId), .string(model.modelId)],
                timeoutSec: 6.0
            )
            if !applyProviderMutationReply(reply) { await syncProvidersAndModelsRPC() }
            showToast("Removed \(model.modelId)")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    public func moveModel(providerId: String, modelId: String, direction: Int) async {
        guard requireRemoteForSettingsChange(),
              let provider = providers.first(where: { $0.id == providerId }) else { return }
        var ids = provider.models.map(\.modelId)
        guard let current = ids.firstIndex(of: modelId) else { return }
        let target = current + direction
        guard target >= 0 && target < ids.count else { return }
        ids.swapAt(current, target)
        do {
            let reply = try await rpcClient.call(
                channel: "provider-settings",
                method: "reorderPersonalModels",
                args: [.string(providerId), .array(ids.map { .string($0) })],
                timeoutSec: 6.0
            )
            if !applyProviderMutationReply(reply) { await syncProvidersAndModelsRPC() }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// Resolves inherited/effective defaults for a draft model (model ID blur / Smart configuration).
    public func resolveModelConfig(providerId: String, modelId: String, originalModelId: String?, personalConfig: [String: Any]?) async -> [String: Any]? {
        guard requireRemoteForSettingsChange() else { return nil }
        var req: [String: Any] = ["providerId": providerId, "modelId": modelId]
        if let originalModelId { req["originalModelId"] = originalModelId }
        if let personalConfig { req["personalConfig"] = personalConfig }
        guard let reply = try? await rpcClient.call(
            channel: "provider-settings",
            method: "resolveModelConfig",
            args: [.fromJSONObject(req)],
            timeoutSec: 6.0
        ) else { return nil }
        return reply.decodeJSONDictionary()
    }

    /// Real `provider-settings.testModelConnectivity`. No local success path exists.
    public func testModelConnectivity(providerId: String, modelId: String) async {
        guard let pIdx = providers.firstIndex(where: { $0.id == providerId }),
              let mIdx = providers[pIdx].models.firstIndex(where: { $0.modelId == modelId || $0.id == modelId }) else { return }
        let provider = providers[pIdx]
        let model = providers[pIdx].models[mIdx]
        guard isRemoteRPCReady else {
            providers[pIdx].models[mIdx].connectivityState = .failed
            providers[pIdx].models[mIdx].connectivityMessage = "Connect to your computer to test"
            return
        }
        providers[pIdx].models[mIdx].connectivityState = .testing
        providers[pIdx].models[mIdx].connectivityMessage = "Testing \(provider.name) / \(model.modelId)"
        let ctx = currentWorkspaceContext
        var req: [String: Any] = [
            "workspacePath": ctx.path,
            "providerId": providerId,
            "modelId": model.modelId
        ]
        if let ident = ctx.identity, !ident.isEmpty { req["workspaceIdentity"] = ident }
        do {
            let reply = try await rpcClient.call(
                channel: "provider-settings",
                method: "testModelConnectivity",
                args: [.fromJSONObject(req)],
                timeoutSec: 20.0
            )
            let dict = reply.decodeJSONDictionary()
            let ok = (dict?["success"] as? Bool) ?? false
            if let p2 = providers.firstIndex(where: { $0.id == providerId }),
               let m2 = providers[p2].models.firstIndex(where: { $0.modelId == model.modelId }) {
                if ok {
                    providers[p2].models[m2].connectivityState = .connected
                    providers[p2].models[m2].connectivityMessage = "Connected"
                    showToast("Connection successful for \(provider.name) / \(model.modelId)")
                } else {
                    let errDict = dict?["error"] as? [String: Any]
                    let code = errDict?["code"] as? String
                    let reason: String
                    switch code {
                    case "provider-unavailable": reason = "Provider is not available."
                    case "model-unavailable": reason = "Model is not available."
                    default: reason = (errDict?["message"] as? String) ?? "Connectivity check failed"
                    }
                    providers[p2].models[m2].connectivityState = .failed
                    providers[p2].models[m2].connectivityMessage = reason
                    showToast("\(provider.name) / \(model.modelId): \(reason)")
                }
            }
        } catch {
            if let p2 = providers.firstIndex(where: { $0.id == providerId }),
               let m2 = providers[p2].models.firstIndex(where: { $0.modelId == model.modelId }) {
                providers[p2].models[m2].connectivityState = .failed
                providers[p2].models[m2].connectivityMessage = error.localizedDescription
            }
            showToast(error.localizedDescription)
        }
    }

    private var preferredHostLocale: String {
        switch language {
        case .chineseSimplified: return "zh-CN"
        default: return "en-US"
        }
    }

    // MARK: - 2. Subagents Studio (1:1 `subagents` RPC)

    public static func validateSubagentName(_ name: String, existingNames: [String] = [], isNew: Bool = true) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 3 || trimmed.count > 50 {
            return "Subagent name must be 3–50 characters."
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Use only letters, numbers, and hyphens (-)."
        }
        let lower = trimmed.lowercased()
        if lower == "general-purpose" || lower == "explore" {
            return "\"\(trimmed)\" is reserved for ZCode's built-in subagents."
        }
        if isNew && existingNames.contains(where: { $0.lowercased() == lower }) {
            return "A subagent named \"\(trimmed)\" already exists."
        }
        return nil
    }

    public func syncSubagentsRPC(workspacePath: String, workspaceIdentity: String?) async {
        var req: [String: Any] = [
            "workspacePath": workspacePath,
            "provider": "glm",
            "mode": "allRuntimeScopes"
        ]
        if let workspaceIdentity, !workspaceIdentity.isEmpty {
            req["workspaceIdentity"] = workspaceIdentity
        }
        guard let val = try? await rpcClient.call(channel: "subagents", method: "list", args: [.fromJSONObject(req)], timeoutSec: 4.5),
              let dict = val.decodeJSONDictionary() else { return }
        // The host list is authoritative; an empty list clears stale rows.
        let rawAgents = (dict["agents"] as? [[String: Any]]) ?? []
        var parsed: [SubagentDefinitionItem] = []
        for a in rawAgents {
            guard let id = a["id"] as? String,
                  let name = a["name"] as? String else { continue }
            let desc = (a["description"] as? String) ?? ""
            let prompt = (a["systemPrompt"] as? String) ?? ""
            let rawColor = (a["color"] as? String) ?? "blue"
            let color = SubagentColor(rawValue: rawColor) ?? .blue
            let scope = (a["scope"] as? String) ?? "user"
            let source = (a["source"] as? String) ?? "user"
            let readOnly = (a["readOnly"] as? Bool) ?? (source != "user")
            let enabled = (a["enabled"] as? Bool) ?? true
            let path = (a["path"] as? String) ?? ""
            let injectMd = (a["injectAgentsMd"] as? Bool) ?? true
            let bg = (a["background"] as? Bool) ?? false
            let permRaw = (a["permissionMode"] as? String) ?? "default"
            let perm = SubagentPermissionMode(rawValue: permRaw) ?? .default
            let tools = (a["tools"] as? [String]) ?? ["*"]

            let selDict = (a["modelSelectionOverride"] as? [String: Any])
                ?? (a["modelSelection"] as? [String: Any])
                ?? (a["defaultModelSelection"] as? [String: Any])
            var modelStr = "inherit"
            var reasonStr = "inherit"
            if let selDict,
               let prov = selDict["providerId"] as? String,
               let mod = selDict["modelId"] as? String,
               !mod.isEmpty {
                modelStr = "\(prov)/\(mod)"
                if let opts = selDict["options"] as? [String: Any],
                   let rl = opts["reasoningLevel"] as? String {
                    reasonStr = rl
                }
            }

            parsed.append(
                SubagentDefinitionItem(
                    id: id,
                    name: name,
                    description: desc,
                    systemPrompt: prompt,
                    color: color,
                    scope: scope,
                    source: source,
                    readOnly: readOnly,
                    enabled: enabled,
                    modelOverride: modelStr,
                    reasoningOverride: reasonStr,
                    allowedTools: tools.isEmpty ? ["*"] : tools,
                    permissionMode: perm,
                    injectAgentsMd: injectMd,
                    runInBackground: bg,
                    filePath: path,
                    pluginId: a["pluginId"] as? String,
                    pluginName: a["pluginName"] as? String
                )
            )
        }
        self.subagents = parsed
    }

    @discardableResult
    public func saveSubagent(_ draft: SubagentDefinitionItem, isNew: Bool) async -> Bool {
        var clean = draft
        clean.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.source = "user"
        clean.readOnly = false
        if clean.filePath.isEmpty || isNew {
            clean.filePath = clean.scope == "workspace"
                ? ".zcode/agents/\(clean.name).md"
                : "~/.zcode/agents/\(clean.name).md"
        }
        if isUITestSeededMode {
            if isNew {
                clean.id = "user:\(clean.scope):\(clean.name)"
                subagents.insert(clean, at: 0)
            } else if let idx = subagents.firstIndex(where: { $0.id == draft.id }) {
                subagents[idx] = clean
            }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        let oldPath = subagents.first(where: { $0.id == draft.id })?.filePath
        let ctx = currentWorkspaceContext
        var cfg: [String: Any] = [
            "name": clean.name,
            "description": clean.description,
            "systemPrompt": clean.systemPrompt,
            "color": clean.color.rawValue,
            "injectAgentsMd": clean.injectAgentsMd,
            "background": clean.runInBackground,
            "permissionMode": clean.permissionMode.rawValue
        ]
        if !clean.isAllTools { cfg["tools"] = clean.allowedTools }
        if clean.modelOverride != "inherit", !clean.modelOverride.isEmpty {
            let parts = clean.modelOverride.split(separator: "/", maxSplits: 1).map(String.init)
            var sel: [String: Any] = [
                "providerId": parts.count == 2 ? parts[0] : "",
                "modelId": parts.count == 2 ? parts[1] : clean.modelOverride
            ]
            if clean.reasoningOverride != "inherit" {
                sel["options"] = ["reasoningLevel": clean.reasoningOverride]
            }
            cfg["modelSelection"] = sel
        }
        var req: [String: Any] = [
            "config": cfg,
            "provider": "glm",
            "scope": clean.scope == "workspace" ? "workspace" : "user",
            "workspacePath": ctx.path
        ]
        if let ident = ctx.identity { req["workspaceIdentity"] = ident }
        do {
            if isNew {
                _ = try await rpcClient.call(channel: "subagents", method: "createAgent", args: [.fromJSONObject(req)], timeoutSec: 8.0)
                showToast("Created subagent \(clean.name)")
            } else {
                req["agentId"] = clean.id
                if let oldPath { req["oldFilePath"] = oldPath }
                _ = try await rpcClient.call(channel: "subagents", method: "updateAgent", args: [.fromJSONObject(req)], timeoutSec: 8.0)
                showToast("Updated subagent \(clean.name)")
            }
            await syncSubagentsRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func deleteSubagent(_ id: String) async -> Bool {
        guard let item = subagents.first(where: { $0.id == id }), !item.readOnly else { return false }
        if isUITestSeededMode {
            subagents.removeAll { $0.id == id }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        do {
            _ = try await rpcClient.call(
                channel: "subagents",
                method: "deleteAgent",
                args: [.fromJSONObject(["agentId": item.id, "filePath": item.filePath])],
                timeoutSec: 6.0
            )
            showToast("Deleted subagent \(item.name)")
            let ctx = currentWorkspaceContext
            await syncSubagentsRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func setSubagentEnabled(_ id: String, enabled: Bool) async -> Bool {
        guard let item = subagents.first(where: { $0.id == id }) else { return false }
        if isUITestSeededMode {
            if let idx = subagents.firstIndex(where: { $0.id == id }) { subagents[idx].enabled = enabled }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        do {
            _ = try await rpcClient.call(
                channel: "subagents",
                method: "setEnabled",
                args: [.fromJSONObject(["agentId": item.id, "enabled": enabled])],
                timeoutSec: 6.0
            )
            if let idx = subagents.firstIndex(where: { $0.id == id }) { subagents[idx].enabled = enabled }
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func setSubagentModelAndEffortOverride(id: String, modelOverride: String, reasoningOverride: String) async -> Bool {
        guard let item = subagents.first(where: { $0.id == id }) else { return false }
        if isUITestSeededMode {
            if let idx = subagents.firstIndex(where: { $0.id == id }) {
                subagents[idx].modelOverride = modelOverride
                subagents[idx].reasoningOverride = reasoningOverride
            }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        var selectionObj: [String: Any]? = nil
        if modelOverride != "inherit" && !modelOverride.isEmpty {
            let parts = modelOverride.split(separator: "/", maxSplits: 1).map(String.init)
            var sel: [String: Any] = [
                "providerId": parts.count == 2 ? parts[0] : "",
                "modelId": parts.count == 2 ? parts[1] : modelOverride
            ]
            if reasoningOverride != "inherit" {
                sel["options"] = ["reasoningLevel": reasoningOverride]
            }
            selectionObj = sel
        }
        do {
            if item.source == "built-in" {
                var req: [String: Any] = ["agentName": item.name]
                if let selectionObj { req["modelSelection"] = selectionObj }
                _ = try await rpcClient.call(channel: "subagents", method: "setBuiltInModelOverride", args: [.fromJSONObject(req)], timeoutSec: 6.0)
            } else if item.source == "plugin" {
                var req: [String: Any] = ["agentId": item.id]
                if let selectionObj { req["modelSelection"] = selectionObj }
                _ = try await rpcClient.call(channel: "subagents", method: "setPluginAgentModelOverride", args: [.fromJSONObject(req)], timeoutSec: 6.0)
            } else if !item.readOnly {
                var updated = item
                updated.modelOverride = modelOverride
                updated.reasoningOverride = reasoningOverride
                return await saveSubagent(updated, isNew: false)
            }
            if let idx = subagents.firstIndex(where: { $0.id == id }) {
                subagents[idx].modelOverride = modelOverride
                subagents[idx].reasoningOverride = reasoningOverride
            }
            showToast("Updated model for \(item.displayName)")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    // MARK: - 3. MCP, Skills, Plugins, Commands, Hooks, Memory, Usage

    public func syncMCPServersRPC(workspacePath: String, workspaceIdentity: String?) async {
        var dirReq: [String: Any] = [:]
        if !workspacePath.isEmpty { dirReq["workspacePath"] = workspacePath }
        if let workspaceIdentity, !workspaceIdentity.isEmpty { dirReq["workspaceIdentity"] = workspaceIdentity }
        var statusReq: [String: Any] = ["workspacePath": workspacePath, "mode": "status"]
        if let workspaceIdentity { statusReq["workspaceIdentity"] = workspaceIdentity }

        async let dirCall = try? rpcClient.call(
            channel: "mcp-sync",
            method: "loadMcpFromUserDirectory",
            args: [.fromJSONObject(dirReq)],
            timeoutSec: 4.0
        )
        async let statusCall = try? rpcClient.call(
            channel: "mcp-sync",
            method: "listWorkspaceMcpServerStatuses",
            args: [.fromJSONObject(statusReq)],
            timeoutSec: 4.0
        )

        let (dirVal, statusVal) = await (dirCall, statusCall)
        guard let dirDict = dirVal?.decodeJSONDictionary() else { return }
        let statuses = (statusVal?.decodeJSONDictionary()?["statuses"] as? [String: [String: Any]]) ?? [:]
        let rawServers = (dirDict["servers"] as? [[String: Any]]) ?? []

        var list: [MCPServerItem] = []
        for s in rawServers {
            guard let name = s["name"] as? String else { continue }
            let scope = (s["scope"] as? String) ?? "user"
            let enabled = (s["enabled"] as? Bool) ?? true
            let cfg = (s["config"] as? [String: Any]) ?? [:]
            let transport = (cfg["type"] as? String) ?? ((cfg["url"] != nil) ? "http" : "stdio")
            let cmdOrUrl = (cfg["url"] as? String) ?? (cfg["command"] as? String) ?? ""
            let args = (cfg["args"] as? [String]) ?? []
            let timeout = (cfg["timeoutMs"] as? Int) ?? 30_000
            let proto = (cfg["protocolVersion"] as? String) ?? "auto"
            let status = statuses[name]?["status"] as? String
            let stText: String = {
                switch status?.lowercased() {
                case "connected": return "Connected and available."
                case "connecting": return "Connecting to the MCP runtime."
                case "disconnected": return "The MCP server is not connected."
                case "failed", "error": return "The MCP server failed to connect."
                case "disabled": return "Disabled"
                case "untrusted": return "The MCP server status is unavailable."
                default: return enabled ? "The MCP server status is unavailable." : "Disabled"
                }
            }()
            let connected = status?.lowercased() == "connected"
            let tools = (statuses[name]?["tools"] as? [String]) ?? []

            list.append(
                MCPServerItem(
                    id: "mcp-\(scope)-\(name)",
                    name: name,
                    scope: scope,
                    transport: transport,
                    endpointOrCommand: cmdOrUrl,
                    args: args,
                    protocolVersion: proto,
                    timeoutMs: timeout,
                    enabled: enabled,
                    connected: connected,
                    statusText: stText,
                    tools: tools,
                    resourcesCount: 0
                )
            )
        }
        self.mcpServers = list
    }

    @discardableResult
    public func upsertMCPServer(_ draft: MCPServerItem, isNew: Bool) async -> Bool {
        if isUITestSeededMode {
            if let idx = mcpServers.firstIndex(where: { $0.id == draft.id }) { mcpServers[idx] = draft }
            else { mcpServers.append(draft) }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        var cfg: [String: Any] = ["type": draft.transport, "timeoutMs": draft.timeoutMs]
        if draft.transport == "stdio" {
            cfg["command"] = draft.endpointOrCommand
            if !draft.args.isEmpty { cfg["args"] = draft.args }
        } else {
            cfg["url"] = draft.endpointOrCommand
        }
        if draft.transport != "sse" { cfg["protocolVersion"] = draft.protocolVersion }
        if let data = draft.envOrHeadersJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           !obj.isEmpty {
            cfg[draft.transport == "stdio" ? "env" : "headers"] = obj
        }
        var req: [String: Any] = [
            "action": "upsert",
            "source": "zcodeagentmcp",
            "name": draft.name,
            "config": cfg
        ]
        if draft.scope == "workspace", let path = activeProject?.rootPath { req["projectPath"] = path }
        do {
            _ = try await rpcClient.call(channel: "mcp-sync", method: "saveMcpToUserDirectory", args: [.fromJSONObject(req)], timeoutSec: 6.0)
            showToast("Saved MCP server \(draft.name)")
            let ctx = currentWorkspaceContext
            await syncMCPServersRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func deleteMCPServer(_ item: MCPServerItem) async -> Bool {
        if isUITestSeededMode {
            mcpServers.removeAll { $0.id == item.id }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        do {
            _ = try await rpcClient.call(
                channel: "mcp-sync",
                method: "saveMcpToUserDirectory",
                args: [.fromJSONObject(["action": "delete", "source": "zcodeagentmcp", "name": item.name])],
                timeoutSec: 6.0
            )
            showToast("Removed MCP server \(item.name)")
            let ctx = currentWorkspaceContext
            await syncMCPServersRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func setMCPServerEnabled(_ item: MCPServerItem, enabled: Bool) async -> Bool {
        if isUITestSeededMode {
            if let idx = mcpServers.firstIndex(where: { $0.id == item.id }) { mcpServers[idx].enabled = enabled }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        do {
            _ = try await rpcClient.call(
                channel: "mcp-sync",
                method: "saveMcpToUserDirectory",
                args: [.fromJSONObject(["action": "set-enabled", "name": item.name, "enabled": enabled])],
                timeoutSec: 6.0
            )
            if let idx = mcpServers.firstIndex(where: { $0.id == item.id }) {
                mcpServers[idx].enabled = enabled
                mcpServers[idx].statusText = enabled ? "Enabled" : "Disabled"
            }
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    public func syncSkillsRPC(workspacePath: String, workspaceIdentity: String?) async {
        var req: [String: Any] = ["workspacePath": workspacePath, "provider": "glm"]
        if let workspaceIdentity { req["workspaceIdentity"] = workspaceIdentity }
        guard let val = try? await rpcClient.call(channel: "skills", method: "list", args: [.fromJSONObject(req)], timeoutSec: 4.5),
              let rawSkills = val.decodeJSONDictionary()?["skills"] as? [[String: Any]] else { return }

        self.skills = rawSkills.compactMap { s in
            guard let id = s["id"] as? String, let name = s["name"] as? String else { return nil }
            let rawScope = (s["scope"] as? String) ?? "user"
            return SkillCatalogItem(
                id: id,
                name: name,
                summary: (s["description"] as? String) ?? "",
                scope: rawScope.capitalized,
                pluginName: s["pluginName"] as? String,
                filePath: (s["path"] as? String) ?? "",
                enabled: (s["enabled"] as? Bool) ?? true,
                markdownBody: (s["body"] as? String) ?? ""
            )
        }
    }

    @discardableResult
    public func setSkillEnabled(_ item: SkillCatalogItem, enabled: Bool) async -> Bool {
        if isUITestSeededMode {
            if let idx = skills.firstIndex(where: { $0.id == item.id }) { skills[idx].enabled = enabled }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        let ctx = currentWorkspaceContext
        var req: [String: Any] = [
            "workspacePath": ctx.path,
            "provider": "glm",
            "scope": item.scope.lowercased(),
            "skillId": item.id,
            "enabled": enabled
        ]
        if let ident = ctx.identity { req["workspaceIdentity"] = ident }
        do {
            _ = try await rpcClient.call(channel: "skills", method: "setEnabled", args: [.fromJSONObject(req)], timeoutSec: 6.0)
            if let idx = skills.firstIndex(where: { $0.id == item.id }) { skills[idx].enabled = enabled }
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    public func syncPluginsRPC(workspacePath: String, workspaceIdentity: String?) async {
        var req: [String: Any] = [:]
        if !workspacePath.isEmpty { req["workspacePath"] = workspacePath }
        if let workspaceIdentity { req["workspaceIdentity"] = workspaceIdentity }
        guard let val = try? await rpcClient.call(channel: "plugin-management", method: "getPluginsOverview", args: [.fromJSONObject(req)], timeoutSec: 6.0),
              let dict = val.decodeJSONDictionary() else { return }

        let rawMarketplaces = (dict["marketplaces"] as? [[String: Any]]) ?? []
        self.pluginMarketplaces = rawMarketplaces.compactMap { item in
            (item["name"] as? String) ?? (item["title"] as? String) ?? (item["id"] as? String)
        }

        var merged: [PluginCatalogItem] = []
        let installed = (dict["installedPlugins"] as? [[String: Any]]) ?? []
        for p in installed {
            let name = (p["name"] as? String) ?? (p["pluginName"] as? String)
            guard let name else { continue }
            let version = (p["version"] as? String) ?? ""
            let marketplace = (p["marketplace"] as? String) ?? ""
            let id = (p["id"] as? String) ?? (marketplace.isEmpty ? name : "\(name)@\(marketplace)")
            let summary = (p["description"] as? String)
                ?? ((p["listing"] as? [String: Any])?["description"] as? String)
                ?? ""
            merged.append(
                PluginCatalogItem(
                    id: id,
                    name: name,
                    version: version,
                    marketplace: marketplace,
                    scope: (p["scope"] as? String) ?? "user",
                    summary: summary,
                    componentBadges: ((p["componentTypes"] as? [String]) ?? []).map { $0.capitalized },
                    updateAvailableVersion: (p["latestVersion"] as? String),
                    installed: true,
                    enabled: (p["enabled"] as? Bool) ?? false
                )
            )
        }
        let available = (dict["availablePlugins"] as? [[String: Any]]) ?? []
        let installedIds = Set(merged.map(\.id))
        for p in available {
            let name = (p["name"] as? String) ?? (p["pluginName"] as? String)
            guard let name else { continue }
            let marketplace = (p["marketplace"] as? String) ?? ""
            let id = (p["id"] as? String) ?? (marketplace.isEmpty ? name : "\(name)@\(marketplace)")
            if installedIds.contains(id) { continue }
            merged.append(
                PluginCatalogItem(
                    id: id,
                    name: name,
                    version: (p["version"] as? String) ?? "",
                    marketplace: marketplace,
                    scope: (p["scope"] as? String) ?? "user",
                    summary: (p["description"] as? String)
                        ?? ((p["listing"] as? [String: Any])?["description"] as? String)
                        ?? "",
                    componentBadges: ((p["componentTypes"] as? [String]) ?? []).map { $0.capitalized },
                    installed: false,
                    enabled: false
                )
            )
        }
        self.plugins = merged
    }

    /// Real `plugin-management.installPlugin` (name + marketplace + scope).
    @discardableResult
    public func installPlugin(_ item: PluginCatalogItem) async -> Bool {
        guard isRemoteRPCReady else {
            showToast("Connect to your computer to install plugins")
            return false
        }
        guard !item.marketplace.isEmpty else {
            showToast("This plugin has no marketplace source")
            return false
        }
        let ctx = currentWorkspaceContext
        var req: [String: Any] = [
            "pluginName": item.name,
            "marketplace": item.marketplace,
            "scope": "user",
            "workspacePath": ctx.path
        ]
        if let ident = ctx.identity { req["workspaceIdentity"] = ident }
        do {
            _ = try await rpcClient.call(channel: "plugin-management", method: "installPlugin", args: [.fromJSONObject(req)], timeoutSec: 60.0)
            showToast("Installed \(item.name)")
            await syncPluginsRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func setPluginEnabled(_ item: PluginCatalogItem, enabled: Bool) async -> Bool {
        if isUITestSeededMode {
            if let idx = plugins.firstIndex(where: { $0.id == item.id }) { plugins[idx].enabled = enabled }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        let ctx = currentWorkspaceContext
        var req: [String: Any] = ["workspacePath": ctx.path, "pluginId": item.id, "enabled": enabled, "scope": "user"]
        if let ident = ctx.identity { req["workspaceIdentity"] = ident }
        do {
            _ = try await rpcClient.call(channel: "plugin-management", method: "setPluginEnabled", args: [.fromJSONObject(req)], timeoutSec: 10.0)
            if let idx = plugins.firstIndex(where: { $0.id == item.id }) { plugins[idx].enabled = enabled }
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    public func syncCommandsRPC(workspacePath: String) async {
        var req: [String: Any] = ["agentSource": "zcodeAgent"]
        if !workspacePath.isEmpty { req["workspacePath"] = workspacePath }
        guard let val = try? await rpcClient.call(
            channel: "commands",
            method: "list",
            args: [.fromJSONObject(req)],
            timeoutSec: 4.0
        ), let dict = val.decodeJSONDictionary() else { return }

        let raw = (dict["commands"] as? [[String: Any]]) ?? []
        var parsed: [SlashCommandItem] = []
        for c in raw {
            guard let id = c["id"] as? String, let name = c["name"] as? String else { continue }
            let src = (c["source"] as? String) ?? "user"
            let scope: String
            if src == "plugin" { scope = "Plugin" }
            else if (c["scope"] as? String) == "project" || (c["storageLevel"] as? String) == "project" { scope = "Project" }
            else { scope = "User" }
            parsed.append(
                SlashCommandItem(
                    id: id,
                    trigger: name,
                    summary: (c["description"] as? String) ?? "",
                    argumentHint: (c["argumentHint"] as? String) ?? "",
                    scope: scope,
                    enabled: (c["enabled"] as? Bool) ?? true,
                    filePath: (c["filePath"] as? String) ?? "",
                    promptTemplate: (c["prompt"] as? String) ?? ""
                )
            )
        }
        // No fixture System commands are injected; the host list is authoritative.
        self.slashCommands = parsed
    }

    @discardableResult
    public func upsertSlashCommand(_ draft: SlashCommandItem, isNew: Bool) async -> Bool {
        if isUITestSeededMode {
            if let idx = slashCommands.firstIndex(where: { $0.id == draft.id }) { slashCommands[idx] = draft }
            else { slashCommands.append(draft) }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        let cleanName = draft.trigger.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !cleanName.isEmpty else {
            showToast("Command name is required")
            return false
        }
        guard !draft.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("Prompt is required")
            return false
        }
        let oldPath = slashCommands.first(where: { $0.id == draft.id })?.filePath
        let cfg: [String: Any] = [
            "name": cleanName,
            "prompt": draft.promptTemplate,
            "description": draft.summary,
            "argumentHint": draft.argumentHint
        ]
        var req: [String: Any] = [
            "agentSource": "zcodeAgent",
            "storageLevel": draft.scope == "Project" ? "project" : "global",
            "workspacePath": currentWorkspaceContext.path,
            "config": cfg
        ]
        do {
            if isNew {
                _ = try await rpcClient.call(channel: "commands", method: "writeCommandFile", args: [.fromJSONObject(req)], timeoutSec: 6.0)
            } else {
                if let oldPath, !oldPath.isEmpty { req["oldFilePath"] = oldPath }
                _ = try await rpcClient.call(channel: "commands", method: "updateCommandFile", args: [.fromJSONObject(req)], timeoutSec: 6.0)
            }
            showToast("Saved command /\(cleanName)")
            await syncCommandsRPC(workspacePath: currentWorkspaceContext.path)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func deleteSlashCommand(_ item: SlashCommandItem) async -> Bool {
        guard item.scope != "System" else { return false }
        if isUITestSeededMode {
            slashCommands.removeAll { $0.id == item.id }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        guard !item.filePath.isEmpty else {
            showToast("This command has no file to delete")
            return false
        }
        do {
            _ = try await rpcClient.call(channel: "commands", method: "deleteCommandFile", args: [.fromJSONObject(["filePath": item.filePath])], timeoutSec: 6.0)
            showToast("Deleted \(item.trigger)")
            await syncCommandsRPC(workspacePath: currentWorkspaceContext.path)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    public func syncHooksRPC(workspacePath: String, workspaceIdentity: String?) async {
        var req: [String: Any] = ["workspacePath": workspacePath, "scope": "workspace"]
        if let workspaceIdentity { req["workspaceIdentity"] = workspaceIdentity }
        guard let val = try? await rpcClient.call(channel: "hooks", method: "loadHooks", args: [.fromJSONObject(req)], timeoutSec: 4.0),
              let dict = val.decodeJSONDictionary() else { return }
        let raw = (dict["hooks"] as? [[String: Any]]) ?? []

        self.hooks = raw.compactMap { h in
            guard let id = h["id"] as? String,
                  let event = h["event"] as? String,
                  let cmd = h["command"] as? String else { return nil }
            let loc = h["location"] as? [String: Any]
            return HookRuleItem(
                id: id,
                event: event,
                matcher: (h["matcher"] as? String) ?? "",
                hookType: (h["type"] as? String) ?? "command",
                scope: (loc?["scope"] as? String) ?? "user",
                command: cmd,
                argsLines: ((h["args"] as? [String]) ?? []).joined(separator: "\n"),
                shell: (h["shell"] as? String) ?? "/bin/zsh",
                runAsync: (h["async"] as? Bool) ?? false,
                timeoutSec: (h["timeout"] as? Int) ?? 60,
                statusMessage: (h["statusMessage"] as? String) ?? "",
                editable: (h["editable"] as? Bool) ?? true,
                enabled: (h["enabled"] as? Bool) ?? true
            )
        }
        self.pendingHookTrustItems = Self.parsePendingHookTrust(dict["workspaceHookSnapshot"] as? [String: Any])
    }

    private static func parsePendingHookTrust(_ snapshot: [String: Any]?) -> [PendingHookTrustItem] {
        guard let snapshot,
              let bundleDigest = snapshot["bundleDigest"] as? String, !bundleDigest.isEmpty else { return [] }
        let rawHooks = (snapshot["hooks"] as? [[String: Any]]) ?? []
        return rawHooks.compactMap { h in
            guard let digest = h["hookDeclarationDigest"] as? String, !digest.isEmpty else { return nil }
            let trust = (h["workspaceHook"] as? [String: Any])?["trustState"] as? String
            if trust == "trusted_persistent" { return nil }
            let reviewId = (h["reviewItemId"] as? String) ?? (h["id"] as? String) ?? digest
            return PendingHookTrustItem(
                bundleDigest: bundleDigest,
                hookDeclarationDigest: digest,
                reviewItemId: reviewId
            )
        }
    }

    /// Grants trust for the workspace hook declarations the host reported (real `hooks.grantWorkspaceHookTrust`).
    @discardableResult
    public func grantPendingWorkspaceHookTrust() async -> Bool {
        guard requireRemoteForSettingsChange() else { return false }
        guard !pendingHookTrustItems.isEmpty else { return true }
        let ctx = currentWorkspaceContext
        do {
            for item in pendingHookTrustItems {
                var req: [String: Any] = [
                    "bundleDigest": item.bundleDigest,
                    "hookDeclarationDigest": item.hookDeclarationDigest
                ]
                if !ctx.path.isEmpty { req["workspacePath"] = ctx.path }
                if let ident = ctx.identity { req["workspaceIdentity"] = ident }
                _ = try await rpcClient.call(channel: "hooks", method: "grantWorkspaceHookTrust", args: [.fromJSONObject(req)], timeoutSec: 8.0)
            }
            pendingHookTrustItems = []
            await syncHooksRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity)
            showToast("Workspace hooks trusted")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func upsertHookRule(_ draft: HookRuleItem) async -> Bool {
        if isUITestSeededMode {
            if let idx = hooks.firstIndex(where: { $0.id == draft.id }) { hooks[idx] = draft }
            else { hooks.append(draft) }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        var updated = hooks
        if let idx = updated.firstIndex(where: { $0.id == draft.id }) { updated[idx] = draft }
        else { updated.append(draft) }
        let ok = await pushHooksToDesktop(updated)
        if ok {
            hooks = updated
            showToast("Saved hook on \(draft.event)")
        }
        return ok
    }

    @discardableResult
    public func deleteHookRule(_ item: HookRuleItem) async -> Bool {
        if isUITestSeededMode {
            hooks.removeAll { $0.id == item.id }
            return true
        }
        guard requireRemoteForSettingsChange() else { return false }
        let updated = hooks.filter { $0.id != item.id }
        let ok = await pushHooksToDesktop(updated)
        if ok {
            hooks = updated
            showToast("Deleted hook")
        }
        return ok
    }

    @discardableResult
    public func pushHooksToDesktopIfConnected() async -> Bool {
        guard isRemoteRPCReady else { return false }
        return await pushHooksToDesktop(hooks)
    }

    private func pushHooksToDesktop(_ list: [HookRuleItem]) async -> Bool {
        let serialized: [[String: Any]] = list.filter(\.editable).map { h in
            var d: [String: Any] = [
                "id": h.id,
                "event": h.event,
                "matcher": h.matcher,
                "type": h.hookType,
                "command": h.command,
                "timeout": h.timeoutSec,
                "enabled": h.enabled,
                "editable": true,
                "location": [
                    "source": "zcode",
                    "scope": h.scope == "project" ? "project" : "user",
                    "directoryPath": ""
                ]
            ]
            if h.hookType == "process" {
                d["args"] = h.argsLines.split(separator: "\n").map(String.init)
            } else {
                d["async"] = h.runAsync
                if !h.shell.isEmpty { d["shell"] = h.shell }
            }
            if !h.statusMessage.isEmpty { d["statusMessage"] = h.statusMessage }
            return d
        }
        let ctx = currentWorkspaceContext
        var req: [String: Any] = ["workspacePath": ctx.path, "scope": "workspace", "hooks": serialized]
        if let ident = ctx.identity { req["workspaceIdentity"] = ident }
        do {
            _ = try await rpcClient.call(channel: "hooks", method: "saveHooks", args: [.fromJSONObject(req)], timeoutSec: 8.0)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    public func syncMemoriesRPC() async {
        guard let val = try? await rpcClient.call(channel: "memory", method: "loadMemory", args: [.fromJSONObject([:])], timeoutSec: 4.0),
              let dict = val.decodeJSONDictionary() else { return }
        if let mem = dict["memory"] as? [String: Any], let content = mem["content"] as? String {
            self.userMemoryMarkdown = content
        } else if dict["memory"] is NSNull {
            self.userMemoryMarkdown = ""
        }
    }

    @discardableResult
    public func saveUserMemoryMarkdown(_ content: String) async -> Bool {
        guard isRemoteRPCReady else {
            showToast("Connect to your computer to save memory")
            return false
        }
        do {
            _ = try await rpcClient.call(
                channel: "memory",
                method: "saveMemory",
                args: [.fromJSONObject(["config": ["content": content]])],
                timeoutSec: 8.0
            )
            userMemoryMarkdown = content
            showToast("Saved global MEMORY.md")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    // MARK: Usage stats (real host payloads only)

    public func syncUsageStatsRPC(range: String = "7d") async {
        guard isRemoteRPCReady else {
            usageStatsSnapshot = nil
            usageStatsError = nil
            usageStatsLoading = false
            return
        }
        usageStatsLoading = true
        defer { usageStatsLoading = false }
        var req: [String: Any] = ["range": range, "timeZone": TimeZone.current.identifier]
        if req["timeZone"] as? String == nil { req["timeZone"] = "UTC" }
        do {
            let reply = try await rpcClient.call(
                channel: "usage-stats",
                method: "getAppUsageSnapshot",
                args: [.fromJSONObject(req)],
                timeoutSec: 15.0
            )
            guard let dict = reply.decodeJSONDictionary() else {
                usageStatsError = "The host returned an empty usage snapshot"
                return
            }
            let summary = (dict["summary"] as? [String: Any]) ?? [:]
            let rawModels = (dict["models"] as? [[String: Any]]) ?? []
            let models = rawModels.compactMap { m -> UsageModelTotal? in
                guard let mid = m["modelId"] as? String else { return nil }
                return UsageModelTotal(modelId: mid, totalTokens: (m["totalTokens"] as? Int) ?? 0)
            }
            let rawDaily = (dict["dailyModelUsage"] as? [[String: Any]]) ?? []
            let daily = rawDaily.compactMap { d -> UsageDailyPoint? in
                guard let date = d["date"] as? String else { return nil }
                let entries = ((d["models"] as? [[String: Any]]) ?? []).compactMap { m -> UsageModelTotal? in
                    guard let mid = m["modelId"] as? String else { return nil }
                    return UsageModelTotal(modelId: mid, totalTokens: (m["totalTokens"] as? Int) ?? 0)
                }
                return UsageDailyPoint(
                    date: date,
                    totalTokens: entries.reduce(0) { $0 + $1.totalTokens },
                    models: entries
                )
            }
            usageStatsSnapshot = UsageStatsSnapshot(
                range: (dict["range"] as? String) ?? range,
                generatedAt: (dict["generatedAt"] as? Double) ?? (dict["generatedAt"] as? Int).map(Double.init),
                totalTokens: (summary["totalTokens"] as? Int) ?? 0,
                peakDayTokens: (summary["peakDayTokens"] as? Int) ?? 0,
                longestSessionMs: (summary["longestSessionMs"] as? Int) ?? 0,
                currentStreakDays: (summary["currentStreakDays"] as? Int) ?? 0,
                longestStreakDays: (summary["longestStreakDays"] as? Int) ?? 0,
                models: models,
                dailyModelUsage: daily
            )
            usageStatsError = nil
        } catch {
            usageStatsError = error.localizedDescription
        }
    }

    /// Loads the real Coding Plan entitlement snapshot from `usage-stats`.
    public func syncCodingPlanEntitlementRPC() async {
        guard isRemoteRPCReady else {
            codingPlanEntitlement = nil
            codingPlanEntitlementError = nil
            codingPlanEntitlementLoading = false
            return
        }
        guard let account = codingPlanAccountContext() else {
            codingPlanEntitlement = nil
            codingPlanEntitlementError = "No connected Z.ai or BigModel Coding Plan account is available for quota lookup. Connect a Coding Plan account first."
            codingPlanEntitlementLoading = false
            return
        }
        codingPlanEntitlementLoading = true
        defer { codingPlanEntitlementLoading = false }
        let req: [String: Any] = [
            "includeSubscription": true,
            "preferredProviderId": account.providerId,
            "accountAccess": account.access,
            "allowDisabledPreferredProvider": true,
            "requirePreferredProvider": true,
            "allowEnvApiKey": false
        ]
        do {
            let reply = try await rpcClient.call(
                channel: "usage-stats",
                method: "getEntitlementSnapshot",
                args: [.fromJSONObject(req)],
                timeoutSec: 20.0
            )
            guard let dict = reply.decodeJSONDictionary() else {
                codingPlanEntitlementError = "The host returned an empty entitlement snapshot"
                return
            }
            let snapshot = (dict["visibleSnapshot"] as? [String: Any]) ?? dict
            codingPlanEntitlement = Self.parseEntitlement(snapshot)
            codingPlanEntitlementError = nil
        } catch {
            codingPlanEntitlement = nil
            codingPlanEntitlementError = error.localizedDescription
        }
    }

    private func codingPlanAccountContext() -> (providerId: String, access: [String: Any])? {
        let candidates = providers.filter { $0.accessType == "zhipu-account" && $0.entitled }
        if let provider = candidates.first(where: { $0.executable }) ?? candidates.first {
            var access = provider.effectiveConfigDictionary["access"] as? [String: Any] ?? [:]
            access["type"] = "zhipu-account"
            if access["accountType"] == nil {
                access["accountType"] = provider.id.contains("bigmodel") ? "bigmodel" : "zai"
            }
            if access["mode"] == nil { access["mode"] = "individual-coding-plan" }
            if access["entitled"] == nil { access["entitled"] = provider.entitled }
            return (provider.id, access)
        }
        return nil
    }

    private static func parseEntitlement(_ snapshot: [String: Any]) -> CodingPlanEntitlementSnapshot {
        let quota = (snapshot["quota"] as? [String: Any]) ?? [:]
        let rawLimits = (quota["limits"] as? [[String: Any]]) ?? []
        let limits = rawLimits.map { l in
            CodingPlanLimit(
                type: (l["type"] as? String) ?? "",
                unit: l["unit"] as? Int,
                number: l["number"] as? Int,
                percentage: (l["percentage"] as? Double) ?? (l["percentage"] as? Int).map(Double.init),
                remaining: (l["remaining"] as? Double) ?? (l["remaining"] as? Int).map(Double.init),
                currentValue: (l["currentValue"] as? Double) ?? (l["currentValue"] as? Int).map(Double.init),
                usage: (l["usage"] as? Double) ?? (l["usage"] as? Int).map(Double.init),
                nextResetTime: l["nextResetTime"] as? String,
                showName: (l["showName"] as? String) ?? (l["name"] as? String)
            )
        }
        let subscription = (snapshot["subscription"] as? [String: Any]) ?? [:]
        let details = (subscription["details"] as? [[String: Any]]) ?? []
        let productNames = details.compactMap { ($0["productName"] as? String) ?? ($0["productId"] as? String) }
        let expires = details.compactMap { ($0["expireTime"] as? String) ?? ($0["expiredAt"] as? String) ?? ($0["endTime"] as? String) }.first
        return CodingPlanEntitlementSnapshot(
            planLevel: (quota["level"] as? String) ?? (snapshot["planLevel"] as? String),
            unavailableReason: snapshot["unavailableReason"] as? String,
            remaining: (snapshot["remaining"] as? String) ?? (snapshot["remaining"] as? Int).map(String.init),
            limits: limits,
            productNames: productNames,
            expiresAt: expires
        )
    }

    // MARK: - Workspace search scope (.zcodeignore) — real file-channel RPC

    public struct WorkspaceFileSearchIgnoreSnapshot: Equatable {
        public var content: String
        public var source: String // "file" | "template"

        public init(content: String, source: String) {
            self.content = content
            self.source = source
        }
    }

    /// `file.readWorkspaceFileSearchIgnore({rootPath})` -> `{content, source}`.
    /// `source == "template"` means `.zcodeignore` does not exist yet and the preview is not written.
    public func readWorkspaceFileSearchIgnore(rootPath: String) async -> WorkspaceFileSearchIgnoreSnapshot? {
        guard !rootPath.isEmpty else { return nil }
        guard isRemoteRPCReady else {
            showToast("Connect to your computer to load ignore rules")
            return nil
        }
        do {
            let value = try await rpcClient.call(
                channel: "file",
                method: "readWorkspaceFileSearchIgnore",
                args: [.fromJSONObject(["rootPath": rootPath])],
                timeoutSec: 8
            )
            guard let dict = value.decodeJSONDictionary(), let content = dict["content"] as? String else {
                return nil
            }
            return WorkspaceFileSearchIgnoreSnapshot(
                content: content,
                source: (dict["source"] as? String) ?? "file"
            )
        } catch {
            showToast("Could not load ignore rules. \(error.localizedDescription)")
            return nil
        }
    }

    /// `file.writeWorkspaceFileSearchIgnore({rootPath, content})` writes `.zcodeignore`.
    @discardableResult
    public func writeWorkspaceFileSearchIgnore(rootPath: String, content: String) async -> Bool {
        guard !rootPath.isEmpty, isRemoteRPCReady else {
            showToast("Connect to your computer to save ignore rules")
            return false
        }
        do {
            _ = try await rpcClient.call(
                channel: "file",
                method: "writeWorkspaceFileSearchIgnore",
                args: [.fromJSONObject(["rootPath": rootPath, "content": content])],
                timeoutSec: 10
            )
            showToast("Saved; effective on the next search")
            return true
        } catch {
            showToast("Save failed. \(error.localizedDescription)")
            return false
        }
    }

    /// `file.applyWorkspaceFileSearchIgnoreTransform({rootPath, transform})` with
    /// transform `sync-gitignore` or `reset-defaults`; returns the transformed editor content.
    public func applyWorkspaceFileSearchIgnoreTransform(rootPath: String, transform: String) async -> String? {
        guard !rootPath.isEmpty else { return nil }
        guard isRemoteRPCReady else {
            showToast("Connect to your computer to edit ignore rules")
            return nil
        }
        do {
            let value = try await rpcClient.call(
                channel: "file",
                method: "applyWorkspaceFileSearchIgnoreTransform",
                args: [.fromJSONObject(["rootPath": rootPath, "transform": transform])],
                timeoutSec: 8
            )
            return value.decodeJSONDictionary()?["content"] as? String
        } catch {
            showToast("Failed to apply the section operation. \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Archived sessions (real zcode-task RPC forwards)

    public func restoreArchivedSession(_ sessionId: String) {
        restoreSession(sessionId)
    }

    public func deleteArchivedSessionPermanently(_ sessionId: String) {
        deleteSession(sessionId)
    }
}
