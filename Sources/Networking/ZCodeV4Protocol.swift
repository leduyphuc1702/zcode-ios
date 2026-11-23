import Foundation

/// Pure (side-effect free) pieces of the ZCode Desktop 3.16.3 V4 conversation protocol:
/// the `wireVersion: 3` topic frame assembler and the snapshot/delta reducers for
/// `conversation/<sessionId>` and `sessions-index/<workspaceKey>` topics.
public enum ZCodeV4 {
    public static let protocolVersion = 3
    public static let assemblyTimeout: TimeInterval = 30
    public static let rowsRangeMaxLimit = 200

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as NSNumber: return v.intValue
        case let v as Double: return Int(v)
        case let v as String: return Int(v)
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let v as Double: return v
        case let v as NSNumber: return v.doubleValue
        case let v as Int: return Double(v)
        default: return nil
        }
    }
}

// MARK: - Wire frame assembler (`TopicWireFrameAssembler`)

public struct V4WireFrameAssembler {
    public enum Output {
        /// A fully assembled logical frame plus its `deliveryKind` ("initial" | "online" | "recovery").
        case frame([String: Any], deliveryKind: String)
        case fault(String)
        case ignored
    }

    struct Pending {
        var logicalFrameId: String
        var ordinal: Int
        var fragmentCount: Int
        var logicalBytes: Int?
        var checksum: String?
        var parts: [Int: Data]
        var startedAt: Date
    }

    private var settledOrdinal: [String: Int] = [:]
    private var pending: [String: Pending] = [:]

    public init() {}

    public mutating func reset(topic: String? = nil) {
        guard let topic else {
            settledOrdinal.removeAll()
            pending.removeAll()
            return
        }
        for key in settledOrdinal.keys where key.hasPrefix(topic + "|") { settledOrdinal[key] = nil }
        for key in pending.keys where key.hasPrefix(topic + "|") { pending[key] = nil }
    }

    /// Drops incomplete assemblies older than the protocol timeout; returns the expired stream keys (`topic|subscriptionId`).
    public mutating func expire(now: Date = Date()) -> [String] {
        let expired = pending.filter { now.timeIntervalSince($0.value.startedAt) > ZCodeV4.assemblyTimeout }.map(\.key)
        for key in expired { pending[key] = nil }
        return expired
    }

    public mutating func ingest(_ envelope: [String: Any], now: Date = Date()) -> Output {
        guard ZCodeV4.int(envelope["wireVersion"]) == ZCodeV4.protocolVersion,
              let topic = envelope["topic"] as? String,
              let subscriptionId = envelope["subscriptionId"] as? String,
              let ordinal = ZCodeV4.int(envelope["logicalFrameOrdinal"]), ordinal >= 1 else {
            return .ignored
        }
        let deliveryKind = (envelope["deliveryKind"] as? String) ?? "online"
        let key = "\(topic)|\(subscriptionId)"
        if let settled = settledOrdinal[key], ordinal <= settled { return .ignored }

        switch envelope["kind"] as? String {
        case "complete":
            guard let frame = Self.frameObject(envelope["frame"]) else {
                return .fault("proto.frameAssemblyInvalidFrame")
            }
            pending[key] = nil
            settledOrdinal[key] = ordinal
            return Self.validated(frame, topic: topic, subscriptionId: subscriptionId, deliveryKind: deliveryKind)

        case "fragment":
            guard let index = ZCodeV4.int(envelope["fragmentIndex"]),
                  let count = ZCodeV4.int(envelope["fragmentCount"]), count >= 1, count <= 1024,
                  index >= 0, index < count,
                  let b64 = envelope["dataBase64"] as? String,
                  let chunk = Data(base64Encoded: b64) else {
                return .fault("proto.frameAssemblyInvalidFragment")
            }
            let frameId = (envelope["logicalFrameId"] as? String) ?? "\(ordinal)"
            var entry = pending[key]
            if let current = entry {
                if ordinal < current.ordinal { return .ignored }
                if ordinal == current.ordinal, current.logicalFrameId != frameId {
                    pending[key] = nil
                    return .fault("proto.frameAssemblyOrdinalConflict")
                }
                if ordinal > current.ordinal { entry = nil }
            }
            var assembly = entry ?? Pending(
                logicalFrameId: frameId,
                ordinal: ordinal,
                fragmentCount: count,
                logicalBytes: ZCodeV4.int(envelope["logicalBytes"]),
                checksum: ((envelope["checksum"] as? [String: Any])?["value"] as? String)?.lowercased(),
                parts: [:],
                startedAt: now
            )
            assembly.parts[index] = chunk
            guard assembly.parts.count == assembly.fragmentCount else {
                pending[key] = assembly
                return .ignored
            }
            pending[key] = nil
            settledOrdinal[key] = ordinal
            var data = Data()
            for i in 0..<assembly.fragmentCount {
                guard let part = assembly.parts[i] else { return .fault("proto.frameAssemblyMissingFragment") }
                data.append(part)
            }
            if let expected = assembly.logicalBytes, expected != data.count {
                return .fault("proto.frameAssemblyLengthMismatch")
            }
            if let expected = assembly.checksum, ZCodeVQLCodec.crc32Hex(data) != expected {
                return .fault("proto.frameAssemblyChecksumMismatch")
            }
            guard let frame = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return .fault("proto.frameAssemblyInvalidFrame")
            }
            return Self.validated(frame, topic: topic, subscriptionId: subscriptionId, deliveryKind: deliveryKind)

        default:
            return .ignored
        }
    }

    private static func frameObject(_ raw: Any?) -> [String: Any]? {
        if let dict = raw as? [String: Any] { return dict }
        if let text = raw as? String, let data = text.data(using: .utf8) {
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return nil
    }

    private static func validated(_ frame: [String: Any], topic: String, subscriptionId: String, deliveryKind: String) -> Output {
        if let frameTopic = frame["topic"] as? String, frameTopic != topic { return .fault("proto.frameAssemblyTopicMismatch") }
        if let frameSub = frame["subscriptionId"] as? String, frameSub != subscriptionId { return .fault("proto.frameAssemblyTopicMismatch") }
        return .frame(frame, deliveryKind: deliveryKind)
    }
}

