import Foundation

public struct ServerInfoResponse: Codable {
    public let serverId: String?
    public let version: String
    public let protocolVersion: Int?
    public let authRequired: Bool?
}

public struct RemoteWorkspaceSummary: Equatable {
    public let workspaceKey: String
    public let workspacePath: String
    public let name: String
    public let branchName: String
    public let isDirty: Bool
    public let tasks: [RemoteTaskSummary]
}

public struct RemoteTaskSummary: Equatable {
    public let id: String
    public let title: String
    public let workspacePath: String
    public let status: String
    public let pinned: Bool
    public let updatedAt: Date
}

/// Native URLSessionWebSocketTask client implementing both:
/// 1. Direct ZCode Server binary RPC (`SocketProtocol` + `VQL` over `/ws`)
/// 2. Official Z.AI Remote Relay V2/V4 (`wss://zcode.z.ai/api/v1/remote/ws2` with `role: "terminal"`,
///    `auth_challenge` HMAC-SHA256 proof, `pair_status`, `bootstrap-request`, `workspace-bridge-open`, and CRC32 `rpc-frame`)
public actor ZCodeRPCClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var nextRequestId: Int32 = 1
    private var nextOutboundSeq: Int = 1
    private var isInitialized = false
    private var isRelayMode = false
    private var activeBridgeSessionId: String?

    private var pendingReplies: [Int32: CheckedContinuation<VQLValue, Error>] = [:]
    private var pendingAppRequests: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var pairingContinuation: CheckedContinuation<Void, Error>?
    private var phaseCallback: (@Sendable (RelayPairingPhase) -> Void)?
    private var eventHandlers: [Int32: @Sendable (VQLValue) -> Void] = [:]
    private var fragmentBuffers: [Int: [Int: Data]] = [:]
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    private var currentDeviceSid: String = ""
    private var currentPassHash: String = ""

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 14
        self.session = URLSession(configuration: config)
    }

    public func probeServerInfo(host: String, port: Int, useTLS: Bool, token: String?) async throws -> ServerInfoResponse {
        let scheme = useTLS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):\(port)/api/server-info") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
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
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        // Verify live WebSocket connectivity with a native ping before declaring connected
        try await sendWebSocketPing(task: task)
        startReceiveLoop(task: task, isRelayV2: false)
        onPhase?(.connected)
    }

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

        try await sendWebSocketPing(task: task)
        onPhase?(.authenticating)

        startReceiveLoop(task: task, isRelayV2: true)

        // Exact `auth_init` handshake from `remote-v4.js` (`X2t`)
        let authInit: [String: Any] = [
            "type": "auth_init",
            "role": "terminal",
            "device_sid": sid,
            "meta": [
                "platform": "web",
                "version": "3.16.3",
                "name": deviceName
            ],
            "client_ts": Int(Date().timeIntervalSince1970 * 1000)
        ]
        try await sendJSONEnvelope(authInit, on: task)

        // Await `pair_status == "matched"` (or explicit relay error / 20s timeout)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.awaitRelayPaired()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                throw NSError(
                    domain: "ZCodeRelay",
                    code: 408,
                    userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for ZCode Desktop pairing confirmation. Ensure ZCode is online on your computer and the Remote URL is active."]
                )
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func awaitRelayPaired() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            if let old = self.pairingContinuation {
                old.resume(throwing: URLError(.cancelled))
            }
            self.pairingContinuation = cont
        }
    }

    // MARK: - Relay V4 Workspace Bootstrap & Bridge Open

    public func bootstrapRelayWorkspaces() async -> [RemoteWorkspaceSummary] {
        guard isRelayMode else { return [] }

        let reqId = "bootstrap-\(UUID().uuidString.lowercased())"
        let payload: [String: Any] = [
            "zcode_type": "bootstrap-request",
            "requestId": reqId
        ]

        guard let resp = try? await sendAppRequest(payload: payload, requestId: reqId, expectedType: "bootstrap-response", timeoutSec: 8),
              let result = resp["result"] as? [String: Any],
              let rawWorkspaces = result["workspaces"] as? [[String: Any]] else {
            return []
        }

        var summaries: [RemoteWorkspaceSummary] = []
        for ws in rawWorkspaces {
            let path = (ws["workspacePath"] as? String) ?? (ws["path"] as? String) ?? ""
            guard !path.isEmpty else { continue }
            let identity = (ws["workspaceIdentity"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = (identity?.isEmpty == false) ? identity! : path
            let folderName = (ws["name"] as? String) ?? URL(fileURLWithPath: path).lastPathComponent
            let branch = (ws["branchName"] as? String) ?? "main"
            let dirty = (ws["isDirty"] as? Bool) ?? false

            var parsedTasks: [RemoteTaskSummary] = []
            if let rawTasks = ws["tasks"] as? [[String: Any]] {
                for t in rawTasks {
                    guard let tid = (t["taskId"] as? String) ?? (t["id"] as? String) else { continue }
                    let title = (t["title"] as? String) ?? "Untitled task"
                    let status = (t["status"] as? String) ?? "idle"
                    let pinned = (t["pinned"] as? Bool) ?? false
                    let updatedMs = (t["updatedAt"] as? Double) ?? (Date().timeIntervalSince1970 * 1000)
                    parsedTasks.append(
                        RemoteTaskSummary(
                            id: tid,
                            title: title,
                            workspacePath: path,
                            status: status,
                            pinned: pinned,
                            updatedAt: Date(timeIntervalSince1970: updatedMs > 9_999_999_999 ? updatedMs / 1000.0 : updatedMs)
                        )
                    )
                }
            }

            summaries.append(
                RemoteWorkspaceSummary(
                    workspaceKey: key,
                    workspacePath: path,
                    name: folderName.isEmpty ? path : folderName,
                    branchName: branch,
                    isDirty: dirty,
                    tasks: parsedTasks
                )
            )
        }

        // Open bridge on the primary workspace if available
        if let first = summaries.first {
            let bridgeId = "bridge-\(UUID().uuidString.lowercased())"
            let openReqId = "workspace-bridge-\(UUID().uuidString.lowercased())"
            let openPayload: [String: Any] = [
                "zcode_type": "workspace-bridge-open",
                "requestId": openReqId,
                "bridgeSessionId": bridgeId,
                "bridgeGeneration": 1,
                "workspaceKey": first.workspaceKey
            ]
            if let bridgeResp = try? await sendAppRequest(payload: openPayload, requestId: bridgeId, expectedType: "workspace-bridge-ready", matchField: "bridgeSessionId", timeoutSec: 8),
               let bridgeObj = bridgeResp["bridge"] as? [String: Any],
               let readyId = bridgeObj["bridgeSessionId"] as? String {
                self.activeBridgeSessionId = readyId
            }
        }

        return summaries
    }

    private func sendAppRequest(
        payload: [String: Any],
        requestId: String,
        expectedType: String,
        matchField: String = "requestId",
        timeoutSec: Double = 8
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

    // MARK: - Binary RPC Calls & Subscriptions

    public func call(channel: String, method: String, args: [VQLValue] = []) async throws -> VQLValue {
        guard let task = webSocketTask else {
            throw URLError(.notConnectedToInternet)
        }
        let reqId = nextRequestId
        nextRequestId += 1
        let frame = ZCodeVQLCodec.buildRPCRequestFrame(id: reqId, channel: channel, method: method, args: args)

        return try await withCheckedThrowingContinuation { continuation in
            pendingReplies[reqId] = continuation
            Task {
                do {
                    try await self.sendBinaryRPCFrame(frame, on: task)
                } catch {
                    self.failRequest(id: reqId, error: error)
                }
            }
        }
    }

    public func listen(channel: String, event: String, arg: VQLValue = .undefined, onEvent: @escaping @Sendable (VQLValue) -> Void) async throws -> Int32 {
        guard let task = webSocketTask else {
            throw URLError(.notConnectedToInternet)
        }
        let subId = nextRequestId
        nextRequestId += 1
        eventHandlers[subId] = onEvent
        let frame = ZCodeVQLCodec.buildRPCEventListenFrame(id: subId, channel: channel, event: event, arg: arg)
        try await sendBinaryRPCFrame(frame, on: task)
        return subId
    }

    private func sendBinaryRPCFrame(_ frame: Data, on task: URLSessionWebSocketTask) async throws {
        if isRelayMode {
            let seq = nextOutboundSeq
            nextOutboundSeq += 1
            var payload: [String: Any] = [
                "zcode_type": "rpc-frame",
                "messageSeq": seq,
                "fragmentIndex": 0,
                "fragmentCount": 1,
                "dataBase64": frame.base64EncodedString(),
                "checksum": [
                    "algorithm": "crc32",
                    "value": ZCodeVQLCodec.crc32Hex(frame)
                ]
            ]
            if let bridgeId = activeBridgeSessionId {
                payload["bridgeSessionId"] = bridgeId
            }
            let envelope: [String: Any] = [
                "type": "data",
                "payload": payload,
                "client_ts": Int(Date().timeIntervalSince1970 * 1000)
            ]
            try await sendJSONEnvelope(envelope, on: task)
        } else {
            try await task.send(.data(frame))
        }
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isInitialized = false
        activeBridgeSessionId = nil

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
                try? await Task.sleep(nanoseconds: 15_000_000_000)
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
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .data(let raw):
                        if isRelayV2, let text = String(data: raw, encoding: .utf8), text.first == "{" {
                            await handleRelayTextEnvelope(text, task: task)
                        } else {
                            handleBinarySocketFrame(raw)
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
                    break
                }
            }
        }
    }

    private func handleBinarySocketFrame(_ raw: Data) {
        guard let unwrapped = try? ZCodeVQLCodec.unwrapSocketFrame(raw) else { return }
        var offset = 0
        guard let header = try? ZCodeVQLCodec.decode(from: unwrapped.payload, offset: &offset),
              case .array(let headerItems) = header,
              let first = headerItems.first,
              case .int32(let responseType) = first else {
            return
        }
        let body = (try? ZCodeVQLCodec.decode(from: unwrapped.payload, offset: &offset)) ?? .undefined

        switch responseType {
        case 200: // Initialize
            isInitialized = true
        case 201: // PromiseSuccess
            if headerItems.count >= 2, case .int32(let reqId) = headerItems[1],
               let cont = pendingReplies.removeValue(forKey: reqId) {
                cont.resume(returning: body)
            }
        case 202, 203, 205: // PromiseError
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

        case "auth_ack", "pair_status_ack":
            let pairStatus = (json["pair_status"] as? String) ?? ""
            if pairStatus == "waiting" {
                phaseCallback?(.waitingPairing)
                startRelayHeartbeat(task: task)
            } else if pairStatus == "matched" {
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

            if zcodeType == "rpc-frame",
               let messageSeq = payload["messageSeq"] as? Int,
               let fragmentIndex = payload["fragmentIndex"] as? Int,
               let fragmentCount = payload["fragmentCount"] as? Int,
               let b64 = payload["dataBase64"] as? String,
               let chunk = Data(base64Encoded: b64) {

                var map = fragmentBuffers[messageSeq, default: [:]]
                map[fragmentIndex] = chunk
                fragmentBuffers[messageSeq] = map

                if map.count == fragmentCount {
                    fragmentBuffers.removeValue(forKey: messageSeq)
                    var assembled = Data()
                    for idx in 0..<fragmentCount {
                        if let part = map[idx] { assembled.append(part) }
                    }
                    if let checksum = payload["checksum"] as? [String: Any],
                       let expected = checksum["value"] as? String {
                        guard ZCodeVQLCodec.crc32Hex(assembled) == expected.lowercased() else { return }
                    }
                    // Send `rpc-frame-ack` back over relay
                    var ackPayload: [String: Any] = [
                        "zcode_type": "rpc-frame-ack",
                        "ackMessageSeq": messageSeq
                    ]
                    if let bridgeId = activeBridgeSessionId {
                        ackPayload["bridgeSessionId"] = bridgeId
                    }
                    try? await sendJSONEnvelope([
                        "type": "data",
                        "payload": ackPayload,
                        "client_ts": Int(Date().timeIntervalSince1970 * 1000)
                    ], on: task)

                    handleBinarySocketFrame(assembled)
                }
                return
            }

            // Match app-level responses (`bootstrap-response`, `workspace-list-response`, `workspace-bridge-ready`)
            if let reqId = payload["requestId"] as? String,
               let cont = pendingAppRequests.removeValue(forKey: "\(zcodeType):\(reqId)") {
                cont.resume(returning: payload)
                return
            }
            if let bridgeId = payload["bridgeSessionId"] as? String,
               let cont = pendingAppRequests.removeValue(forKey: "\(zcodeType):\(bridgeId)") {
                cont.resume(returning: payload)
                return
            }

        default:
            break
        }
    }
}
