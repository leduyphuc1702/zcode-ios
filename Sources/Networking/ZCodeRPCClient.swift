import Foundation

public struct ServerInfoResponse: Codable, Sendable {
    public let serverId: String?
    public let version: String
    public let protocolVersion: Int?
    public let authRequired: Bool?
}

public struct RemoteWorkspaceSummary: Equatable, Sendable {
    public let workspaceKey: String
    public let workspacePath: String
    public let workspaceIdentity: String?
    public let remoteSessionId: String?
    public let name: String
    public let kind: String
    public let connectionState: String
    public let branchName: String
    public let isDirty: Bool
    public let tasks: [RemoteTaskSummary]

    public var canBridge: Bool {
        if kind == "remote" {
            let hasIdentity = !(workspaceIdentity ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasSession = !(remoteSessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasIdentity && hasSession && connectionState != "disconnected"
        }
        return true
    }
}

public struct RemoteTaskSummary: Equatable, Sendable {
    public let id: String
    public let title: String
    public let workspacePath: String
    public let workspaceIdentity: String?
    public let status: String
    public let pinned: Bool
    public let archived: Bool
    public let unread: Bool
    public let updatedAt: Date
    public var createdAt: Date? = nil
    public var mode: String? = nil
    /// Model picker value (`provider/model$level`).
    public var model: String? = nil
    public var thoughtLevel: String? = nil
    /// `permission` or `userInput` when the task is blocked on the user.
    public var pendingInteractionKind: String? = nil
}

public struct RelayBridgeIdentity: Equatable, Sendable {
    public let bridgeSessionId: String
    public let bridgeGeneration: Int?
    public let recoveryId: String?
    public let workspaceKey: String
    public let workspacePath: String
    public let workspaceIdentity: String?
    public let remoteSessionId: String?
    public let kind: String
    public let initialTaskId: String?

    public init(
        bridgeSessionId: String,
        bridgeGeneration: Int?,
        recoveryId: String? = nil,
        workspaceKey: String,
        workspacePath: String,
        workspaceIdentity: String? = nil,
        remoteSessionId: String? = nil,
        kind: String = "local",
        initialTaskId: String? = nil
    ) {
        self.bridgeSessionId = bridgeSessionId
        self.bridgeGeneration = bridgeGeneration
        self.recoveryId = recoveryId
        self.workspaceKey = workspaceKey
        self.workspacePath = workspacePath
        self.workspaceIdentity = workspaceIdentity
        self.remoteSessionId = remoteSessionId
        self.kind = kind
        self.initialTaskId = initialTaskId
    }

    /// Exact identity check matching `pns` / `g0t` in ZCode v3.16.3 (`bridgeSessionId`, `bridgeGeneration`, `recoveryId`).
    public func matchesTransportPayload(_ payload: [String: Any]) -> Bool {
        guard (payload["bridgeSessionId"] as? String) == bridgeSessionId else { return false }
        let incomingGen = (payload["bridgeGeneration"] as? Int)
            ?? (payload["bridgeGeneration"] as? NSNumber)?.intValue
        guard incomingGen == bridgeGeneration else { return false }
        let incomingRecovery = payload["recoveryId"] as? String
        return incomingRecovery == recoveryId
    }
}

public struct RelayBootstrapSnapshot: Equatable, Sendable {
    public let desktopAppVersion: String?
    public let workspaces: [RemoteWorkspaceSummary]
    public let activeWorkspaceKey: String?
    public let activeTaskId: String?
    public let openedBridge: RelayBridgeIdentity?
}

/// Native URLSessionWebSocketTask client implementing both:
/// 1. Direct ZCode Server binary RPC (`SocketProtocol` 13-byte header + `VQL` over `/ws`)
/// 2. Official Z.AI Remote Relay V4 (`wss://zcode.z.ai/api/v1/remote/ws2` with `role: "terminal"`,
///    `auth_challenge` HMAC-SHA256 proof, `pair_status`, `bootstrap-request`, `workspace-bridge-open`,
///    strict `She`/`vtt` `rpc-frame` + `rpc-frame-ack` envelopes, and raw `ChannelClient` VQL payloads)
public actor ZCodeRPCClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private let terminalClientSessionId: String = "ios-\(UUID().uuidString.lowercased())"

    private var nextRequestId: Int32 = 1
    private var nextBridgeGeneration: Int = 0
    private var nextPhysicalSeq: Int = 1
    private var nextMessageSeq: Int = 1
    private var isInitialized = false
    private var isRelayMode = false
    private var pairingAlreadyMatched = false
    private var activeBridgeIdentity: RelayBridgeIdentity?

    private var initWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingReplies: [Int32: CheckedContinuation<VQLValue, Error>] = [:]
    private var pendingAppRequests: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var pairingContinuation: CheckedContinuation<Void, Error>?
    private var phaseCallback: (@Sendable (RelayPairingPhase) -> Void)?
    private var workspaceListUpdateHandler: (@Sendable ([RemoteWorkspaceSummary], String?, String?) -> Void)?
    private var eventHandlers: [Int32: @Sendable (VQLValue) -> Void] = [:]
    private var bridgeChangeHandler: (@Sendable (RelayBridgeIdentity) -> Void)?
    private var bridgeDegradedHandler: (@Sendable (String) -> Void)?
    private var connectionLostHandler: (@Sendable (String) -> Void)?
    private var peerStatusHandler: (@Sendable (Bool) -> Void)?
    private var terminalErrorHandler: (@Sendable (String, String) -> Void)?
    private var fragmentBuffers: [Int: [Int: Data]] = [:]
    /// Inbound `messageSeq`s already handed to the channel; Desktop replays unACKed frames after a relay blip.
    private var deliveredMessageSeqFloor = 0
    private var deliveredMessageSeqs: Set<Int> = []
    private var mobileTaskViewEpoch: String?
    private var mobileTaskViewSeq = 0
    private var mobileTaskViewTaskId: String?
    private var bootstrapRequiredHandler: (@Sendable () -> Void)?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var livenessTask: Task<Void, Never>?
    private var lastInboundAt = Date()
    private var missedPongs = 0
    private var peerOffline = false

    private var currentDeviceSid: String = ""
    private var currentPassHash: String = ""

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    public func setWorkspaceListUpdateHandler(
        _ handler: (@Sendable ([RemoteWorkspaceSummary], String?, String?) -> Void)?
    ) {
        self.workspaceListUpdateHandler = handler
    }

    /// Fired after every successful `workspace-bridge-ready`; all channel subscriptions are gone at that point and must be re-registered.
    public func setBridgeChangeHandler(_ handler: (@Sendable (RelayBridgeIdentity) -> Void)?) {
        self.bridgeChangeHandler = handler
    }

    public func setBridgeDegradedHandler(_ handler: (@Sendable (String) -> Void)?) {
        self.bridgeDegradedHandler = handler
    }

    /// Desktop dropped this terminal as owner (`terminal-owner-ended`, or a bridge open rejected with "bootstrap is required").
    public func setBootstrapRequiredHandler(_ handler: (@Sendable () -> Void)?) {
        self.bootstrapRequiredHandler = handler
    }

    /// Re-establishes terminal ownership and a fresh bridge after Desktop ended the previous owner.
    public func rebootstrap(preferredWorkspaceKey: String?, preferredTaskId: String?) async -> RelayBootstrapSnapshot {
        activeBridgeIdentity = nil
        return await bootstrapRelayWorkspaces(preferredWorkspaceKey: preferredWorkspaceKey, preferredTaskId: preferredTaskId)
    }

    public func sendMobileDiagnostic(event: String, detail: [String: Any]) async {
        guard isRelayMode, let task = webSocketTask else { return }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        try? await sendJSONEnvelope([
            "type": "data",
            "payload": ["zcode_type": "mobile-diagnostic", "event": event, "at": nowMs, "detail": detail],
            "client_ts": nowMs
        ], on: task)
    }

    public func setConnectionLostHandler(_ handler: (@Sendable (String) -> Void)?) {
        self.connectionLostHandler = handler
    }

    /// Relay `pair_status` transitions after the first match: `false` when ZCode Desktop drops off the relay, `true` when it rejoins.
    public func setPeerStatusHandler(_ handler: (@Sendable (Bool) -> Void)?) {
        self.peerStatusHandler = handler
    }

    /// Relay errors received after pairing (code, readable message), e.g. `KICKED`.
    public func setTerminalErrorHandler(_ handler: (@Sendable (String, String) -> Void)?) {
        self.terminalErrorHandler = handler
    }

    public var isRelay: Bool { isRelayMode }

    public var isSocketOpen: Bool { webSocketTask != nil }

    /// Round-trips a WebSocket ping; `false` means the socket is dead even if URLSession has not noticed yet.
    public func probeLiveness(timeoutSec: Double = 5.0) async -> Bool {
        guard let task = webSocketTask else { return false }
        if await Self.ping(task, timeoutSec: timeoutSec) {
            lastInboundAt = Date()
            missedPongs = 0
            return true
        }
        return false
    }

    /// Cancels the socket so the receive loop reports the loss through `connectionLostHandler`.
    public func dropDeadConnection() {
        webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
    }

    private static func ping(_ task: URLSessionWebSocketTask, timeoutSec: Double) async -> Bool {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func claim() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if done { return false }
                done = true
                return true
            }
        }
        let once = Once()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            task.sendPing { error in
                if once.claim() { cont.resume(returning: error == nil) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
                if once.claim() { cont.resume(returning: false) }
            }
        }
    }

    private func startLivenessWatchdog(task: URLSessionWebSocketTask) {
        livenessTask?.cancel()
        lastInboundAt = Date()
        missedPongs = 0
        livenessTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, self.webSocketTask === task else { return }
                let alive = await Self.ping(task, timeoutSec: 8)
                await self.recordLivenessProbe(alive, task: task)
            }
        }
    }

    private func recordLivenessProbe(_ alive: Bool, task: URLSessionWebSocketTask) {
        guard webSocketTask === task else { return }
        if alive {
            missedPongs = 0
            return
        }
        missedPongs += 1
        if missedPongs >= 2, Date().timeIntervalSince(lastInboundAt) > 25 {
            task.cancel(with: .abnormalClosure, reason: nil)
        }
    }

    public func currentBridge() -> RelayBridgeIdentity? {
        activeBridgeIdentity
    }

    // MARK: - Pure Wire Builders (1:1 with ZCode v3.16.3 `She` & `vtt` strict Zod schemas)

    public static func resolveWorkspaceKey(workspacePath: String, workspaceIdentity: String?) -> String {
        if let trimmed = workspaceIdentity?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }
        return workspacePath
    }

    public static func buildRPCFramePayloads(
        vqlPayload: Data,
        identity: RelayBridgeIdentity,
        firstPhysicalSeq: Int,
        messageSeq: Int,
        maxFragmentBytes: Int = 32_768
    ) -> (payloads: [[String: Any]], nextPhysicalSeq: Int) {
        let safeMax = max(1024, maxFragmentBytes)
        let totalBytes = vqlPayload.count
        let fragmentCount = max(1, Int(ceil(Double(totalBytes) / Double(safeMax))))
        let crc = ZCodeVQLCodec.crc32Hex(vqlPayload)

        var out: [[String: Any]] = []
        out.reserveCapacity(fragmentCount)

        for index in 0..<fragmentCount {
            let start = index * safeMax
            let end = min(totalBytes, start + safeMax)
            let slice = vqlPayload.subdata(in: start..<end)
            var frame: [String: Any] = [
                "zcode_type": "rpc-frame",
                "bridgeSessionId": identity.bridgeSessionId,
                "seq": firstPhysicalSeq + index,
                "messageSeq": messageSeq,
                "fragmentIndex": index,
                "fragmentCount": fragmentCount,
                "messageBytes": totalBytes,
                "checksum": [
                    "algorithm": "crc32",
                    "value": crc
                ],
                "dataBase64": slice.base64EncodedString()
            ]
            if let gen = identity.bridgeGeneration {
                frame["bridgeGeneration"] = gen
            }
            if let rec = identity.recoveryId, !rec.isEmpty {
                frame["recoveryId"] = rec
            }
            out.append(frame)
        }

        return (out, firstPhysicalSeq + fragmentCount)
    }

    public static func buildRPCFrameAckPayload(
        identity: RelayBridgeIdentity,
        ackMessageSeq: Int
    ) -> [String: Any] {
        var ack: [String: Any] = [
            "zcode_type": "rpc-frame-ack",
            "bridgeSessionId": identity.bridgeSessionId,
            "ackMessageSeq": ackMessageSeq
        ]
        if let gen = identity.bridgeGeneration {
            ack["bridgeGeneration"] = gen
        }
        if let rec = identity.recoveryId, !rec.isEmpty {
            ack["recoveryId"] = rec
        }
        return ack
    }

    public static func parseWorkspaceSummaries(from rawWorkspaces: [[String: Any]]) -> [RemoteWorkspaceSummary] {
        var summaries: [RemoteWorkspaceSummary] = []
        for ws in rawWorkspaces {
            let path = ((ws["workspacePath"] as? String) ?? (ws["path"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            let rawIdentity = (ws["workspaceIdentity"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = (rawIdentity?.isEmpty == false) ? rawIdentity : nil
            let rawRemoteSession = (ws["remoteSessionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteSessionId = (rawRemoteSession?.isEmpty == false) ? rawRemoteSession : nil
            let key = resolveWorkspaceKey(workspacePath: path, workspaceIdentity: identity)

            let label = ((ws["label"] as? String) ?? (ws["name"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = URL(fileURLWithPath: path).lastPathComponent
            let displayName = !label.isEmpty ? label : (fallbackName.isEmpty ? path : fallbackName)
            let kind = (ws["kind"] as? String) ?? ((identity != nil || remoteSessionId != nil) ? "remote" : "local")
            let connState = (ws["connectionState"] as? String) ?? "connected"
            let branch = (ws["branchName"] as? String) ?? "main"
            let dirty = (ws["isDirty"] as? Bool) ?? false

            var parsedTasks: [RemoteTaskSummary] = []
            if let rawTasks = ws["tasks"] as? [[String: Any]] {
                parsedTasks = rawTasks.compactMap { parseTaskSummary($0, fallbackWorkspacePath: path, fallbackWorkspaceIdentity: identity) }
            }

            summaries.append(
                RemoteWorkspaceSummary(
                    workspaceKey: key,
                    workspacePath: path,
                    workspaceIdentity: identity,
                    remoteSessionId: remoteSessionId,
                    name: displayName,
                    kind: kind,
                    connectionState: connState,
                    branchName: branch,
                    isDirty: dirty,
                    tasks: parsedTasks
                )
            )
        }
        return summaries
    }

    public static func parseTaskSummary(
        _ dict: [String: Any],
        fallbackWorkspacePath: String,
        fallbackWorkspaceIdentity: String? = nil
    ) -> RemoteTaskSummary? {
        guard let tid = ((dict["taskId"] as? String) ?? (dict["id"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !tid.isEmpty else {
            return nil
        }
        let path = ((dict["workspacePath"] as? String) ?? fallbackWorkspacePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawIdentity = ((dict["workspaceIdentity"] as? String) ?? fallbackWorkspaceIdentity)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = (rawIdentity?.isEmpty == false) ? rawIdentity : nil
        let rawTitle = ((dict["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "Untitled task" : rawTitle
        let status = (dict["status"] as? String) ?? "idle"
        let pinned = (dict["pinned"] as? Bool) ?? false
        let archived = (dict["archived"] as? Bool) ?? false
        let unread = (dict["unread"] as? Bool) ?? ((dict["unreadAt"] as? Double) != nil)
        let rawTs = (dict["updatedAt"] as? Double)
            ?? (dict["updatedAt"] as? Int).map(Double.init)
            ?? (dict["createdAt"] as? Double)
            ?? (Date().timeIntervalSince1970 * 1000)
        let updatedDate = Date(timeIntervalSince1970: rawTs > 9_999_999_999 ? rawTs / 1000.0 : rawTs)
        let createdDate: Date? = {
            guard let raw = (dict["createdAt"] as? Double) ?? (dict["createdAt"] as? Int).map(Double.init) else { return nil }
            return Date(timeIntervalSince1970: raw > 9_999_999_999 ? raw / 1000.0 : raw)
        }()
        let pending = dict["pendingInteraction"] as? [String: Any]

        return RemoteTaskSummary(
            id: tid,
            title: title,
            workspacePath: path,
            workspaceIdentity: identity,
            status: status,
            pinned: pinned,
            archived: archived,
            unread: unread,
            updatedAt: updatedDate,
            createdAt: createdDate,
            mode: dict["mode"] as? String,
            model: dict["model"] as? String,
            thoughtLevel: dict["thoughtLevel"] as? String,
            pendingInteractionKind: pending?["kind"] as? String
        )
    }

    // MARK: - Direct Server Probe & Connect

    public func probeServerInfo(host: String, port: Int, useTLS: Bool, token: String?) async throws -> ServerInfoResponse {
        let scheme = useTLS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):\(port)/api/server-info") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ServerInfoResponse.self, from: data)
    }

    public func connectDirectServer(
        wsURLString: String,
        token: String?,
        onPhase: (@Sendable (RelayPairingPhase) -> Void)? = nil
    ) async throws {
        disconnect()
        self.phaseCallback = onPhase
        onPhase?(.connecting)

        guard var components = URLComponents(string: wsURLString) else {
            throw URLError(.badURL)
        }
        if let token, !token.isEmpty {
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "token" }) {
                items.append(URLQueryItem(name: "token", value: token))
            }
            components.queryItems = items
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        self.isRelayMode = false
        self.isInitialized = false
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        try await sendWebSocketPing(task: task)
        startReceiveLoop(task: task, isRelayV2: false)
        onPhase?(.connected)
    }

    // MARK: - Cloud Relay V2/V4 Pairing

    public func connectCloudRelayV2(
        host: String = "zcode.z.ai",
        mid: String,
        sid: String,
        passHash: String,
        relayToken: String?,
        deviceName: String,
        onPhase: (@Sendable (RelayPairingPhase) -> Void)? = nil
    ) async throws {
        disconnect()
        self.phaseCallback = onPhase
        self.currentDeviceSid = sid
        self.currentPassHash = passHash
        self.isRelayMode = true
        self.isInitialized = false

        onPhase?(.connecting)

        let cleanHost = host.isEmpty ? "zcode.z.ai" : host
        guard var components = URLComponents(string: "wss://\(cleanHost)/api/v1/remote/ws2") else {
            throw URLError(.badURL)
        }
        var queryItems: [URLQueryItem] = []
        if !mid.isEmpty {
            queryItems.append(URLQueryItem(name: "mid", value: mid))
        }
        if let relayToken, !relayToken.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: relayToken))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        if let relayToken, !relayToken.isEmpty {
            request.setValue("Bearer \(relayToken)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        startReceiveLoop(task: task, isRelayV2: true)
        onPhase?(.authenticating)

        let authInit: [String: Any] = [
            "type": "auth_init",
            "role": "terminal",
            "device_sid": sid,
            "meta": [
                "platform": "web",
                "version": "3.16.3",
                "name": deviceName.isEmpty ? "iPhone" : String(deviceName.prefix(64))
            ],
            "client_ts": Int(Date().timeIntervalSince1970 * 1000)
        ]
        try await sendJSONEnvelope(authInit, on: task)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.awaitRelayPaired()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 18_000_000_000)
                throw NSError(
                    domain: "ZCodeRelay",
                    code: 408,
                    userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for ZCode Desktop pairing confirmation. Ensure ZCode is open on your computer and Remote Control is enabled."]
                )
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func awaitRelayPaired() async throws {
        if pairingAlreadyMatched {
            return
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            if self.pairingAlreadyMatched {
                cont.resume(returning: ())
                return
            }
            if let old = self.pairingContinuation {
                old.resume(throwing: URLError(.cancelled))
            }
            self.pairingContinuation = cont
        }
    }

    // MARK: - Relay V4 Bootstrap & Workspace Bridge Open

    public func bootstrapRelayWorkspaces(
        preferredWorkspaceKey: String? = nil,
        preferredTaskId: String? = nil
    ) async -> RelayBootstrapSnapshot {
        guard isRelayMode else {
            return RelayBootstrapSnapshot(
                desktopAppVersion: nil,
                workspaces: [],
                activeWorkspaceKey: nil,
                activeTaskId: nil,
                openedBridge: nil
            )
        }

        let reqId = "bootstrap-\(UUID().uuidString.lowercased())"
        let payload: [String: Any] = [
            "zcode_type": "bootstrap-request",
            "terminalClientSessionId": terminalClientSessionId,
            "requestId": reqId
        ]

        guard let resp = try? await sendAppRequest(
            payload: payload,
            requestId: reqId,
            expectedType: "bootstrap-response",
            timeoutSec: 8.0
        ),
              let result = resp["result"] as? [String: Any] else {
            return RelayBootstrapSnapshot(
                desktopAppVersion: nil,
                workspaces: [],
                activeWorkspaceKey: nil,
                activeTaskId: nil,
                openedBridge: nil
            )
        }

        let desktopVersion = result["desktopAppVersion"] as? String
        let rawWorkspaces = (result["workspaces"] as? [[String: Any]]) ?? []
        let summaries = Self.parseWorkspaceSummaries(from: rawWorkspaces)

        let mobileView = result["mobileViewState"] as? [String: Any]
        let initialView = result["initialViewState"] as? [String: Any]
        let resolvedWorkspaceKey = preferredWorkspaceKey
            ?? (mobileView?["activeWorkspaceKey"] as? String)
            ?? (initialView?["activeWorkspaceKey"] as? String)
        let resolvedTaskId = preferredTaskId
            ?? (mobileView?["activeTaskId"] as? String)
            ?? (initialView?["activeTaskId"] as? String)

        let targetWorkspace: RemoteWorkspaceSummary? = {
            if let key = resolvedWorkspaceKey,
               let exact = summaries.first(where: { $0.workspaceKey == key && $0.canBridge }) {
                return exact
            }
            if let firstBridgeable = summaries.first(where: \.canBridge) {
                return firstBridgeable
            }
            return summaries.first
        }()

        var openedBridge: RelayBridgeIdentity?
        if let targetWorkspace, targetWorkspace.canBridge {
            let taskForTarget = (targetWorkspace.workspaceKey == resolvedWorkspaceKey) ? resolvedTaskId : nil
            openedBridge = try? await openWorkspaceBridge(
                workspaceKey: targetWorkspace.workspaceKey,
                taskId: taskForTarget,
                timeoutSec: 6.0
            )
        }

        return RelayBootstrapSnapshot(
            desktopAppVersion: desktopVersion,
            workspaces: summaries,
            activeWorkspaceKey: openedBridge?.workspaceKey ?? targetWorkspace?.workspaceKey ?? resolvedWorkspaceKey,
            activeTaskId: openedBridge?.initialTaskId ?? resolvedTaskId,
            openedBridge: openedBridge
        )
    }

    @discardableResult
    public func openWorkspaceBridge(
        workspaceKey: String,
        taskId: String? = nil,
        timeoutSec: Double = 4.0,
        forceReopen: Bool = false
    ) async throws -> RelayBridgeIdentity {
        if !forceReopen, let current = activeBridgeIdentity, current.workspaceKey == workspaceKey {
            return current
        }

        nextBridgeGeneration += 1
        let generation = nextBridgeGeneration
        let bridgeSessionId = "bridge-\(UUID().uuidString.lowercased())"
        let requestId = "workspace-bridge-\(UUID().uuidString.lowercased())"
        let recoveryId: String? = forceReopen ? "rec-\(UUID().uuidString.lowercased())" : nil

        resetChannelStateForNewBridge()

        var openPayload: [String: Any] = [
            "zcode_type": "workspace-bridge-open",
            "terminalClientSessionId": terminalClientSessionId,
            "requestId": requestId,
            "bridgeSessionId": bridgeSessionId,
            "bridgeGeneration": generation,
            "workspaceKey": workspaceKey
        ]
        if let taskId, !taskId.isEmpty {
            openPayload["taskId"] = taskId
        }
        if let recoveryId {
            openPayload["recoveryId"] = recoveryId
        }

        let resp = try await sendAppRequest(
            payload: openPayload,
            requestId: bridgeSessionId,
            expectedType: "workspace-bridge-ready",
            timeoutSec: timeoutSec
        )

        let identity = Self.parseBridgeIdentity(
            from: resp,
            fallbackBridgeId: bridgeSessionId,
            fallbackGeneration: generation,
            fallbackWorkspaceKey: workspaceKey,
            fallbackRecoveryId: recoveryId
        )
        self.activeBridgeIdentity = identity
        if !isInitialized {
            await waitUntilInitialized(maxWaitSec: 1.5)
        }

        await sendMobileViewStateUpdate(workspaceKey: identity.workspaceKey, taskId: identity.initialTaskId ?? taskId)
        bridgeChangeHandler?(identity)
        return identity
    }

    public func sendMobileViewStateUpdate(workspaceKey: String, taskId: String? = nil) async {
        guard isRelayMode, let task = webSocketTask else { return }
        mobileTaskViewTaskId = taskId
        await sendMobileTaskViewUpdate()
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var viewState: [String: Any] = [
            "activeWorkspaceKey": workspaceKey,
            "updatedAt": nowMs
        ]
        if let taskId, !taskId.isEmpty {
            viewState["activeTaskId"] = taskId
        }
        let payload: [String: Any] = [
            "zcode_type": "mobile-view-state-update",
            "viewState": viewState,
            "deviceInfo": [
                "platform": "ios",
                "version": "3.16.3",
                "name": "ZCode iOS",
                "browserPlatform": "iOS Native SwiftUI",
                "online": true,
                "updatedAt": nowMs
            ]
        ]
        try? await sendJSONEnvelope([
            "type": "data",
            "payload": payload,
            "client_ts": nowMs
        ], on: task)
    }

    /// Answers Desktop's `mobile-task-view-request` (and follows task switches) so it knows which task the phone shows.
    private func sendMobileTaskViewUpdate() async {
        guard isRelayMode, let task = webSocketTask, let epoch = mobileTaskViewEpoch,
              let identity = activeBridgeIdentity else { return }
        mobileTaskViewSeq += 1
        var payload: [String: Any] = [
            "zcode_type": "mobile-task-view-update",
            "epoch": epoch,
            "seq": mobileTaskViewSeq,
            "bridgeSessionId": identity.bridgeSessionId
        ]
        if let gen = identity.bridgeGeneration { payload["bridgeGeneration"] = gen }
        if let taskId = mobileTaskViewTaskId, !taskId.isEmpty, !taskId.hasPrefix("task-") {
            var view: [String: Any] = ["workspacePath": identity.workspacePath, "taskId": taskId]
            if let wsIdentity = identity.workspaceIdentity, !wsIdentity.isEmpty { view["workspaceIdentity"] = wsIdentity }
            payload["view"] = view
        } else {
            payload["view"] = NSNull()
        }
        try? await sendJSONEnvelope([
            "type": "data",
            "payload": payload,
            "client_ts": Int(Date().timeIntervalSince1970 * 1000)
        ], on: task)
    }

    private static func parseBridgeIdentity(
        from payload: [String: Any],
        fallbackBridgeId: String,
        fallbackGeneration: Int?,
        fallbackWorkspaceKey: String,
        fallbackRecoveryId: String? = nil
    ) -> RelayBridgeIdentity {
        let bridgeDict = (payload["bridge"] as? [String: Any]) ?? [:]
        let bridgeId = (bridgeDict["bridgeSessionId"] as? String)
            ?? (payload["bridgeSessionId"] as? String)
            ?? fallbackBridgeId
        let gen: Int?
        if let g = (bridgeDict["bridgeGeneration"] as? Int) ?? (bridgeDict["bridgeGeneration"] as? NSNumber)?.intValue {
            gen = g
        } else if let g = (payload["bridgeGeneration"] as? Int) ?? (payload["bridgeGeneration"] as? NSNumber)?.intValue {
            gen = g
        } else {
            gen = fallbackGeneration
        }
        let recoveryId = (bridgeDict["recoveryId"] as? String) ?? (payload["recoveryId"] as? String) ?? fallbackRecoveryId
        let wsKey = (bridgeDict["workspaceKey"] as? String) ?? fallbackWorkspaceKey
        let wsPath = (bridgeDict["workspacePath"] as? String) ?? wsKey
        let wsIdentity = bridgeDict["workspaceIdentity"] as? String
        let remoteSessionId = bridgeDict["remoteSessionId"] as? String
        let kind = (bridgeDict["kind"] as? String) ?? "local"
        let initialTaskId = bridgeDict["initialTaskId"] as? String

        return RelayBridgeIdentity(
            bridgeSessionId: bridgeId,
            bridgeGeneration: gen,
            recoveryId: recoveryId,
            workspaceKey: wsKey,
            workspacePath: wsPath,
            workspaceIdentity: wsIdentity,
            remoteSessionId: remoteSessionId,
            kind: kind,
            initialTaskId: initialTaskId
        )
    }

    private func markMessageDelivered(_ seq: Int) {
        deliveredMessageSeqs.insert(seq)
        while deliveredMessageSeqs.remove(deliveredMessageSeqFloor + 1) != nil {
            deliveredMessageSeqFloor += 1
        }
        if deliveredMessageSeqs.count > 512, let lowest = deliveredMessageSeqs.min() {
            deliveredMessageSeqFloor = lowest
            deliveredMessageSeqs.remove(lowest)
        }
    }

    private func resetChannelStateForNewBridge() {
        isInitialized = false
        nextPhysicalSeq = 1
        nextMessageSeq = 1
        fragmentBuffers.removeAll()
        deliveredMessageSeqFloor = 0
        deliveredMessageSeqs.removeAll()
        eventHandlers.removeAll()
        let oldReplies = pendingReplies
        pendingReplies.removeAll()
        for (_, cont) in oldReplies {
            cont.resume(throwing: URLError(.cancelled))
        }
    }

    private func sendAppRequest(
        payload: [String: Any],
        requestId: String,
        expectedType: String,
        timeoutSec: Double = 5.0
    ) async throws -> [String: Any] {
        guard let task = webSocketTask else {
            throw URLError(.notConnectedToInternet)
        }
        let waitKey = "\(expectedType):\(requestId)"
        let envelope: [String: Any] = [
            "type": "data",
            "payload": payload,
            "client_ts": Int(Date().timeIntervalSince1970 * 1000)
        ]

        return try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any], Error>) in
                    Task {
                        await self.registerAppContinuation(key: waitKey, continuation: cont)
                        do {
                            try await self.sendJSONEnvelope(envelope, on: task)
                        } catch {
                            await self.failAppRequest(key: waitKey, error: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
                await self.removeAppRequest(key: waitKey)
                throw URLError(.timedOut)
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func registerAppContinuation(key: String, continuation: CheckedContinuation<[String: Any], Error>) {
        pendingAppRequests[key] = continuation
    }

    private func removeAppRequest(key: String) {
        pendingAppRequests.removeValue(forKey: key)
    }

    private func failAppRequest(key: String, error: Error) {
        if let cont = pendingAppRequests.removeValue(forKey: key) {
            cont.resume(throwing: error)
        }
    }

    // MARK: - VQL Channel RPC Calls & Subscriptions

    public func call(
        channel: String,
        method: String,
        args: [VQLValue] = [],
        timeoutSec: Double = 6.0
    ) async throws -> VQLValue {
        guard webSocketTask != nil else {
            throw URLError(.notConnectedToInternet)
        }
        if isRelayMode, activeBridgeIdentity == nil {
            throw NSError(
                domain: "ZCodeRPC",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No active ZCode Desktop workspace bridge is open."]
            )
        }

        if !isInitialized {
            await waitUntilInitialized(maxWaitSec: min(0.6, timeoutSec * 0.3))
        }

        guard let task = webSocketTask else {
            throw URLError(.notConnectedToInternet)
        }

        let reqId = nextRequestId
        nextRequestId += 1
        let rawPayload = ZCodeVQLCodec.buildRawRPCRequestPayload(
            id: reqId,
            channel: channel,
            method: method,
            args: args
        )

        return try await withThrowingTaskGroup(of: VQLValue.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<VQLValue, Error>) in
                    Task {
                        await self.registerReplyContinuation(id: reqId, continuation: continuation)
                        do {
                            try await self.sendChannelPayload(rawPayload, on: task)
                        } catch {
                            await self.failRequest(id: reqId, error: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
                await self.timeoutRequest(id: reqId)
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    public func listen(
        channel: String,
        event: String,
        arg: VQLValue = .undefined,
        onEvent: @escaping @Sendable (VQLValue) -> Void
    ) async throws -> Int32 {
        guard let task = webSocketTask else {
            throw URLError(.notConnectedToInternet)
        }
        if isRelayMode, activeBridgeIdentity == nil {
            throw URLError(.notConnectedToInternet)
        }
        if !isInitialized {
            await waitUntilInitialized(maxWaitSec: 0.6)
        }
        let subId = nextRequestId
        nextRequestId += 1
        eventHandlers[subId] = onEvent
        let rawPayload = ZCodeVQLCodec.buildRawRPCEventListenPayload(
            id: subId,
            channel: channel,
            event: event,
            arg: arg
        )
        try await sendChannelPayload(rawPayload, on: task)
        return subId
    }

    public func unlisten(_ subId: Int32) async {
        guard eventHandlers.removeValue(forKey: subId) != nil, let task = webSocketTask else { return }
        if isRelayMode, activeBridgeIdentity == nil { return }
        try? await sendChannelPayload(ZCodeVQLCodec.buildRawRPCEventDisposePayload(id: subId), on: task)
    }

    private func waitUntilInitialized(maxWaitSec: Double) async {
        if isInitialized { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.awaitInitializeSignal()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(maxWaitSec * 1_000_000_000))
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func awaitInitializeSignal() async {
        if isInitialized { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if self.isInitialized {
                cont.resume()
            } else {
                self.initWaiters.append(cont)
            }
        }
    }

    private func markChannelInitialized() {
        isInitialized = true
        let waiters = initWaiters
        initWaiters.removeAll()
        for w in waiters {
            w.resume()
        }
    }

    private func registerReplyContinuation(id: Int32, continuation: CheckedContinuation<VQLValue, Error>) {
        pendingReplies[id] = continuation
    }

    private func timeoutRequest(id: Int32) {
        pendingReplies.removeValue(forKey: id)
    }

    private func sendChannelPayload(_ rawVQL: Data, on task: URLSessionWebSocketTask) async throws {
        if isRelayMode {
            guard let identity = activeBridgeIdentity else {
                throw URLError(.notConnectedToInternet)
            }
            let msgSeq = nextMessageSeq
            nextMessageSeq += 1
            let built = Self.buildRPCFramePayloads(
                vqlPayload: rawVQL,
                identity: identity,
                firstPhysicalSeq: nextPhysicalSeq,
                messageSeq: msgSeq
            )
            nextPhysicalSeq = built.nextPhysicalSeq

            for framePayload in built.payloads {
                let envelope: [String: Any] = [
                    "type": "data",
                    "payload": framePayload,
                    "client_ts": Int(Date().timeIntervalSince1970 * 1000)
                ]
                try await sendJSONEnvelope(envelope, on: task)
            }
        } else {
            let socketFrame = ZCodeVQLCodec.wrapSocketFrame(payload: rawVQL)
            try await task.send(.data(socketFrame))
        }
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        livenessTask?.cancel()
        livenessTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isInitialized = false
        pairingAlreadyMatched = false
        activeBridgeIdentity = nil

        let waiters = initWaiters
        initWaiters.removeAll()
        for w in waiters {
            w.resume()
        }

        if let pairCont = pairingContinuation {
            pairingContinuation = nil
            pairCont.resume(throwing: URLError(.cancelled))
        }
        let appReqs = pendingAppRequests
        pendingAppRequests.removeAll()
        for (_, cont) in appReqs {
            cont.resume(throwing: URLError(.cancelled))
        }
        let replies = pendingReplies
        pendingReplies.removeAll()
        for (_, cont) in replies {
            cont.resume(throwing: URLError(.cancelled))
        }
        eventHandlers.removeAll()
        fragmentBuffers.removeAll()
    }

    private func failRequest(id: Int32, error: Error) {
        if let cont = pendingReplies.removeValue(forKey: id) {
            cont.resume(throwing: error)
        }
    }

    private func sendWebSocketPing(task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    private func sendJSONEnvelope(_ object: [String: Any], on task: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        try await task.send(.string(text))
    }

    private func startRelayHeartbeat(task: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                let query: [String: Any] = [
                    "type": "pair_status_query",
                    "client_ts": Int(Date().timeIntervalSince1970 * 1000)
                ]
                try? await self.sendJSONEnvelope(query, on: task)
            }
        }
    }

    private func startReceiveLoop(task: URLSessionWebSocketTask, isRelayV2: Bool) {
        receiveTask?.cancel()
        peerOffline = false
        startLivenessWatchdog(task: task)
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    self.lastInboundAt = Date()
                    switch message {
                    case .data(let raw):
                        if isRelayV2, let text = String(data: raw, encoding: .utf8), text.first == "{" {
                            await handleRelayTextEnvelope(text, task: task)
                        } else {
                            handleDirectSocketData(raw)
                        }
                    case .string(let text):
                        if isRelayV2 {
                            await handleRelayTextEnvelope(text, task: task)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if let pairCont = self.pairingContinuation {
                        self.pairingContinuation = nil
                        pairCont.resume(throwing: error)
                    }
                    if !Task.isCancelled {
                        self.handleSocketClosed(error)
                    }
                    break
                }
            }
        }
    }

    private func handleSocketClosed(_ error: Error) {
        let wasPaired = pairingAlreadyMatched || !isRelayMode
        livenessTask?.cancel()
        livenessTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        webSocketTask = nil
        pairingAlreadyMatched = false
        activeBridgeIdentity = nil
        isInitialized = false
        let replies = pendingReplies
        pendingReplies.removeAll()
        for (_, cont) in replies {
            cont.resume(throwing: error)
        }
        eventHandlers.removeAll()
        if wasPaired {
            connectionLostHandler?(error.localizedDescription)
        }
    }

    private func handleDirectSocketData(_ raw: Data) {
        var cursor = 0
        while cursor + 13 <= raw.count {
            let slice = raw.subdata(in: cursor..<raw.count)
            guard let unwrapped = try? ZCodeVQLCodec.unwrapSocketFrame(slice) else { break }
            cursor += 13 + unwrapped.payload.count
            if unwrapped.type == 1 && !unwrapped.payload.isEmpty {
                handleRawVQLChannelMessage(unwrapped.payload)
            }
        }
    }

    public func handleIncomingVQLMessageForTesting(_ rawPayload: Data) {
        handleRawVQLChannelMessage(rawPayload)
    }

    private func handleRawVQLChannelMessage(_ rawPayload: Data) {
        var offset = 0
        guard let header = try? ZCodeVQLCodec.decode(from: rawPayload, offset: &offset),
              case .array(let headerItems) = header,
              let first = headerItems.first,
              case .int32(let responseType) = first else {
            return
        }
        let body = (offset < rawPayload.count)
            ? ((try? ZCodeVQLCodec.decode(from: rawPayload, offset: &offset)) ?? .undefined)
            : .undefined

        switch responseType {
        case 200: // Initialize
            markChannelInitialized()
        case 201: // PromiseSuccess
            if headerItems.count >= 2, case .int32(let reqId) = headerItems[1],
               let cont = pendingReplies.removeValue(forKey: reqId) {
                cont.resume(returning: body)
            }
        case 202, 203, 205: // PromiseError / PromiseErrorObj
            if headerItems.count >= 2, case .int32(let reqId) = headerItems[1],
               let cont = pendingReplies.removeValue(forKey: reqId) {
                let errMsg = body.decodeJSONDictionary()?["message"] as? String ?? "RPC Error"
                cont.resume(throwing: NSError(domain: "ZCodeRPC", code: Int(responseType), userInfo: [NSLocalizedDescriptionKey: errMsg]))
            }
        case 204: // EventFire
            if headerItems.count >= 2, case .int32(let subId) = headerItems[1],
               let handler = eventHandlers[subId] {
                handler(body)
            }
        default:
            break
        }
    }

    private func handleRelayTextEnvelope(_ text: String, task: URLSessionWebSocketTask) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "auth_challenge":
            if let nonce = json["nonce"] as? String {
                let proof = ZaiAuthAndRemoteService.calculateChallengeProof(
                    passHash: currentPassHash,
                    nonce: nonce,
                    role: "terminal",
                    deviceSid: currentDeviceSid
                )
                let resp: [String: Any] = [
                    "type": "auth_response",
                    "device_sid": currentDeviceSid,
                    "proof": proof,
                    "client_ts": Int(Date().timeIntervalSince1970 * 1000)
                ]
                try? await sendJSONEnvelope(resp, on: task)
            }

        case "auth_ack", "pair_status_ack", "pair_status":
            let pairStatus = (json["pair_status"] as? String) ?? (json["status"] as? String) ?? ""
            if pairStatus == "waiting" {
                if pairingAlreadyMatched {
                    if !peerOffline {
                        peerOffline = true
                        activeBridgeIdentity = nil
                        peerStatusHandler?(false)
                    }
                    if heartbeatTask == nil { startRelayHeartbeat(task: task) }
                    return
                }
                phaseCallback?(.waitingPairing)
                startRelayHeartbeat(task: task)
            } else if pairStatus == "matched" {
                if pairingAlreadyMatched {
                    if peerOffline {
                        peerOffline = false
                        peerStatusHandler?(true)
                    }
                    return
                }
                pairingAlreadyMatched = true
                phaseCallback?(.pairedSyncing)
                startRelayHeartbeat(task: task)
                if let cont = pairingContinuation {
                    pairingContinuation = nil
                    cont.resume(returning: ())
                }
            }

        case "error":
            let code = (json["code"] as? String) ?? "RELAY_ERROR"
            let rawMsg = (json["message"] as? String) ?? ""
            let readable: String
            switch code {
            case "DEVICE_OFFLINE":
                readable = "Target ZCode computer is currently offline. Keep ZCode open on your computer and try again."
            case "AUTH_FAILED":
                readable = "Remote authentication failed. Sign in with the same Z.AI account as your computer or scan a fresh QR code."
            case "WRONG_PARAM":
                readable = "Invalid or expired ZCode Remote URL parameters."
            case "KICKED":
                readable = "Another remote controller took over this ZCode session."
            default:
                readable = rawMsg.isEmpty ? "Relay error (\(code))." : rawMsg
            }
            if pairingAlreadyMatched {
                terminalErrorHandler?(code, readable)
                return
            }
            phaseCallback?(.failed(readable))
            if let cont = pairingContinuation {
                pairingContinuation = nil
                cont.resume(throwing: NSError(domain: "ZCodeRelay", code: 400, userInfo: [NSLocalizedDescriptionKey: readable]))
            }

        case "data":
            guard let payload = json["payload"] as? [String: Any],
                  let zcodeType = payload["zcode_type"] as? String else {
                return
            }

            if zcodeType == "rpc-frame-ack" {
                return
            }

            if zcodeType == "rpc-frame" {
                guard let identity = activeBridgeIdentity,
                      identity.matchesTransportPayload(payload) else {
                    return
                }
                guard let messageSeq = (payload["messageSeq"] as? Int) ?? (payload["messageSeq"] as? NSNumber)?.intValue,
                      let fragmentIndex = (payload["fragmentIndex"] as? Int) ?? (payload["fragmentIndex"] as? NSNumber)?.intValue,
                      let fragmentCount = (payload["fragmentCount"] as? Int) ?? (payload["fragmentCount"] as? NSNumber)?.intValue,
                      let b64 = payload["dataBase64"] as? String,
                      let chunk = Data(base64Encoded: b64) else {
                    return
                }

                if messageSeq <= deliveredMessageSeqFloor || deliveredMessageSeqs.contains(messageSeq) {
                    if fragmentIndex == fragmentCount - 1 {
                        try? await sendJSONEnvelope([
                            "type": "data",
                            "payload": Self.buildRPCFrameAckPayload(identity: identity, ackMessageSeq: messageSeq),
                            "client_ts": Int(Date().timeIntervalSince1970 * 1000)
                        ], on: task)
                    }
                    return
                }

                var map = fragmentBuffers[messageSeq, default: [:]]
                map[fragmentIndex] = chunk
                fragmentBuffers[messageSeq] = map

                if map.count == fragmentCount {
                    fragmentBuffers.removeValue(forKey: messageSeq)
                    var assembled = Data()
                    for idx in 0..<fragmentCount {
                        if let part = map[idx] { assembled.append(part) }
                    }
                    if let expectedBytes = (payload["messageBytes"] as? Int) ?? (payload["messageBytes"] as? NSNumber)?.intValue,
                       assembled.count != expectedBytes {
                        return
                    }
                    if let checksum = payload["checksum"] as? [String: Any],
                       let expected = checksum["value"] as? String {
                        guard ZCodeVQLCodec.crc32Hex(assembled) == expected.lowercased() else { return }
                    }

                    let ackPayload = Self.buildRPCFrameAckPayload(
                        identity: identity,
                        ackMessageSeq: messageSeq
                    )
                    try? await sendJSONEnvelope([
                        "type": "data",
                        "payload": ackPayload,
                        "client_ts": Int(Date().timeIntervalSince1970 * 1000)
                    ], on: task)

                    markMessageDelivered(messageSeq)
                    handleRawVQLChannelMessage(assembled)
                }
                return
            }

            if zcodeType == "mobile-task-view-request" {
                if let epoch = payload["epoch"] as? String {
                    if epoch != mobileTaskViewEpoch { mobileTaskViewSeq = 0 }
                    mobileTaskViewEpoch = epoch
                    await sendMobileTaskViewUpdate()
                }
                return
            }

            if zcodeType == "workspace-list-updated",
               let result = payload["result"] as? [String: Any] {
                let rawWs = (result["workspaces"] as? [[String: Any]]) ?? []
                let list = Self.parseWorkspaceSummaries(from: rawWs)
                let activeKey = result["activeWorkspaceKey"] as? String
                let activeTask = result["activeTaskId"] as? String
                workspaceListUpdateHandler?(list, activeKey, activeTask)
                return
            }

            if zcodeType == "bridge-degraded" {
                if let identity = activeBridgeIdentity, identity.matchesTransportPayload(payload) {
                    let reason = (payload["reason"] as? String) ?? "rpc-transport-fault"
                    if reason == "terminal-owner-ended" {
                        activeBridgeIdentity = nil
                        bootstrapRequiredHandler?()
                    } else {
                        bridgeDegradedHandler?(reason)
                    }
                }
                return
            }

            if zcodeType == "app-error" || zcodeType == "workspace-bridge-error" {
                let errMsg = (payload["error"] as? String) ?? (payload["reason"] as? String) ?? "Remote bridge error"
                let err = NSError(domain: "ZCodeRelay", code: 422, userInfo: [NSLocalizedDescriptionKey: errMsg])
                let needsBootstrap = errMsg.localizedCaseInsensitiveContains("bootstrap is required")
                if needsBootstrap { activeBridgeIdentity = nil }
                defer { if needsBootstrap { bootstrapRequiredHandler?() } }
                if let reqId = payload["requestId"] as? String {
                    for (key, cont) in pendingAppRequests where key.hasSuffix(":\(reqId)") {
                        pendingAppRequests.removeValue(forKey: key)
                        cont.resume(throwing: err)
                        return
                    }
                }
                if let bridgeId = payload["bridgeSessionId"] as? String {
                    for (key, cont) in pendingAppRequests where key.hasSuffix(":\(bridgeId)") {
                        pendingAppRequests.removeValue(forKey: key)
                        cont.resume(throwing: err)
                        return
                    }
                }
                return
            }

            // Set bridge identity synchronously BEFORE resuming continuation so back-to-back `[200]` Initialize frames are accepted immediately.
            if zcodeType == "workspace-bridge-ready",
               let bridgeId = payload["bridgeSessionId"] as? String {
                let parsedIdentity = Self.parseBridgeIdentity(
                    from: payload,
                    fallbackBridgeId: bridgeId,
                    fallbackGeneration: nextBridgeGeneration,
                    fallbackWorkspaceKey: ""
                )
                self.activeBridgeIdentity = parsedIdentity
                if let cont = pendingAppRequests.removeValue(forKey: "\(zcodeType):\(bridgeId)") {
                    cont.resume(returning: payload)
                    return
                }
            }

            if let reqId = payload["requestId"] as? String,
               let cont = pendingAppRequests.removeValue(forKey: "\(zcodeType):\(reqId)") {
                cont.resume(returning: payload)
                return
            }

        default:
            break
        }
    }
}