// MARK: - Conversation reducer

public struct V4ConversationState {
    public enum ApplyResult: Equatable {
        case applied
        case ignored
        /// `fromSeq` does not continue the local `seq`, or deltas arrived before any snapshot.
        case gap
    }

    public let sessionId: String
    public var subscriptionId: String?
    /// Top-level snapshot fields (everything except `rows`).
    public private(set) var state: [String: Any] = [:]
    public private(set) var rows: [[String: Any]] = []
    public private(set) var totalCount = 0
    public private(set) var firstRowId: Int?
    public private(set) var seq = 0
    public private(set) var logEpoch = ""
    public private(set) var hasSnapshot = false

    public init(sessionId: String) {
        self.sessionId = sessionId
    }

    public var topic: String { "conversation/\(sessionId)" }
    public var revision: Int { ZCodeV4.int(state["revision"]) ?? 0 }
    public var base: [String: Any]? { hasSnapshot ? ["logEpoch": logEpoch, "seq": seq] : nil }
    /// True when older rows exist on the host before the local window.
    public var hasOlderRows: Bool {
        guard let firstRowId, let oldest = rows.first.flatMap({ ZCodeV4.int($0["rowId"]) }) else { return false }
        return oldest > firstRowId
    }

    public mutating func apply(frame: [String: Any]) -> ApplyResult {
        guard let payload = frame["payload"] as? [String: Any] else { return .ignored }
        switch payload["kind"] as? String {
        case "snapshot":
            guard let snapshot = payload["snapshot"] as? [String: Any] else { return .ignored }
            replace(snapshot: snapshot)
            if let toSeq = ZCodeV4.int(frame["toSeq"]), toSeq > seq { seq = toSeq }
            return .applied
        case "deltas":
            guard hasSnapshot else { return .gap }
            guard let toSeq = ZCodeV4.int(frame["toSeq"]) else { return .ignored }
            if toSeq <= seq { return .ignored }
            guard ZCodeV4.int(frame["fromSeq"]) == seq else { return .gap }
            for delta in (payload["deltas"] as? [[String: Any]]) ?? [] {
                apply(delta: delta)
            }
            seq = toSeq
            return .applied
        default:
            return .ignored
        }
    }

    public mutating func replace(snapshot: [String: Any]) {
        var top = snapshot
        let rowsObj = top.removeValue(forKey: "rows") as? [String: Any]
        state = top
        rows = (rowsObj?["window"] as? [[String: Any]]) ?? []
        totalCount = ZCodeV4.int(rowsObj?["totalCount"]) ?? rows.count
        firstRowId = ZCodeV4.int(rowsObj?["firstRowId"])
        seq = ZCodeV4.int(snapshot["seq"]) ?? 0
        logEpoch = (snapshot["logEpoch"] as? String) ?? ""
        hasSnapshot = true
    }

    /// Prepends a page from `conversationRowsRangeV4` (only when it belongs to the same `logEpoch`).
    @discardableResult
    public mutating func prepend(olderRows page: [[String: Any]], atLogEpoch: String) -> Bool {
        guard hasSnapshot, atLogEpoch == logEpoch else { return false }
        let oldest = rows.first.flatMap { ZCodeV4.int($0["rowId"]) } ?? Int.max
        let older = page
            .filter { (ZCodeV4.int($0["rowId"]) ?? Int.max) < oldest }
            .sorted { (ZCodeV4.int($0["rowId"]) ?? 0) < (ZCodeV4.int($1["rowId"]) ?? 0) }
        rows.insert(contentsOf: older, at: 0)
        return !older.isEmpty
    }

