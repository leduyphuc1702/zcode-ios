import Foundation

// MARK: - Composer catalogs (1:1 with ZCode Desktop 3.16.3)
//
// Desktop renderer references:
// - `CV` / `JUt`  → workspace presentation slash commands (`zcode-session.readWorkspacePresentation`)
// - `KUt` / `qUt` → app commands ("Plan mode"; side/btw are desktop-only and omitted on mobile)
// - `sWt`         → slash popover sections: Commands / Skills / Agents
// - `XUt`/`FUt`   → `$skill` labels + "Workspace · description" descriptions
// - `TUt`/`ZUt`   → agent labels + "Built-in · description" descriptions
// - `YWt`/`AWt`   → "@" mention sections: Plugins / Files / Sessions
// - `HWt`/`VWt`   → session grouping + ordering
// - `MK`/`jK`     → fuzzy ranking (prefix < substring < subsequence; label < value < description < keywords)

struct ComposerCommandItem: Identifiable, Equatable {
    let id: String
    /// `name` with every leading slash stripped (`BK`).
    let value: String
    /// `inputHint.trim()` or `/value` (`JUt`); app commands use their localized label.
    let label: String
    let description: String
    let keywords: [String]
    /// `app-slash:` ids execute an app action instead of inserting text (`zK` / `$Ut`).
    let isAppCommand: Bool

    /// `chat.slash.app.plan.label` / `chat.slash.app.plan.description`.
    static let planMode = ComposerCommandItem(
        id: "app-slash:plan",
        value: "plan",
        label: "Plan mode",
        description: "Enable Plan mode",
        keywords: ["plan", "计划", "计划模式"],
        isAppCommand: true
    )
}

struct ComposerSkillItem: Identifiable, Equatable {
    let id: String
    let name: String
    /// `"Workspace · description"` (`FUt`).
    let description: String
    let keywords: [String]
}

struct ComposerAgentItem: Identifiable, Equatable {
    let id: String
    let name: String
    /// `"Built-in · description"` (`TUt`).
    let description: String
    let keywords: [String]
}

struct ComposerPluginItem: Identifiable, Equatable {
    let id: String
    let pluginId: String
    let name: String
    let description: String
    let keywords: [String]
    /// `conflictingPluginIds.length > 0` in the desktop plugin reference catalog.
    let isDisabled: Bool
    static let conflictReason = "Name conflicts with another enabled plugin"
}

struct ComposerFileItem: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let relativePath: String
    /// `relativePath` for the main workspace root, absolute `path` for additional roots (`AWt`).
    let mentionPath: String
    let type: String
    let rootName: String
    let rootPath: String

    var isDirectory: Bool { type == "directory" }
}

struct ComposerSessionItem: Identifiable, Equatable {
    let id: String
    let taskId: String
    let label: String
    let description: String
    let keywords: [String]
    let workspaceKey: String
    let groupId: String
    let groupTitle: String
}

struct ComposerSessionGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [ComposerSessionItem]
}

// MARK: - Desktop fuzzy ranking (`MK` / `jK` / `yUt` / `SUt` / `bUt`)

enum ComposerFuzzy {
    /// `hUt = 1e3`
    static let defaultLimit = 1000

    struct Candidate {
        let label: String
        let value: String
        let description: String
        let keywords: [String]
        let isPlugin: Bool
        let isDirectory: Bool

        init(
            label: String,
            value: String,
            description: String = "",
            keywords: [String] = [],
            isPlugin: Bool = false,
            isDirectory: Bool = false
        ) {
            self.label = label
            self.value = value
            self.description = description
            self.keywords = keywords
            self.isPlugin = isPlugin
            self.isDirectory = isDirectory
        }
    }

