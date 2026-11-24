import Foundation

// MARK: - ZCode project tree (`project.readTree`) — the desktop sidebar's data source

extension AppStore {
    /// Loads `{projects, tasks}` exactly like the desktop sidebar loader (`Mdt`). Returns false when the host
    /// can't serve the `project` channel, so callers can fall back to the per-workspace fan-out.
    @discardableResult
    func loadProjectTree(preferredActiveTaskId: String?) async -> Bool {
        guard !isUITestSeededMode else { return true }
        #if DEBUG
        if LoadBench.consumeTreeFailure() { return false }
        #endif
        guard let value = try? await rpcClient.call(
            channel: "project",
            method: "readTree",
            args: [.fromJSONObject(["includeDeleted": true, "includeDeletedTasks": true])],
            timeoutSec: 30.0
        ), let tree = value.decodeJSONDictionary(),
              let rawTasks = tree["tasks"] as? [[String: Any]] else {
            return false
        }
        await loadTaskGroups()

        let rawProjects = (tree["projects"] as? [[String: Any]]) ?? []
        var nextProjects: [SidebarProject] = []
        for raw in rawProjects {
            guard let id = raw["id"] as? String, !id.isEmpty, (raw["deleted"] as? Bool) != true else { continue }
            let roots = ((raw["roots"] as? [[String: Any]]) ?? [])
                .sorted { (ZCodeV4.double($0["position"]) ?? 0) < (ZCodeV4.double($1["position"]) ?? 0) }
            let paths = roots.compactMap { $0["rootPath"] as? String }
            let primary = roots.first(where: { ($0["isPrimary"] as? Bool) == true })?["rootPath"] as? String
            let name = ((raw["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            nextProjects.append(SidebarProject(
                id: id,
                hostId: (raw["hostId"] as? String) ?? "local",
                name: name.isEmpty ? ((primary ?? paths.first).map { ($0 as NSString).lastPathComponent } ?? "New project") : name,
                position: Int(ZCodeV4.double(raw["position"]) ?? 0),
                pinned: (raw["pinned"] as? Bool) ?? false,
                roots: paths,
                primaryRoot: primary
            ))
        }

        let previousById = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var next: [AgentTaskSession] = []
        for raw in rawTasks {
            guard var task = Self.treeTaskSession(from: raw) else { continue }
            let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: task.workspacePath, workspaceIdentity: task.workspaceIdentity)
            guard seen.insert("\(key)::\(task.id)").inserted else { continue }
            if let identity = task.workspaceIdentity, workspaceIdentityByPath[task.workspacePath] == nil {
                workspaceIdentityByPath[task.workspacePath] = identity
            }
            if let existing = previousById[task.id] {
                task = Self.carryingLiveState(into: task, from: existing)
                if existing.status == .running || existing.status == .waitingApproval
                    || existing.status == .waitingQuestion || existing.status == .waitingPlan {
                    task.status = existing.status
                }
                task.pendingInteractionCount = existing.pendingInteractionCount
                task.pendingInteractionIsUserInput = existing.pendingInteractionIsUserInput
                task.activityPhase = existing.activityPhase
                task.hasBackgroundWork = existing.hasBackgroundWork
                task.subagentRuns = existing.subagentRuns
                task.contextUsage = existing.contextUsage
                task.goals = existing.goals
                if existing.updatedAt > task.updatedAt, existing.status == .running { task.updatedAt = existing.updatedAt }
            }
            if task.id == activeSessionId { task.unread = false }
            next.append(task)
        }
        let nextIds = Set(next.map(\.id))
        next.append(contentsOf: sessions.filter { $0.id.hasPrefix("task-") && !nextIds.contains($0.id) })

        sidebarProjects = nextProjects.sorted { lhs, rhs in
            lhs.position == rhs.position ? lhs.id < rhs.id : lhs.position < rhs.position
        }
        sessions = next
        sidebarTreeLoaded = true
        applyControllerActivities()
        if liveSync.controller.subscriptionId != nil {
            Task { @MainActor in await self.registerControllerSources() }
        }

        if let preferredActiveTaskId, next.contains(where: { $0.id == preferredActiveTaskId }) {
            activeSessionId = preferredActiveTaskId
        } else if !next.contains(where: { $0.id == activeSessionId }) {
            activeSessionId = AppStore.sortedForSidebar(next.filter { !$0.archived }).first?.id ?? ""
        }
        return true
    }

