import Foundation
import CryptoKit

/// Bookkeeping for the V4 conversation protocol (main actor only, not observed).
final class V4SyncState {
    /// nil = not probed yet, false = host lacks V4 (legacy zcode-task facade is used instead).
    var available: Bool?
    var handshakeDone = false
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
    var rowTargets: [String: [String: Any]] = [:]
    var foregroundExecutionId: String?
    var loadingOlder = false
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
        handshakeTask?.cancel()
        handshakeTask = nil
        assembler.reset()
        conversationFrameSubs.removeAll()
        indexFrameSubs.removeAll()
        lifecycleSubId = nil
        conversation?.subscriptionId = nil
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
        if v4Sync.handshakeDone { return true }
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
                self.v4Sync.available = true
                await self.v4ListenLifecycle()
                return true
            } catch {
                if Self.isUnsupportedMethod(error) { self.v4Sync.available = false }
                return false
            }
        }
        v4Sync.handshakeTask = task
        let ok = await task.value
        v4Sync.handshakeTask = nil
        return ok
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

    private func v4Resubscribe(sessionId: String) async {
        v4Sync.conversation = nil
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
                if current.hasSnapshot { v4Sync.snapshotWatchdog?.cancel() }
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
        guard await v4EnsureHandshake() else { return false }
        if let conv = v4Sync.conversation, conv.sessionId == session.id, conv.subscriptionId != nil || v4Sync.subscribeInFlight == session.id {
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

        let conv = V4ConversationState(sessionId: session.id)
        v4Sync.conversation = conv
        v4Sync.conversationWorkspacePath = path
        v4Sync.conversationWorkspaceIdentity = identity
        v4Sync.awaitingAck = true
        v4Sync.staged.removeAll()
        v4Sync.subscribeInFlight = session.id
        v4Sync.rowTargets.removeAll()
        v4Sync.assembler.reset(topic: conv.topic)
        defer { if v4Sync.subscribeInFlight == session.id { v4Sync.subscribeInFlight = nil } }

        var arg = v4WorkspaceArg(path, identity)
        arg["sessionId"] = session.id
        do {
            let value = try await rpcClient.call(channel: "zcode-agent", method: "subscribeConversationV4", args: [.fromJSONObject(arg)], timeoutSec: 25)
            guard v4Sync.conversation?.sessionId == session.id else { return true }
            let dict = value.decodeJSONDictionary() ?? [:]
            let ack = (dict["ack"] as? [String: Any]) ?? dict
            guard let subscriptionId = ack["subscriptionId"] as? String else {
                throw V4CommandError(status: "failed", reasonCode: nil, message: "Host returned no subscription id.")
            }
            v4Sync.conversation?.subscriptionId = subscriptionId
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

    /// Loads up to 200 older transcript rows before the current window.
    public func loadOlderMessages() {
        guard let conv = v4Sync.conversation, conv.hasOlderRows, !v4Sync.loadingOlder,
              let oldest = conv.rows.first.flatMap({ ZCodeV4.int($0["rowId"]) }) else { return }
        v4Sync.loadingOlder = true
        var arg = v4WorkspaceArg(v4Sync.conversationWorkspacePath, v4Sync.conversationWorkspaceIdentity)
        arg["sessionId"] = conv.sessionId
        arg["beforeRowId"] = oldest
        arg["limit"] = ZCodeV4.rowsRangeMaxLimit
        Task { @MainActor in
            defer { self.v4Sync.loadingOlder = false }
            guard let value = try? await self.rpcClient.call(channel: "zcode-agent", method: "conversationRowsRangeV4", args: [.fromJSONObject(arg)], timeoutSec: 15),
                  let dict = value.decodeJSONDictionary(),
                  var current = self.v4Sync.conversation, current.sessionId == conv.sessionId else { return }
            if current.prepend(olderRows: (dict["rows"] as? [[String: Any]]) ?? [], atLogEpoch: (dict["atLogEpoch"] as? String) ?? "") {
                self.v4Sync.conversation = current
                self.v4Publish()
            }
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
        v4Sync.foregroundExecutionId = projection.foregroundExecutionId
        if session != sessions[idx] { sessions[idx] = session }
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
            let value = try await rpcClient.call(channel: "zcode-agent", method: "sendConversationCommandV4", args: [.fromJSONObject(arg)], timeoutSec: 30)
            let dict = value.decodeJSONDictionary() ?? [:]
            let ack = (dict["ack"] as? [String: Any]) ?? dict
            let status = (ack["status"] as? String) ?? "accepted"
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
            if v4Owns(sessionId) { continue }
            var session = sessions[idx]
            if let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                session.title = title
            }
            let pendingKind = (entry["pendingInteraction"] as? [String: Any])?["kind"] as? String
            session.status = {
                if pendingKind == "permission" { return .waitingApproval }
                if pendingKind == "userInput" { return .waitingQuestion }
                switch entry["phase"] as? String {
                case "running", "prewarming": return .running
                case "error": return .error
                case "completedSuccess": return .completed
                default: return .idle
                }
            }()
            if let activity = ZCodeV4.double(entry["lastActivityAt"]) {
                let date = Date(timeIntervalSince1970: activity / 1000)
                if date > session.updatedAt { session.updatedAt = date }
            }
            if session != sessions[idx] { sessions[idx] = session }
        }
        if unknown {
            scheduleWorkspaceRefresh(projectId: target.projectId, workspacePath: target.path, workspaceIdentity: target.identity)
        }
    }
}
