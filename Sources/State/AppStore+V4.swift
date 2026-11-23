import Foundation
import CryptoKit

/// Bookkeeping for the V4 conversation protocol (main actor only, not observed).
final class V4SyncState {
    /// nil = not probed yet, false = host lacks V4 (legacy zcode-task facade is used instead).
    var available: Bool?
    var handshakeDone = false
    /// Relay bridge the handshake was made on; a new bridge needs its own hello.
    var handshakeBridgeId: String?
    var handshakeTask: Task<Bool, Never>?
    var assembler = V4WireFrameAssembler()
    var conversationFrameSubs: [String: Int32] = [:]
    var indexFrameSubs: [String: Int32] = [:]
    var lifecycleSubId: Int32?

    var conversation: V4ConversationState?
    var conversationWorkspacePath = ""
    var conversationWorkspaceIdentity: String?
    var awaitingAck = false
    var staged: [[String: Any]] = []
    var subscribeInFlight: String?
    var resyncInFlight = false
    var snapshotWatchdog: Task<Void, Never>?
    var lifecycleRetry: Task<Void, Never>?
    var lifecycleAttempt = 0
    var publishTask: Task<Void, Never>?
    var cacheSaveTask: Task<Void, Never>?
    var rowTargets: [String: [String: Any]] = [:]
    /// Raw attachment refs of user rows keyed by message id, replayed by `editUserQuery`.
    var userAttachmentRefs: [String: [[String: Any]]] = [:]
    var foregroundExecutionId: String?
    var loadingOlder = false
    /// Bytes of user-row attachments already read from the host, keyed by attachment `ref`.
    var attachmentData: [String: (data: Data, mimeType: String)] = [:]
    /// Oldest row id whose older page last failed; automatic paging pauses there until the window changes.
    var olderFailedBeforeRowId: Int?
    /// Read-only child conversation shown in the subagent pane (`subscribeConversationV4` on `childSessionId`).
    var child: V4ConversationState?
    var childAwaitingAck = false
    var childStaged: [[String: Any]] = []
    var childResyncInFlight = false
    /// Locally echoed user prompts shown until the host row arrives.
    var optimistic: [(message: ChatTurnMessage, sentAt: Date)] = []

    var indexes: [String: V4SessionsIndexState] = [:]
    var indexTargets: [String: (projectId: String, path: String, identity: String?)] = [:]
    var indexAwaitingAck: Set<String> = []
    var indexStaged: [String: [[String: Any]]] = [:]
    /// Session ids seen in an index but missing locally that already triggered a task-list refresh.
    var refreshedUnknownSessions: Set<String> = []

    /// Everything bound to the current host connection; channel listeners are already gone at this point.
    func resetConnection() {
        handshakeDone = false
        handshakeBridgeId = nil
        handshakeTask?.cancel()
        handshakeTask = nil
        assembler.reset()
        conversationFrameSubs.removeAll()
        indexFrameSubs.removeAll()
        lifecycleSubId = nil
        conversation?.subscriptionId = nil
        child?.subscriptionId = nil
        childAwaitingAck = false
        childStaged.removeAll()
        childResyncInFlight = false
        awaitingAck = false
        staged.removeAll()
        subscribeInFlight = nil
        resyncInFlight = false
        snapshotWatchdog?.cancel()
        lifecycleRetry?.cancel()
        indexes.removeAll()
        indexAwaitingAck.removeAll()
        indexStaged.removeAll()
    }
}

struct V4CommandError: LocalizedError {
    let status: String
    let reasonCode: String?
    let message: String?
    var errorDescription: String? { message ?? reasonCode ?? "Command \(status)" }
}

extension AppStore {
    private static let attachmentChunkBytes = 384 * 1024

    // MARK: - Handshake

    /// True when the active session is driven by the V4 conversation stream.
    func v4Owns(_ sessionId: String?) -> Bool {
        guard let sessionId, v4Sync.available == true, let conv = v4Sync.conversation else { return false }
        return conv.sessionId == sessionId && conv.subscriptionId != nil
    }

    func v4EnsureHandshake() async -> Bool {
        guard !isUITestSeededMode else { return false }
        if v4Sync.available == false { return false }
        let bridgeId = await rpcClient.currentBridge()?.bridgeSessionId
        if v4Sync.handshakeDone, v4Sync.handshakeBridgeId == bridgeId { return true }
        v4Sync.handshakeDone = false
        if let running = v4Sync.handshakeTask { return await running.value }
        let task = Task { @MainActor () -> Bool in
            do {
                _ = try await self.rpcClient.call(channel: "zcode-agent", method: "helloConversationV4", args: [], timeoutSec: 10)
                let hello: [String: Any] = [
                    "kind": "clientHello",
                    "protocolVersion": ZCodeV4.protocolVersion,
                    "clientId": Self.remoteClientId,
                    "clientKind": "mobileApp",
                    "appVersion": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0",
                    "capabilities": ["workspaceHookReviewUi": false, "workflowRunDeltas": true, "historyFirst": true]
                ]
                _ = try await self.rpcClient.call(channel: "zcode-agent", method: "initializeConversationV4", args: [.fromJSONObject(hello)], timeoutSec: 10)
                self.v4Sync.handshakeDone = true
                self.v4Sync.handshakeBridgeId = bridgeId
                self.v4Sync.available = true
                await self.v4ListenLifecycle()
                return true
            } catch {
                LoadBench.mark("handshake failed \(error.localizedDescription)")
                if Self.isUnsupportedMethod(error) { self.v4Sync.available = false }
                return false
            }
        }
        v4Sync.handshakeTask = task
        let ok = await task.value
        v4Sync.handshakeTask = nil
        return ok
    }

    static func isHandshakeRequired(_ error: Error) -> Bool {
        let parts = [(error as? V4CommandError)?.reasonCode, (error as? V4CommandError)?.message, error.localizedDescription]
        return parts.contains { ($0 ?? "").localizedCaseInsensitiveContains("handshakeRequired") }
    }

    private static func isUnsupportedMethod(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("unknown method") || text.contains("not found") || text.contains("is not a function")
            || text.contains("not allowed") || text.contains("unsupported")
    }

    private func v4ListenLifecycle() async {
        guard v4Sync.lifecycleSubId == nil else { return }
        v4Sync.lifecycleSubId = try? await rpcClient.listen(channel: "zcode-agent", event: "onAgentRuntimeLifecycle") { [weak self] value in
            Task { @MainActor in
                guard let event = value.decodeJSONValue() as? [String: Any] else { return }
                self?.v4HandleLifecycle(event)
            }
        }
    }