    /// Debounced re-read for `broadcast state:projects` and workspace task-list events.
    func scheduleProjectTreeRefresh(delay: Double = 0.4) {
        guard !isUITestSeededMode else { return }
        projectTreeRefreshTask?.cancel()
        projectTreeRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard !(await self.loadProjectTree(preferredActiveTaskId: self.activeSessionId)), !Task.isCancelled else { return }
            if self.sidebarTreeLoaded {
                // The per-workspace fan-out only covers open desktop tabs; it must not replace a loaded tree.
                if self.isLiveHostConnected { self.scheduleProjectTreeRefresh(delay: 5) }
            } else {
                await self.loadAllWorkspaceTasks(preferredActiveTaskId: self.activeSessionId)
            }
        }
    }

    /// `TaskEntry` (task meta + `pinned/archived/hostId/projectId`) → session.
    static func treeTaskSession(from raw: [String: Any]) -> AgentTaskSession? {
        guard let taskId = (raw["taskId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !taskId.isEmpty,
              let path = (raw["workspacePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        let identity = (raw["workspaceIdentity"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: path, workspaceIdentity: identity)
        func date(_ value: Any?) -> Date? {
            guard let ms = ZCodeV4.double(value), ms > 0 else { return nil }
            return Date(timeIntervalSince1970: ms > 9_999_999_999 ? ms / 1000 : ms)
        }
        let updated = date(raw["updatedAt"]) ?? date(raw["createdAt"]) ?? Date(timeIntervalSince1970: 0)
        let summary = RemoteTaskSummary(
            id: taskId,
            title: (raw["title"] as? String) ?? "",
            workspacePath: path,
            workspaceIdentity: identity,
            status: (raw["status"] as? String) ?? "idle",
            pinned: (raw["pinned"] as? Bool) ?? false,
            archived: (raw["archived"] as? Bool) ?? false,
            unread: ZCodeV4.double(raw["unreadAt"]) != nil,
            updatedAt: updated,
            createdAt: date(raw["createdAt"]) ?? updated,
            mode: raw["mode"] as? String,
            model: raw["model"] as? String,
            thoughtLevel: raw["thoughtLevel"] as? String
        )
        var session = makeAgentSession(from: summary, projectId: stableProjectId(for: key))
        // Completed/errored is a past outcome, not a live state: only the sessions index reports running.
        session.status = .idle
        session.lastOutcomeError = (raw["status"] as? String) == "error"
        session.inProjectTree = true
        session.treeProjectId = (raw["projectId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        session.workspaceIdentity = identity
        session.workspacePurpose = raw["workspacePurpose"] as? String
        session.hostId = (raw["hostId"] as? String) ?? "local"
        session.forkedFromTaskId = raw["forkedFromTaskId"] as? String
        session.cronAutomationId = (raw["cronAutomationId"] as? String) ?? (raw["automationId"] as? String)
        session.offPeakTaskId = raw["offPeakTaskId"] as? String
        if let traceId = raw["traceId"] as? String, !traceId.isEmpty { session.traceId = traceId }
        if let summaryDict = raw["changeSummary"] as? [String: Any] {
            let files = (summaryDict["files"] as? [Any]) ?? []
            session.changeFileCount = files.count
            if !files.isEmpty {
                session.changeAdded = Int(ZCodeV4.double(summaryDict["added"]) ?? 0)
                session.changeRemoved = Int(ZCodeV4.double(summaryDict["removed"]) ?? 0)
            }
        }
        return session
    }

    // MARK: - Task groups (`task-groups.read`, `mft` / `Jht`)

    func loadTaskGroups() async {
        guard !isUITestSeededMode,
              let value = try? await rpcClient.call(channel: "task-groups", method: "read", args: [], timeoutSec: 10.0),
              let dict = value.decodeJSONDictionary() else { return }
        func num(_ v: Any?) -> Double { ZCodeV4.double(v) ?? 0 }
        taskGroups = TaskGroupsStructure(
            groups: ((dict["groups"] as? [[String: Any]]) ?? []).compactMap { g in
                guard let id = g["id"] as? String else { return nil }
                return .init(id: id, title: (g["title"] as? String) ?? "", color: g["color"] as? String)
            },
            members: ((dict["members"] as? [[String: Any]]) ?? []).compactMap { m in
                guard let gid = m["groupId"] as? String, let wk = m["workspaceKey"] as? String, let tid = m["taskId"] as? String else { return nil }
                return .init(groupId: gid, workspaceKey: wk, taskId: tid, sortOrder: num(m["sortOrder"]))
            },
            order: ((dict["order"] as? [[String: Any]]) ?? []).compactMap { o in
                guard let type = o["type"] as? String, let key = o["key"] as? String else { return nil }
                return .init(type: type, key: key, sortOrder: num(o["sortOrder"]))
            }
        )
    }

    /// `ZN`: `JSON.stringify([workspaceKey, taskId])`.
    static func groupTaskKey(_ task: AgentTaskSession) -> String {
        let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: task.workspacePath, workspaceIdentity: task.workspaceIdentity)
        guard let data = try? JSONSerialization.data(withJSONObject: [key, task.id], options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "[\"\(key)\",\"\(task.id)\"]" }
        return text
    }

    static func groupDisplayTitle(_ group: TaskGroupsStructure.Group) -> String {
        if group.id == "zcode-default-group-cron" && group.title == "cron" { return "Scheduled tasks" }
        if group.id == "zcode-default-group-off-peak" && group.title == "off-peak" { return "Off-peak tasks" }
        return group.title
    }

    /// Root order entries (groups and ungrouped tasks interleaved), each group with its members in `sortOrder`.
    func sidebarGroupNodes() -> [SidebarGroupNode] {
        let structure = taskGroups
        let candidates = sidebarVisibleTasks.filter { !$0.pinned }
        var byKey: [String: AgentTaskSession] = [:]
        var keyOrder: [String] = []
        for task in Self.sortedForTimeline(candidates) {
            let key = Self.groupTaskKey(task)
            if byKey[key] == nil { keyOrder.append(key) }
            byKey[key] = task
        }
        let groupsById = Dictionary(structure.groups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var grouped = Set<String>()
        var membersByGroup: [String: [AgentTaskSession]] = [:]
        for member in structure.members.sorted(by: { $0.sortOrder < $1.sortOrder }) where groupsById[member.groupId] != nil {
            guard let data = try? JSONSerialization.data(withJSONObject: [member.workspaceKey, member.taskId], options: [.withoutEscapingSlashes]),
                  let key = String(data: data, encoding: .utf8) else { continue }
            grouped.insert(key)
            if let task = byKey[key] { membersByGroup[member.groupId, default: []].append(task) }
        }
        var entries = structure.order.sorted { $0.sortOrder < $1.sortOrder }
        var present = Set(entries.map { "\($0.type):\($0.key)" })
        for group in structure.groups where !present.contains("group:\(group.id)") {
            entries.append(.init(type: "group", key: group.id, sortOrder: 0))
            present.insert("group:\(group.id)")
        }
        for key in keyOrder where !present.contains("task:\(key)") && !grouped.contains(key) {
            entries.append(.init(type: "task", key: key, sortOrder: 0))
        }
        return entries.compactMap { entry in
            if entry.type == "task" {
                guard let task = byKey[entry.key], !grouped.contains(entry.key) else { return nil }
                return .task(task)
            }
            guard let group = groupsById[entry.key] else { return nil }
            return .group(group, tasks: membersByGroup[group.id] ?? [])
        }
    }

    // MARK: - Ordering (`hO` / `I7e`)

    /// Working tasks (running/prewarming or with background work) first, then updatedAt DESC, createdAt DESC, taskId ASC.
    static func sortedForSidebar(_ tasks: [AgentTaskSession]) -> [AgentTaskSession] {
        tasks.sorted { a, b in
            let aw = a.isWorking, bw = b.isWorking
            if aw != bw { return aw }
            if aw {
                if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
                return a.id < b.id
            }
            return updatedOrder(a, b)
        }
    }

    /// Timeline order: updatedAt DESC, createdAt DESC, taskId ASC (no working-first boost).
    static func sortedForTimeline(_ tasks: [AgentTaskSession]) -> [AgentTaskSession] {
        tasks.sorted(by: updatedOrder)
    }

    private static func updatedOrder(_ a: AgentTaskSession, _ b: AgentTaskSession) -> Bool {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id < b.id
    }

    // MARK: - Sidebar sections (`ON`)

    var sidebarVisibleTasks: [AgentTaskSession] {
        sessions.filter { !$0.archived && !$0.id.hasPrefix("task-") }
    }

    func sidebarPinnedTasks() -> [AgentTaskSession] {
        Self.sortedForSidebar(sidebarVisibleTasks.filter(\.pinned))
    }

    func sidebarTasks(inProject projectId: String) -> [AgentTaskSession] {
        Self.sortedForSidebar(sidebarVisibleTasks.filter { !$0.pinned && $0.treeProjectId == projectId })
    }

    /// The "Tasks" section: local project-less tasks (conversation and draft workspaces).
    func sidebarProjectlessTasks() -> [AgentTaskSession] {
        Self.sortedForSidebar(sidebarVisibleTasks.filter { !$0.pinned && $0.treeProjectId == nil && $0.hostId == "local" })
    }

    func sidebarTimelineTasks() -> [AgentTaskSession] {
        Self.sortedForTimeline(sidebarVisibleTasks)
    }

    func sidebarArchivedTasks() -> [AgentTaskSession] {
        Self.sortedForTimeline(sessions.filter(\.archived))
    }

    /// `vdt`: any non-archived task of the project carries an unread watermark.
    func sidebarProjectHasUnread(_ project: SidebarProject) -> Bool {
        sessions.contains { $0.treeProjectId == project.id && !$0.archived && $0.unread }
    }

    /// Workspace label used by the timeline row and the draft pill.
    func sidebarWorkspaceLabel(for task: AgentTaskSession) -> String {
        if task.workspacePurpose == "conversation" || task.treeProjectId == nil && Self.isConversationWorkspace(task.workspacePath) {
            return "Tasks"
        }
        if let pid = task.treeProjectId, let project = sidebarProjects.first(where: { $0.id == pid }) {
            return project.name
        }
        return (task.workspacePath as NSString).lastPathComponent
    }

    static func isConversationWorkspace(_ path: String) -> Bool {
        path.contains("/.zcode/workspace/")
    }

    // MARK: - Bridge targeting

    /// Opens the relay bridge for a task. Tasks whose workspace isn't an open desktop tab are addressed by
    /// `taskId + taskHostId`, which makes the desktop prepare that task's workspace (`prepareProjectWorkspace`).
    /// A new task whose workspace isn't an open tab is opened with a `project` intent instead
    /// (`{projectId}` for a project, `{projectId: null, draftId}` for a project-less draft), and the session
    /// adopts the workspace the desktop prepared.
    func openBridge(for session: AgentTaskSession, timeoutSec: Double = 6.0) async throws {
        guard await rpcClient.isRelay else { return }
        let identity = session.workspaceIdentity ?? workspaceIdentityByPath[session.workspacePath]
        let key = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: session.workspacePath, workspaceIdentity: identity)
        let isDraft = session.id.hasPrefix("task-")
        let isOpenTab = !session.workspacePath.isEmpty && projects.contains { $0.rootPath == session.workspacePath }

        if isDraft, !isOpenTab, session.inProjectTree || session.workspacePath.isEmpty {
            var intent: [String: Any] = ["projectId": session.treeProjectId ?? NSNull()]
            if session.treeProjectId != nil {
                intent["hostId"] = session.hostId
            } else {
                intent["draftId"] = UUID().uuidString.lowercased()
            }
            let anchorKey: String
            if let current = await rpcClient.currentBridge() {
                anchorKey = current.workspaceKey
            } else {
                anchorKey = projects.first.map {
                    ZCodeRPCClient.resolveWorkspaceKey(workspacePath: $0.rootPath, workspaceIdentity: workspaceIdentityByPath[$0.rootPath])
                } ?? key
            }
            let bridge = try await rpcClient.openWorkspaceBridge(workspaceKey: anchorKey, project: intent, timeoutSec: timeoutSec)
            if let idx = sessions.firstIndex(where: { $0.id == session.id }), !bridge.workspacePath.isEmpty {
                sessions[idx].workspacePath = bridge.workspacePath
                sessions[idx].workspaceIdentity = bridge.workspaceIdentity
                if let wsId = bridge.workspaceIdentity, !wsId.isEmpty {
                    workspaceIdentityByPath[bridge.workspacePath] = wsId
                }
                sessions[idx].projectId = Self.stableProjectId(for: bridge.workspaceKey)
                if session.treeProjectId == nil { sessions[idx].workspacePurpose = "conversation" }
            }
            return
        }

        _ = try await rpcClient.openWorkspaceBridge(
            workspaceKey: key,
            taskId: isDraft ? nil : session.id,
            taskHostId: (!isDraft && !isOpenTab) ? session.hostId : nil,
            timeoutSec: timeoutSec
        )
    }

    /// Project a new task is created in: its sidebar project, else the project on the task's host rooted at its
    /// workspace. The host files tasks created without one outside every project (`reserveCreatedTask`).
    func treeProjectIdForNewTask(_ session: AgentTaskSession) -> String? {
        if let id = session.treeProjectId { return id }
        let path = session.workspacePath
        guard !path.isEmpty, session.workspacePurpose != "conversation", !Self.isConversationWorkspace(path) else { return nil }
        let candidates = sidebarProjects.filter { $0.hostId == session.hostId && $0.roots.contains(path) }
        return (candidates.first { $0.primaryRoot == path } ?? candidates.first)?.id
    }

    /// "New task" for a ZCode project (`treeProjectId`) or, with nil, a project-less conversation draft.
    public func createNewTask(treeProjectId: String?) {
        let project = treeProjectId.flatMap { id in sidebarProjects.first(where: { $0.id == id }) }
        let path = project?.rootPath ?? ""
        let workspace = projects.first(where: { $0.rootPath == path })
        createNewSession(inProjectId: workspace?.id)
        guard let idx = sessions.firstIndex(where: { $0.id == activeSessionId }),
              activeConnection?.transport == .cloudRelayV2 || !path.isEmpty else { return }
        sessions[idx].inProjectTree = true
        sessions[idx].treeProjectId = project?.id
        sessions[idx].hostId = project?.hostId ?? "local"
        sessions[idx].workspacePath = path
        sessions[idx].workspaceIdentity = workspaceIdentityByPath[path]
        sessions[idx].workspacePurpose = project == nil ? "conversation" : "project"
        sessions[idx].projectId = workspace?.id ?? (path.isEmpty ? "" : Self.stableProjectId(for: path))
    }
}

extension AgentTaskSession {
    /// `P7e`: session phase running/prewarming (or background work).
    var isWorking: Bool { isPhaseRunning || hasBackgroundWork }

    /// `N7e`: activity phase running/prewarming; the local conversation status covers hosts without activity.
    var isPhaseRunning: Bool {
        if let activityPhase { return activityPhase == "running" || activityPhase == "prewarming" }
        return status == .running || status == .waitingApproval || status == .waitingQuestion || status == .waitingPlan
    }

    /// `hit`: error > unread > loading > none.
    enum SidebarIndicator { case error, unread, loading, none }

    var sidebarIndicator: SidebarIndicator {
        if let activityPhase {
            if activityPhase == "error" { return .error }
        } else if status == .error || (!isPhaseRunning && lastOutcomeError) {
            return .error
        }
        if unread { return .unread }
        if isPhaseRunning { return .loading }
        return .none
    }

    /// `F7e` tag: "Awaiting approval" / "Awaiting approval · N".
    var pendingTagText: String? {
        var count = pendingInteractionCount
        if count == 0 {
            if pendingPermission != nil || status == .waitingApproval { count = 1 }
            else if pendingQuestion != nil || pendingPlan != nil || status == .waitingQuestion || status == .waitingPlan { count = 1 }
        }
        guard count > 0 else { return nil }
        let label = "Awaiting approval"
        return count > 1 ? "\(label) · \(count)" : label
    }
}
