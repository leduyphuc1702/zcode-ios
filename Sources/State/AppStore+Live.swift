import Foundation
import Network
import SwiftUI

// MARK: - Host model selection types (mirror of @zcode/shared ModelSelection / model-selection view)

public struct LiveModelSelection: Equatable, Hashable {
    public var providerId: String
    public var modelId: String
    public var reasoningLevel: String?

    public init(providerId: String, modelId: String, reasoningLevel: String? = nil) {
        self.providerId = providerId
        self.modelId = modelId
        self.reasoningLevel = reasoningLevel
    }

    /// Parses the host picker value `provider/model$level` (provider ends at the first `/`).
    public init?(pickerValue: String?) {
        guard let raw = pickerValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let slash = raw.firstIndex(of: "/"), slash != raw.startIndex else { return nil }
        let provider = String(raw[..<slash])
        var model = String(raw[raw.index(after: slash)...])
        var level: String?
        if let dollar = model.firstIndex(of: "$"), dollar != model.startIndex, model.index(after: dollar) != model.endIndex {
            level = String(model[model.index(after: dollar)...])
            model = String(model[..<dollar])
        }
        guard !model.isEmpty else { return nil }
        self.init(providerId: provider, modelId: model, reasoningLevel: level)
    }

    public init?(json: [String: Any]?) {
        guard let json,
              let provider = json["providerId"] as? String, !provider.isEmpty,
              let model = json["modelId"] as? String, !model.isEmpty else { return nil }
        let level = (json["options"] as? [String: Any])?["reasoningLevel"] as? String
        self.init(providerId: provider, modelId: model, reasoningLevel: level)
    }

    public var jsonObject: [String: Any] {
        var out: [String: Any] = ["providerId": providerId, "modelId": modelId]
        if let reasoningLevel, !reasoningLevel.isEmpty {
            out["options"] = ["reasoningLevel": reasoningLevel]
        }
        return out
    }
}

public struct LiveModelOption: Identifiable, Equatable, Hashable {
    public var providerId: String
    public var providerName: String
    public var modelId: String
    public var contextWindow: Int?
    public var supportsImage: Bool
    public var reasoningLevels: [String]

    public var id: String { "\(providerId)/\(modelId)" }
    public var defaultReasoningLevel: String? { reasoningLevels.last }
}

public struct LiveModelProviderGroup: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var models: [LiveModelOption]
}

/// Non-observed bookkeeping for host subscriptions; all access happens on the main actor.
final class LiveSyncState {
    var workspaceSubs: [String: Int32] = [:]
    var activeTaskId: String?
    var activeTaskSubId: Int32?
    var subscribingTaskId: String?
    var modelViewSubId: Int32?
    var snapshotRefetch: [String: Task<Void, Never>] = [:]
    var workspaceRefresh: [String: Task<Void, Never>] = [:]
    var elicitations: [String: [String: Any]] = [:]
    var elicitationAnswers: [String: [Int: [String]]] = [:]
    var elicitationIndex: [String: Int] = [:]
    var permissionOptions: [String: [[String: Any]]] = [:]
    var streamingMessageId: [String: String] = [:]
    var suppressBridgeResubscribe = false
    var resubscribeTask: Task<Void, Never>?
    var reconnectTask: Task<Void, Never>?
    var reconnectAttempts = 0
    var syncedConnectionId: String?
    var kickedConnectionId: String?
    var isForeground = true
    var networkSatisfied = true
    var networkInterfaceSignature = ""
    var pathMonitor: NWPathMonitor?
    var resumeCheckTask: Task<Void, Never>?
    var peerResyncTask: Task<Void, Never>?
    var backgroundedAt: Date?
    var rebootstrapTask: Task<Void, Never>?
    var bridgeRecoveryTask: Task<Void, Never>?
    let controller = ControllerTaskIndexState()

    func reset() {
        controller.reset()
        workspaceSubs.removeAll()
        activeTaskId = nil
        activeTaskSubId = nil
        subscribingTaskId = nil
        modelViewSubId = nil
        snapshotRefetch.values.forEach { $0.cancel() }
        snapshotRefetch.removeAll()
        workspaceRefresh.values.forEach { $0.cancel() }
        workspaceRefresh.removeAll()
        streamingMessageId.removeAll()
        resubscribeTask?.cancel()
        resubscribeTask = nil
    }
}

extension AppStore {
    static let remoteClientId: String = {
        let key = "zcode_mobile_client_id_v1"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty { return existing }
        let fresh = "ios-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    var isLiveHostConnected: Bool {
        guard !isUITestSeededMode, let conn = activeConnection else { return false }
        return conn.transport != .enterpriseSandbox && conn.state == .connected
    }

    // MARK: - Model view

    public var liveModelOptions: [LiveModelOption] {
        liveModelGroups.flatMap(\.models)
    }

    public func liveModel(providerId: String?, modelId: String) -> LiveModelOption? {
        if let providerId, let exact = liveModelOptions.first(where: { $0.providerId == providerId && $0.modelId == modelId }) {
            return exact
        }
        return liveModelOptions.first(where: { $0.modelId == modelId })
    }

    /// Model selection to send for a session: task-local first, then the host's preferred selection.
    public func modelSelection(for session: AgentTaskSession) -> LiveModelSelection? {
        if !session.modelId.isEmpty {
            if let provider = session.modelProviderId, !provider.isEmpty {
                return LiveModelSelection(providerId: provider, modelId: session.modelId, reasoningLevel: session.reasoningLevel)
            }
            if let option = liveModel(providerId: nil, modelId: session.modelId) {
                return LiveModelSelection(
                    providerId: option.providerId,
                    modelId: option.modelId,
                    reasoningLevel: session.reasoningLevel ?? option.defaultReasoningLevel
                )
            }
        }
        return preferredModelSelection
    }

    public func reasoningLevels(for session: AgentTaskSession?) -> [String] {
        guard let session else { return [] }
        let selection = modelSelection(for: session)
        return liveModel(providerId: selection?.providerId, modelId: selection?.modelId ?? session.modelId)?.reasoningLevels ?? []
    }

    func refreshLiveModelView() async {
        guard let value = try? await rpcClient.call(channel: "model-selection", method: "getView", args: [], timeoutSec: 8.0),
              let dict = value.decodeJSONDictionary() else { return }
        applyModelView(dict)
    }