    mutating func apply(delta: [String: Any]) {
        switch delta["op"] as? String {
        case "row.appended":
            guard let row = delta["row"] as? [String: Any] else { return }
            if let id = ZCodeV4.int(row["rowId"]), let idx = rowIndex(id) {
                rows[idx] = row
            } else {
                rows.append(row)
                totalCount += 1
            }
            if firstRowId == nil, rows.count == 1 { firstRowId = ZCodeV4.int(row["rowId"]) }
        case "row.upserted":
            guard let row = delta["row"] as? [String: Any], let id = ZCodeV4.int(row["rowId"]),
                  let idx = rowIndex(id) else { return }
            rows[idx] = row
        case "row.removed":
            guard let from = ZCodeV4.int(delta["fromRowId"]) else { return }
            let before = rows.count
            rows.removeAll { (ZCodeV4.int($0["rowId"]) ?? 0) >= from }
            if let first = firstRowId, from <= first {
                totalCount = 0
                firstRowId = nil
            } else {
                totalCount = max(0, totalCount - (before - rows.count))
            }
        case "row.delta":
            guard let id = ZCodeV4.int(delta["rowId"]), let idx = rowIndex(id),
                  let path = delta["path"] as? String, let append = delta["append"] as? String else { return }
            var row = rows[idx]
            switch path {
            case "output.text":
                var output = (row["output"] as? [String: Any]) ?? [:]
                output["text"] = ((output["text"] as? String) ?? "") + append
                row["output"] = output
            default:
                row[path] = ((row[path] as? String) ?? "") + append
            }
            rows[idx] = row
        case "state.updated":
            guard let patch = delta["patch"] as? [String: Any] else { return }
            for (key, value) in patch where key != "rows" {
                state[key] = value
            }
        case "workflowRun.updated", "workflowRun.removed":
            applyWorkflowRun(delta)
        default:
            break
        }
    }

    private mutating func applyWorkflowRun(_ delta: [String: Any]) {
        guard let runId = delta["runId"] as? String else { return }
        var container = (state["workflowRuns"] as? [String: Any]) ?? ["revision": 0, "runs": [Any]()]
        var runs = (container["runs"] as? [[String: Any]]) ?? []
        if (delta["op"] as? String) == "workflowRun.removed" {
            runs.removeAll { ($0["runId"] as? String) == runId }
        } else {
            var run = runs.first(where: { ($0["runId"] as? String) == runId }) ?? ["runId": runId]
            if let patch = delta["run"] as? [String: Any] {
                for (key, value) in patch { run[key] = value }
            }
            for key in (delta["cleared"] as? [String]) ?? [] { run[key] = nil }
            if let idx = runs.firstIndex(where: { ($0["runId"] as? String) == runId }) {
                runs[idx] = run
            } else {
                runs.append(run)
            }
        }
        container["runs"] = runs
        if let revision = delta["revision"] { container["revision"] = revision }
        state["workflowRuns"] = container
    }

    private func rowIndex(_ rowId: Int) -> Int? {
        // Rows are appended in rowId order, so search from the tail where streaming happens.
        rows.lastIndex { ZCodeV4.int($0["rowId"]) == rowId }
    }
}

// MARK: - Sessions index reducer

public struct V4SessionsIndexState {
    public let workspaceKey: String
    public var subscriptionId: String?
    public private(set) var sessions: [String: [String: Any]] = [:]
    public private(set) var seq = 0
    public private(set) var logEpoch = ""
    public private(set) var hasSnapshot = false

    public init(workspaceKey: String) {
        self.workspaceKey = workspaceKey
    }

    public var topic: String { "sessions-index/\(workspaceKey)" }
    public var base: [String: Any]? { hasSnapshot ? ["logEpoch": logEpoch, "seq": seq] : nil }

    public mutating func apply(frame: [String: Any]) -> V4ConversationState.ApplyResult {
        guard let payload = frame["payload"] as? [String: Any] else { return .ignored }
        switch payload["kind"] as? String {
        case "snapshot":
            guard let snapshot = payload["snapshot"] as? [String: Any] else { return .ignored }
            var map: [String: [String: Any]] = [:]
            for entry in (snapshot["sessions"] as? [[String: Any]]) ?? [] {
                if let id = entry["sessionId"] as? String { map[id] = entry }
            }
            sessions = map
            logEpoch = (snapshot["logEpoch"] as? String) ?? ""
            seq = ZCodeV4.int(frame["toSeq"]) ?? ZCodeV4.int(snapshot["seq"]) ?? 0
            hasSnapshot = true
            return .applied
        case "deltas":
            guard hasSnapshot else { return .gap }
            guard let toSeq = ZCodeV4.int(frame["toSeq"]) else { return .ignored }
            if toSeq <= seq { return .ignored }
            guard ZCodeV4.int(frame["fromSeq"]) == seq else { return .gap }
            for delta in (payload["deltas"] as? [[String: Any]]) ?? [] {
                switch delta["op"] as? String {
                case "session.upserted":
                    if let entry = delta["session"] as? [String: Any], let id = entry["sessionId"] as? String {
                        sessions[id] = entry
                    }
                case "session.removed":
                    if let id = delta["sessionId"] as? String { sessions[id] = nil }
                default:
                    break
                }
            }
            seq = toSeq
            return .applied
        default:
            return .ignored
        }
    }
}