    /// `jK`: prefix match best, substring `100 + index`, Han query disables subsequence,
    /// subsequence `200 + gaps + (length delta)`. Empty candidate → nil.
    static func score(candidate rawCandidate: String, query rawQuery: String) -> Int? {
        let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if candidate.isEmpty { return nil }
        if query.isEmpty { return 0 }
        if candidate.hasPrefix(query) { return candidate.count - query.count }
        if let range = candidate.range(of: query) {
            return 100 + candidate.distance(from: candidate.startIndex, to: range.lowerBound)
        }
        // `vUt`: queries containing Han only match via prefix/substring.
        if query.unicodeScalars.contains(where: { $0.properties.isIdeographic }) { return nil }
        var gaps = 0
        var searchStart = candidate.startIndex
        for character in query {
            guard let found = candidate[searchStart...].firstIndex(of: character) else { return nil }
            gaps += candidate.distance(from: searchStart, to: found)
            searchStart = candidate.index(after: found)
        }
        return 200 + gaps + (candidate.count - query.count)
    }

    /// `MK`: per-item minimum of label, value + 25, description + 100 (never for plugins), keywords + 300.
    static func score(_ item: Candidate, query: String) -> Int? {
        let labelScore = score(candidate: item.label, query: query)
        let valueScore = score(candidate: item.value, query: query)
        let descriptionScore = item.isPlugin ? nil : score(candidate: item.description, query: query)
        var keywordScore = Int.max
        for keyword in item.keywords {
            guard let raw = score(candidate: keyword, query: query) else { continue }
            keywordScore = min(keywordScore, raw + 300)
        }
        var best = Int.max
        if let labelScore { best = min(best, labelScore) }
        if let valueScore { best = min(best, valueScore + 25) }
        if let descriptionScore { best = min(best, descriptionScore + 100) }
        best = min(best, keywordScore)
        return best == Int.max ? nil : best
    }