    private func v4HandleLifecycle(_ event: [String: Any]) {
        guard let conv = v4Sync.conversation else { return }
        let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: v4Sync.conversationWorkspacePath, workspaceIdentity: v4Sync.conversationWorkspaceIdentity)
        guard (event["workspaceKey"] as? String) == key else { return }
        let sessionId = conv.sessionId
        v4Sync.lifecycleRetry?.cancel()
        if (event["state"] as? String) == "unavailable" {
            v4Sync.conversation?.subscriptionId = nil
            let delays: [UInt64] = [250, 1000, 3000]
            let delay = delays[min(v4Sync.lifecycleAttempt, delays.count - 1)]
            v4Sync.lifecycleAttempt += 1
            v4Sync.lifecycleRetry = Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
                guard !Task.isCancelled else { return }
                await self.v4Resubscribe(sessionId: sessionId)
            }
        } else {
            v4Sync.lifecycleAttempt = 0
            v4Sync.lifecycleRetry = Task { @MainActor in await self.v4Resubscribe(sessionId: sessionId) }
        }
    }

    /// Keeps the current snapshot so the new subscription resumes from it (`base`) instead of downloading it again.
    private func v4Resubscribe(sessionId: String) async {
        if v4Sync.conversation?.sessionId != sessionId { v4Sync.conversation = nil }
        if let session = sessions.first(where: { $0.id == sessionId }) {
            _ = await v4SubscribeConversation(session)
        }
    }

    // MARK: - Frame listeners

    private func v4WorkspaceArg(_ path: String, _ identity: String?) -> [String: Any] {
        var arg: [String: Any] = ["workspacePath": path]
        if let identity, !identity.isEmpty { arg["workspaceIdentity"] = identity }
        return arg
    }

    private func v4EnsureFrameListener(path: String, identity: String?, event: String) async -> Bool {
        let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: path, workspaceIdentity: identity)
        let isIndex = event == "onDynamicSessionsIndexFrame"
        if (isIndex ? v4Sync.indexFrameSubs[key] : v4Sync.conversationFrameSubs[key]) != nil { return true }
        guard let subId = try? await rpcClient.listen(
            channel: "zcode-agent",
            event: event,
            arg: .fromJSONObject(v4WorkspaceArg(path, identity)),
            onEvent: { [weak self] value in
                Task { @MainActor in
                    guard let envelope = value.decodeJSONValue() as? [String: Any] else { return }
                    self?.v4HandleEnvelope(envelope)
                }
            }
        ) else { return false }
        if isIndex { v4Sync.indexFrameSubs[key] = subId } else { v4Sync.conversationFrameSubs[key] = subId }
        return true
    }

    func v4HandleEnvelope(_ envelope: [String: Any]) {
        guard let topic = envelope["topic"] as? String else { return }
        if topic.hasPrefix("sessions-index/") {
            v4HandleIndexEnvelope(envelope, topic: topic)
            return
        }
        if let child = v4Sync.child, topic == child.topic {
            v4HandleChildEnvelope(envelope)
            return
        }
        guard let conv = v4Sync.conversation, topic == conv.topic else { return }
        if v4Sync.awaitingAck {
            if v4Sync.staged.count < 1024 { v4Sync.staged.append(envelope) }
            return
        }
        guard let subId = conv.subscriptionId, (envelope["subscriptionId"] as? String) == subId else { return }
        switch v4Sync.assembler.ingest(envelope) {
        case .frame(let frame, _):
            guard var current = v4Sync.conversation, current.subscriptionId == subId else { return }
            let result = current.apply(frame: frame)
            v4Sync.conversation = current
            switch result {
            case .applied:
                if current.hasSnapshot {
                    v4Sync.snapshotWatchdog?.cancel()
                    LoadBench.noteLive(current.sessionId, "frame")
                }
                v4SchedulePublish()
            case .gap:
                v4Resync(force: !current.hasSnapshot)
            case .ignored:
                break
            }
        case .fault:
            v4Resync(force: true)
        case .ignored:
            break
        }
    }

    // MARK: - Conversation subscription

    /// Subscribes the V4 conversation stream for `session`; false means the caller should use the legacy task stream.
    func v4SubscribeConversation(_ session: AgentTaskSession) async -> Bool {
        guard !isUITestSeededMode, !session.id.hasPrefix("task-") else { return false }
        LoadBench.mark("v4 subscribe requested \(session.id)")
        guard await v4EnsureHandshake() else { return false }
        if let conv = v4Sync.conversation, conv.sessionId == session.id, conv.subscriptionId != nil || v4Sync.subscribeInFlight == session.id {
            LoadBench.mark("v4 subscribe skipped (already) \(session.id)")
            return true
        }
        let path = session.workspacePath
        let identity = workspaceIdentityByPath[path]

        if let old = v4Sync.conversation, let oldSub = old.subscriptionId {
            var arg = v4WorkspaceArg(v4Sync.conversationWorkspacePath, v4Sync.conversationWorkspaceIdentity)
            arg["subscriptionId"] = oldSub
            let client = rpcClient
            Task { _ = try? await client.call(channel: "zcode-agent", method: "unsubscribeConversationV4", args: [.fromJSONObject(arg)], timeoutSec: 6) }
        }
        guard await v4EnsureFrameListener(path: path, identity: identity, event: "onDynamicConversationFrame") else { return false }

        var conv: V4ConversationState
        if let current = v4Sync.conversation, current.sessionId == session.id, current.hasSnapshot {
            conv = current
        } else {
            if let previous = v4Sync.conversation { v4SaveConversationCache(previous) }
            v4Sync.subscribeInFlight = session.id
            let cached = await V4LocalCache.loadConversation(key: v4ConversationCacheKey(sessionId: session.id, path: path, identity: identity))
            guard v4Sync.subscribeInFlight == session.id else { return true }
            conv = cached.flatMap { V4ConversationState(cachePayload: $0, sessionId: session.id) } ?? V4ConversationState(sessionId: session.id)
        }
        conv.subscriptionId = nil
        v4Sync.conversation = conv
        v4Sync.conversationWorkspacePath = path
        v4Sync.conversationWorkspaceIdentity = identity
        v4Sync.awaitingAck = true
        v4Sync.staged.removeAll()
        v4Sync.subscribeInFlight = session.id
        v4Sync.rowTargets.removeAll()
        v4Sync.userAttachmentRefs.removeAll()
        v4Sync.assembler.reset(topic: conv.topic)
        defer { if v4Sync.subscribeInFlight == session.id { v4Sync.subscribeInFlight = nil } }
        if conv.hasSnapshot { v4Publish() }

        var arg = v4WorkspaceArg(path, identity)
        arg["sessionId"] = session.id
        if let base = conv.base { arg["base"] = base }
        LoadBench.mark("subscribe \(session.id) cached=\(conv.hasSnapshot)")
        do {
            let value: VQLValue
            do {
                value = try await rpcClient.call(channel: "zcode-agent", method: "subscribeConversationV4", args: [.fromJSONObject(arg)], timeoutSec: 25)
            } catch where arg["base"] != nil && !Self.isUnsupportedMethod(error) && !(error is URLError)
                && !error.localizedDescription.localizedCaseInsensitiveContains("timed out") {
                arg.removeValue(forKey: "base")
                v4Sync.staged.removeAll()
                value = try await rpcClient.call(channel: "zcode-agent", method: "subscribeConversationV4", args: [.fromJSONObject(arg)], timeoutSec: 25)
            }
            guard v4Sync.conversation?.sessionId == session.id else { return true }
            let dict = value.decodeJSONDictionary() ?? [:]
            let ack = (dict["ack"] as? [String: Any]) ?? dict
            guard let subscriptionId = ack["subscriptionId"] as? String else {
                throw V4CommandError(status: "failed", reasonCode: nil, message: "Host returned no subscription id.")
            }
            v4Sync.conversation?.subscriptionId = subscriptionId
            let resumed = (ack["mode"] as? String) == "resume" && arg["base"] != nil
                && (ack["logEpoch"] as? String) == v4Sync.conversation?.logEpoch
            if !resumed, v4Sync.conversation?.hasSnapshot == true { v4Sync.conversation?.awaitFreshSnapshot() }
            LoadBench.mark("ack \(ack["mode"] as? String ?? "?") resumed=\(resumed) \(session.id)")
            if resumed { LoadBench.noteLive(session.id, "resume") }
            v4Sync.awaitingAck = false
            liveSync.activeTaskId = session.id
            let staged = v4Sync.staged
            v4Sync.staged.removeAll()
            for envelope in staged where (envelope["subscriptionId"] as? String) == subscriptionId {
                v4HandleEnvelope(envelope)
            }
            v4ArmSnapshotWatchdog(sessionId: session.id)
            return true
        } catch {
            if v4Sync.conversation?.sessionId == session.id {
                v4Sync.conversation = nil
                v4Sync.awaitingAck = false
            }
            if Self.isUnsupportedMethod(error) { v4Sync.available = false }
            return false
        }
    }

    private func v4ArmSnapshotWatchdog(sessionId: String) {
        v4Sync.snapshotWatchdog?.cancel()
        v4Sync.snapshotWatchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let conv = self.v4Sync.conversation, conv.sessionId == sessionId, !conv.hasSnapshot else { return }
            self.v4Resync(force: true)
        }
    }

    func v4Resync(force: Bool) {
        guard !v4Sync.resyncInFlight, let conv = v4Sync.conversation, let subId = conv.subscriptionId else { return }
        v4Sync.resyncInFlight = true
        let sessionId = conv.sessionId
        var arg = v4WorkspaceArg(v4Sync.conversationWorkspacePath, v4Sync.conversationWorkspaceIdentity)
        arg["subscriptionId"] = subId
        arg["base"] = force ? NSNull() : (conv.base ?? NSNull())
        if force { arg["forceSnapshot"] = true }
        v4Sync.assembler.reset(topic: conv.topic)
        Task { @MainActor in
            defer { self.v4Sync.resyncInFlight = false }
            do {
                _ = try await self.rpcClient.call(channel: "zcode-agent", method: "resyncConversationV4", args: [.fromJSONObject(arg)], timeoutSec: 25)
                if force { self.v4ArmSnapshotWatchdog(sessionId: sessionId) }
            } catch {
                guard self.v4Sync.conversation?.sessionId == sessionId else { return }
                self.v4Sync.resyncInFlight = false
                await self.v4Resubscribe(sessionId: sessionId)
            }
        }
    }

    /// Loads up to 200 older transcript rows before the current window. `userInitiated` retries a page that failed.
    public func loadOlderMessages(userInitiated: Bool = false) {
        guard let conv = v4Sync.conversation, conv.hasOlderRows, !v4Sync.loadingOlder,
              let oldest = conv.rows.first.flatMap({ ZCodeV4.int($0["rowId"]) }) else { return }
        if !userInitiated, v4Sync.olderFailedBeforeRowId == oldest { return }
        v4Sync.loadingOlder = true
        var arg = v4WorkspaceArg(v4Sync.conversationWorkspacePath, v4Sync.conversationWorkspaceIdentity)
        arg["sessionId"] = conv.sessionId
        arg["beforeRowId"] = oldest
        arg["limit"] = ZCodeV4.rowsRangeMaxLimit
        Task { @MainActor in
            defer { self.v4Sync.loadingOlder = false }
            let value = try? await self.rpcClient.call(channel: "zcode-agent", method: "conversationRowsRangeV4", args: [.fromJSONObject(arg)], timeoutSec: 15)
            guard var current = self.v4Sync.conversation, current.sessionId == conv.sessionId else { return }
            guard let dict = value?.decodeJSONDictionary(),
                  current.prepend(olderRows: (dict["rows"] as? [[String: Any]]) ?? [], atLogEpoch: (dict["atLogEpoch"] as? String) ?? "") else {
                self.v4Sync.olderFailedBeforeRowId = oldest
                return
            }
            self.v4Sync.olderFailedBeforeRowId = nil
            self.v4Sync.conversation = current
            self.v4Publish()
        }
    }

    public var canLoadOlderMessages: Bool {
        guard let conv = v4Sync.conversation, conv.sessionId == activeSession?.id else { return false }
        return conv.hasOlderRows
    }

    // MARK: - Projection

    func v4SchedulePublish() {
        guard v4Sync.publishTask == nil else { return }
        v4Sync.publishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            self.v4Sync.publishTask = nil
            self.v4Publish()
        }
    }

    func v4Publish() {
        guard let conv = v4Sync.conversation, conv.hasSnapshot,
              let idx = sessions.firstIndex(where: { $0.id == conv.sessionId }) else { return }
        let projection = V4ConversationMapper.project(conv) { [liveSync] id in liveSync.elicitationIndex[id] ?? 0 }
        var session = sessions[idx]

        var messages = projection.messages
        let recentUserTexts = Set(messages.suffix(12).filter { $0.role == "user" }.map(\.content))
        v4Sync.optimistic.removeAll { entry in
            recentUserTexts.contains(entry.message.content) || Date().timeIntervalSince(entry.sentAt) > 20
        }
        messages.append(contentsOf: v4Sync.optimistic.map(\.message))
        session.messages = messages

        session.status = projection.status
        if !v4Sync.optimistic.isEmpty, session.status == .idle || session.status == .completed {
            session.status = .running
        }
        if let title = projection.title { session.title = title }
        if let mode = projection.mode { session.mode = mode }
        if let model = projection.model {
            session.modelProviderId = model.providerId
            session.modelId = model.modelId
            session.reasoningLevel = model.reasoningLevel
        }
        session.contextUsage = projection.contextUsage
        if let usage = projection.contextUsage {
            session.contextUsedPercent = Int((usage.fraction * 100).rounded())
            session.totalTokensIn = usage.cumulativeInputTokens
            session.totalTokensOut = usage.cumulativeOutputTokens
            session.cachedTokens = usage.cumulativeCacheReadTokens
        }
        session.todos = projection.todos
        Self.applyGoalState(conv.state["goal"] as? [String: Any], to: &session)
        session.subagentRuns = projection.subagentRuns
        session.queuedPrompts = projection.queue
        session.pendingPermission = projection.permission
        session.pendingQuestion = projection.question
        session.pendingPlan = projection.plan
        session.statusNoticeText = projection.statusNotice
        for (id, options) in projection.permissionOptions { liveSync.permissionOptions[id] = options }
        if let request = projection.elicitation, let id = request["requestId"] as? String {
            liveSync.elicitations[id] = request
        }
        v4Sync.rowTargets = projection.rowTargets
        v4Sync.userAttachmentRefs = projection.userAttachmentRefs
        v4Sync.foregroundExecutionId = projection.foregroundExecutionId
        if session != sessions[idx] { sessions[idx] = session }
        v4ScheduleCacheSave()
    }

    // MARK: - Local cache

    /// Shows the cached transcript of `session` right away (read-only) while its bridge and subscription come up.
    func v4PreviewCachedConversation(_ session: AgentTaskSession) async {
        guard !isUITestSeededMode, !session.id.hasPrefix("task-"), session.messages.isEmpty else { return }
        let key = v4ConversationCacheKey(sessionId: session.id, path: session.workspacePath, identity: workspaceIdentityByPath[session.workspacePath])
        guard let payload = await V4LocalCache.loadConversation(key: key),
              let conv = V4ConversationState(cachePayload: payload, sessionId: session.id), conv.hasSnapshot,
              v4Sync.conversation?.sessionId != session.id || v4Sync.conversation?.hasSnapshot != true,
              let idx = sessions.firstIndex(where: { $0.id == session.id }), sessions[idx].messages.isEmpty else { return }
        let projection = V4ConversationMapper.project(conv) { _ in 0 }
        sessions[idx].messages = projection.messages
        sessions[idx].todos = projection.todos
        LoadBench.mark("cache preview \(session.id) msgs=\(projection.messages.count)")
    }

    func v4ConversationCacheKey(sessionId: String, path: String, identity: String?) -> String {
        V4LocalCache.key("conversation", activeConnectionId, ZCodeRPCClient.resolveWorkspaceKey(workspacePath: path, workspaceIdentity: identity), sessionId)
    }

    private func v4AttachmentCacheKey(ref: String) -> String {
        V4LocalCache.key("attachment", activeConnectionId, ZCodeRPCClient.resolveWorkspaceKey(workspacePath: v4Sync.conversationWorkspacePath, workspaceIdentity: v4Sync.conversationWorkspaceIdentity), ref)
    }

    private func v4ScheduleCacheSave() {
        guard !isUITestSeededMode, v4Sync.cacheSaveTask == nil else { return }
        v4Sync.cacheSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.v4Sync.cacheSaveTask = nil
            guard !Task.isCancelled, let conv = self.v4Sync.conversation else { return }
            self.v4SaveConversationCache(conv)
        }
    }

    /// Persists the window the user is looking at; the next open renders it at once and resumes from its `seq`.
    func v4SaveConversationCache(_ conv: V4ConversationState) {
        guard !isUITestSeededMode, let payload = conv.cachePayload(maxRows: V4LocalCache.conversationRowLimit) else { return }
        let key = v4ConversationCacheKey(sessionId: conv.sessionId, path: v4Sync.conversationWorkspacePath, identity: v4Sync.conversationWorkspaceIdentity)
        V4LocalCache.saveConversation(payload, key: key)
    }

    // MARK: - Commands

    @discardableResult
    func v4Command(
        _ type: String,
        payload: [String: Any],
        sessionId: String?,
        workspacePath: String,
        cas: Bool = false,
        rowTarget: Bool = false,
        projectId: String? = nil
    ) async throws -> [String: Any] {
        let identity = workspaceIdentityByPath[workspacePath]
        var attempt = 0
        var rehandshaked = false
        var baseRevision = v4Sync.conversation.flatMap { $0.sessionId == sessionId ? $0.revision : nil }
        while true {
            var envelope: [String: Any] = [
                "commandId": "cmd-\(UUID().uuidString.lowercased())",
                "clientId": Self.remoteClientId,
                "sessionId": sessionId ?? NSNull(),
                "type": type,
                "payload": payload,
                "issuedAt": Int(Date().timeIntervalSince1970 * 1000)
            ]
            if cas || rowTarget, let baseRevision { envelope["baseRevision"] = baseRevision }
            if rowTarget, let conv = v4Sync.conversation, conv.sessionId == sessionId { envelope["baseLogEpoch"] = conv.logEpoch }
            var arg = v4WorkspaceArg(workspacePath, identity)
            if let projectId { arg["projectId"] = projectId }
            arg["envelope"] = envelope
            let ack: [String: Any]
            do {
                let value = try await rpcClient.call(channel: "zcode-agent", method: "sendConversationCommandV4", args: [.fromJSONObject(arg)], timeoutSec: 30)
                let dict = value.decodeJSONDictionary() ?? [:]
                ack = (dict["ack"] as? [String: Any]) ?? dict
            } catch where !rehandshaked && Self.isHandshakeRequired(error) {
                rehandshaked = true
                v4Sync.handshakeDone = false
                guard await v4EnsureHandshake() else { throw error }
                continue
            }
            let status = (ack["status"] as? String) ?? "accepted"
            if !rehandshaked, status != "accepted", status != "duplicate", status != "noop",
               Self.isHandshakeRequired(V4CommandError(status: status, reasonCode: ack["reasonCode"] as? String, message: ack["message"] as? String)) {
                rehandshaked = true
                v4Sync.handshakeDone = false
                if await v4EnsureHandshake() { continue }
            }
            switch status {
            case "accepted", "duplicate", "noop":
                return ack
            case "stale" where (cas || rowTarget) && attempt < 2:
                attempt += 1
                baseRevision = ZCodeV4.int(ack["revisionAtDecision"]) ?? baseRevision
                v4Resync(force: false)
            default:
                if status == "stale" { v4Resync(force: false) }
                throw V4CommandError(status: status, reasonCode: ack["reasonCode"] as? String, message: ack["message"] as? String)
            }
        }
    }

    /// Production send path over V4; returns false if V4 is unavailable so the caller can use the legacy facade.
    func v4SendPrompt(
        sessionId: String,
        text: String,
        attachments: [ComposerAttachment],
        quotes: [ConversationQuote],
        queue: Bool
    ) async -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return false }
        guard await v4EnsureHandshake() else { return false }
        let path = session.workspacePath
        let identity = workspaceIdentityByPath[path]
        let selection = modelSelection(for: session)
        var targetId = sessionId

        do {
            if sessionId.hasPrefix("task-") {
                var config: [String: Any] = ["mode": session.mode.wireValue, "planEnabled": session.mode == .plan]
                if let selection {
                    config["modelSelection"] = selection.jsonObject
                    config["provider"] = selection.providerId
                    config["model"] = selection.modelId
                    if let level = selection.reasoningLevel { config["thought"] = level }
                }
                let ack = try await v4Command(
                    "createSession",
                    payload: ["workspaceId": ZCodeRPCClient.resolveWorkspaceKey(workspacePath: path, workspaceIdentity: identity), "config": config],
                    sessionId: nil,
                    workspacePath: path
                )
                guard let created = (ack["result"] as? [String: Any])?["sessionId"] as? String, !created.isEmpty else {
                    throw V4CommandError(status: "failed", reasonCode: nil, message: "Host did not return a session id.")
                }
                if let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) { sessions[sIdx].id = created }
                if activeSessionId == sessionId { activeSessionId = created }
                targetId = created
                if let fresh = sessions.first(where: { $0.id == created }) { _ = await v4SubscribeConversation(fresh) }
            }

            let refs = try await v4UploadAttachments(attachments, sessionId: targetId, workspacePath: path)
            var payload: [String: Any] = ["text": text, "mode": session.mode.wireValue, "planEnabled": session.mode == .plan]
            if !refs.isEmpty { payload["attachments"] = refs }
            if let selection { payload["modelSelection"] = selection.jsonObject }
            if queue { payload["requestedDelivery"] = "queue" }
            if !quotes.isEmpty {
                payload["conversationQuotes"] = quotes.map { quote -> [String: Any] in
                    var q: [String: Any] = ["text": quote.text]
                    if let path = quote.path { q["path"] = path }
                    if let sender = quote.senderName { q["senderName"] = sender }
                    if let messageId = quote.messageId { q["messageId"] = messageId }
                    return q
                }
            }
            if let conv = v4Sync.conversation, conv.sessionId == targetId,
               ((conv.state["inputRouting"] as? [String: Any])?["mode"] as? String) == "choice" {
                payload["heldQueueDisposition"] = "keepQueueAndSend"
            }
            try await v4Command("sendText", payload: payload, sessionId: targetId, workspacePath: path)
            if v4Sync.conversation?.sessionId != targetId, let fresh = sessions.first(where: { $0.id == targetId }) {
                _ = await v4SubscribeConversation(fresh)
            }
            return true
        } catch {
            if let idx = sessions.firstIndex(where: { $0.id == targetId }) {
                sessions[idx].status = .error
                sessions[idx].statusNoticeText = "Couldn't send: \(error.localizedDescription)"
            }
            v4Sync.optimistic.removeAll()
            return true
        }
    }

    private func v4UploadAttachments(_ attachments: [ComposerAttachment], sessionId: String, workspacePath: String) async throws -> [[String: Any]] {
        var refs: [[String: Any]] = []
        for attachment in attachments where attachment.kind != "comment" {
            guard let data = attachment.previewPNGData ?? attachment.filePath.flatMap({ try? Data(contentsOf: URL(fileURLWithPath: $0)) }),
                  !data.isEmpty else { continue }
            let mime = Self.mimeType(for: attachment, data: data)
            if Self.needsHostFileCopy(kind: attachment.kind, data: data) {
                do {
                    let path = try await copyFileToHost(name: attachment.name, data: data)
                    refs.append(["ref": path, "fileName": attachment.name, "mime": mime, "bytes": data.count])
                    continue
                } catch {
                    showToast("Couldn't copy \(attachment.name) to the Mac: \(error.localizedDescription)")
                }
            }
            let totalChunks = max(1, Int((Double(data.count) / Double(Self.attachmentChunkBytes)).rounded(.up)))
            var base = v4WorkspaceArg(workspacePath, workspaceIdentityByPath[workspacePath])
            base["uploadId"] = "upl-\(UUID().uuidString.lowercased())"
            base["sessionId"] = sessionId
            var begin = base
            begin["fileName"] = attachment.name
            begin["mime"] = mime
            begin["totalBytes"] = data.count
            begin["totalChunks"] = totalChunks
            begin["checksum"] = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            do {
                let started = try await rpcClient.call(channel: "zcode-agent", method: "attachmentBeginV4", args: [.fromJSONObject(begin)], timeoutSec: 20).decodeJSONDictionary() ?? [:]
                var ref = started["ref"] as? String
                if (started["state"] as? String) != "committed" {
                    var index = ZCodeV4.int(started["nextChunkIndex"]) ?? 0
                    while index < totalChunks {
                        let lower = index * Self.attachmentChunkBytes
                        let upper = min(data.count, lower + Self.attachmentChunkBytes)
                        var chunk = base
                        chunk["chunkIndex"] = index
                        chunk["dataBase64"] = data.subdata(in: lower..<upper).base64EncodedString()
                        let progress = try await rpcClient.call(channel: "zcode-agent", method: "attachmentChunkV4", args: [.fromJSONObject(chunk)], timeoutSec: 30).decodeJSONDictionary() ?? [:]
                        index = ZCodeV4.int(progress["nextChunkIndex"]) ?? (index + 1)
                    }
                    let committed = try await rpcClient.call(channel: "zcode-agent", method: "attachmentCommitV4", args: [.fromJSONObject(base)], timeoutSec: 30).decodeJSONDictionary() ?? [:]
                    ref = committed["ref"] as? String
                }
                guard let ref else { throw V4CommandError(status: "failed", reasonCode: nil, message: "Upload of \(attachment.name) returned no reference.") }
                refs.append(["ref": ref, "fileName": attachment.name, "mime": mime, "bytes": data.count])
            } catch {
                _ = try? await rpcClient.call(channel: "zcode-agent", method: "attachmentAbortV4", args: [.fromJSONObject(base)], timeoutSec: 6)
                throw error
            }
        }
        return refs
    }

    private static func mimeType(for attachment: ComposerAttachment, data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if bytes.count >= 12, bytes[8...11] == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "application/pdf" }
        switch URL(fileURLWithPath: attachment.name).pathExtension.lowercased() {
        case "heic": return "image/heic"
        case "txt", "log": return "text/plain"
        case "md": return "text/markdown"
        case "json": return "application/json"
        case "csv": return "text/csv"
        case "html", "htm": return "text/html"
        case "zip": return "application/zip"
        case "swift", "js", "ts", "py", "rb", "go", "rs", "java", "kt", "c", "h", "m", "cpp", "sh", "yml", "yaml", "xml", "css":
            return "text/plain"
        default: return "application/octet-stream"
        }
    }

    func v4Stop(sessionId: String, workspacePath: String) {
        var payload: [String: Any] = [:]
        if let exec = v4Sync.foregroundExecutionId { payload["expectedForegroundExecutionId"] = exec }
        Task { @MainActor in
            do {
                try await self.v4Command("stop", payload: payload, sessionId: sessionId, workspacePath: workspacePath)
            } catch {
                self.showToast("Couldn't stop: \(error.localizedDescription)")
            }
        }
    }

    func v4ResolveInteraction(sessionId: String, workspacePath: String, interactionId: String, answer: [String: Any]) {
        Task { @MainActor in
            do {
                try await self.v4Command(
                    "resolveInteraction",
                    payload: ["interactionId": interactionId, "answer": answer],
                    sessionId: sessionId,
                    workspacePath: workspacePath
                )
                self.liveSync.elicitations[interactionId] = nil
                self.liveSync.elicitationAnswers[interactionId] = nil
                self.liveSync.elicitationIndex[interactionId] = nil
                self.liveSync.permissionOptions[interactionId] = nil
            } catch {
                self.showToast("Couldn't send response: \(error.localizedDescription)")
                self.v4Resync(force: false)
            }
        }
    }

    /// Queue / config / feedback commands; each reports failure with a toast and resyncs.
    func v4Fire(_ type: String, payload: [String: Any], session: AgentTaskSession, cas: Bool = true, rowTarget: Bool = false, failure: String) {
        Task { @MainActor in
            do {
                try await self.v4Command(type, payload: payload, sessionId: session.id, workspacePath: session.workspacePath, cas: cas, rowTarget: rowTarget)
            } catch {
                self.showToast("\(failure): \(error.localizedDescription)")
                self.v4Resync(force: false)
            }
        }
    }

    func v4SetFeedback(messageId: String, rating: Int, session: AgentTaskSession) -> Bool {
        guard v4Owns(session.id), let target = v4Sync.rowTargets[messageId], target["entityId"] != nil else { return false }
        let feedback: Any = rating == 1 ? "like" as Any : (rating == -1 ? "dislike" as Any : NSNull())
        v4Fire("setAssistantFeedback", payload: ["target": target, "feedback": feedback], session: session, rowTarget: true, failure: "Couldn't save feedback")
        return true
    }

    func v4CanTarget(messageId: String) -> Bool {
        guard let session = activeSession, v4Owns(session.id) else { return false }
        return v4Sync.rowTargets[messageId]?["entityId"] != nil
    }

    /// `forkAssistant`: the host branches a new task from this assistant turn.
    func v4ForkAssistant(messageId: String) {
        guard let session = activeSession, v4Owns(session.id),
              let target = v4Sync.rowTargets[messageId], target["entityId"] != nil else { return }
        Task { @MainActor in
            do {
                let ack = try await self.v4Command("forkAssistant", payload: ["target": target], sessionId: session.id, workspacePath: session.workspacePath, rowTarget: true)
                let result = ack["result"] as? [String: Any]
                let childId = (result?["childSessionId"] as? String) ?? (result?["sessionId"] as? String)
                await self.loadAllWorkspaceTasks(preferredActiveTaskId: nil)
                if let childId, let child = self.sessions.first(where: { $0.id == childId }) {
                    self.selectSession(child)
                }
            } catch {
                self.showToast("Couldn't fork task: \(error.localizedDescription)")
            }
        }
    }

    /// `applyFileRewind`: restores workspace files to the state at this turn.
    func v4ApplyFileRewind(messageId: String) {
        guard let session = activeSession, v4Owns(session.id),
              let target = v4Sync.rowTargets[messageId], target["entityId"] != nil else { return }
        v4Fire("applyFileRewind", payload: ["target": target], session: session, rowTarget: true, failure: "Couldn't rewind files")
    }

    func v4RetryTurn(messageId: String) {
        guard let session = activeSession, v4Owns(session.id),
              let target = v4Sync.rowTargets[messageId], target["entityId"] != nil else { return }
        v4Fire("retryTurn", payload: ["target": target], session: session, rowTarget: true, failure: "Couldn't retry")
    }

    // MARK: - Edit a sent user prompt (`editUserQuery`)

    /// Host ACK result of `editUserQuery`. `blocked` means the file rewind was refused and nothing was changed.
    struct V4EditUserQueryResult: Equatable {
        enum Disposition: String {
            case rewind
            case fork
            case blocked
        }

        var disposition: Disposition?
        var reasonCode: String?
        /// Session that now owns the edited turn (a new id when the host chose to fork).
        var sessionId: String?

        init(disposition: Disposition? = nil, reasonCode: String? = nil, sessionId: String? = nil) {
            self.disposition = disposition
            self.reasonCode = reasonCode
            self.sessionId = sessionId
        }

        var isBlocked: Bool { disposition == .blocked }
    }

    /// Desktop parity: the edit action only appears for `row.actions.canEdit` rows that carry an `entityId` target.
    func v4CanEditUserMessage(_ messageId: String) -> Bool {
        guard let session = activeSession, v4Owns(session.id) else { return false }
        return v4Sync.rowTargets[messageId]?["entityId"] != nil
    }

    /// Pure `editUserQuery` payload builder, mirroring the desktop renderer's `Sa` helper.
    static func editUserQueryPayload(
        target: [String: Any],
        newText: String,
        workspaceMode: String,
        quotes: [ConversationQuote],
        attachmentRefs: [[String: Any]],
        selection: LiveModelSelection?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "target": target,
            "newText": newText,
            "workspaceMode": workspaceMode,
            "attachments": attachmentRefs
        ]
        if !quotes.isEmpty {
            payload["conversationQuotes"] = quotes.map { quote -> [String: Any] in
                var q: [String: Any] = ["text": quote.text]
                if let path = quote.path { q["path"] = path }
                if let sender = quote.senderName { q["senderName"] = sender }
                if let messageId = quote.messageId { q["messageId"] = messageId }
                return q
            }
        }
        if let selection { payload["modelSelection"] = selection.jsonObject }
        return payload
    }

    /// Rewrites a sent prompt on the host. `workspaceMode` is `"preserve"` (conversation only, the desktop "Send"
    /// button) or `"rewind"` (also restores the turn's files, "Reset chat + files").
    ///
    /// Returns only after the host ACK; the caller must not truncate local rows itself — the host snapshot after the
    /// command is authoritative (`editUserQuery` rewinds host-side turns, so following rows disappear on next publish).
    ///
    /// `keptAttachmentIndices` selects which of the row's original attachments survive (all when nil, like the
    /// desktop editor before any removal); `newAttachments` are uploaded and appended after them.
    func v4EditUserQuery(
        messageId: String,
        newText: String,
        workspaceMode: String,
        quotes: [ConversationQuote],
        keptAttachmentIndices: [Int]? = nil,
        newAttachments: [ComposerAttachment] = []
    ) async throws -> V4EditUserQueryResult {
        guard let session = activeSession, v4Owns(session.id),
              let target = v4Sync.rowTargets[messageId], target["entityId"] != nil else {
            throw V4CommandError(status: "unavailable", reasonCode: nil, message: "This message can't be edited on the host right now.")
        }
        let original = v4Sync.userAttachmentRefs[messageId] ?? []
        var refs = Self.keptAttachmentRefs(original, indices: keptAttachmentIndices)
        if !newAttachments.isEmpty {
            refs += try await v4UploadAttachments(newAttachments, sessionId: session.id, workspacePath: session.workspacePath)
        }
        let payload = Self.editUserQueryPayload(
            target: target,
            newText: newText,
            workspaceMode: workspaceMode,
            quotes: quotes,
            attachmentRefs: refs,
            selection: modelSelection(for: session)
        )
        let ack = try await v4Command(
            "editUserQuery",
            payload: payload,
            sessionId: session.id,
            workspacePath: session.workspacePath,
            cas: true,
            rowTarget: true
        )
        var outcome = V4EditUserQueryResult()
        if let result = ack["result"] as? [String: Any], (result["type"] as? String) == "editUserQuery" {
            outcome.disposition = (result["disposition"] as? String).flatMap(V4EditUserQueryResult.Disposition.init(rawValue:))
            outcome.reasonCode = result["reasonCode"] as? String
            outcome.sessionId = result["sessionId"] as? String
        }
        return outcome
    }

    static func keptAttachmentRefs(_ refs: [[String: Any]], indices: [Int]?) -> [[String: Any]] {
        guard let indices else { return refs }
        return indices.filter { refs.indices.contains($0) }.map { refs[$0] }
    }

    /// MIME type of a user-row attachment as recorded by the host.
    func v4UserAttachmentMimeType(messageId: String, index: Int) -> String? {
        guard let refs = v4Sync.userAttachmentRefs[messageId], refs.indices.contains(index) else { return nil }
        return refs[index]["mime"] as? String
    }

    /// Reads a user-row attachment from the host in 512 KB pages (`conversationAttachmentReadV4`, desktop `_Ue`).
    func v4ReadUserAttachment(messageId: String, index: Int) async throws -> (data: Data, mimeType: String) {
        guard let conv = v4Sync.conversation, let refs = v4Sync.userAttachmentRefs[messageId], refs.indices.contains(index),
              let ref = refs[index]["ref"] as? String,
              let target = v4Sync.rowTargets[messageId], let entityId = target["entityId"] as? String,
              let rowId = ZCodeV4.int(target["rowId"]) else {
            throw V4CommandError(status: "unavailable", reasonCode: nil, message: "This attachment isn't available from the host.")
        }
        if let cached = v4Sync.attachmentData[ref] { return cached }
        let diskKey = v4AttachmentCacheKey(ref: ref)
        if let stored = await V4LocalCache.loadAttachment(key: diskKey) {
            v4Sync.attachmentData[ref] = stored
            return stored
        }
        var mimeType = (refs[index]["mime"] as? String) ?? "application/octet-stream"
        if ref.hasPrefix("/") {
            let expected = ZCodeV4.int(refs[index]["bytes"]) ?? 0
            let data = try await readFileBytesInRanges(path: ref, expectedSize: expected, maxBytes: Self.attachmentReadMaxBytes)
            v4Sync.attachmentData[ref] = (data, mimeType)
            return (data, mimeType)
        }
        var arg = v4WorkspaceArg(v4Sync.conversationWorkspacePath, v4Sync.conversationWorkspaceIdentity)
        arg["sessionId"] = conv.sessionId
        arg["ref"] = ref
        arg["target"] = ["rowId": rowId, "entityId": entityId]
        arg["attachmentIndex"] = index
        arg["limit"] = Self.attachmentReadPageBytes
        var data = Data()
        var offset = 0
        while true {
            arg["offset"] = offset
            let page = try await rpcClient.call(channel: "zcode-agent", method: "conversationAttachmentReadV4", args: [.fromJSONObject(arg)], timeoutSec: 30).decodeJSONDictionary() ?? [:]
            guard let chunk = (page["dataBase64"] as? String).flatMap({ Data(base64Encoded: $0) }) else {
                throw V4CommandError(status: "failed", reasonCode: nil, message: "The host returned an unreadable attachment page.")
            }
            if let type = page["mediaType"] as? String, !type.isEmpty { mimeType = type }
            data.append(chunk)
            guard let next = ZCodeV4.int(page["nextOffset"]), next > offset, !chunk.isEmpty,
                  data.count < Self.attachmentReadMaxBytes else { break }
            offset = next
        }
        if v4Sync.attachmentData.count >= Self.attachmentCacheLimit { v4Sync.attachmentData.removeAll() }
        v4Sync.attachmentData[ref] = (data, mimeType)
        V4LocalCache.saveAttachment(data, mimeType: mimeType, key: diskKey)
        return (data, mimeType)
    }

    private static let attachmentReadPageBytes = 512 * 1024
    private static let attachmentReadMaxBytes = 32 * 1024 * 1024
    private static let attachmentCacheLimit = 40

    // MARK: - Subagent child conversation (read-only pane)

    /// Opens the read-only transcript of a subagent's child session, like the desktop side pane (`wIn`).
    public func openSubagentSession(childSessionId: String, title: String) {
        guard !childSessionId.isEmpty else { return }
        if let current = subagentPane, current.sessionId != childSessionId {
            subagentPaneBackStack.append(current)
        }
        subagentPane = SubagentPaneState(sessionId: childSessionId, title: title.isEmpty ? "Subagent" : title)
        showInspectorSheet = false
        showSubagentDrawer = true
        Task { @MainActor in await self.v4SubscribeChild(childSessionId) }
    }

    /// Returns to the parent subagent pane, or closes the pane at the root.
    public func popSubagentSession() {
        if let previous = subagentPaneBackStack.popLast() {
            subagentPane = previous
            subagentPane?.messages = []
            subagentPane?.isLoading = true
            Task { @MainActor in await self.v4SubscribeChild(previous.sessionId) }
        } else {
            closeSubagentSession()
        }
    }

    public func closeSubagentSession() {
        showSubagentDrawer = false
        subagentPane = nil
        subagentPaneBackStack.removeAll()
        v4UnsubscribeChild()
    }

    private func v4UnsubscribeChild() {
        guard let child = v4Sync.child else { return }
        v4Sync.child = nil
        v4Sync.childAwaitingAck = false
        v4Sync.childStaged.removeAll()
        guard let subId = child.subscriptionId else { return }
        var arg = v4WorkspaceArg(v4Sync.conversationWorkspacePath, v4Sync.conversationWorkspaceIdentity)
        arg["subscriptionId"] = subId
        let client = rpcClient
        Task { _ = try? await client.call(channel: "zcode-agent", method: "unsubscribeConversationV4", args: [.fromJSONObject(arg)], timeoutSec: 6) }
    }

    private func v4SubscribeChild(_ childSessionId: String) async {
        v4UnsubscribeChild()
        guard !isUITestSeededMode, isLiveHostConnected, await v4EnsureHandshake(),
              let path = activeSession?.workspacePath else {
            subagentPane?.isLoading = false
            subagentPane?.errorText = "Connect to your computer to view this subagent."
            return
        }
        let identity = workspaceIdentityByPath[path]
        guard await v4EnsureFrameListener(path: path, identity: identity, event: "onDynamicConversationFrame") else {
            subagentPane?.isLoading = false
            subagentPane?.errorText = "Couldn't open the subagent session."
            return
        }
        let child = V4ConversationState(sessionId: childSessionId)
        v4Sync.child = child
        v4Sync.childAwaitingAck = true
        v4Sync.childStaged.removeAll()
        v4Sync.assembler.reset(topic: child.topic)
        var arg = v4WorkspaceArg(path, identity)
        arg["sessionId"] = childSessionId
        do {
            let value = try await rpcClient.call(channel: "zcode-agent", method: "subscribeConversationV4", args: [.fromJSONObject(arg)], timeoutSec: 25)
            guard v4Sync.child?.sessionId == childSessionId else { return }
            let dict = value.decodeJSONDictionary() ?? [:]
            let ack = (dict["ack"] as? [String: Any]) ?? dict
            guard let subscriptionId = ack["subscriptionId"] as? String else {
                throw V4CommandError(status: "failed", reasonCode: nil, message: "Host returned no subscription id.")
            }
            v4Sync.child?.subscriptionId = subscriptionId
            v4Sync.childAwaitingAck = false
            let staged = v4Sync.childStaged
            v4Sync.childStaged.removeAll()
            for envelope in staged where (envelope["subscriptionId"] as? String) == subscriptionId {
                v4HandleChildEnvelope(envelope)
            }
        } catch {
            guard v4Sync.child?.sessionId == childSessionId else { return }
            v4Sync.child = nil
            v4Sync.childAwaitingAck = false
            subagentPane?.isLoading = false
            subagentPane?.errorText = error.localizedDescription
        }
    }

    private func v4HandleChildEnvelope(_ envelope: [String: Any]) {
        if v4Sync.childAwaitingAck {
            if v4Sync.childStaged.count < 1024 { v4Sync.childStaged.append(envelope) }
            return
        }
        guard let child = v4Sync.child, let subId = child.subscriptionId,
              (envelope["subscriptionId"] as? String) == subId else { return }
        switch v4Sync.assembler.ingest(envelope) {
        case .frame(let frame, _):
            guard var current = v4Sync.child, current.subscriptionId == subId else { return }
            let result = current.apply(frame: frame)
            v4Sync.child = current
            switch result {
            case .applied: v4PublishChild()
            case .gap: v4ResyncChild()
            case .ignored: break
            }
        case .fault:
            v4ResyncChild()
        case .ignored:
            break
        }
    }

    private func v4ResyncChild() {
        guard !v4Sync.childResyncInFlight, let child = v4Sync.child, let subId = child.subscriptionId else { return }
        v4Sync.childResyncInFlight = true
        var arg = v4WorkspaceArg(v4Sync.conversationWorkspacePath, v4Sync.conversationWorkspaceIdentity)
        arg["subscriptionId"] = subId
        arg["base"] = NSNull()
        arg["forceSnapshot"] = true
        v4Sync.assembler.reset(topic: child.topic)
        Task { @MainActor in
            defer { self.v4Sync.childResyncInFlight = false }
            _ = try? await self.rpcClient.call(channel: "zcode-agent", method: "resyncConversationV4", args: [.fromJSONObject(arg)], timeoutSec: 25)
        }
    }

    private func v4PublishChild() {
        guard let child = v4Sync.child, child.hasSnapshot, subagentPane?.sessionId == child.sessionId else { return }
        let projection = V4ConversationMapper.project(child) { _ in 0 }
        var pane = subagentPane!
        pane.messages = projection.messages
        pane.status = projection.status
        pane.statusNotice = projection.statusNotice
        pane.todos = projection.todos
        if let model = projection.model {
            pane.model = model
        } else if let label = projection.messages.last(where: { !($0.modelLabel ?? "").isEmpty })?.modelLabel {
            pane.model = LiveModelSelection(providerId: "", modelId: label)
        }
        pane.isLoading = false
        pane.errorText = nil
        if pane != subagentPane { subagentPane = pane }
    }

    /// Stops a running subagent or background job (`cancelBackgroundWork {workId}`) on the active session.
    public func cancelBackgroundWork(workId: String) {
        guard let session = activeSession else { return }
        v4Fire("cancelBackgroundWork", payload: ["workId": workId], session: session, cas: false, failure: "Couldn't stop the subagent")
    }

    // MARK: - Sessions index

    func v4SubscribeSessionsIndex(projectId: String, path: String, identity: String?) async {
        guard await v4EnsureHandshake() else { return }
        let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: path, workspaceIdentity: identity)
        if v4Sync.indexes[key]?.subscriptionId != nil || v4Sync.indexAwaitingAck.contains(key) { return }
        v4Sync.indexTargets[key] = (projectId, path, identity)
        guard await v4EnsureFrameListener(path: path, identity: identity, event: "onDynamicSessionsIndexFrame") else { return }
        v4Sync.indexes[key] = V4SessionsIndexState(workspaceKey: key)
        v4Sync.indexAwaitingAck.insert(key)
        v4Sync.indexStaged[key] = []
        v4Sync.assembler.reset(topic: "sessions-index/\(key)")
        var arg = v4WorkspaceArg(path, identity)
        arg["runtimePolicy"] = "existing-only"
        defer { v4Sync.indexAwaitingAck.remove(key) }
        guard let value = try? await rpcClient.call(channel: "zcode-agent", method: "subscribeSessionsIndexV4", args: [.fromJSONObject(arg)], timeoutSec: 20),
              let dict = value.decodeJSONDictionary() else {
            v4Sync.indexes[key] = nil
            return
        }
        let ack = (dict["ack"] as? [String: Any]) ?? dict
        guard let subscriptionId = ack["subscriptionId"] as? String else {
            v4Sync.indexes[key] = nil
            return
        }
        v4Sync.indexes[key]?.subscriptionId = subscriptionId
        v4Sync.indexAwaitingAck.remove(key)
        let staged = v4Sync.indexStaged.removeValue(forKey: key) ?? []
        for envelope in staged where (envelope["subscriptionId"] as? String) == subscriptionId {
            v4HandleEnvelope(envelope)
        }
    }

    private func v4HandleIndexEnvelope(_ envelope: [String: Any], topic: String) {
        let key = String(topic.dropFirst("sessions-index/".count))
        guard var index = v4Sync.indexes[key] else { return }
        if v4Sync.indexAwaitingAck.contains(key) {
            v4Sync.indexStaged[key, default: []].append(envelope)
            return
        }
        guard let subId = index.subscriptionId, (envelope["subscriptionId"] as? String) == subId else { return }
        guard case .frame(let frame, _) = v4Sync.assembler.ingest(envelope) else { return }
        switch index.apply(frame: frame) {
        case .applied:
            v4Sync.indexes[key] = index
            v4ApplySessionsIndex(key: key)
        case .gap:
            var arg = v4WorkspaceArg(v4Sync.indexTargets[key]?.path ?? key, v4Sync.indexTargets[key]?.identity)
            arg["subscriptionId"] = subId
            arg["base"] = NSNull()
            arg["forceSnapshot"] = true
            v4Sync.assembler.reset(topic: topic)
            let client = rpcClient
            Task { @MainActor in
                if (try? await client.call(channel: "zcode-agent", method: "resyncSessionsIndexV4", args: [.fromJSONObject(arg)], timeoutSec: 20)) == nil,
                   let target = self.v4Sync.indexTargets[key] {
                    self.v4Sync.indexes[key] = nil
                    await self.v4SubscribeSessionsIndex(projectId: target.projectId, path: target.path, identity: target.identity)
                }
            }
        case .ignored:
            break
        }
    }

    private func v4ApplySessionsIndex(key: String) {
        guard let index = v4Sync.indexes[key], let target = v4Sync.indexTargets[key] else { return }
        var unknown = false
        for (sessionId, entry) in index.sessions {
            guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else {
                if entry["parentSessionId"] == nil, !v4Sync.refreshedUnknownSessions.contains(sessionId) {
                    v4Sync.refreshedUnknownSessions.insert(sessionId)
                    unknown = true
                }
                continue
            }
            var session = sessions[idx]
            if let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
               !v4Owns(sessionId) {
                session.title = title
            }
            let pendingKind = (entry["pendingInteraction"] as? [String: Any])?["kind"] as? String
            var permission = pendingKind == "permission" ? 1 : 0
            var userInput = pendingKind == "userInput" ? 1 : 0
            if let counts = entry["pendingInteractions"] as? [String: Any] {
                permission = Int(ZCodeV4.double(counts["permissionCount"]) ?? 0)
                userInput = Int(ZCodeV4.double(counts["userInputCount"]) ?? 0)
            }
            Self.applyActivity(phase: (entry["phase"] as? String) ?? "draft",
                               hasBackgroundWork: (entry["hasBackgroundWork"] as? Bool) ?? false,
                               permissionCount: permission,
                               userInputCount: userInput,
                               lastActivityAt: ZCodeV4.double(entry["lastActivityAt"]) ?? 0,
                               ownsStatus: v4Owns(sessionId),
                               to: &session)
            if session != sessions[idx] { sessions[idx] = session }
        }
        if unknown {
            scheduleWorkspaceRefresh(projectId: target.projectId, workspacePath: target.path, workspaceIdentity: target.identity)
        }
    }

    // MARK: - Goal & Workflow-run projections from the V4 snapshot

    /// `snapshot.goal` (`Kf`) -> status panel Goal section.
    static func applyGoalState(_ goal: [String: Any]?, to session: inout AgentTaskSession) {
        guard let goal else {
            session.goals = []
            session.goalElapsedText = nil
            session.goalPaused = false
            return
        }
        let summary = ((goal["summaryTitle"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let objective = ((goal["objective"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = summary.isEmpty ? objective : summary
        let status = (goal["status"] as? String) ?? ""
        session.goals = title.isEmpty
            ? []
            : [GoalObjectiveItem(id: (goal["targetId"] as? String) ?? "goal", title: title, completed: status == "verified")]
        session.goalPaused = status == "paused"
        if let seconds = ZCodeV4.double(goal["timeUsedSeconds"]), seconds > 0 {
            let total = Int(seconds)
            if total >= 3600 {
                session.goalElapsedText = "\(total / 3600)h \((total % 3600) / 60)m"
            } else if total >= 60 {
                session.goalElapsedText = "\(total / 60)m \(total % 60)s"
            } else {
                session.goalElapsedText = "\(total)s"
            }
        } else {
            session.goalElapsedText = nil
        }
    }

    /// Workflow runs reported by `snapshot.workflowRuns` for the active conversation.
    public var activeWorkflowRunSummaries: [LiveWorkflowRunSummary] {
        guard let session = activeSession, v4Owns(session.id),
              let conv = v4Sync.conversation,
              let container = conv.state["workflowRuns"] as? [String: Any],
              let runs = container["runs"] as? [[String: Any]] else { return [] }
        return runs.compactMap { run in
            guard let runId = run["runId"] as? String, !runId.isEmpty else { return nil }
            let status = (run["status"] as? String) ?? "pending"
            var title: String?
            for row in conv.rows {
                let launch = (row["workflowLaunch"] as? [String: Any])
                    ?? ((row["turnHeader"] as? [String: Any])?["workflowLaunch"] as? [String: Any])
                guard let launch, (launch["runId"] as? String) == runId else { continue }
                title = (launch["name"] as? String) ?? (launch["description"] as? String)
                if title?.isEmpty == true { title = nil }
                break
            }
            let usage = run["usage"] as? [String: Any]
            let spent = ZCodeV4.int(usage?["spentTokens"])
            let nodesUsed = ZCodeV4.int(usage?["nodesUsed"]) ?? (run["nodes"] as? [[String: Any]])?.count
            var parts: [String] = []
            if let nodesUsed, nodesUsed > 0 { parts.append("\(nodesUsed) steps") }
            if let spent, spent > 0 { parts.append("\(spent) tokens") }
            let detail: String = {
                if let error = run["error"] as? String, !error.isEmpty { return error }
                if let result = run["resultPreview"] as? String, !result.isEmpty { return result }
                if let stop = run["stopReason"] as? String, !stop.isEmpty { return "Stopped: \(stop)" }
                return ""
            }()
            return LiveWorkflowRunSummary(
                id: runId,
                title: title ?? "Workflow \(runId.prefix(8))",
                status: status,
                detail: detail,
                usageText: parts.joined(separator: " · ")
            )
        }
    }
}

public struct LiveWorkflowRunSummary: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var status: String
    public var detail: String
    public var usageText: String

    public init(id: String, title: String, status: String, detail: String, usageText: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.usageText = usageText
    }
}
