import Foundation

/// One `controller/tasks-index` row's live part (`activity` + `sourceAvailability`).
struct ControllerTaskActivity: Equatable {
    var phase: String
    var lastActivityAt: Double
    var hasBackgroundWork: Bool
    var permissionCount: Int
    var userInputCount: Int
}

/// Bookkeeping for the `window-controller` tasks-index subscription (`dit` / `windowControllerTaskListRegistry`).
final class ControllerTaskIndexState {
    var frameSubId: Int32?
    var subscriptionId: String?
    var subscribing = false
    var logEpoch: String?
    var seq: Int = 0
    var staged: [[String: Any]] = []
    /// taskId -> activity, only for rows whose source is online and which carry an activity.
    var activities: [String: ControllerTaskActivity] = [:]
    var registeredScopesSignature = ""
    var resyncInFlight = false

    func reset() {
        frameSubId = nil
        subscriptionId = nil
        subscribing = false
        logEpoch = nil
        seq = 0
        staged.removeAll()
        registeredScopesSignature = ""
        resyncInFlight = false
    }
}

extension AppStore {
    static let controllerTasksTopic = "controller/tasks-index"

    /// Desktop's sidebar reads every task's live activity from the window controller, across all workspaces
    /// (`readActivities()` -> `__zcodeSessionActivity`), not only the bridged workspace's sessions index.
    func subscribeControllerTaskIndex() async {
        guard !isUITestSeededMode else { return }
        let state = liveSync.controller
        guard state.frameSubId == nil, !state.subscribing else {
            await registerControllerSources()
            return
        }
        state.subscribing = true
        defer { state.subscribing = false }
        guard let subId = try? await rpcClient.listen(
            channel: "window-controller",
            event: "onDynamicControllerFrame",
            onEvent: { [weak self] value in
                Task { @MainActor in
                    guard let frame = value.decodeJSONValue() as? [String: Any] else { return }
                    self?.handleControllerFrame(frame)
                }
            }
        ) else { return }
        state.frameSubId = subId
        await registerControllerSources()
        guard let value = try? await rpcClient.call(
            channel: "window-controller",
            method: "subscribeControllerV4",
            args: [.fromJSONObject(["topic": Self.controllerTasksTopic, "visibility": "foreground"])],
            timeoutSec: 20
        ), let dict = value.decodeJSONDictionary(),
              let subscriptionId = ((dict["ack"] as? [String: Any]) ?? dict)["subscriptionId"] as? String else {
            await rpcClient.unlisten(subId)
            state.frameSubId = nil
            state.staged.removeAll()
            return
        }
        state.subscriptionId = subscriptionId
        let staged = state.staged
        state.staged.removeAll()
        for frame in staged where (frame["subscriptionId"] as? String) == subscriptionId {
            handleControllerFrame(frame)
        }
    }