    func applyModelView(_ dict: [String: Any]) {
        var groups: [LiveModelProviderGroup] = []
        for provider in (dict["providers"] as? [[String: Any]]) ?? [] {
            guard let providerId = provider["providerId"] as? String, !providerId.isEmpty else { continue }
            let providerName = (provider["providerName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? providerId
            var models: [LiveModelOption] = []
            for model in (provider["models"] as? [[String: Any]]) ?? [] {
                guard let modelId = model["modelId"] as? String, !modelId.isEmpty else { continue }
                let config = model["config"] as? [String: Any]
                if (config?["enabled"] as? Bool) == false { continue }
                let properties = config?["properties"] as? [String: Any]
                let inputFormat = properties?["inputFormat"] as? [String: Any]
                let optionSpecs = config?["optionSpecs"] as? [String: Any]
                let levels = ((optionSpecs?["reasoningLevel"] as? [String: Any])?["values"] as? [String]) ?? []
                models.append(LiveModelOption(
                    providerId: providerId,
                    providerName: providerName,
                    modelId: modelId,
                    contextWindow: properties?["contextWindow"] as? Int,
                    supportsImage: (inputFormat?["supportsImage"] as? Bool) ?? false,
                    reasoningLevels: levels
                ))
            }
            if let order = (provider["config"] as? [String: Any])?["modelOrder"] as? [String], !order.isEmpty {
                let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
                models.sort { (rank[$0.modelId] ?? Int.max) < (rank[$1.modelId] ?? Int.max) }
            }
            if !models.isEmpty {
                groups.append(LiveModelProviderGroup(id: providerId, name: providerName, models: models))
            }
        }
        liveModelGroups = groups
        if let preferred = LiveModelSelection(json: dict["preferredSelection"] as? [String: Any]) {
            preferredModelSelection = preferred
        } else if preferredModelSelection == nil, let first = groups.first?.models.first {
            preferredModelSelection = LiveModelSelection(providerId: first.providerId, modelId: first.modelId, reasoningLevel: first.defaultReasoningLevel)
        }
    }

    // MARK: - Composer actions (model / reasoning / mode)

    public func selectModel(_ option: LiveModelOption) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == activeSession?.id }) else {
            preferredModelSelection = LiveModelSelection(providerId: option.providerId, modelId: option.modelId, reasoningLevel: option.defaultReasoningLevel)
            return
        }
        playSelectionHaptic()
        let keepLevel = sessions[sIdx].reasoningLevel.flatMap { option.reasoningLevels.contains($0) ? $0 : nil }
        let selection = LiveModelSelection(
            providerId: option.providerId,
            modelId: option.modelId,
            reasoningLevel: keepLevel ?? option.defaultReasoningLevel
        )
        sessions[sIdx].modelProviderId = selection.providerId
        sessions[sIdx].modelId = selection.modelId
        sessions[sIdx].reasoningLevel = selection.reasoningLevel
        let session = sessions[sIdx]
        guard isLiveHostConnected, !session.id.hasPrefix("task-") else { return }
        if v4Owns(session.id) {
            v4SwitchModel(selection, session: session)
            return
        }
        Task { @MainActor in
            do {
                _ = try await self.rpcClient.call(
                    channel: "zcode-task",
                    method: "setModel",
                    args: [.fromJSONObject(["taskId": session.id, "modelSelection": selection.jsonObject])],
                    timeoutSec: 10.0
                )
            } catch {
                self.showToast("Couldn't switch model: \(error.localizedDescription)")
                self.scheduleSnapshotRefetch(taskId: session.id, delay: 0.05)
            }
        }
    }

    public func selectReasoningLevel(_ level: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == activeSession?.id }) else { return }
        playSelectionHaptic()
        if sessions[sIdx].modelProviderId == nil, let selection = modelSelection(for: sessions[sIdx]) {
            sessions[sIdx].modelProviderId = selection.providerId
            sessions[sIdx].modelId = selection.modelId
        }
        sessions[sIdx].reasoningLevel = level
        let session = sessions[sIdx]
        guard isLiveHostConnected, !session.id.hasPrefix("task-") else { return }
        if v4Owns(session.id), let selection = modelSelection(for: session) {
            v4SwitchModel(LiveModelSelection(providerId: selection.providerId, modelId: selection.modelId, reasoningLevel: level), session: session)
            return
        }
        Task { @MainActor in
            do {
                _ = try await self.rpcClient.call(
                    channel: "zcode-task",
                    method: "setConfigOption",
                    args: [.fromJSONObject(["taskId": session.id, "configId": "thought_level", "value": level])],
                    timeoutSec: 10.0
                )
            } catch {
                self.showToast("Couldn't change reasoning: \(error.localizedDescription)")
                self.scheduleSnapshotRefetch(taskId: session.id, delay: 0.05)
            }
        }
    }

    public func selectMode(_ mode: AgentExecutionMode) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == activeSession?.id }) else { return }
        playSelectionHaptic()
        sessions[sIdx].mode = mode
        let session = sessions[sIdx]
        guard isLiveHostConnected, !session.id.hasPrefix("task-") else { return }
        if v4Owns(session.id) {
            v4Fire("switchCollaborationMode", payload: ["mode": mode.wireValue], session: session, failure: "Couldn't change mode")
            return
        }
        Task { @MainActor in
            do {
                _ = try await self.rpcClient.call(
                    channel: "zcode-task",
                    method: "setMode",
                    args: [.fromJSONObject(["taskId": session.id, "mode": mode.wireValue])],
                    timeoutSec: 10.0
                )
            } catch {
                self.showToast("Couldn't change mode: \(error.localizedDescription)")
                self.scheduleSnapshotRefetch(taskId: session.id, delay: 0.05)
            }
        }
    }

    private func v4SwitchModel(_ selection: LiveModelSelection, session: AgentTaskSession) {
        var payload: [String: Any] = ["provider": selection.providerId, "model": selection.modelId]
        if let level = selection.reasoningLevel { payload["thought"] = level }
        v4Fire("switchModelConfig", payload: payload, session: session, failure: "Couldn't switch model")
    }

    // MARK: - Task lists (all workspaces, official scope fan-out)

    private func scopeArg(workspacePath: String, workspaceIdentity: String?) -> VQLValue {
        var req: [String: Any] = ["workspacePath": workspacePath]
        if let workspaceIdentity, !workspaceIdentity.isEmpty {
            req["workspaceIdentity"] = workspaceIdentity
        }
        return .fromJSONObject(req)
    }

    /// Mirrors the official renderer: listTasks + listPinnedTasks + listArchivedTasks + listDeletedTaskIds + listPinnedTaskIds.
    /// Returns nil when the host could not serve this workspace through the current bridge.
    func fetchWorkspaceTaskScope(
        workspacePath: String,
        workspaceIdentity: String?,
        projectId: String,
        timeoutSec: Double
    ) async -> [AgentTaskSession]? {
        let arg = scopeArg(workspacePath: workspacePath, workspaceIdentity: workspaceIdentity)
        let client = rpcClient
        async let regularCall = try? client.call(channel: "zcode-task", method: "listTasks", args: [arg], timeoutSec: timeoutSec)
        async let pinnedCall = try? client.call(channel: "zcode-task", method: "listPinnedTasks", args: [arg], timeoutSec: timeoutSec)
        async let archivedCall = try? client.call(channel: "zcode-task", method: "listArchivedTasks", args: [arg], timeoutSec: timeoutSec)
        async let deletedCall = try? client.call(channel: "zcode-task", method: "listDeletedTaskIds", args: [arg], timeoutSec: timeoutSec)
        async let pinnedIdsCall = try? client.call(channel: "zcode-task", method: "listPinnedTaskIds", args: [], timeoutSec: timeoutSec)
        let (regular, pinned, archived, deleted, pinnedIds) = await (regularCall, pinnedCall, archivedCall, deletedCall, pinnedIdsCall)

        if regular == nil && pinned == nil && archived == nil {
            return nil
        }

        let deletedSet = Set((deleted?.decodeJSONValue() as? [Any])?.compactMap { $0 as? String } ?? [])
        let pinnedSet = Set((pinnedIds?.decodeJSONValue() as? [Any])?.compactMap { $0 as? String } ?? [])

        var seen = Set<String>()
        var out: [AgentTaskSession] = []
        func ingest(_ value: VQLValue?, archivedFlag: Bool, pinnedFlag: Bool) {
            guard let items = value?.decodeJSONValue() as? [Any] else { return }
            for item in items {
                guard let dict = item as? [String: Any],
                      let summary = ZCodeRPCClient.parseTaskSummary(dict, fallbackWorkspacePath: workspacePath, fallbackWorkspaceIdentity: workspaceIdentity),
                      !deletedSet.contains(summary.id),
                      seen.insert(summary.id).inserted else { continue }
                var session = Self.makeAgentSession(from: summary, projectId: projectId)
                if archivedFlag { session.archived = true }
                if pinnedFlag || pinnedSet.contains(summary.id) { session.pinned = true }
                out.append(session)
            }
        }
        ingest(pinned, archivedFlag: false, pinnedFlag: true)
        ingest(regular, archivedFlag: false, pinnedFlag: false)
        ingest(archived, archivedFlag: true, pinnedFlag: false)

        out.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
        return out
    }

    /// Loads tasks for every opened Desktop workspace. Workspaces the current bridge can't serve
    /// (e.g. SSH remotes on another server) get their own bridge, then the primary bridge is restored.
    func loadAllWorkspaceTasks(preferredActiveTaskId: String?) async {
        guard !isUITestSeededMode else { return }
        let projectList = projects
        guard !projectList.isEmpty else { return }

        var results: [String: [AgentTaskSession]] = [:]
        var failed: [WorkspaceProject] = []
        await withTaskGroup(of: (WorkspaceProject, [AgentTaskSession]?).self) { group in
            for project in projectList {
                let identity = workspaceIdentityByPath[project.rootPath]
                group.addTask { @MainActor in
                    let tasks = await self.fetchWorkspaceTaskScope(
                        workspacePath: project.rootPath,
                        workspaceIdentity: identity,
                        projectId: project.id,
                        timeoutSec: 8.0
                    )
                    return (project, tasks)
                }
            }
            for await (project, tasks) in group {
                if let tasks { results[project.id] = tasks } else { failed.append(project) }
            }
        }

        if !failed.isEmpty, await rpcClient.isRelay {
            let primaryBridge = await rpcClient.currentBridge()
            liveSync.suppressBridgeResubscribe = true
            for project in failed {
                let identity = workspaceIdentityByPath[project.rootPath]
                let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: project.rootPath, workspaceIdentity: identity)
                guard (try? await rpcClient.openWorkspaceBridge(workspaceKey: key, taskId: nil, timeoutSec: 6.0)) != nil else { continue }
                if let tasks = await fetchWorkspaceTaskScope(workspacePath: project.rootPath, workspaceIdentity: identity, projectId: project.id, timeoutSec: 8.0) {
                    results[project.id] = tasks
                }
            }
            if let primaryBridge, await rpcClient.currentBridge()?.workspaceKey != primaryBridge.workspaceKey {
                _ = try? await rpcClient.openWorkspaceBridge(
                    workspaceKey: primaryBridge.workspaceKey,
                    taskId: primaryBridge.initialTaskId,
                    timeoutSec: 6.0
                )
            }
            liveSync.suppressBridgeResubscribe = false
        }

        guard !results.isEmpty else { return }
        var merged: [AgentTaskSession] = []
        for project in projectList {
            if let fresh = results[project.id] {
                for var task in fresh {
                    if let existing = sessions.first(where: { $0.id == task.id }) {
                        task.messages = existing.messages
                        task.todos = existing.todos.isEmpty ? task.todos : existing.todos
                        task.contextUsedPercent = existing.contextUsedPercent
                        task.pendingPermission = existing.pendingPermission
                        task.pendingQuestion = existing.pendingQuestion
                        task.pendingPlan = existing.pendingPlan
                        task.queuedPrompts = existing.queuedPrompts
                    }
                    merged.append(task)
                }
            } else {
                merged.append(contentsOf: sessions.filter { $0.projectId == project.id })
            }
        }
        let mergedIds = Set(merged.map(\.id))
        merged.append(contentsOf: sessions.filter { $0.id.hasPrefix("task-") && !mergedIds.contains($0.id) })
        sessions = merged

        if let preferredActiveTaskId, merged.contains(where: { $0.id == preferredActiveTaskId }) {
            activeSessionId = preferredActiveTaskId
        } else if !merged.contains(where: { $0.id == activeSessionId }) {
            activeSessionId = merged.first(where: { !$0.archived && $0.projectId == activeProjectId })?.id
                ?? merged.first(where: { !$0.archived })?.id ?? ""
        }
    }

    // MARK: - Realtime subscriptions

    func installLiveConnectionHandlers() async {
        await rpcClient.setBridgeChangeHandler { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.liveSync.suppressBridgeResubscribe else { return }
                self.liveSync.workspaceSubs.removeAll()
                self.liveSync.modelViewSubId = nil
                self.liveSync.activeTaskSubId = nil
                self.liveSync.activeTaskId = nil
                self.scheduleResubscribe(handlersCleared: true)
            }
        }
        await rpcClient.setBridgeDegradedHandler { [weak self] reason in
            Task { @MainActor in
                self?.recoverDegradedBridge(reason: reason)
            }
        }
        await rpcClient.setBootstrapRequiredHandler { [weak self] in
            Task { @MainActor in
                self?.rebootstrapRelay(reason: "bootstrap-required")
            }
        }
        await rpcClient.setConnectionLostHandler { [weak self] reason in
            Task { @MainActor in
                self?.handleHostConnectionLost(reason: reason)
            }
        }
        await rpcClient.setPeerStatusHandler { [weak self] online in
            Task { @MainActor in
                self?.handlePeerStatus(online: online)
            }
        }
        await rpcClient.setTerminalErrorHandler { [weak self] code, message in
            Task { @MainActor in
                self?.handleTerminalError(code: code, message: message)
            }
        }
    }

    func scheduleResubscribe(handlersCleared: Bool) {
        liveSync.resubscribeTask?.cancel()
        liveSync.resubscribeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await self.resubscribeAll(handlersCleared: handlersCleared)
        }
    }

    func resubscribeAll(handlersCleared: Bool) async {
        guard isLiveHostConnected || pairingPhase == .pairedSyncing else { return }
        if !handlersCleared {
            for subId in liveSync.workspaceSubs.values { await rpcClient.unlisten(subId) }
            if let modelSub = liveSync.modelViewSubId { await rpcClient.unlisten(modelSub) }
            if let taskSub = liveSync.activeTaskSubId { await rpcClient.unlisten(taskSub) }
            for subId in Array(v4Sync.conversationFrameSubs.values) + Array(v4Sync.indexFrameSubs.values) {
                await rpcClient.unlisten(subId)
            }
            if let lifecycle = v4Sync.lifecycleSubId { await rpcClient.unlisten(lifecycle) }
            for subId in [hostSettings.broadcastSubId, hostSettings.providerSubId].compactMap({ $0 }) {
                await rpcClient.unlisten(subId)
            }
            if let controllerSub = liveSync.controller.frameSubId { await rpcClient.unlisten(controllerSub) }
        }
        liveSync.controller.reset()
        v4Sync.resetConnection()
        resetHostSettingsSubscriptions()
        liveSync.workspaceSubs.removeAll()
        liveSync.modelViewSubId = nil
        liveSync.activeTaskSubId = nil
        liveSync.activeTaskId = nil

        if let subId = try? await rpcClient.listen(channel: "model-selection", event: "onDidChange", onEvent: { [weak self] _ in
            Task { @MainActor in await self?.refreshLiveModelView() }
        }) {
            liveSync.modelViewSubId = subId
        }
        await refreshLiveModelView()
        await subscribeHostSettings()

        for project in projects {
            await subscribeWorkspaceEvents(project)
        }

        if let session = activeSession, !session.id.hasPrefix("task-") {
            await subscribeActiveTask(session)
        }
        await subscribeSessionsIndexes()
        await subscribeControllerTaskIndex()
    }

    /// Live status badges for every session; over the relay only the bridged workspace is reachable.
    func subscribeSessionsIndexes() async {
        guard await v4EnsureHandshake() else { return }
        let bridgeKey = await rpcClient.currentBridge()?.workspaceKey
        let isRelay = await rpcClient.isRelay
        for project in projects {
            let identity = workspaceIdentityByPath[project.rootPath]
            let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: project.rootPath, workspaceIdentity: identity)
            if isRelay, key != bridgeKey { continue }
            await v4SubscribeSessionsIndex(projectId: project.id, path: project.rootPath, identity: identity)
        }
    }

    func subscribeWorkspaceEvents(_ project: WorkspaceProject) async {
        let identity = workspaceIdentityByPath[project.rootPath]
        let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: project.rootPath, workspaceIdentity: identity)
        guard liveSync.workspaceSubs[key] == nil else { return }
        let projectId = project.id
        let path = project.rootPath
        if let subId = try? await rpcClient.listen(
            channel: "zcode-task",
            event: "onDynamicWorkspaceEvent",
            arg: scopeArg(workspacePath: path, workspaceIdentity: identity),
            onEvent: { [weak self] value in
                Task { @MainActor in
                    guard let event = value.decodeJSONValue() as? [String: Any] else { return }
                    self?.handleWorkspaceEvent(event, projectId: projectId, workspacePath: path, workspaceIdentity: identity)
                }
            }
        ) {
            liveSync.workspaceSubs[key] = subId
        }
    }

    /// Subscribes to the replayable task stream (also loads the task on the host so sendPrompt can find it).
    func subscribeActiveTask(_ session: AgentTaskSession) async {
        guard !isUITestSeededMode, !session.id.hasPrefix("task-") else { return }
        if liveSync.activeTaskId == session.id, liveSync.activeTaskSubId != nil { return }
        if liveSync.subscribingTaskId == session.id { return }
        liveSync.subscribingTaskId = session.id
        defer { if liveSync.subscribingTaskId == session.id { liveSync.subscribingTaskId = nil } }

        if let oldSub = liveSync.activeTaskSubId {
            await rpcClient.unlisten(oldSub)
        }
        liveSync.activeTaskSubId = nil
        liveSync.activeTaskId = nil

        if await v4SubscribeConversation(session) { return }

        let taskId = session.id
        let identity = workspaceIdentityByPath[session.workspacePath]
        var req: [String: Any] = [
            "taskId": taskId,
            "workspacePath": session.workspacePath,
            "deliveryKind": "replayable"
        ]
        if let identity, !identity.isEmpty { req["workspaceIdentity"] = identity }

        if let subId = try? await rpcClient.listen(
            channel: "zcode-task",
            event: "onDynamicTaskEvent",
            arg: .fromJSONObject(req),
            onEvent: { [weak self] value in
                Task { @MainActor in
                    guard let event = value.decodeJSONValue() as? [String: Any] else { return }
                    self?.applyTaskStreamEvent(event, taskId: taskId)
                }
            }
        ) {
            liveSync.activeTaskSubId = subId
            liveSync.activeTaskId = taskId
        }
        await hydrateTaskSnapshot(sessionId: taskId, workspacePath: session.workspacePath, workspaceIdentity: identity)
    }

    func scheduleSnapshotRefetch(taskId: String, delay: Double = 0.35) {
        guard !isUITestSeededMode, !v4Owns(taskId), liveSync.snapshotRefetch[taskId] == nil,
              let session = sessions.first(where: { $0.id == taskId }) else { return }
        let path = session.workspacePath
        let identity = workspaceIdentityByPath[path]
        liveSync.snapshotRefetch[taskId] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.liveSync.snapshotRefetch[taskId] = nil
            guard !Task.isCancelled else { return }
            await self.hydrateTaskSnapshot(sessionId: taskId, workspacePath: path, workspaceIdentity: identity)
        }
    }

    func scheduleWorkspaceRefresh(projectId: String, workspacePath: String, workspaceIdentity: String?) {
        if sidebarTreeLoaded {
            scheduleProjectTreeRefresh()
            return
        }
        guard liveSync.workspaceRefresh[projectId] == nil else { return }
        liveSync.workspaceRefresh[projectId] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.liveSync.workspaceRefresh[projectId] = nil
            guard let fresh = await self.fetchWorkspaceTaskScope(
                workspacePath: workspacePath,
                workspaceIdentity: workspaceIdentity,
                projectId: projectId,
                timeoutSec: 8.0
            ) else { return }
            var merged = self.sessions.filter { $0.projectId != projectId || $0.id.hasPrefix("task-") }
            for var task in fresh {
                if let existing = self.sessions.first(where: { $0.id == task.id }) {
                    task.messages = existing.messages
                    task.todos = existing.todos
                    task.contextUsedPercent = existing.contextUsedPercent
                    task.pendingPermission = existing.pendingPermission
                    task.pendingQuestion = existing.pendingQuestion
                    task.pendingPlan = existing.pendingPlan
                    task.queuedPrompts = existing.queuedPrompts
                    if task.id == self.activeSessionId { task.unread = false }
                }
                merged.append(task)
            }
            self.sessions = merged
        }
    }

    func handleWorkspaceEvent(_ event: [String: Any], projectId: String, workspacePath: String, workspaceIdentity: String?) {
        let reason = ((event["reason"] as? String) ?? "").lowercased()
        let taskId = event["taskId"] as? String
        if reason.contains("delet"), let taskId {
            sessions.removeAll(where: { $0.id == taskId })
            if activeSessionId == taskId {
                activeSessionId = sessions.first(where: { !$0.archived })?.id ?? ""
            }
            return
        }
        guard let meta = event["taskMeta"] as? [String: Any],
              let summary = ZCodeRPCClient.parseTaskSummary(meta, fallbackWorkspacePath: workspacePath, fallbackWorkspaceIdentity: workspaceIdentity) else {
            scheduleWorkspaceRefresh(projectId: projectId, workspacePath: workspacePath, workspaceIdentity: workspaceIdentity)
            return
        }
        let fresh = Self.makeAgentSession(from: summary, projectId: projectId)
        if let idx = sessions.firstIndex(where: { $0.id == summary.id }) {
            sessions[idx].title = fresh.title
            sessions[idx].updatedAt = fresh.updatedAt
            sessions[idx].mode = fresh.mode
            if !fresh.modelId.isEmpty {
                sessions[idx].modelId = fresh.modelId
                sessions[idx].modelProviderId = fresh.modelProviderId
                sessions[idx].reasoningLevel = fresh.reasoningLevel
            }
            if reason.contains("archiv") { sessions[idx].archived = !reason.contains("unarchiv") }
            if reason.contains("pin") { sessions[idx].pinned = !reason.contains("unpin") }
            if summary.archived { sessions[idx].archived = true }
            if summary.pinned { sessions[idx].pinned = true }
            if let tree = Self.treeTaskSession(from: meta) {
                sessions[idx].lastOutcomeError = tree.lastOutcomeError
                if tree.changeFileCount > 0 || sessions[idx].changeFileCount > 0 {
                    sessions[idx].changeAdded = tree.changeAdded
                    sessions[idx].changeRemoved = tree.changeRemoved
                    sessions[idx].changeFileCount = tree.changeFileCount
                }
            }
            let isViewing = summary.id == activeSessionId && liveSync.activeTaskId == summary.id
            if !isViewing {
                if !sidebarTreeLoaded { sessions[idx].status = fresh.status }
                sessions[idx].unread = fresh.unread
            }
        } else if sidebarTreeLoaded {
            scheduleProjectTreeRefresh()
        } else if !summary.archived {
            sessions.insert(fresh, at: 0)
        }
    }

    // MARK: - Stream reducer (zcode-task onDynamicTaskEvent)

    func applyTaskStreamEvent(_ event: [String: Any], taskId: String) {
        let type = (event["type"] as? String) ?? ""
        if type == "task_stream_mirror_batch" {
            for op in (event["ops"] as? [[String: Any]]) ?? [] {
                if (op["kind"] as? String) == "stream_event", let inner = op["event"] as? [String: Any] {
                    applyTaskStreamEvent(inner, taskId: taskId)
                } else {
                    scheduleSnapshotRefetch(taskId: taskId)
                }
            }
            if (event["terminal"] as? Bool) == true { scheduleSnapshotRefetch(taskId: taskId) }
            return
        }
        if let eventTaskId = event["taskId"] as? String, eventTaskId != taskId { return }
        guard let sIdx = sessions.firstIndex(where: { $0.id == taskId }) else { return }

        switch type {
        case "agent_message_chunk", "agent_thought_chunk":
            guard event["parentToolUseId"] == nil || event["parentToolUseId"] is NSNull else { return }
            let text = Self.chunkText(event["content"])
            guard !text.isEmpty else { return }
            if sessions[sIdx].status != .running { sessions[sIdx].status = .running }
            let mIdx = streamingAssistantIndex(sessionIndex: sIdx, messageId: event["messageId"] as? String)
            if type == "agent_thought_chunk" {
                sessions[sIdx].messages[mIdx].thought = (sessions[sIdx].messages[mIdx].thought ?? "") + text
            } else {
                sessions[sIdx].messages[mIdx].content += text
            }
        case "tool_call":
            guard event["parentToolUseId"] == nil || event["parentToolUseId"] is NSNull else { return }
            let mIdx = streamingAssistantIndex(sessionIndex: sIdx, messageId: nil)
            let tool = Self.parseTool(event, fallbackId: (event["toolId"] as? String) ?? UUID().uuidString)
            if let tIdx = sessions[sIdx].messages[mIdx].tools.firstIndex(where: { $0.id == tool.id }) {
                sessions[sIdx].messages[mIdx].tools[tIdx] = tool
            } else {
                sessions[sIdx].messages[mIdx].tools.append(tool)
            }
        case "tool_call_update":
            guard let toolId = event["toolId"] as? String else { return }
            for mIdx in sessions[sIdx].messages.indices.reversed() {
                guard let tIdx = sessions[sIdx].messages[mIdx].tools.firstIndex(where: { $0.id == toolId }) else { continue }
                var tool = sessions[sIdx].messages[mIdx].tools[tIdx]
                if let status = event["status"] as? String { tool.status = Self.toolStatus(status) }
                if let title = event["title"] as? String, !title.isEmpty { tool.title = title }
                let output = Self.stringify(event["content"])
                if !output.isEmpty { tool.output = output }
                if let error = Self.stringify(event["error"]).nilIfEmpty { tool.output = error }
                sessions[sIdx].messages[mIdx].tools[tIdx] = tool
                break
            }
        case "plan":
            if let steps = event["steps"] as? [[String: Any]] {
                sessions[sIdx].todos = Self.parsePlanSteps(steps)
            }
        case "permission_request":
            applyPermissionRequest(event, sessionIndex: sIdx)
        case "permission_response":
            sessions[sIdx].pendingPermission = nil
            if sessions[sIdx].status == .waitingApproval { sessions[sIdx].status = .running }
        case "elicitation_request":
            applyElicitationRequest(event, sessionIndex: sIdx)
        case "elicitation_response":
            sessions[sIdx].pendingQuestion = nil
            sessions[sIdx].pendingPlan = nil
            if sessions[sIdx].status == .waitingQuestion || sessions[sIdx].status == .waitingPlan {
                sessions[sIdx].status = .running
            }
        case "task_run_started", "turn_steer_status":
            sessions[sIdx].status = .running
            sessions[sIdx].statusNoticeText = nil
        case "task_complete":
            sessions[sIdx].status = .completed
            liveSync.streamingMessageId[taskId] = nil
            scheduleSnapshotRefetch(taskId: taskId, delay: 0.1)
            if sessions[sIdx].id != activeSessionId { sessions[sIdx].unread = true }
        case "task_error":
            sessions[sIdx].status = .error
            let message = Self.stringify(event["error"]).nilIfEmpty ?? Self.stringify(event["message"]).nilIfEmpty
            sessions[sIdx].statusNoticeText = message
            liveSync.streamingMessageId[taskId] = nil
            scheduleSnapshotRefetch(taskId: taskId, delay: 0.1)
        case "usage_update":
            if let used = Self.number(event["used"]), let size = Self.number(event["size"]), size > 0 {
                sessions[sIdx].contextUsedPercent = min(100, max(0, Int((used / size * 100).rounded())))
            }
        case "mode_update":
            if let mode = (event["mode"] as? String) ?? (event["currentModeId"] as? String) {
                sessions[sIdx].mode = AgentExecutionMode(wire: mode)
            }
        case "session_info_update":
            if let title = (event["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                sessions[sIdx].title = title
            }
        case "task_snapshot_updated", "config_option_update", "turn_steer_queued":
            scheduleSnapshotRefetch(taskId: taskId)
        default:
            break
        }
    }

    private func streamingAssistantIndex(sessionIndex sIdx: Int, messageId: String?) -> Int {
        let taskId = sessions[sIdx].id
        let wantedId = liveSync.streamingMessageId[taskId]
        if let wantedId, let idx = sessions[sIdx].messages.lastIndex(where: { $0.id == wantedId }) {
            return idx
        }
        if let messageId, let idx = sessions[sIdx].messages.lastIndex(where: { $0.id == messageId }) {
            liveSync.streamingMessageId[taskId] = messageId
            return idx
        }
        if let last = sessions[sIdx].messages.indices.last,
           sessions[sIdx].messages[last].role == "assistant",
           sessions[sIdx].status == .running {
            liveSync.streamingMessageId[taskId] = sessions[sIdx].messages[last].id
            return last
        }
        let newId = messageId ?? UUID().uuidString
        sessions[sIdx].messages.append(ChatTurnMessage(
            id: newId,
            role: "assistant",
            content: "",
            thought: nil,
            thoughtDurationMs: 0,
            tools: [],
            attachments: [],
            timestamp: Date(),
            modelLabel: sessions[sIdx].modelId.nilIfEmpty,
            tokensIn: 0,
            tokensOut: 0,
            durationMs: 0,
            feedback: 0
        ))
        liveSync.streamingMessageId[taskId] = newId
        return sessions[sIdx].messages.count - 1
    }

    // MARK: - Interactive requests

    private func applyPermissionRequest(_ request: [String: Any], sessionIndex sIdx: Int) {
        guard let requestId = request["requestId"] as? String else { return }
        let options = (request["options"] as? [[String: Any]]) ?? []
        liveSync.permissionOptions[requestId] = options
        let toolName = (request["title"] as? String) ?? (request["kind"] as? String) ?? "Tool"
        let raw = request["raw"] as? [String: Any]
        let input = Self.permissionInput(raw)
        let target = (input["command"] as? String)
            ?? (input["file_path"] as? String)
            ?? (input["path"] as? String)
            ?? (input["url"] as? String)
            ?? (input["pattern"] as? String)
            ?? ""
        let description = (request["description"] as? String) ?? toolName
        let preview: String = {
            if let command = input["command"] as? String { return "$ \(command)" }
            if let oldText = input["old_string"] as? String, let newText = input["new_string"] as? String {
                return Self.miniDiff(old: oldText, new: newText)
            }
            if let content = input["content"] as? String { return String(content.prefix(1200)) }
            return target.isEmpty ? description : target
        }()
        let lower = toolName.lowercased()
        let risk = lower.contains("bash") || lower.contains("exec") ? "MEDIUM" : "LOW"
        sessions[sIdx].pendingPermission = PermissionPrompt(
            id: requestId,
            toolName: toolName,
            summary: description,
            commandOrPath: target.isEmpty ? description : target,
            previewDiffOrCommand: preview,
            riskLevel: risk
        )
        sessions[sIdx].status = .waitingApproval
    }

    private func applyElicitationRequest(_ request: [String: Any], sessionIndex sIdx: Int) {
        guard let requestId = request["requestId"] as? String else { return }
        liveSync.elicitations[requestId] = request
        let schema = request["schema"] as? [String: Any]
        let isPlan = (schema?["interaction"] as? String) == "plan_approval" || (schema?["toolName"] as? String) == "ExitPlanMode"
        if isPlan {
            let planText = ((schema?["plan"] as? String) ?? (request["message"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed = Self.splitPlan(planText)
            sessions[sIdx].pendingPlan = PlanReviewPrompt(
                id: requestId,
                title: (request["header"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Implementation plan",
                summary: parsed.summary,
                steps: parsed.steps,
                verification: ""
            )
            sessions[sIdx].pendingQuestion = nil
            sessions[sIdx].status = .waitingPlan
            return
        }
        let index = liveSync.elicitationIndex[requestId] ?? 0
        sessions[sIdx].pendingQuestion = Self.questionPrompt(from: request, index: index)
        sessions[sIdx].pendingPlan = nil
        sessions[sIdx].status = .waitingQuestion
    }

    static func elicitationQuestions(_ request: [String: Any]) -> [[String: Any]] {
        if let questions = request["questions"] as? [[String: Any]], !questions.isEmpty { return questions }
        return [[
            "question": (request["message"] as? String) ?? "Input required",
            "header": (request["header"] as? String) ?? "",
            "options": (request["options"] as? [[String: Any]]) ?? [],
            "multiSelect": (request["multiSelect"] as? Bool) ?? false
        ]]
    }

    static func questionPrompt(from request: [String: Any], index: Int) -> QuestionPrompt {
        let questions = elicitationQuestions(request)
        let q = questions[min(index, questions.count - 1)]
        let options = ((q["options"] as? [[String: Any]]) ?? []).enumerated().map { i, opt in
            QuestionOptionItem(
                id: (opt["value"] as? String) ?? "opt-\(i)",
                label: (opt["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (opt["value"] as? String) ?? "Option \(i + 1)",
                detail: (opt["description"] as? String) ?? "",
                previewCode: nil
            )
        }
        let header = (q["header"] as? String) ?? ""
        return QuestionPrompt(
            id: (request["requestId"] as? String) ?? UUID().uuidString,
            header: questions.count > 1 ? "\(header.isEmpty ? "Question" : header) · \(index + 1)/\(questions.count)" : header,
            question: (q["question"] as? String) ?? "Input required",
            multiSelect: (q["multiSelect"] as? Bool) ?? false,
            options: options
        )
    }

    /// Returns true when the response went to the live host (production); false means caller should run the fixture path.
    func respondToPermissionLive(allow: Bool, rememberForSession: Bool) -> Bool {
        guard isLiveHostConnected, let sIdx = sessions.firstIndex(where: { $0.id == activeSession?.id }),
              let perm = sessions[sIdx].pendingPermission else { return false }
        let options = liveSync.permissionOptions[perm.id] ?? []
        func pick(_ predicate: (String) -> Bool) -> String? {
            options.first(where: { predicate((($0["kind"] as? String) ?? "").lowercased()) })?["optionId"] as? String
        }
        let optionId: String? = {
            if !allow {
                return pick { $0.contains("reject") || $0.contains("deny") } ?? (options.last?["optionId"] as? String)
            }
            if rememberForSession, let always = pick({ $0.contains("always") || $0.contains("session") }) {
                return always
            }
            return pick { $0.contains("allow") && !$0.contains("always") } ?? pick { $0.contains("allow") } ?? (options.first?["optionId"] as? String)
        }()
        guard let optionId else {
            showToast("This request has no matching option on the host")
            return true
        }
        let session = sessions[sIdx]
        sessions[sIdx].pendingPermission = nil
        sessions[sIdx].status = .running
        var req: [String: Any] = [
            "taskId": session.id,
            "workspacePath": session.workspacePath,
            "requestId": perm.id,
            "optionId": optionId
        ]
        if let identity = workspaceIdentityByPath[session.workspacePath], !identity.isEmpty { req["workspaceIdentity"] = identity }
        playNotificationHaptic(allow ? .success : .warning)
        if v4Owns(session.id) {
            v4ResolveInteraction(sessionId: session.id, workspacePath: session.workspacePath, interactionId: perm.id, answer: ["optionId": optionId])
            return true
        }
        Task { @MainActor in
            do {
                _ = try await self.rpcClient.call(channel: "zcode-task", method: "respondPermission", args: [.fromJSONObject(req)], timeoutSec: 10.0)
                self.liveSync.permissionOptions[perm.id] = nil
            } catch {
                self.showToast("Couldn't send decision: \(error.localizedDescription)")
                self.scheduleSnapshotRefetch(taskId: session.id, delay: 0.05)
            }
        }
        return true
    }

    func respondToQuestionLive(selectedLabel: String) -> Bool {
        guard isLiveHostConnected, let sIdx = sessions.firstIndex(where: { $0.id == activeSession?.id }),
              let question = sessions[sIdx].pendingQuestion,
              let request = liveSync.elicitations[question.id] else { return false }
        let requestId = question.id
        let questions = Self.elicitationQuestions(request)
        let index = liveSync.elicitationIndex[requestId] ?? 0
        let labels = question.multiSelect
            ? selectedLabel.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
            : [selectedLabel]
        let values = labels.map { label in question.options.first(where: { $0.label == label })?.id ?? label }
        var answers = liveSync.elicitationAnswers[requestId] ?? [:]
        answers[index] = values
        liveSync.elicitationAnswers[requestId] = answers

        if index + 1 < questions.count {
            liveSync.elicitationIndex[requestId] = index + 1
            sessions[sIdx].pendingQuestion = Self.questionPrompt(from: request, index: index + 1)
            return true
        }

        var content: [String: Any] = [:]
        var byQuestion: [String: String] = [:]
        for (i, q) in questions.enumerated() {
            let picked = answers[i] ?? []
            let multi = (q["multiSelect"] as? Bool) ?? false
            byQuestion[(q["question"] as? String) ?? "Question \(i + 1)"] = picked.joined(separator: ", ")
            content["answer_\(i)"] = multi ? picked : (picked.first ?? "")
        }
        content["answers"] = byQuestion
        if questions.count == 1 {
            content["answer"] = content["answer_0"]
        }
        sendElicitationResponse(sessionIndex: sIdx, requestId: requestId, action: "accept", content: content)
        return true
    }

    func respondToPlanLive(approved: Bool) -> Bool {
        guard isLiveHostConnected, let sIdx = sessions.firstIndex(where: { $0.id == activeSession?.id }),
              let plan = sessions[sIdx].pendingPlan,
              let request = liveSync.elicitations[plan.id] else { return false }
        if approved {
            let questions = Self.elicitationQuestions(request)
            let firstValue = ((questions.first?["options"] as? [[String: Any]])?.first?["value"] as? String) ?? "approve"
            let content: [String: Any] = [
                "answers": [((questions.first?["question"] as? String) ?? "Plan"): firstValue],
                "answer_0": firstValue,
                "answer": firstValue
            ]
            sendElicitationResponse(sessionIndex: sIdx, requestId: plan.id, action: "accept", content: content)
        } else {
            sendElicitationResponse(sessionIndex: sIdx, requestId: plan.id, action: "decline", content: nil)
            showToast("Plan declined — add feedback in the composer")
        }
        return true
    }

    private func sendElicitationResponse(sessionIndex sIdx: Int, requestId: String, action: String, content: [String: Any]?) {
        let session = sessions[sIdx]
        sessions[sIdx].pendingQuestion = nil
        sessions[sIdx].pendingPlan = nil
        sessions[sIdx].status = .running
        var req: [String: Any] = [
            "taskId": session.id,
            "workspacePath": session.workspacePath,
            "requestId": requestId,
            "action": action,
            "clientMode": "web-remote-replayable"
        ]
        if let content { req["content"] = content }
        if let identity = workspaceIdentityByPath[session.workspacePath], !identity.isEmpty { req["workspaceIdentity"] = identity }
        playNotificationHaptic(.success)
        if v4Owns(session.id) {
            var answer: [String: Any] = ["action": action]
            if let content { answer["content"] = content }
            if action == "accept", (liveSync.elicitations[requestId]?["v4Generic"] as? Bool) == true,
               let value = content?["answer_0"] as? String {
                answer = ["optionId": value]
            }
            v4ResolveInteraction(sessionId: session.id, workspacePath: session.workspacePath, interactionId: requestId, answer: answer)
            return
        }
        Task { @MainActor in
            do {
                _ = try await self.rpcClient.call(channel: "zcode-task", method: "respondElicitation", args: [.fromJSONObject(req)], timeoutSec: 10.0)
                self.liveSync.elicitations[requestId] = nil
                self.liveSync.elicitationAnswers[requestId] = nil
                self.liveSync.elicitationIndex[requestId] = nil
            } catch {
                self.showToast("Couldn't send answer: \(error.localizedDescription)")
                self.scheduleSnapshotRefetch(taskId: session.id, delay: 0.05)
            }
        }
    }

    // MARK: - Connection recovery

    private var recoveryTarget: (key: String, taskId: String?)? {
        guard let session = activeSession ?? sessions.first else { return nil }
        let identity = workspaceIdentityByPath[session.workspacePath]
        let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: session.workspacePath, workspaceIdentity: identity)
        return (key, session.id.hasPrefix("task-") ? nil : session.id)
    }

    /// Bridge faulted while this terminal still owns the session: reopen with a new bridge identity and recoveryId.
    private func recoverDegradedBridge(reason: String) {
        guard isLiveHostConnected, liveSync.rebootstrapTask == nil, let target = recoveryTarget else { return }
        liveSync.bridgeRecoveryTask?.cancel()
        liveSync.bridgeRecoveryTask = Task { @MainActor in
            defer { self.liveSync.bridgeRecoveryTask = nil }
            await self.rpcClient.sendMobileDiagnostic(event: "recover-start", detail: ["reason": "bridge-degraded", "degradedReason": reason])
            for delay: UInt64 in [0, 500_000_000, 2_000_000_000] {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                guard !Task.isCancelled, self.isLiveHostConnected else { return }
                do {
                    _ = try await self.rpcClient.openWorkspaceBridge(
                        workspaceKey: target.key,
                        taskId: target.taskId,
                        timeoutSec: 6.0,
                        forceReopen: true
                    )
                    return
                } catch {
                    if self.liveSync.rebootstrapTask != nil { return }
                }
            }
            self.rebootstrapRelay(reason: "bridge-reopen-failed")
        }
    }

    /// Desktop ended this terminal's ownership (grace timer, restart, or replaced): bootstrap again, then reopen the bridge.
    func rebootstrapRelay(reason: String) {
        guard isLiveHostConnected, liveSync.rebootstrapTask == nil else { return }
        liveSync.bridgeRecoveryTask?.cancel()
        let target = recoveryTarget
        liveSync.rebootstrapTask = Task { @MainActor in
            defer { self.liveSync.rebootstrapTask = nil }
            await self.rpcClient.sendMobileDiagnostic(event: "recover-start", detail: ["reason": reason])
            for delay: UInt64 in [0, 1_000_000_000, 3_000_000_000] {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                guard !Task.isCancelled, self.isLiveHostConnected else { return }
                let snapshot = await self.rpcClient.rebootstrap(preferredWorkspaceKey: target?.key, preferredTaskId: target?.taskId)
                if snapshot.openedBridge != nil {
                    await self.loadAllWorkspaceTasks(preferredActiveTaskId: self.activeSessionId)
                    return
                }
            }
            self.setLiveNotice("Lost the workspace on your computer. Pull to refresh or reconnect.")
        }
    }

    private func handleHostConnectionLost(reason: String) {
        guard !isUITestSeededMode, let idx = connections.firstIndex(where: { $0.id == activeConnectionId }),
              connections[idx].state == .connected else { return }
        connections[idx].state = .disconnected
        liveSync.reset()
        setLiveNotice("Connection to your computer was lost. Reconnecting…")
        startReconnectLoop(connectionId: connections[idx].id, immediate: false)
    }

    /// Keeps retrying while the app is in the foreground with a usable network; paused otherwise and resumed by
    /// `handleScenePhase(.active)` / the path monitor. Never gives up on its own.
    func startReconnectLoop(connectionId: String, immediate: Bool) {
        guard liveSync.kickedConnectionId != connectionId else { return }
        if immediate { liveSync.reconnectAttempts = 0 }
        liveSync.reconnectTask?.cancel()
        liveSync.reconnectTask = Task { @MainActor in
            while !Task.isCancelled {
                guard self.activeConnectionId == connectionId,
                      self.liveSync.kickedConnectionId != connectionId,
                      let state = self.connections.first(where: { $0.id == connectionId })?.state,
                      state != .connected,
                      self.liveSync.isForeground, self.liveSync.networkSatisfied else { return }
                let attempt = self.liveSync.reconnectAttempts
                self.liveSync.reconnectAttempts += 1
                if attempt > 0 || !immediate {
                    let base = min(30.0, pow(2.0, Double(min(attempt, 5))))
                    try? await Task.sleep(nanoseconds: UInt64(base * Double.random(in: 0.8...1.2) * 1_000_000_000))
                }
                guard !Task.isCancelled, self.activeConnectionId == connectionId,
                      self.liveSync.isForeground, self.liveSync.networkSatisfied else { return }
                await self.connectToWorkstation(connectionId, silent: true)
                if self.connections.first(where: { $0.id == connectionId })?.state == .connected {
                    self.liveSync.reconnectAttempts = 0
                    self.clearLiveNotice()
                    return
                }
            }
        }
    }

    private func handlePeerStatus(online: Bool) {
        guard isLiveHostConnected, let connection = activeConnection else { return }
        liveSync.peerResyncTask?.cancel()
        if !online {
            liveSync.workspaceSubs.removeAll()
            liveSync.modelViewSubId = nil
            liveSync.activeTaskSubId = nil
            liveSync.activeTaskId = nil
            setLiveNotice("ZCode on your computer is offline. Waiting for it to come back…")
            return
        }
        liveSync.peerResyncTask = Task { @MainActor in
            if await self.syncRemoteWorkspacesFromServer(for: connection) {
                self.clearLiveNotice()
            } else {
                await self.rpcClient.dropDeadConnection()
            }
        }
    }

    private func handleTerminalError(code: String, message: String) {
        guard let idx = connections.firstIndex(where: { $0.id == activeConnectionId }) else { return }
        guard code == "KICKED" else {
            showToast(message)
            return
        }
        liveSync.kickedConnectionId = connections[idx].id
        liveSync.reconnectTask?.cancel()
        connections[idx].state = .disconnected
        liveSync.reset()
        setLiveNotice(message)
        Task { await self.rpcClient.disconnect() }
    }

    /// An explicit user connect lifts a takeover block so auto-reconnect works again.
    func clearReconnectBlock(for connectionId: String) {
        if liveSync.kickedConnectionId == connectionId { liveSync.kickedConnectionId = nil }
    }

    // MARK: - App lifecycle & network

    public func handleScenePhase(_ phase: ScenePhase) {
        guard !isUITestSeededMode else { return }
        switch phase {
        case .active:
            let wasBackground = !liveSync.isForeground
            liveSync.isForeground = true
            if wasBackground {
                verifyLiveConnection()
                scheduleHostSettingsRefresh()
            }
        case .background:
            liveSync.isForeground = false
            liveSync.backgroundedAt = Date()
        default:
            break
        }
    }

    public func startNetworkMonitorIfNeeded() {
        guard liveSync.pathMonitor == nil, !isUITestSeededMode else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let signature = path.availableInterfaces.map { "\($0.type)" }.joined(separator: ",")
            Task { @MainActor in
                self?.handleNetworkPath(satisfied: satisfied, signature: signature)
            }
        }
        monitor.start(queue: DispatchQueue(label: "ai.zcode.mobile.path-monitor"))
        liveSync.pathMonitor = monitor
    }

    private func handleNetworkPath(satisfied: Bool, signature: String) {
        let wasSatisfied = liveSync.networkSatisfied
        let changedInterface = !liveSync.networkInterfaceSignature.isEmpty && liveSync.networkInterfaceSignature != signature
        liveSync.networkSatisfied = satisfied
        liveSync.networkInterfaceSignature = signature
        guard satisfied, !wasSatisfied || changedInterface else { return }
        verifyLiveConnection()
    }

    /// After resume or a network change: reconnect if the socket is dead, otherwise re-read host state that may
    /// have changed while events could not be delivered.
    func verifyLiveConnection() {
        guard let connection = activeConnection, connection.transport != .enterpriseSandbox,
              liveSync.kickedConnectionId != connection.id else { return }
        liveSync.resumeCheckTask?.cancel()
        liveSync.resumeCheckTask = Task { @MainActor in
            switch connection.state {
            case .connected:
                if await self.rpcClient.probeLiveness(timeoutSec: 4.0) {
                    await self.resyncAfterResume()
                } else {
                    await self.rpcClient.dropDeadConnection()
                }
            case .disconnected, .error:
                if self.liveSync.syncedConnectionId == connection.id {
                    self.startReconnectLoop(connectionId: connection.id, immediate: true)
                }
            case .connecting:
                break
            }
        }
    }

    private func resyncAfterResume() async {
        guard isLiveHostConnected else { return }
        if await rpcClient.isRelay, await rpcClient.currentBridge() == nil {
            rebootstrapRelay(reason: "resume-without-bridge")
            return
        }
        await loadAllWorkspaceTasks(preferredActiveTaskId: nil)
        if liveSync.activeTaskSubId == nil || liveSync.workspaceSubs.count < projects.count {
            await resubscribeAll(handlersCleared: false)
            return
        }
        await refreshLiveModelView()
        await refreshHostSettings()
        if let session = activeSession, v4Owns(session.id) {
            v4Resync(force: false)
        } else if let session = activeSession, !session.id.hasPrefix("task-") {
            await hydrateTaskSnapshot(
                sessionId: session.id,
                workspacePath: session.workspacePath,
                workspaceIdentity: workspaceIdentityByPath[session.workspacePath]
            )
        }
    }

    private func setLiveNotice(_ text: String) {
        liveConnectionNotice = text
    }

    private func clearLiveNotice() {
        liveConnectionNotice = nil
    }

    // MARK: - Snapshot parser (zcode-task getTaskSnapshot)

    func applyTaskSnapshot(_ dict: [String: Any], sessionIndex sIdx: Int) {
        let taskId = sessions[sIdx].id
        var pendingKind: String?
        if let meta = dict["meta"] as? [String: Any] {
            if let title = (meta["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                sessions[sIdx].title = title
            }
            if let traceId = meta["traceId"] as? String, !traceId.isEmpty {
                sessions[sIdx].traceId = traceId
            }
            if let mode = meta["mode"] as? String {
                sessions[sIdx].mode = AgentExecutionMode(wire: mode)
            }
            if let selection = LiveModelSelection(pickerValue: meta["model"] as? String) {
                sessions[sIdx].modelProviderId = selection.providerId
                sessions[sIdx].modelId = selection.modelId
                sessions[sIdx].reasoningLevel = (meta["thoughtLevel"] as? String) ?? selection.reasoningLevel
            } else if let level = meta["thoughtLevel"] as? String {
                sessions[sIdx].reasoningLevel = level
            }
            pendingKind = (meta["pendingInteraction"] as? [String: Any])?["kind"] as? String
            if let statusRaw = meta["status"] as? String {
                sessions[sIdx].status = Self.sessionStatus(statusRaw, pendingKind: pendingKind)
            }
        }

        if let rawMessages = dict["messages"] as? [[String: Any]] {
            var turns: [ChatTurnMessage] = []
            turns.reserveCapacity(rawMessages.count)
            for m in rawMessages {
                if let synthetic = m["syntheticTimeline"], !(synthetic is NSNull), (synthetic as? Bool) != false { continue }
                if let turn = Self.parseMessage(m) { turns.append(turn) }
            }
            sessions[sIdx].messages = turns
            if sessions[sIdx].status == .running, let last = turns.last, last.role == "assistant" {
                liveSync.streamingMessageId[taskId] = last.id
            } else {
                liveSync.streamingMessageId[taskId] = nil
            }
        }

        let runtime = dict["runtime"] as? [String: Any]
        if let permissions = runtime?["pendingPermissions"] as? [[String: Any]], let first = permissions.first {
            applyPermissionRequest(first, sessionIndex: sIdx)
        } else if runtime != nil {
            sessions[sIdx].pendingPermission = nil
        }
        if let elicitations = runtime?["pendingElicitations"] as? [[String: Any]], let first = elicitations.first {
            applyElicitationRequest(first, sessionIndex: sIdx)
        } else if runtime != nil {
            sessions[sIdx].pendingQuestion = nil
            sessions[sIdx].pendingPlan = nil
        }
        if let usage = runtime?["contextUsage"] as? [String: Any],
           let used = Self.number(usage["used"]), let size = Self.number(usage["size"]), size > 0 {
            sessions[sIdx].contextUsedPercent = min(100, max(0, Int((used / size * 100).rounded())))
        }
        if let plan = runtime?["plan"] as? [[String: Any]] {
            sessions[sIdx].todos = Self.parsePlanSteps(plan)
        }
        if sessions[sIdx].status == .completed || sessions[sIdx].status == .idle {
            sessions[sIdx].statusNoticeText = nil
        }
    }

    static func sessionStatus(_ raw: String, pendingKind: String?) -> TaskSessionStatus {
        if let pendingKind {
            return pendingKind == "permission" ? .waitingApproval : .waitingQuestion
        }
        switch raw {
        case "running", "streaming", "in_progress": return .running
        case "error", "failed": return .error
        case "completed", "done": return .completed
        default: return TaskSessionStatus(rawValue: raw) ?? .idle
        }
    }

    private static func parseMessage(_ m: [String: Any]) -> ChatTurnMessage? {
        let role = (m["role"] as? String) ?? "assistant"
        var content = (m["content"] as? String) ?? stringify(m["content"])
        var thought = m["thought"] as? String
        let parts = (m["parts"] as? [[String: Any]]) ?? []
        if content.isEmpty {
            content = parts.filter { ($0["type"] as? String) == "content" }.compactMap { $0["content"] as? String }.joined()
        }
        if (thought ?? "").isEmpty {
            let joined = parts.filter { ($0["type"] as? String) == "thought" }.compactMap { $0["content"] as? String }.joined()
            thought = joined.isEmpty ? nil : joined
        }
        let tools: [ToolCallItem] = ((m["tools"] as? [[String: Any]]) ?? []).enumerated().map { i, t in
            parseTool(t, fallbackId: "\((m["id"] as? String) ?? "msg")-tool-\(i)")
        }
        if content.isEmpty && (thought ?? "").isEmpty && tools.isEmpty { return nil }
        let rawTs = number(m["timestamp"]) ?? Date().timeIntervalSince1970 * 1000
        let modelLabel: String? = {
            guard role == "assistant" else { return nil }
            if let picker = m["model"] as? String {
                return LiveModelSelection(pickerValue: picker)?.modelId ?? picker
            }
            if let dict = m["model"] as? [String: Any] { return dict["modelId"] as? String }
            return nil
        }()
        var finalContent = content
        if (m["interrupted"] as? Bool) == true, role == "assistant", finalContent.isEmpty, tools.isEmpty {
            finalContent = "_Interrupted_"
        }
        return ChatTurnMessage(
            id: (m["id"] as? String) ?? UUID().uuidString,
            role: role,
            content: finalContent,
            thought: thought,
            thoughtDurationMs: 0,
            tools: tools,
            attachments: [],
            timestamp: Date(timeIntervalSince1970: rawTs > 9_999_999_999 ? rawTs / 1000.0 : rawTs),
            modelLabel: modelLabel,
            tokensIn: 0,
            tokensOut: 0,
            durationMs: Int(number(m["durationMs"]) ?? 0),
            feedback: (m["feedback"] as? String) == "up" ? 1 : ((m["feedback"] as? String) == "down" ? -1 : 0)
        )
    }

    static func parseTool(_ t: [String: Any], fallbackId: String) -> ToolCallItem {
        let id = (t["toolId"] as? String) ?? (t["id"] as? String) ?? fallbackId
        let toolName = (t["toolName"] as? String) ?? (t["name"] as? String) ?? "Tool"
        let kindRaw = ((t["kind"] as? String) ?? "").lowercased()
        let lower = toolName.lowercased()
        let kind: ToolCallKind = {
            switch kindRaw {
            case "execute": return .bash
            case "edit": return lower.contains("write") ? .writeFile : .editFile
            case "search": return .search
            case "read": return .readFile
            default: break
            }
            if lower.contains("bash") || lower.contains("exec") || lower.contains("terminal") { return .bash }
            if lower.contains("edit") || lower.contains("patch") { return .editFile }
            if lower.contains("write") { return .writeFile }
            if lower.contains("search") || lower.contains("grep") || lower.contains("glob") { return .search }
            if lower == "task" || lower.contains("agent") { return .subagent }
            if lower.contains("mcp") || lower.contains("__") { return .mcp }
            return .readFile
        }()
        let input = (t["input"] as? [String: Any]) ?? [:]
        let filePath = (input["file_path"] as? String) ?? (input["path"] as? String) ?? (input["notebook_path"] as? String)
        let command = input["command"] as? String
        let title = (t["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? toolName
        let errorText = stringify(t["error"])
        let outputText = stringify(t["output"])
        var diff: String?
        var added = 0
        var removed = 0
        if let oldText = input["old_string"] as? String, let newText = input["new_string"] as? String {
            diff = miniDiff(old: oldText, new: newText)
            removed = oldText.isEmpty ? 0 : oldText.components(separatedBy: "\n").count
            added = newText.isEmpty ? 0 : newText.components(separatedBy: "\n").count
        } else if kind == .writeFile, let body = input["content"] as? String {
            added = body.isEmpty ? 0 : body.components(separatedBy: "\n").count
        }
        let subtitle = filePath ?? command ?? (input["pattern"] as? String) ?? (input["description"] as? String) ?? ""
        return ToolCallItem(
            id: id,
            kind: kind,
            title: title,
            subtitle: String(subtitle.prefix(120)),
            status: toolStatus((t["status"] as? String) ?? "completed"),
            filePath: filePath,
            lineRange: nil,
            diffPatch: diff,
            command: command,
            output: errorText.isEmpty ? outputText.nilIfEmpty : errorText,
            durationMs: Int(number(t["durationMs"]) ?? 0),
            addedLines: added,
            removedLines: removed,
            subagentSteps: [],
            toolName: toolName
        )
    }

    static func toolStatus(_ raw: String) -> ToolCallStatus {
        switch raw.lowercased() {
        case "pending", "in_progress", "running": return .running
        case "failed", "denied", "stopped", "error": return .failed
        default: return .completed
        }
    }

    static func parsePlanSteps(_ steps: [[String: Any]]) -> [TodoChecklistItem] {
        steps.enumerated().map { i, step in
            TodoChecklistItem(
                id: (step["id"] as? String) ?? "plan-\(i)",
                content: (step["title"] as? String) ?? (step["content"] as? String) ?? "",
                status: (step["status"] as? String) ?? "pending",
                priority: (step["priority"] as? String) ?? "medium"
            )
        }
    }

    private static func permissionInput(_ raw: [String: Any]?) -> [String: Any] {
        guard let raw else { return [:] }
        if let input = raw["input"] as? [String: Any] { return input }
        if let toolCall = raw["toolCall"] as? [String: Any] {
            if let rawInput = toolCall["rawInput"] as? [String: Any] { return rawInput }
            if let input = toolCall["input"] as? [String: Any] { return input }
        }
        if let toolInput = raw["toolInput"] as? [String: Any] { return toolInput }
        return [:]
    }

    static func splitPlan(_ text: String) -> (summary: String, steps: [String]) {
        var summaryLines: [String] = []
        var steps: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let range = line.range(of: #"^(?:[-*+]|\d+[.)])\s+"#, options: .regularExpression) {
                steps.append(String(line[range.upperBound...]))
            } else if steps.isEmpty {
                summaryLines.append(line.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression))
            } else {
                steps.append(line.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression))
            }
        }
        return (summaryLines.joined(separator: "\n"), steps)
    }

    static func miniDiff(old: String, new: String) -> String {
        let removed = old.isEmpty ? [] : old.components(separatedBy: "\n").map { "-\($0)" }
        let added = new.isEmpty ? [] : new.components(separatedBy: "\n").map { "+\($0)" }
        return (removed + added).prefix(400).joined(separator: "\n")
    }

    static func chunkText(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String { return text }
            if let inner = dict["content"] { return chunkText(inner) }
        }
        if let items = value as? [Any] { return items.map { chunkText($0) }.joined() }
        return ""
    }

    static func stringify(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let s = value as? String { return s }
        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String { return text }
            if let message = dict["message"] as? String { return message }
            if let content = dict["content"] { return stringify(content) }
        }
        if let items = value as? [Any] {
            return items.map { stringify($0) }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(value)"
    }

    static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