    /// `MK`: with a query → score/sort/slice; without → `requireQuery ? [] : SUt(sorted).slice(limit)`.
    static func rank<T>(
        _ items: [T],
        query: String,
        limit: Int = defaultLimit,
        requireQuery: Bool = false,
        candidate: (T) -> Candidate
    ) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if requireQuery { return [] }
            return Array(directoryFirstStable(items, isDirectory: { candidate($0).isDirectory }).prefix(limit))
        }
        var scored: [(index: Int, item: T, score: Int)] = []
        scored.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            guard let score = score(candidate(item), query: trimmed) else { continue }
            scored.append((index, item, score))
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.index < rhs.index
        }
        return scored.prefix(limit).map(\.item)
    }

    /// `SUt`: stable partition, directories first (the task's explicit ordering requirement).
    static func directoryFirstStable<T>(_ items: [T], isDirectory: (T) -> Bool) -> [T] {
        var files: [T] = []
        var directories: [T] = []
        files.reserveCapacity(items.count)
        for item in items {
            if isDirectory(item) { directories.append(item) } else { files.append(item) }
        }
        return directories + files
    }

    static func uniqueKeywords(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

// MARK: - Host-backed composer catalogs

extension AppStore {

    // MARK: Workspace context

    /// Active task workspace when a session exists; otherwise the open project root.
    func composerWorkspaceContext() -> (path: String, identity: String?) {
        if let session = activeSession, !session.workspacePath.isEmpty {
            let identity = session.workspaceIdentity ?? workspaceIdentityByPath[session.workspacePath]
            return (session.workspacePath, identity)
        }
        let path = activeProject?.rootPath ?? projects.first?.rootPath ?? ""
        let identity = path.isEmpty ? nil : workspaceIdentityByPath[path]
        return (path, identity)
    }

    func composerWorkspaceKey(path: String, identity: String?) -> String {
        ZCodeRPCClient.resolveWorkspaceKey(workspacePath: path, workspaceIdentity: identity)
    }

    static func composerStripLeadingSlashes(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.drop(while: { $0 == "/" }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Slash commands (`CV` → `zcode-session.readWorkspacePresentation` → `JUt`)

    /// Desktop reads the presentation once per workspace and re-hydrates when the catalog is empty.
    /// Returns the mapped commands plus the raw host count (drives `chat.slash.emptyUnavailable`).
    func readComposerWorkspaceCommands(
        workspacePath: String,
        workspaceIdentity: String?
    ) async -> (commands: [ComposerCommandItem], rawCount: Int)? {
        guard !workspacePath.isEmpty else { return ([], 0) }
        var request: [String: Any] = ["workspacePath": workspacePath]
        if let workspaceIdentity, !workspaceIdentity.isEmpty {
            request["workspaceIdentity"] = workspaceIdentity
        }
        guard let value = try? await rpcClient.call(
            channel: "zcode-session",
            method: "readWorkspacePresentation",
            args: [.fromJSONObject(request)],
            timeoutSec: 6.0
        ), let dict = value.decodeJSONDictionary() else {
            return nil
        }
        let raw = (dict["slashCommands"] as? [[String: Any]]) ?? []
        var commands: [ComposerCommandItem] = []
        for entry in raw {
            let name = (entry["name"] as? String) ?? ""
            let value = Self.composerStripLeadingSlashes(name)
            // `JUt`: skip empty names and the built-in "plan" command (case-insensitive).
            guard !value.isEmpty, value.lowercased() != "plan" else { continue }
            let rawHint = (entry["inputHint"] as? String) ?? ""
            let hint = rawHint.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = (entry["description"] as? String) ?? ""
            commands.append(
                ComposerCommandItem(
                    id: "slash:\(value)",
                    value: value,
                    label: hint.isEmpty ? "/\(value)" : hint,
                    description: description,
                    keywords: ComposerFuzzy.uniqueKeywords([value, name, description, rawHint]),
                    isAppCommand: false
                )
            )
        }
        return (commands, raw.count)
    }

    /// Seeded fixture mode only: `commands.list` fixtures presented with desktop mapping.
    func seededComposerCommands() -> [ComposerCommandItem] {
        slashCommands.compactMap { item in
            let trigger = item.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            if trigger.lowercased() == "plan mode" || trigger.lowercased() == "/plan" { return nil }
            let value = Self.composerStripLeadingSlashes(trigger)
            guard !value.isEmpty else { return nil }
            return ComposerCommandItem(
                id: "slash:\(value)",
                value: value,
                label: "/\(value)",
                description: item.summary,
                keywords: ComposerFuzzy.uniqueKeywords([value, trigger, item.summary, item.argumentHint]),
                isAppCommand: false
            )
        }
    }

    /// Desktop merges `KUt(appCommands)` after the host catalog, de-duplicating by value.
    static func composerCommands(host: [ComposerCommandItem], includePlanMode: Bool) -> [ComposerCommandItem] {
        var merged = host
        let existing = Set(host.map(\.value))
        if includePlanMode, !existing.contains(ComposerCommandItem.planMode.value) {
            merged.append(.planMode)
        }
        return merged
    }

    // MARK: Skills (`FUt` / `XUt`, fed by the host skill catalog)

    static func composerSkillVisible(_ skill: SkillCatalogItem) -> Bool {
        // `OUt`: only skills living under the GLM skill roots (or plugin scope) are referenced.
        if skill.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "plugin" { return true }
        if skill.id.hasPrefix("glm:") { return true }
        let normalized = skill.filePath.replacingOccurrences(of: "\\", with: "/")
        return normalized.contains("/.zcode/skills/") || normalized.contains("/.zcode/cli/plugins/cache/")
    }

    static func composerSkillScopeRank(_ skill: SkillCatalogItem) -> Int {
        switch skill.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "workspace": return 0
        case "plugin": return 1
        default: return 2
        }
    }

    static func composerSkillScopeLabel(_ skill: SkillCatalogItem) -> String {
        switch skill.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "workspace": return "Workspace"
        case "plugin": return "Plugin"
        default: return "User"
        }
    }

    static func composerSkillItems(from skills: [SkillCatalogItem]) -> [ComposerSkillItem] {
        var byName: [String: SkillCatalogItem] = [:]
        var order: [String] = []
        for skill in skills where skill.enabled && composerSkillVisible(skill) {
            let key = skill.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if let existing = byName[key] {
                if composerSkillScopeRank(skill) < composerSkillScopeRank(existing) {
                    byName[key] = skill
                }
            } else {
                byName[key] = skill
                order.append(key)
            }
        }
        return order.compactMap { key in
            guard let skill = byName[key] else { return nil }
            let scopeLabel = composerSkillScopeLabel(skill)
            let description = skill.summary.isEmpty ? scopeLabel : "\(scopeLabel) · \(skill.summary)"
            return ComposerSkillItem(
                id: "skill:\(skill.id)",
                name: skill.name,
                description: description,
                keywords: ComposerFuzzy.uniqueKeywords([skill.name, skill.summary, description, skill.scope])
            )
        }
    }

    // MARK: Agents (`TUt` / `ZUt`, fed by the host subagent catalog)

    static func composerAgentScopeRank(_ agent: SubagentDefinitionItem) -> Int {
        if agent.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "workspace" { return 0 }
        if agent.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "user" { return 1 }
        return 2
    }

    static func composerAgentScopeLabel(_ agent: SubagentDefinitionItem) -> String {
        let scope = agent.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let source = agent.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if scope == "workspace" { return "Workspace" }
        if source == "plugin" { return "Plugin" }
        if source == "built-in" { return "Built-in" }
        return "User"
    }

    static func composerAgentItems(from subagents: [SubagentDefinitionItem]) -> [ComposerAgentItem] {
        var byName: [String: SubagentDefinitionItem] = [:]
        var order: [String] = []
        for agent in subagents where agent.enabled {
            let key = agent.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if let existing = byName[key] {
                if composerAgentScopeRank(agent) < composerAgentScopeRank(existing) {
                    byName[key] = agent
                }
            } else {
                byName[key] = agent
                order.append(key)
            }
        }
        return order.compactMap { key in
            guard let agent = byName[key] else { return nil }
            let scopeLabel = composerAgentScopeLabel(agent)
            let description = agent.description.isEmpty ? scopeLabel : "\(scopeLabel) · \(agent.description)"
            let model = agent.modelOverride.isEmpty || agent.modelOverride == "inherit" ? nil : agent.modelOverride
            return ComposerAgentItem(
                id: "subagent:\(agent.id)",
                name: agent.name,
                description: description,
                keywords: ComposerFuzzy.uniqueKeywords(
                    [agent.name, agent.description, agent.scope, agent.source, scopeLabel, model ?? "", agent.filePath]
                )
            )
        }
    }

    // MARK: Plugins (`FWt`)

    static func composerPluginItems(from plugins: [PluginCatalogItem]) -> [ComposerPluginItem] {
        let enabled = plugins.filter { $0.installed && $0.enabled }
        var nameCounts: [String: Int] = [:]
        for plugin in enabled {
            let key = plugin.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            nameCounts[key, default: 0] += 1
        }
        return enabled.map { plugin in
            let key = plugin.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ComposerPluginItem(
                id: "plugin:\(plugin.id)",
                pluginId: plugin.id,
                name: plugin.name,
                description: plugin.summary,
                keywords: ComposerFuzzy.uniqueKeywords([plugin.name, plugin.id, plugin.marketplace]),
                isDisabled: (nameCounts[key] ?? 0) > 1
            )
        }
    }

    // MARK: Sessions (`HWt` / `VWt` / `BWt`)

    static func composerSessionLabel(_ title: String) -> String {
        var label = title
        let prefix = "#sess_"
        if label.hasPrefix(prefix) {
            // `RWt`: /^#sess_[a-zA-Z0-9._-]+\s*/
            let tokenStart = label.index(label.startIndex, offsetBy: prefix.count)
            var index = tokenStart
            while index < label.endIndex {
                let character = label[index]
                let isTokenCharacter = character.isASCII
                    && (character.isLetter || character.isNumber || character == "." || character == "_" || character == "-")
                guard isTokenCharacter else { break }
                index = label.index(after: index)
            }
            if index > tokenStart {
                label = String(label[index...])
            }
        }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled session" : trimmed
    }

    static func composerBasename(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        if let last = parts.last { return String(last) }
        return trimmed
    }

    func composerSessionItems() -> [ComposerSessionItem] {
        let context = composerWorkspaceContext()
        let currentKey = composerWorkspaceKey(path: context.path, identity: context.identity)
        // `VWt`: dedupe by taskId keeping the newest, skip non-tree drafts.
        var byTaskId: [String: AgentTaskSession] = [:]
        var order: [String] = []
        for session in sessions where !session.archived && !session.id.hasPrefix("task-") {
            if let existing = byTaskId[session.id] {
                if session.updatedAt > existing.updatedAt { byTaskId[session.id] = session }
            } else {
                byTaskId[session.id] = session
                order.append(session.id)
            }
        }
        let deduped = order.compactMap { byTaskId[$0] }
        let projectNames = Dictionary(
            sidebarProjects.map { ("\($0.hostId)::\($0.id)", $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        // `LWt`: current workspace first, then updatedAt DESC, createdAt DESC, title ASC.
        let sorted = deduped.sorted { lhs, rhs in
            let lhsKey = composerWorkspaceKey(path: lhs.workspacePath, identity: lhs.workspaceIdentity)
            let rhsKey = composerWorkspaceKey(path: rhs.workspacePath, identity: rhs.workspaceIdentity)
            let lhsCurrent = lhsKey == currentKey
            let rhsCurrent = rhsKey == currentKey
            if lhsCurrent != rhsCurrent { return lhsCurrent }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return sorted.map { session in
            let workspaceKey = composerWorkspaceKey(path: session.workspacePath, identity: session.workspaceIdentity)
            let projectKey = session.treeProjectId.map { "\(session.hostId)::\($0)" } ?? "\(session.hostId)::"
            let groupTitle = session.treeProjectId.flatMap { projectNames["\(session.hostId)::\($0)"] } ?? "Tasks"
            return ComposerSessionItem(
                id: "session:\(session.id)",
                taskId: session.id,
                label: Self.composerSessionLabel(session.title),
                description: Self.composerBasename(session.workspacePath),
                keywords: ComposerFuzzy.uniqueKeywords([
                    session.title,
                    session.id,
                    session.workspacePath,
                    session.workspaceIdentity ?? "",
                    session.modelId,
                    session.modelProviderId ?? ""
                ]),
                workspaceKey: workspaceKey,
                groupId: projectKey,
                groupTitle: groupTitle
            )
        }
    }

    /// `YWt` / `HWt`: "@" → current workspace only, one group, no per-group cap;
    /// "#" → all same-authority workspaces grouped by project, 20 per group.
    func composerSessionGroups(query: String, groupedByProject: Bool) -> [ComposerSessionGroup] {
        let all = composerSessionItems()
        let context = composerWorkspaceContext()
        let currentKey = composerWorkspaceKey(path: context.path, identity: context.identity)
        let candidates = groupedByProject ? all : all.filter { $0.workspaceKey == currentKey }
        if !groupedByProject {
            let ranked = ComposerFuzzy.rank(candidates, query: query, limit: Int.max, requireQuery: false) { item in
                ComposerFuzzy.Candidate(
                    label: item.label,
                    value: item.taskId,
                    description: item.description,
                    keywords: item.keywords
                )
            }
            guard !ranked.isEmpty else { return [] }
            return [ComposerSessionGroup(id: "sessions", title: "Sessions", items: ranked)]
        }
        var grouped: [String: [ComposerSessionItem]] = [:]
        var groupOrder: [String] = []
        for item in candidates {
            if grouped[item.groupId] == nil { groupOrder.append(item.groupId) }
            grouped[item.groupId, default: []].append(item)
        }
        return groupOrder.compactMap { groupId in
            guard let items = grouped[groupId], let first = items.first else { return nil }
            let ranked = ComposerFuzzy.rank(items, query: query, limit: 20, requireQuery: false) { item in
                ComposerFuzzy.Candidate(
                    label: item.label,
                    value: item.taskId,
                    description: item.description,
                    keywords: item.keywords
                )
            }
            guard !ranked.isEmpty else { return nil }
            return ComposerSessionGroup(id: groupId, title: first.groupTitle, items: ranked)
        }
    }

    // MARK: Files (`AWt` → `file.searchWorkspaceFiles`)

    /// Additional search roots: session directories for a real task, project roots for a draft.
    func composerAdditionalRoots(for session: AgentTaskSession?) async -> [String] {
        guard let session else { return [] }
        let isDraft = session.id.hasPrefix("task-")
        let identity = session.workspaceIdentity ?? workspaceIdentityByPath[session.workspacePath]
        if !isDraft, !session.workspacePath.isEmpty {
            var request: [String: Any] = [
                "taskId": session.id,
                "workspacePath": session.workspacePath
            ]
            if let identity, !identity.isEmpty { request["workspaceIdentity"] = identity }
            if let value = try? await rpcClient.call(
                channel: "project",
                method: "resolveSessionDirectories",
                args: [.fromJSONObject(request)],
                timeoutSec: 6.0
            ), let dict = value.decodeJSONDictionary(),
               let directories = dict["additionalDirectories"] as? [String] {
                return directories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        }
        guard let projectId = session.treeProjectId else { return [] }
        if let project = sidebarProjects.first(where: { $0.id == projectId && $0.hostId == session.hostId })
            ?? sidebarProjects.first(where: { $0.id == projectId }) {
            return project.roots
        }
        // Fallback: `projectService.readProjects()`.
        guard let value = try? await rpcClient.call(
            channel: "project",
            method: "readProjects",
            args: [],
            timeoutSec: 6.0
        ) else { return [] }
        let rows: [[String: Any]]
        if let array = value.decodeJSONValue() as? [[String: Any]] {
            rows = array
        } else if let dict = value.decodeJSONDictionary(),
                  let array = dict["projects"] as? [[String: Any]] {
            rows = array
        } else {
            return []
        }
        guard let project = rows.first(where: { ($0["id"] as? String) == projectId }),
              let roots = project["roots"] as? [[String: Any]] else { return [] }
        return roots.compactMap { $0["rootPath"] as? String }
    }

    /// `AWt`: search the workspace root plus additional roots, dedupe by absolute path, cap at `limit`.
    func searchComposerFiles(
        mainRoot: String,
        additionalRoots: [String],
        workspaceIdentity: String?,
        query: String,
        limit: Int,
        refresh: Bool = false
    ) async throws -> [ComposerFileItem] {
        guard !mainRoot.isEmpty else { return [] }
        var seenRoots = Set<String>()
        var roots: [String] = []
        for root in [mainRoot] + additionalRoots {
            let trimmed = root.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seenRoots.insert(trimmed).inserted else { continue }
            roots.append(trimmed)
        }
        var merged: [String: ComposerFileItem] = [:]
        var order: [String] = []
        for root in roots {
            var request: [String: Any] = [
                "rootPath": root,
                "query": query,
                "limit": limit
            ]
            if let workspaceIdentity, !workspaceIdentity.isEmpty {
                request["workspaceIdentity"] = workspaceIdentity
            }
            if refresh { request["refresh"] = true }
            let value = try await rpcClient.call(
                channel: "file",
                method: "searchWorkspaceFiles",
                args: [.fromJSONObject(request)],
                timeoutSec: 10.0
            )
            guard let rows = value.decodeJSONValue() as? [[String: Any]] else { continue }
            let rootName = Self.composerBasename(root)
            for row in rows {
                guard let path = row["path"] as? String, !path.isEmpty else { continue }
                if merged[path] != nil { continue }
                let relativePath = (row["relativePath"] as? String) ?? path
                let mentionPath = root == mainRoot ? relativePath : path
                let item = ComposerFileItem(
                    id: "file:\(path)",
                    name: (row["name"] as? String) ?? Self.composerBasename(path),
                    path: path,
                    relativePath: relativePath,
                    mentionPath: mentionPath,
                    type: (row["type"] as? String) ?? "file",
                    rootName: rootName,
                    rootPath: root
                )
                merged[path] = item
                order.append(path)
            }
        }
        let items = order.compactMap { merged[$0] }
        return Array(items.prefix(limit))
    }
}