    /// The controller only projects workspaces it was asked to list (`listTaskList` registers each scope as a source).
    func registerControllerSources() async {
        guard !isUITestSeededMode else { return }
        var seen = Set<String>()
        var scopes: [[String: Any]] = []
        for session in AppStore.sortedForTimeline(sessions.filter { !$0.archived && !$0.id.hasPrefix("task-") }) {
            let identity = session.workspaceIdentity ?? workspaceIdentityByPath[session.workspacePath]
            let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: session.workspacePath, workspaceIdentity: identity)
            guard seen.insert(key).inserted else { continue }
            var scope: [String: Any] = ["workspacePath": session.workspacePath]
            if let identity, !identity.isEmpty { scope["workspaceIdentity"] = identity }
            scopes.append(scope)
            if scopes.count >= 80 { break }
        }
        guard !scopes.isEmpty else { return }
        let signature = seen.sorted().joined(separator: "\n")
        let state = liveSync.controller
        guard signature != state.registeredScopesSignature else { return }
        let query: [String: Any] = ["kind": "active", "workspaceScopes": scopes, "sortBy": "updated", "limit": 1]
        guard (try? await rpcClient.call(channel: "window-controller", method: "listTaskList", args: [.fromJSONObject(query)], timeoutSec: 25)) != nil else { return }
        state.registeredScopesSignature = signature
    }

    func handleControllerFrame(_ frame: [String: Any]) {
        guard (frame["topic"] as? String) == Self.controllerTasksTopic else { return }
        let state = liveSync.controller
        guard let subscriptionId = state.subscriptionId else {
            if state.frameSubId != nil { state.staged.append(frame) }
            return
        }
        guard (frame["subscriptionId"] as? String) == subscriptionId,
              let payload = frame["payload"] as? [String: Any] else { return }
        let fromSeq = ZCodeV4.int(frame["fromSeq"]) ?? 0
        let toSeq = ZCodeV4.int(frame["toSeq"]) ?? fromSeq
        let epoch = frame["logEpoch"] as? String
        switch payload["kind"] as? String {
        case "snapshot":
            let tasks = ((payload["snapshot"] as? [String: Any])?["tasks"] as? [[String: Any]]) ?? []
            var next: [String: ControllerTaskActivity] = [:]
            for row in tasks {
                if let (taskId, activity) = Self.controllerActivity(row) { next[taskId] = activity }
            }
            state.activities = next
            state.logEpoch = epoch
            state.seq = toSeq
            state.resyncInFlight = false
        case "deltas":
            guard epoch == state.logEpoch, fromSeq == state.seq else {
                resyncControllerTaskIndex()
                return
            }
            for delta in (payload["deltas"] as? [[String: Any]]) ?? [] {
                switch delta["op"] as? String {
                case "task.upserted":
                    guard let row = delta["task"] as? [String: Any],
                          let taskId = (row["address"] as? [String: Any])?["taskId"] as? String else { continue }
                    state.activities[taskId] = Self.controllerActivity(row)?.1
                case "task.removed":
                    if let taskId = (delta["address"] as? [String: Any])?["taskId"] as? String {
                        state.activities[taskId] = nil
                    }
                default:
                    break
                }
            }
            state.seq = toSeq
        default:
            return
        }
        applyControllerActivities()
    }

    private func resyncControllerTaskIndex() {
        let state = liveSync.controller
        guard let subscriptionId = state.subscriptionId, !state.resyncInFlight else { return }
        state.resyncInFlight = true
        var arg: [String: Any] = ["subscriptionId": subscriptionId, "forceSnapshot": true]
        if let epoch = state.logEpoch { arg["base"] = ["logEpoch": epoch, "seq": state.seq] }
        let client = rpcClient
        Task { @MainActor in
            if (try? await client.call(channel: "window-controller", method: "resyncControllerV4", args: [.fromJSONObject(arg)], timeoutSec: 20)) == nil {
                state.resyncInFlight = false
            }
        }
    }

    static func controllerActivity(_ row: [String: Any]) -> (String, ControllerTaskActivity)? {
        guard let taskId = (row["address"] as? [String: Any])?["taskId"] as? String,
              (row["sourceAvailability"] as? String) == "online",
              let activity = row["activity"] as? [String: Any],
              let phase = activity["phase"] as? String else { return nil }
        let pending = activity["pendingInteractions"] as? [String: Any]
        return (taskId, ControllerTaskActivity(
            phase: phase,
            lastActivityAt: ZCodeV4.double(activity["lastActivityAt"]) ?? 0,
            hasBackgroundWork: (activity["hasBackgroundWork"] as? Bool) ?? false,
            permissionCount: Int(ZCodeV4.double(pending?["permissionCount"]) ?? 0),
            userInputCount: Int(ZCodeV4.double(pending?["userInputCount"]) ?? 0)
        ))
    }

    /// Overlays controller activity onto sessions (`mO`): phase drives the sidebar indicator, `lastActivityAt` the age.
    func applyControllerActivities() {
        let activities = liveSync.controller.activities
        guard liveSync.controller.subscriptionId != nil else { return }
        var next = sessions
        var changed = false
        for idx in next.indices {
            let id = next[idx].id
            guard !id.hasPrefix("task-") else { continue }
            var session = next[idx]
            if let activity = activities[id] {
                Self.applyActivity(phase: activity.phase,
                                   hasBackgroundWork: activity.hasBackgroundWork,
                                   permissionCount: activity.permissionCount,
                                   userInputCount: activity.userInputCount,
                                   lastActivityAt: activity.lastActivityAt,
                                   ownsStatus: v4Owns(id),
                                   to: &session)
            } else if session.activityPhase != nil {
                session.activityPhase = nil
                session.hasBackgroundWork = false
                if !v4Owns(id), session.status == .running { session.status = .idle }
            }
            if session != next[idx] {
                next[idx] = session
                changed = true
            }
        }
        if changed { sessions = next }
    }

    /// `zV`: at most two units of d/h/m/s, seconds rounded and at least 1s ("Working for 2m 5s").
    static func workDurationText(milliseconds: Double) -> String {
        let total = max(1, Int((milliseconds / 1000).rounded()))
        let parts = [(total / 86_400, "d"), (total % 86_400 / 3600, "h"), (total % 3600 / 60, "m")]
            .filter { $0.0 > 0 }
            .map { "\($0.0)\($0.1)" }
        let seconds = total % 60
        let all = parts + ((seconds > 0 || parts.isEmpty) ? ["\(seconds)s"] : [])
        return all.prefix(2).joined(separator: " ")
    }

    /// Start of the running turn: the newest user prompt in the conversation.
    static func runningTurnStart(_ session: AgentTaskSession) -> Date? {
        session.messages.last(where: { $0.role == "user" })?.timestamp
    }

    /// Shared by the controller tasks index and the per-workspace sessions index (same `Jae` activity shape).
    static func applyActivity(phase: String, hasBackgroundWork: Bool, permissionCount: Int, userInputCount: Int,
                              lastActivityAt: Double, ownsStatus: Bool, to session: inout AgentTaskSession) {
        session.activityPhase = phase
        session.hasBackgroundWork = hasBackgroundWork
        session.pendingInteractionCount = permissionCount + userInputCount
        session.pendingInteractionIsUserInput = userInputCount > 0
        if lastActivityAt > 0 {
            let date = Date(timeIntervalSince1970: lastActivityAt / 1000)
            if date > session.updatedAt { session.updatedAt = date }
        }
        guard !ownsStatus else { return }
        session.status = {
            if permissionCount > 0 { return .waitingApproval }
            if userInputCount > 0 { return .waitingQuestion }
            switch phase {
            case "running", "prewarming": return .running
            case "error": return .error
            case "completedSuccess": return .completed
            default: return .idle
            }
        }()
    }
}
