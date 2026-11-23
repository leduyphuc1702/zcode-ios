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

    private var currentWorkspaceContext: (path: String, identity: String?) {
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

    public func pushDesktopSettingPatch(_ patch: [String: Any]) {
        guard isRemoteRPCReady else { return }
        Task {
            _ = try? await rpcClient.call(
                channel: "setting",
                method: "update",
                args: [.fromJSONObject(patch)],
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
    }

    // MARK: - 1. Models & Providers (1:1 `provider-settings` RPC + Local Persistence)

    public func syncProvidersAndModelsRPC() async {
        guard let val = try? await rpcClient.call(channel: "provider-settings", method: "getView", args: [], timeoutSec: 4.5),
              let dict = val.decodeJSONDictionary() else { return }
        applyProviderSettingsViewDictionary(dict)
    }

    private func applyProviderSettingsViewDictionary(_ dict: [String: Any]) {
        let rev = (dict["revision"] as? Int) ?? 1
        guard let rawProviders = dict["providers"] as? [[String: Any]], !rawProviders.isEmpty else { return }

        var parsed: [ModelProviderConfig] = []
        for p in rawProviders {
            guard let pid = p["providerId"] as? String else { continue }
            let pname = (p["providerName"] as? String) ?? pid
            let enabled = (p["enabled"] as? Bool) ?? true
            let templateId = p["templateId"] as? String
            let effCfg = (p["effectiveConfig"] as? [String: Any]) ?? [:]
            let group = (effCfg["group"] as? String) ?? (pid.hasPrefix("account:") ? "zai-family" : "standard-personal")
            let apiDict = (effCfg["api"] as? [String: Any]) ?? [:]
            let accessDict = (effCfg["access"] as? [String: Any]) ?? [:]
            let apiType = (apiDict["type"] as? String) ?? ProviderAPIFormat.anthropicMessages.rawValue
            let baseURL = (apiDict["baseUrl"] as? String) ?? ""
            let apiKeyMgmt = accessDict["apiKeyManagementUrl"] as? String
            let rawKey = (accessDict["apiKey"] as? String) ?? ""
            let acctState = (p["accountState"] as? [String: Any]) ?? [:]
            let availability = (acctState["availability"] as? String) ?? "available"
            let entitled = (acctState["entitled"] as? Bool) ?? (p["executable"] as? Bool ?? true)
            let isBuiltin = pid.hasPrefix("account:") || group != "standard-personal"

            let statusText: String = {
                if isBuiltin {
                    if availability == "available" && entitled { return "Active • Account Entitled" }
                    if let reason = acctState["unavailableReason"] as? String { return reason.replacingOccurrences(of: "-", with: " ").capitalized }
                    return availability.capitalized
                }
                return !rawKey.isEmpty ? "API Key Configured" : "API Key Required"
            }()

            var models: [ModelDescriptor] = []
            if let rawModels = p["models"] as? [[String: Any]] {
                for m in rawModels {
                    guard let mid = m["modelId"] as? String else { continue }
                    let mEnabled = (m["enabled"] as? Bool) ?? true
                    let mBuiltin = (m["builtin"] as? Bool) ?? false
                    let useRec = (m["useRecommendedConfig"] as? Bool) ?? true
                    let mEff = (m["effectiveConfig"] as? [String: Any]) ?? [:]
                    let props = (mEff["properties"] as? [String: Any]) ?? [:]
                    let ctxTokens = (props["contextWindow"] as? Int) ?? 200_000
                    let inFmt = (props["inputFormat"] as? [String: Any]) ?? [:]
                    let supportsImg = (inFmt["supportsImage"] as? Bool) ?? true
                    let supportsVid = (inFmt["supportsVideo"] as? Bool) ?? false
                    let supportsAud = (inFmt["supportsAudio"] as? Bool) ?? false
                    let supportsPdf = (inFmt["supportsPdf"] as? Bool) ?? false
                    let supportsTool = (props["supportsToolCall"] as? Bool) ?? true
                    let supportsJson = (props["supportsJsonSchemaOutput"] as? Bool) ?? true
                    let supportsWeb = (props["supportsNativeWebSearch"] as? Bool) ?? false
                    let supportsMid = (props["supportsMidConversationSystem"] as? Bool) ?? true

                    let optSpecs = (mEff["optionSpecs"] as? [String: Any]) ?? [:]
                    let rSpec = (optSpecs["reasoningLevel"] as? [String: Any]) ?? [:]
                    let rValues = (rSpec["values"] as? [String]) ?? ["off", "low", "medium", "high", "max"]
                    let maxOutSpec = (optSpecs["maxOutputTokens"] as? [String: Any]) ?? [:]
                    let maxOut = (maxOutSpec["max"] as? Int) ?? 16_384

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
                            supportsVision: supportsImg,
                            supportsVideo: supportsVid,
                            supportsAudio: supportsAud,
                            supportsPdf: supportsPdf,
                            supportsToolCall: supportsTool,
                            supportsReasoning: !rValues.isEmpty,
                            supportsJsonSchemaOutput: supportsJson,
                            supportsNativeWebSearch: supportsWeb,
                            supportsMidConversationSystem: supportsMid,
                            reasoningLevels: rValues
                        )
                    )
                }
            }

            parsed.append(
                ModelProviderConfig(
                    id: pid,
                    name: pname,
                    baseURL: baseURL,
                    protocolKind: apiType,
                    group: group,
                    templateId: templateId,
                    apiKeyManagementURL: apiKeyMgmt,
                    hasConfiguredAPIKey: !rawKey.isEmpty || KeychainStore.load("provider_key_\(pid)") != nil,
                    enabled: enabled,
                    isBuiltin: isBuiltin,
                    entitled: entitled,
                    accountAvailability: availability,
                    statusText: statusText,
                    logoKey: templateId ?? "custom",
                    revision: rev,
                    models: models
                )
            )
        }

        if !parsed.isEmpty {
            self.providers = parsed
        }
    }

    @discardableResult
    public func createProvider(
        template: ProviderTemplateDescriptor?,
        customName: String,
        baseURL: String,
        apiFormat: ProviderAPIFormat,
        apiKey: String
    ) -> String {
        let cleanName = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (template?.name ?? "Custom Provider")
            : customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (template?.defaultBaseURL ?? "https://api.openai.com/v1")
            : baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let localId = "personal-\(UUID().uuidString.prefix(8).lowercased())"

        if !cleanKey.isEmpty {
            KeychainStore.save(cleanKey, for: "provider_key_\(localId)")
        }

        let seedModels: [ModelDescriptor] = (template?.defaultModelIds ?? []).map { mid in
            ModelDescriptor(
                id: "\(localId)/\(mid)",
                modelId: mid,
                name: mid,
                providerId: localId,
                providerName: cleanName,
                enabled: true,
                builtin: template != nil,
                useRecommendedConfig: true,
                contextWindowK: mid.lowercased().contains("1m") ? 1000 : 200,
                maxOutputTokens: 32_768,
                supportsVision: true,
                supportsReasoning: true
            )
        }

        let newProvider = ModelProviderConfig(
            id: localId,
            name: cleanName,
            baseURL: cleanURL,
            protocolKind: apiFormat.rawValue,
            group: "standard-personal",
            templateId: template?.id,
            apiKeyManagementURL: template?.apiKeyURL,
            hasConfiguredAPIKey: !cleanKey.isEmpty,
            enabled: true,
            isBuiltin: false,
            entitled: true,
            accountAvailability: "available",
            statusText: !cleanKey.isEmpty ? "API Key Configured" : "API Key Required",
            logoKey: template?.id ?? "custom",
            models: seedModels
        )
        providers.append(newProvider)
        showToast("Added provider \(cleanName)")

        if isRemoteRPCReady {
            Task {
                var req: [String: Any] = ["providerName": cleanName, "locale": "en-US"]
                if let tid = template?.id {
                    req["templateId"] = tid
                }
                req["initialConfig"] = [
                    "api": ["type": apiFormat.rawValue, "baseUrl": cleanURL],
                    "access": ["type": "api-key", "apiKey": cleanKey]
                ]
                if let reply = try? await rpcClient.call(channel: "provider-settings", method: "createPersonalProvider", args: [.fromJSONObject(req)], timeoutSec: 5.0),
                   let dict = reply.decodeJSONDictionary(),
                   let viewDict = dict["view"] as? [String: Any] {
                    await MainActor.run {
                        self.applyProviderSettingsViewDictionary(viewDict)
                    }
                }
            }
        }
        return localId
    }

    public func updateProviderConnection(
        providerId: String,
        name: String,
        baseURL: String,
        apiFormat: ProviderAPIFormat,
        apiKey: String?,
        enabled: Bool
    ) {
        guard let idx = providers.firstIndex(where: { $0.id == providerId }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            providers[idx].name = trimmedName
        }
        providers[idx].baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        providers[idx].apiFormat = apiFormat
        providers[idx].enabled = enabled

        if let apiKey {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty {
                KeychainStore.delete("provider_key_\(providerId)")
                providers[idx].hasConfiguredAPIKey = false
                if !providers[idx].isBuiltin { providers[idx].statusText = "API Key Required" }
            } else {
                KeychainStore.save(trimmedKey, for: "provider_key_\(providerId)")
                providers[idx].hasConfiguredAPIKey = true
                if !providers[idx].isBuiltin { providers[idx].statusText = "API Key Configured" }
            }
        }
        showToast("Saved \(providers[idx].name)")

        if isRemoteRPCReady, !providers[idx].isAccountProvider {
            let savedKey = KeychainStore.load("provider_key_\(providerId)") ?? ""
            let overlay: [String: Any] = [
                "api": [
                    "type": apiFormat.rawValue,
                    "baseUrl": providers[idx].baseURL
                ],
                "access": [
                    "type": "api-key",
                    "apiKey": savedKey
                ]
            ]
            let meta: [String: Any] = [
                "providerName": providers[idx].name,
                "enabled": enabled
            ]
            Task {
                if let reply = try? await rpcClient.call(
                    channel: "provider-settings",
                    method: "savePersonalProviderOverlay",
                    args: [.string(providerId), .fromJSONObject(overlay), .fromJSONObject(meta)],
                    timeoutSec: 5.0
                ), let viewDict = reply.decodeJSONDictionary() {
                    await MainActor.run {
                        self.applyProviderSettingsViewDictionary(viewDict)
                    }
                }
            }
        }
    }

    public func deleteProvider(_ providerId: String) {
        guard let idx = providers.firstIndex(where: { $0.id == providerId }),
              !providers[idx].isAccountProvider else { return }
        let removedName = providers[idx].name
        KeychainStore.delete("provider_key_\(providerId)")
        providers.remove(at: idx)
        showToast("Deleted \(removedName)")

        if isRemoteRPCReady {
            Task {
                if let reply = try? await rpcClient.call(
                    channel: "provider-settings",
                    method: "deletePersonalProvider",
                    args: [.string(providerId)],
                    timeoutSec: 4.5
                ), let viewDict = reply.decodeJSONDictionary() {
                    await MainActor.run { self.applyProviderSettingsViewDictionary(viewDict) }
                }
            }
        }
    }

    public func movePersonalProvider(providerId: String, direction: Int) {
        let personalIds = providers.filter { !$0.isAccountProvider }.map(\.id)
        guard let currentPos = personalIds.firstIndex(of: providerId) else { return }
        let targetPos = currentPos + direction
        guard targetPos >= 0 && targetPos < personalIds.count else { return }
        let otherId = personalIds[targetPos]
        guard let a = providers.firstIndex(where: { $0.id == providerId }),
              let b = providers.firstIndex(where: { $0.id == otherId }) else { return }
        providers.swapAt(a, b)

        if isRemoteRPCReady {
            let reordered = providers.filter { !$0.isAccountProvider }.map(\.id)
            Task {
                _ = try? await rpcClient.call(
                    channel: "provider-settings",
                    method: "reorderPersonalProviders",
                    args: [.array(reordered.map { .string($0) })],
                    timeoutSec: 4.0
                )
            }
        }
    }

    public func upsertModel(providerId: String, originalModelId: String?, draft: ModelDescriptor) {
        guard let pIdx = providers.firstIndex(where: { $0.id == providerId }) else { return }
        var normalized = draft
        normalized.providerId = providerId
        normalized.providerName = providers[pIdx].name
        normalized.id = "\(providerId)/\(draft.modelId)"

        if let originalModelId,
           let mIdx = providers[pIdx].models.firstIndex(where: { $0.modelId == originalModelId || $0.id == originalModelId }) {
            providers[pIdx].models[mIdx] = normalized
        } else if let existingIdx = providers[pIdx].models.firstIndex(where: { $0.modelId == draft.modelId }) {
            providers[pIdx].models[existingIdx] = normalized
        } else {
            normalized.builtin = false
            providers[pIdx].models.append(normalized)
        }
        showToast("Saved model \(draft.modelId)")

        if isRemoteRPCReady {
            let overlay: [String: Any] = [
                "enabled": normalized.enabled,
                "properties": [
                    "contextWindow": normalized.contextWindowTokens,
                    "supportsToolCall": normalized.supportsToolCall,
                    "supportsJsonSchemaOutput": normalized.supportsJsonSchemaOutput,
                    "supportsNativeWebSearch": normalized.supportsNativeWebSearch,
                    "supportsMidConversationSystem": normalized.supportsMidConversationSystem,
                    "inputFormat": [
                        "supportsText": true,
                        "supportsImage": normalized.supportsVision,
                        "supportsVideo": normalized.supportsVideo,
                        "supportsAudio": normalized.supportsAudio,
                        "supportsPdf": normalized.supportsPdf
                    ]
                ],
                "optionSpecs": [
                    "reasoningLevel": ["values": normalized.reasoningLevels],
                    "maxOutputTokens": ["max": normalized.maxOutputTokens]
                ]
            ]
            let rev = providers[pIdx].revision
            Task {
                if let originalModelId {
                    let req: [String: Any] = [
                        "providerId": providerId,
                        "originalModelId": originalModelId,
                        "nextModelId": normalized.modelId,
                        "basedOnRevision": rev,
                        "personalConfig": overlay,
                        "useRecommendedConfig": normalized.useRecommendedConfig
                    ]
                    if let reply = try? await rpcClient.call(channel: "provider-settings", method: "savePersonalModelDraft", args: [.fromJSONObject(req)], timeoutSec: 5.0),
                       let viewDict = reply.decodeJSONDictionary() {
                        await MainActor.run { self.applyProviderSettingsViewDictionary(viewDict) }
                    }
                } else {
                    if let reply = try? await rpcClient.call(
                        channel: "provider-settings",
                        method: "addPersonalModel",
                        args: [.string(providerId), .string(normalized.modelId), .fromJSONObject(overlay), .bool(normalized.useRecommendedConfig)],
                        timeoutSec: 5.0
                    ), let viewDict = reply.decodeJSONDictionary() {
                        await MainActor.run { self.applyProviderSettingsViewDictionary(viewDict) }
                    }
                }
            }
        }
    }

    public func setModelEnabled(providerId: String, modelId: String, enabled: Bool) {
        guard let pIdx = providers.firstIndex(where: { $0.id == providerId }),
              let mIdx = providers[pIdx].models.firstIndex(where: { $0.modelId == modelId || $0.id == modelId }) else { return }
        providers[pIdx].models[mIdx].enabled = enabled
        let rawModelId = providers[pIdx].models[mIdx].modelId

        if isRemoteRPCReady {
            Task {
                _ = try? await rpcClient.call(
                    channel: "provider-settings",
                    method: "setPersonalModelEnabled",
                    args: [.string(providerId), .string(rawModelId), .bool(enabled)],
                    timeoutSec: 4.0
                )
            }
        }
    }

    public func deleteModel(providerId: String, modelId: String) {
        guard let pIdx = providers.firstIndex(where: { $0.id == providerId }),
              let mIdx = providers[pIdx].models.firstIndex(where: { $0.modelId == modelId || $0.id == modelId }) else { return }
        let rawModelId = providers[pIdx].models[mIdx].modelId
        providers[pIdx].models.remove(at: mIdx)
        showToast("Removed \(rawModelId)")

        if isRemoteRPCReady {
            Task {
                _ = try? await rpcClient.call(
                    channel: "provider-settings",
                    method: "deletePersonalModel",
                    args: [.string(providerId), .string(rawModelId)],
                    timeoutSec: 4.0
                )
            }
        }
    }

    public func testModelConnectivity(providerId: String, modelId: String) async {
        guard let pIdx = providers.firstIndex(where: { $0.id == providerId }),
              let mIdx = providers[pIdx].models.firstIndex(where: { $0.modelId == modelId || $0.id == modelId }) else { return }

        let rawModelId = providers[pIdx].models[mIdx].modelId
        providers[pIdx].models[mIdx].connectivityState = .testing
        providers[pIdx].models[mIdx].connectivityMessage = "Testing…"
        let started = Date()

        if isRemoteRPCReady {
            let ctx = currentWorkspaceContext
            var req: [String: Any] = [
                "workspacePath": ctx.path.isEmpty ? "." : ctx.path,
                "providerId": providerId,
                "modelId": rawModelId
            ]
            if let ident = ctx.identity, !ident.isEmpty {
                req["workspaceIdentity"] = ident
            }
            do {
                let reply = try await rpcClient.call(
                    channel: "provider-settings",
                    method: "testModelConnectivity",
                    args: [.fromJSONObject(req)],
                    timeoutSec: 12.0
                )
                let ms = max(12, Int(Date().timeIntervalSince(started) * 1000))
                let dict = reply.decodeJSONDictionary()
                let ok = (dict?["success"] as? Bool) ?? false
                if let p2 = providers.firstIndex(where: { $0.id == providerId }),
                   let m2 = providers[p2].models.firstIndex(where: { $0.modelId == rawModelId }) {
                    if ok {
                        providers[p2].models[m2].connectivityState = .connected
                        providers[p2].models[m2].connectivityMessage = "Connected • \(ms)ms"
                        showToast("\(rawModelId) reachable (\(ms)ms)")
                    } else {
                        let errDict = dict?["error"] as? [String: Any]
                        let msg = (errDict?["message"] as? String) ?? "Connectivity check failed"
                        providers[p2].models[m2].connectivityState = .failed
                        providers[p2].models[m2].connectivityMessage = msg
                    }
                }
                return
            } catch {
                if let p2 = providers.firstIndex(where: { $0.id == providerId }),
                   let m2 = providers[p2].models.firstIndex(where: { $0.modelId == rawModelId }) {
                    providers[p2].models[m2].connectivityState = .failed
                    providers[p2].models[m2].connectivityMessage = error.localizedDescription
                }
                return
            }
        }

        providers[pIdx].models[mIdx].connectivityState = .failed
        providers[pIdx].models[mIdx].connectivityMessage = "Connect to your computer to test"
    }

    // MARK: - 2. Subagents Studio (1:1 `subagents` RPC + Validation)

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
              let dict = val.decodeJSONDictionary(),
              let rawAgents = dict["agents"] as? [[String: Any]] else { return }

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

    public func saveSubagent(_ draft: SubagentDefinitionItem, isNew: Bool) {
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

        if isNew {
            clean.id = "user:\(clean.scope):\(clean.name)"
            subagents.insert(clean, at: 0)
            showToast("Created subagent \(clean.name)")
        } else if let idx = subagents.firstIndex(where: { $0.id == draft.id }) {
            let oldPath = subagents[idx].filePath
            subagents[idx] = clean
            showToast("Updated subagent \(clean.name)")
            if isRemoteRPCReady {
                dispatchSubagentUpsertRPC(clean, isNew: false, oldFilePath: oldPath)
                return
            }
        }
        if isRemoteRPCReady {
            dispatchSubagentUpsertRPC(clean, isNew: true, oldFilePath: nil)
        }
    }

    private func dispatchSubagentUpsertRPC(_ item: SubagentDefinitionItem, isNew: Bool, oldFilePath: String?) {
        let ctx = currentWorkspaceContext
        var cfg: [String: Any] = [
            "name": item.name,
            "description": item.description,
            "systemPrompt": item.systemPrompt,
            "color": item.color.rawValue,
            "injectAgentsMd": item.injectAgentsMd,
            "background": item.runInBackground,
            "permissionMode": item.permissionMode.rawValue
        ]
        if !item.isAllTools {
            cfg["tools"] = item.allowedTools
        }
        if item.modelOverride != "inherit", !item.modelOverride.isEmpty {
            let parts = item.modelOverride.split(separator: "/", maxSplits: 1).map(String.init)
            var sel: [String: Any] = [
                "providerId": parts.count == 2 ? parts[0] : "account:zai-individual-coding-plan",
                "modelId": parts.count == 2 ? parts[1] : item.modelOverride
            ]
            if item.reasoningOverride != "inherit" {
                sel["options"] = ["reasoningLevel": item.reasoningOverride]
            }
            cfg["modelSelection"] = sel
        }

        var req: [String: Any] = [
            "config": cfg,
            "provider": "glm",
            "scope": item.scope == "workspace" ? "workspace" : "user",
            "workspacePath": ctx.path
        ]
        if let ident = ctx.identity { req["workspaceIdentity"] = ident }

        Task {
            if isNew {
                _ = try? await rpcClient.call(channel: "subagents", method: "createAgent", args: [.fromJSONObject(req)], timeoutSec: 5.0)
            } else {
                req["agentId"] = item.id
                if let oldFilePath { req["oldFilePath"] = oldFilePath }
                _ = try? await rpcClient.call(channel: "subagents", method: "updateAgent", args: [.fromJSONObject(req)], timeoutSec: 5.0)
            }
            await syncSubagentsRPC(workspacePath: ctx.path, workspaceIdentity: ctx.identity)
        }
    }

    public func deleteSubagent(_ id: String) {
        guard let idx = subagents.firstIndex(where: { $0.id == id }),
              !subagents[idx].readOnly else { return }
        let removed = subagents.remove(at: idx)
        showToast("Deleted subagent \(removed.name)")

        if isRemoteRPCReady {
            Task {
                _ = try? await rpcClient.call(
                    channel: "subagents",
                    method: "deleteAgent",
                    args: [.fromJSONObject(["agentId": removed.id, "filePath": removed.filePath])],
                    timeoutSec: 4.5
                )
            }
        }
    }

    public func setSubagentEnabled(_ id: String, enabled: Bool) {
        guard let idx = subagents.firstIndex(where: { $0.id == id }) else { return }
        subagents[idx].enabled = enabled

        if isRemoteRPCReady {
            Task {
                _ = try? await rpcClient.call(
                    channel: "subagents",
                    method: "setEnabled",
                    args: [.fromJSONObject(["agentId": id, "enabled": enabled])],
                    timeoutSec: 4.0
                )
            }
        }
    }

    public func setSubagentModelAndEffortOverride(id: String, modelOverride: String, reasoningOverride: String) {
        guard let idx = subagents.firstIndex(where: { $0.id == id }) else { return }
        subagents[idx].modelOverride = modelOverride
        subagents[idx].reasoningOverride = reasoningOverride
        let item = subagents[idx]
        showToast("Updated model for \(item.displayName)")

        guard isRemoteRPCReady else { return }
        var selectionObj: [String: Any]? = nil
        if modelOverride != "inherit" && !modelOverride.isEmpty {
            let parts = modelOverride.split(separator: "/", maxSplits: 1).map(String.init)
            var sel: [String: Any] = [
                "providerId": parts.count == 2 ? parts[0] : "account:zai-individual-coding-plan",
                "modelId": parts.count == 2 ? parts[1] : modelOverride
            ]
            if reasoningOverride != "inherit" {
                sel["options"] = ["reasoningLevel": reasoningOverride]
            }
            selectionObj = sel
        }

        Task {
            if item.source == "built-in" {
                var req: [String: Any] = ["agentName": item.name]
                if let selectionObj { req["modelSelection"] = selectionObj }
                _ = try? await rpcClient.call(channel: "subagents", method: "setBuiltInModelOverride", args: [.fromJSONObject(req)], timeoutSec: 4.0)
            } else if item.source == "plugin" {
                var req: [String: Any] = ["agentId": item.id]
                if let selectionObj { req["modelSelection"] = selectionObj }
                _ = try? await rpcClient.call(channel: "subagents", method: "setPluginAgentModelOverride", args: [.fromJSONObject(req)], timeoutSec: 4.0)
            } else if !item.readOnly {
                dispatchSubagentUpsertRPC(item, isNew: false, oldFilePath: item.filePath)
            }
        }
    }

    // MARK: - 3. MCP, Skills, Plugins, Commands, Hooks, Memory, Usage & Archives RPC

    public func syncMCPServersRPC(workspacePath: String, workspaceIdentity: String?) async {
        async let dirCall = try? rpcClient.call(
            channel: "mcp-sync",
            method: "loadMcpFromUserDirectory",
            args: [.fromJSONObject(["workspacePath": workspacePath])],
            timeoutSec: 4.0
        )
        var statusReqBuilder: [String: Any] = ["workspacePath": workspacePath, "mode": "status"]
        if let workspaceIdentity { statusReqBuilder["workspaceIdentity"] = workspaceIdentity }
        let statusReq = statusReqBuilder
        async let statusCall = try? rpcClient.call(
            channel: "mcp-sync",
            method: "listWorkspaceMcpServerStatuses",
            args: [.fromJSONObject(statusReq)],
            timeoutSec: 4.0
        )

        let (dirVal, statusVal) = await (dirCall, statusCall)
        let statuses = (statusVal?.decodeJSONDictionary()?["statuses"] as? [String: [String: Any]]) ?? [:]

        guard let rawServers = dirVal?.decodeJSONDictionary()?["servers"] as? [[String: Any]] else { return }
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
            let stText = (statuses[name]?["status"] as? String) ?? (enabled ? "Configured" : "Disabled")
            let connected = stText.lowercased().contains("connect") || stText.lowercased().contains("ready") || stText.lowercased() == "ok"

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
                    statusText: stText.capitalized,
                    tools: (statuses[name]?["tools"] as? [String]) ?? [],
                    resourcesCount: 0
                )
            )
        }
        self.mcpServers = list
    }

    public func upsertMCPServer(_ draft: MCPServerItem, isNew: Bool) {
        if let idx = mcpServers.firstIndex(where: { $0.id == draft.id || $0.name == draft.name }) {
            mcpServers[idx] = draft
        } else {
            mcpServers.append(draft)
        }
        showToast("Saved MCP server \(draft.name)")

        if isRemoteRPCReady {
            var cfg: [String: Any] = ["type": draft.transport, "timeoutMs": draft.timeoutMs]
            if draft.transport == "stdio" {
                cfg["command"] = draft.endpointOrCommand
                if !draft.args.isEmpty { cfg["args"] = draft.args }
            } else {
                cfg["url"] = draft.endpointOrCommand
            }
            if draft.transport != "sse" {
                cfg["protocolVersion"] = draft.protocolVersion
            }
            if let data = draft.envOrHeadersJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               !obj.isEmpty {
                cfg[draft.transport == "stdio" ? "env" : "headers"] = obj
            }
            var req: [String: Any] = [
                "action": "upsert",
                "name": draft.name,
                "config": cfg,
                "enabled": draft.enabled
            ]
            if draft.scope == "workspace", let path = activeProject?.rootPath {
                req["projectPath"] = path
            }
            Task {
                _ = try? await rpcClient.call(channel: "mcp-sync", method: "saveMcpToUserDirectory", args: [.fromJSONObject(req)], timeoutSec: 4.5)
            }
        }
    }

    public func deleteMCPServer(_ item: MCPServerItem) {
        mcpServers.removeAll(where: { $0.id == item.id })
        showToast("Removed MCP server \(item.name)")
        if isRemoteRPCReady {
            Task {
                _ = try? await rpcClient.call(
                    channel: "mcp-sync",
                    method: "saveMcpToUserDirectory",
                    args: [.fromJSONObject(["action": "delete", "name": item.name])],
                    timeoutSec: 4.0
                )
            }
        }
    }

    public func setMCPServerEnabled(_ item: MCPServerItem, enabled: Bool) {
        guard let idx = mcpServers.firstIndex(where: { $0.id == item.id }) else { return }
        mcpServers[idx].enabled = enabled
        mcpServers[idx].statusText = enabled ? "Enabled" : "Disabled"
        if isRemoteRPCReady {
            Task {
                _ = try? await rpcClient.call(
                    channel: "mcp-sync",
                    method: "saveMcpToUserDirectory",
                    args: [.fromJSONObject(["action": "set-enabled", "name": item.name, "enabled": enabled])],
                    timeoutSec: 4.0
                )
            }
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

    public func setSkillEnabled(_ item: SkillCatalogItem, enabled: Bool) {
        guard let idx = skills.firstIndex(where: { $0.id == item.id }) else { return }
        skills[idx].enabled = enabled
        if isRemoteRPCReady {
            let ctx = currentWorkspaceContext
            var req: [String: Any] = [
                "workspacePath": ctx.path,
                "provider": "glm",
                "scope": item.scope.lowercased(),
                "skillId": item.id,
                "enabled": enabled
            ]
            if let ident = ctx.identity { req["workspaceIdentity"] = ident }
            Task {
                _ = try? await rpcClient.call(channel: "skills", method: "setEnabled", args: [.fromJSONObject(req)], timeoutSec: 4.0)
            }
        }
    }

    public func syncPluginsRPC(workspacePath: String, workspaceIdentity: String?) async {
        var req: [String: Any] = ["workspacePath": workspacePath]
        if let workspaceIdentity { req["workspaceIdentity"] = workspaceIdentity }
        guard let val = try? await rpcClient.call(channel: "plugin-management", method: "getPluginsOverview", args: [.fromJSONObject(req)], timeoutSec: 4.5),
              let dict = val.decodeJSONDictionary() else { return }

        if let mks = dict["marketplaces"] as? [[String: Any]] {
            let names = mks.compactMap { $0["name"] as? String }
            if !names.isEmpty { self.pluginMarketplaces = names }
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
        self.plugins = merged
    }

    public func setPluginEnabled(_ item: PluginCatalogItem, enabled: Bool) {
        guard let idx = plugins.firstIndex(where: { $0.id == item.id }) else { return }
        plugins[idx].enabled = enabled
        if isRemoteRPCReady {
            let ctx = currentWorkspaceContext
            var req: [String: Any] = ["workspacePath": ctx.path, "pluginId": item.id, "enabled": enabled]
            if let ident = ctx.identity { req["workspaceIdentity"] = ident }
            Task {
                _ = try? await rpcClient.call(channel: "plugin-management", method: "setPluginEnabled", args: [.fromJSONObject(req)], timeoutSec: 4.5)
            }
        }
    }

    public func syncCommandsRPC(workspacePath: String) async {
        guard let val = try? await rpcClient.call(
            channel: "commands",
            method: "list",
            args: [.fromJSONObject(["workspacePath": workspacePath, "agentSource": "zcodeAgent"])],
            timeoutSec: 4.0
        ), let raw = val.decodeJSONDictionary()?["commands"] as? [[String: Any]] else { return }

        var parsed: [SlashCommandItem] = []
        for c in raw {
            guard let id = c["id"] as? String, let name = c["name"] as? String else { continue }
            let src = (c["source"] as? String) ?? "user"
            let scope = src == "plugin" ? "Plugin" : (((c["scope"] as? String) == "project") ? "Project" : "User")
            parsed.append(
                SlashCommandItem(
                    id: id,
                    trigger: name,
                    summary: (c["description"] as? String) ?? "Custom slash command",
                    argumentHint: (c["argumentHint"] as? String) ?? "",
                    scope: scope,
                    enabled: (c["enabled"] as? Bool) ?? true,
                    filePath: (c["filePath"] as? String) ?? "",
                    promptTemplate: (c["prompt"] as? String) ?? ""
                )
            )
        }
        self.slashCommands = parsed
    }

    public func upsertSlashCommand(_ draft: SlashCommandItem, isNew: Bool) {
        let oldPath = slashCommands.first(where: { $0.id == draft.id })?.filePath
        if let idx = slashCommands.firstIndex(where: { $0.id == draft.id }) {
            slashCommands[idx] = draft
        } else {
            slashCommands.append(draft)
        }
        showToast("Saved command \(draft.trigger)")

        if isRemoteRPCReady {
            let cleanName = draft.trigger.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
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
            Task {
                if isNew {
                    _ = try? await rpcClient.call(channel: "commands", method: "writeCommandFile", args: [.fromJSONObject(req)], timeoutSec: 4.5)
                } else {
                    if let oldPath { req["oldFilePath"] = oldPath }
                    _ = try? await rpcClient.call(channel: "commands", method: "updateCommandFile", args: [.fromJSONObject(req)], timeoutSec: 4.5)
                }
            }
        }
    }

    public func deleteSlashCommand(_ item: SlashCommandItem) {
        guard item.scope != "System" else { return }
        slashCommands.removeAll(where: { $0.id == item.id })
        showToast("Deleted \(item.trigger)")
        if isRemoteRPCReady && !item.filePath.isEmpty {
            Task {
                _ = try? await rpcClient.call(channel: "commands", method: "deleteCommandFile", args: [.fromJSONObject(["filePath": item.filePath])], timeoutSec: 4.0)
            }
        }
    }

    public func syncHooksRPC(workspacePath: String, workspaceIdentity: String?) async {
        var req: [String: Any] = ["workspacePath": workspacePath]
        if let workspaceIdentity { req["workspaceIdentity"] = workspaceIdentity }
        guard let val = try? await rpcClient.call(channel: "hooks", method: "loadHooks", args: [.fromJSONObject(req)], timeoutSec: 4.0),
              let raw = val.decodeJSONDictionary()?["hooks"] as? [[String: Any]] else { return }

        self.hooks = raw.compactMap { h in
            guard let id = h["id"] as? String,
                  let event = h["event"] as? String,
                  let cmd = h["command"] as? String else { return nil }
            let loc = h["location"] as? [String: Any]
            return HookRuleItem(
                id: id,
                event: event,
                matcher: (h["matcher"] as? String) ?? "*",
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
    }

    public func upsertHookRule(_ draft: HookRuleItem) {
        if let idx = hooks.firstIndex(where: { $0.id == draft.id }) {
            hooks[idx] = draft
        } else {
            hooks.append(draft)
        }
        pushHooksToDesktopIfConnected()
        showToast("Saved hook on \(draft.event)")
    }

    public func deleteHookRule(_ item: HookRuleItem) {
        hooks.removeAll(where: { $0.id == item.id })
        pushHooksToDesktopIfConnected()
        showToast("Deleted hook")
    }

    public func pushHooksToDesktopIfConnected() {
        guard isRemoteRPCReady else { return }
        let serialized: [[String: Any]] = hooks.filter(\.editable).map { h in
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
        let path = currentWorkspaceContext.path
        Task {
            _ = try? await rpcClient.call(
                channel: "hooks",
                method: "saveHooks",
                args: [.fromJSONObject(["workspacePath": path, "hooks": serialized])],
                timeoutSec: 4.5
            )
        }
    }

    public func syncMemoriesRPC() async {
        if let val = try? await rpcClient.call(channel: "memory", method: "loadMemory", args: [.fromJSONObject([:])], timeoutSec: 4.0),
           let mem = val.decodeJSONDictionary()?["memory"] as? [String: Any],
           let content = mem["content"] as? String {
            self.userMemoryMarkdown = content
        }
    }

    public func saveUserMemoryMarkdown(_ content: String) {
        userMemoryMarkdown = content
        showToast("Saved global MEMORY.md")
        if isRemoteRPCReady {
            Task {
                _ = try? await rpcClient.call(
                    channel: "memory",
                    method: "saveMemory",
                    args: [.fromJSONObject(["config": ["content": content]])],
                    timeoutSec: 4.5
                )
            }
        }
    }

    public func syncUsageStatsRPC(range: String = "7d") async {
        guard let val = try? await rpcClient.call(
            channel: "usage-stats",
            method: "getAppUsageStats",
            args: [.fromJSONObject(["range": range])],
            timeoutSec: 4.5
        ), let dict = val.decodeJSONDictionary(),
           let daily = dict["dailyModelUsage"] as? [[String: Any]],
           !daily.isEmpty else { return }

        self.tokenUsageStats = daily.suffix(14).enumerated().map { idx, d in
            let dateStr = (d["date"] as? String) ?? "Day \(idx + 1)"
            let shortLabel = String(dateStr.suffix(5))
            let totalTok = (d["totalTokens"] as? Int) ?? 0
            let inK = max(1, Int(Double(totalTok) * 0.78 / 1000.0))
            let outK = max(1, Int(Double(totalTok) * 0.22 / 1000.0))
            return DailyTokenUsageItem(
                id: "usage-\(dateStr)",
                dayLabel: shortLabel,
                inputTokensK: inK,
                outputTokensK: outK,
                cachedTokensK: Int(Double(inK) * 0.65),
                costUSD: Double(totalTok) / 1_000_000.0 * 3.2
            )
        }
    }

    public func restoreArchivedSession(_ sessionId: String) {
        restoreSession(sessionId)
    }

    public func deleteArchivedSessionPermanently(_ sessionId: String) {
        deleteSession(sessionId)
    }
}
