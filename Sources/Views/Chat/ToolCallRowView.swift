import SwiftUI

// MARK: - Tool family (`qC` classifier + canonical family table)

enum ToolFamily: Equatable {
    case fileRead
    case fileWrite
    case shell
    case search
    case webFetch
    case todo
    case agent
    case subagentStandalone
    case askUser
    case plan
    case skill
    case mcp
    case generic

    static func of(_ tool: ToolCallItem) -> ToolFamily {
        if tool.standaloneSubagentLine != nil { return .subagentStandalone }
        let name = (tool.toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch name {
        case "read", "notebookread": return .fileRead
        case "write", "edit", "multiedit", "applypatch", "apply_patch", "notebookedit": return .fileWrite
        case "bash", "shell": return .shell
        case "glob", "grep", "ls", "websearch", "web_search", "toolsearch", "localtoolsearch": return .search
        case "webfetch", "fetch", "web_fetch": return .webFetch
        case "todoread", "todowrite", "update_plan": return .todo
        case "agent", "task", "subagent", "spawn_agent": return .agent
        case "askuserquestion": return .askUser
        case "exitplanmode", "enterplanmode": return .plan
        case "skill": return .skill
        default: break
        }
        if name.hasPrefix("mcp__") || tool.mcpServer != nil || tool.kind == .mcp { return .mcp }
        if !name.isEmpty { return .generic }
        switch tool.kind {
        case .readFile: return .fileRead
        case .editFile, .writeFile: return .fileWrite
        case .bash: return .shell
        case .search: return .search
        case .mcp: return .mcp
        case .subagent: return .agent
        case .workflow: return .generic
        }
    }

    /// `ksn` read-only allowlist minus `Asn` mutations, redirects (`jsn`) and loops (`Msn`).
    static func isReadOnlyShell(_ command: String) -> Bool {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return false }
        func matches(_ pattern: String) -> Bool {
            cmd.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let readOnly = #"\b(rg|grep|find|ls|cat|head|tail|wc|stat|pwd|which|readlink|tree|sed\s+-n|get-childitem|gci|dir|get-content|gc|type|select-string|sls|get-location|test-path|resolve-path)\b|^git\s+(status|log|show|diff)\b"#
        let mutating = #"\b(sed\s+-i|perl\s+-pi|tee|mv|cp|rm|mkdir|rmdir|touch|truncate|chmod|chown|remove-item|del|erase|set-content|add-content|clear-content|out-file|new-item|move-item|copy-item|rename-item|set-item)\b|^git\s+(add|commit|rm|mv|checkout|switch|restore|reset|clean|revert|cherry-pick|merge|rebase)\b"#
        let redirect = #"(^|[^\d<])>>?\s*\S|&>\s*\S"#
        let loop = #"\b(for|while)\b"#
        return matches(readOnly) && !matches(mutating) && !matches(redirect) && !matches(loop)
    }
}

extension ToolCallItem {
    /// Pending / streaming / running rows use the running presentation (animated kind label).
    var isRunningLike: Bool { status == .running || status == .pendingApproval }
    var isFailed: Bool { status == .failed }
}

// MARK: - Grouping pass (`ecn`)

enum ToolCallDisplayEntry: Identifiable {
    case single(ToolCallItem)
    case exploreGroup(id: String, items: [ToolCallItem])
    case terminalGroup(id: String, items: [ToolCallItem])
    case changesGroup(id: String, items: [ToolCallItem])

    var id: String {
        switch self {
        case .single(let item): return item.id
        case .exploreGroup(let id, _), .terminalGroup(let id, _), .changesGroup(let id, _): return id
        }
    }

    private enum Bucket { case explore, terminal, changes }

    static func group(_ tools: [ToolCallItem], explore: Bool, terminal: Bool, changes: Bool, showTodos: Bool) -> [ToolCallDisplayEntry] {
        var result: [ToolCallDisplayEntry] = []
        var pending: [ToolCallItem] = []
        var pendingBucket: Bucket?

        func flush() {
            defer { pending.removeAll(); pendingBucket = nil }
            guard let bucket = pendingBucket, !pending.isEmpty else { return }
            if pending.count == 1 {
                result.append(.single(pending[0]))
                return
            }
            let id = "group-\(pending[0].id)"
            switch bucket {
            case .explore: result.append(.exploreGroup(id: id, items: pending))
            case .terminal: result.append(.terminalGroup(id: id, items: pending))
            case .changes: result.append(.changesGroup(id: id, items: pending))
            }
        }

        for tool in tools {
            let family = ToolFamily.of(tool)
            if family == .todo && !showTodos { continue }
            let bucket: Bucket? = {
                switch family {
                case .fileRead, .search, .webFetch: return explore ? .explore : nil
                case .shell:
                    let cmd = tool.command ?? ""
                    if ToolFamily.isReadOnlyShell(cmd) { return explore ? .explore : nil }
                    return terminal && !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .terminal : nil
                case .fileWrite: return changes ? .changes : nil
                default: return nil
                }
            }()
            if let bucket {
                if bucket != pendingBucket { flush() }
                pendingBucket = bucket
                pending.append(tool)
            } else {
                flush()
                result.append(.single(tool))
            }
        }
        flush()
        return result
    }

    /// `b7t`: "N fetches, M searches, K lists, J files".
    static func exploreSummary(_ items: [ToolCallItem]) -> String {
        var fetches = 0, searches = 0, lists = 0, files = 0
        for item in items {
            switch ToolFamily.of(item) {
            case .webFetch: fetches += 1
            case .search:
                if (item.searchLabel ?? "").hasPrefix("List") { lists += 1 } else { searches += 1 }
            case .shell:
                let cmd = (item.command ?? "").trimmingCharacters(in: .whitespaces)
                if cmd.hasPrefix("ls") || cmd.hasPrefix("tree") { lists += 1 }
                else if cmd.hasPrefix("rg") || cmd.hasPrefix("grep") || cmd.hasPrefix("find") { searches += 1 }
                else { files += 1 }
            default: files += 1
            }
        }
        var parts: [String] = []
        if fetches > 0 { parts.append(fetches == 1 ? "1 fetch" : "\(fetches) fetches") }
        if searches > 0 { parts.append(searches == 1 ? "1 search" : "\(searches) searches") }
        if lists > 0 { parts.append(lists == 1 ? "1 list" : "\(lists) lists") }
        if files > 0 { parts.append(files == 1 ? "1 file" : "\(files) files") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Tool call list

struct ToolCallListView: View {
    @Bindable var store: AppStore
    let tools: [ToolCallItem]
    let workspacePath: String?

    @Environment(\.zcodePalette) private var palette
    @State private var expandedIds: Set<String> = []

    private var entries: [ToolCallDisplayEntry] {
        ToolCallDisplayEntry.group(
            tools,
            explore: store.toolGroupingExploreEnabled,
            terminal: store.toolGroupingTerminalEnabled,
            changes: store.toolGroupingChangesEnabled,
            showTodos: store.messageStreamShowTodos
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entries) { entry in
                switch entry {
                case .single(let tool):
                    row(tool)
                case .exploreGroup(let id, let items):
                    groupView(id: id, items: items, icon: "magnifyingglass", label: "Explore", summary: exploreGroupSummary(items))
                case .terminalGroup(let id, let items):
                    groupView(id: id, items: items, icon: "terminal", label: "Terminal", summary: terminalGroupSummary(items))
                case .changesGroup(let id, let items):
                    groupView(id: id, items: items, icon: "pencil", label: "Changes", summary: changesGroupSummary(items),
                              added: items.last?.addedLines ?? 0, removed: items.last?.removedLines ?? 0)
                }
            }
        }
    }

    private func row(_ tool: ToolCallItem, nested: Bool = false) -> some View {
        ToolCallRowView(
            store: store,
            tool: tool,
            workspacePath: workspacePath,
            showIcon: !nested,
            isExpanded: expandedIds.contains(tool.id),
            onToggleExpand: { toggle(tool.id) }
        )
    }

    private func toggle(_ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedIds.contains(id) { expandedIds.remove(id) } else { expandedIds.insert(id) }
        }
    }

    private func exploreGroupSummary(_ items: [ToolCallItem]) -> String {
        if let running = items.last(where: \.isRunningLike) {
            return ToolRowPresentation.make(for: running, workspacePath: workspacePath).actionSummary
        }
        return ToolCallDisplayEntry.exploreSummary(items)
    }

    private func terminalGroupSummary(_ items: [ToolCallItem]) -> String {
        if let running = items.last(where: \.isRunningLike) {
            return "Running · \(ToolRowPresentation.singleLine(running.command ?? ""))"
        }
        var text = items.count == 1 ? "1 command" : "\(items.count) commands"
        let failed = items.filter(\.isFailed).count
        let stopped = items.filter { $0.rawStatus == "cancelled" }.count
        if failed > 0 { text += " · \(failed) failed" }
        if stopped > 0 { text += " · \(stopped) stopped" }
        return text
    }

    private func changesGroupSummary(_ items: [ToolCallItem]) -> String {
        let files = Set(items.compactMap(\.filePath))
        var text = files.isEmpty ? "\(items.count) tools" : (files.count == 1 ? "1 file" : "\(files.count) files")
        if let last = items.last {
            let verb = ToolRowPresentation.writeOperation(last).running
            let name = last.filePath.map { ($0 as NSString).lastPathComponent } ?? ""
            text += " · \(verb) \(name)"
        }
        return text
    }

    private func groupView(id: String, items: [ToolCallItem], icon: String, label: String, summary: String,
                           added: Int = 0, removed: Int = 0) -> some View {
        let isExpanded = expandedIds.contains(id)
        let isRunning = items.contains(where: \.isRunningLike)
        return VStack(alignment: .leading, spacing: 8) {
            Button { toggle(id) } label: {
                HStack(spacing: 8) {
                    ToolLeadingIcon(symbol: icon, isRunning: isRunning)
                    ToolKindLabel(text: label, isRunning: isRunning)
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !isExpanded {
                        ToolDiffCount(added: added, removed: removed)
                    }
                    ToolChevron(isExpanded: isExpanded)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toolGroup_\(id)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { tool in
                        row(tool, nested: true)
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle().fill(palette.border).frame(width: 1).padding(.leading, 8)
                }
            }
        }
    }
}

// MARK: - Shared row pieces (`ToolLayout`)

struct ToolLeadingIcon: View {
    let symbol: String
    let isRunning: Bool
    var tint: Color?
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        Group {
            if isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .tint(palette.foregroundSubtle)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(tint ?? palette.foregroundSubtle)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// Kind label: medium weight, subtlest colour; pulses while running.
struct ToolKindLabel: View {
    let text: String
    let isRunning: Bool
    @Environment(\.zcodePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(palette.foregroundMuted)
            .opacity(isRunning && !reduceMotion && pulse ? 0.45 : 1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(4)
            .onAppear { updatePulse() }
            .onChange(of: isRunning) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        guard isRunning, !reduceMotion else { pulse = false; return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
    }
}

struct ToolDiffCount: View {
    let added: Int
    let removed: Int
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        if added > 0 || removed > 0 {
            HStack(spacing: 4) {
                if added > 0 { Text("+\(added)").foregroundStyle(palette.success) }
                if removed > 0 { Text("-\(removed)").foregroundStyle(palette.destructive) }
            }
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .fixedSize()
            .layoutPriority(3)
        }
    }
}

struct ToolChevron: View {
    let isExpanded: Bool
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.foregroundMuted)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
    }
}

// MARK: - Single tool row

struct ToolCallRowView: View {
    @Bindable var store: AppStore
    let tool: ToolCallItem
    let workspacePath: String?
    var showIcon: Bool = true
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    @Environment(\.zcodePalette) private var palette

    private var family: ToolFamily { ToolFamily.of(tool) }
    private var presentation: ToolRowPresentation { ToolRowPresentation.make(for: tool, workspacePath: workspacePath) }

    var body: some View {
        if family == .subagentStandalone {
            Text(tool.standaloneSubagentLine ?? "")
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundSubtle)
                .lineLimit(2)
                .accessibilityIdentifier("toolRow_\(tool.id)")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded && presentation.canToggle {
                    ToolExpandedBody(store: store, tool: tool, family: family, workspacePath: workspacePath)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var header: some View {
        let p = presentation
        return Button(action: activate) {
            HStack(spacing: 7) {
                if showIcon {
                    ToolLeadingIcon(symbol: p.icon, isRunning: tool.isRunningLike,
                                    tint: tool.isFailed ? palette.destructive : nil)
                }
                if !p.kindLabel.isEmpty {
                    ToolKindLabel(text: p.kindLabel, isRunning: tool.isRunningLike)
                }
                kindDetailView(p)
                primaryView(p)
                if let secondary = p.secondary, !(isExpanded && p.hideSecondaryWhenOpen) {
                    Text(secondary)
                        .font(.system(size: 13.5, design: p.secondaryMonospaced ? .monospaced : .default))
                        .foregroundStyle(palette.foregroundMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }
                ToolDiffCount(added: tool.addedLines, removed: tool.removedLines)
                if tool.isFailed && p.showsFailedLabel {
                    Text("Failed")
                        .font(.system(size: 13.5))
                        .foregroundStyle(palette.destructive)
                        .underline(pattern: .dot, color: palette.destructive.opacity(0.6))
                        .fixedSize()
                }
                if p.canToggle {
                    ToolChevron(isExpanded: isExpanded)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .contextMenu { contextItems }
        .accessibilityIdentifier(family == .agent ? "openSubagentTool_\(tool.id)" : (p.filePath != nil ? "openToolFile_\(tool.id)" : "toolRow_\(tool.id)"))
    }

    @ViewBuilder
    private func kindDetailView(_ p: ToolRowPresentation) -> some View {
        switch p.kindDetail {
        case .agentChip(let name):
            Text(name)
                .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                .foregroundStyle(ToolRowPresentation.agentColor(name))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 144, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(3)
            if p.primary != nil {
                Text("·").foregroundStyle(palette.foregroundMuted)
            }
        case .text(let text):
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(palette.foregroundSubtle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            if p.primary != nil {
                Text("·").foregroundStyle(palette.foregroundMuted)
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func primaryView(_ p: ToolRowPresentation) -> some View {
        switch p.primary {
        case .file(let name, _):
            let icon = ToolFileIconSpec.forFileName(name)
            HStack(spacing: 5) {
                Image(systemName: icon.symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(icon.color ?? palette.foregroundSubtle)
                Text(name)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(2)
        case .text(let text, let mono):
            Text(text)
                .font(.system(size: 14, design: mono ? .monospaced : .default))
                .foregroundStyle(mono ? palette.foregroundMuted : palette.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(2)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var contextItems: some View {
        if let error = tool.errorText, tool.isFailed {
            Button {
                UIPasteboard.general.string = error
                store.showToast("Copied")
            } label: {
                Label("Copy error", systemImage: "doc.on.doc")
            }
        }
        if let path = presentation.filePath {
            Button {
                openFile(path)
            } label: {
                Label("Open file", systemImage: "doc.text")
            }
        }
        if family == .shell, let command = tool.command {
            Button {
                UIPasteboard.general.string = command
                store.showToast("Copied")
            } label: {
                Label("Copy command", systemImage: "terminal")
            }
        }
    }

    private var isInteractive: Bool {
        switch family {
        case .agent: return tool.subagentRunId != nil
        case .fileRead: return presentation.filePath != nil
        default: return presentation.canToggle
        }
    }

    private func activate() {
        switch family {
        case .agent:
            guard let child = tool.subagentRunId else { return }
            store.openSubagentSession(childSessionId: child, title: tool.agentDescription ?? tool.agentName ?? "Subagent")
        case .fileRead:
            if let path = presentation.filePath { openFile(path) }
        default:
            if presentation.canToggle { onToggleExpand() }
        }
    }

    private func openFile(_ path: String) {
        let lower = path.lowercased()
        let isVisual = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf", ".csv"].contains { lower.hasSuffix($0) }
        store.openFileInInspector(pathOrId: path, preferPreview: isVisual)
    }
}

// MARK: - Expanded bodies

struct ToolExpandedBody: View {
    @Bindable var store: AppStore
    let tool: ToolCallItem
    let family: ToolFamily
    let workspacePath: String?
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        switch family {
        case .fileWrite:
            VStack(alignment: .leading, spacing: 8) {
                if let patch = tool.diffPatch, !patch.isEmpty {
                    ToolDiffPreview(patch: patch, showLineNumbers: store.showLineNumbers)
                } else if let content = tool.contentPreview, !content.isEmpty {
                    ToolCodeBox(text: content, maxHeight: 240, showLineNumbers: store.showLineNumbers)
                } else if let input = tool.inputJSON {
                    ToolLabeledBlock(title: "Parameters", text: input, maxHeight: 240)
                }
                if let error = tool.errorText {
                    ToolLabeledBlock(title: "Error", text: error, maxHeight: 240, isError: true)
                }
            }
        case .shell:
            ToolShellPanel(command: tool.command ?? "", output: tool.output ?? tool.errorText, isRunning: tool.isRunningLike)
        case .todo:
            if let items = tool.todoItems {
                ToolTodoList(items: items)
            } else {
                genericBody(rawFallback: false)
            }
        case .askUser:
            ToolQuestionList(items: tool.questionAnswers ?? [])
        case .plan:
            if let plan = tool.planMarkdown {
                Text(LocalizedStringKey(plan))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.foregroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(palette.border).frame(width: 1) }
                    .padding(.leading, 6)
            } else {
                ToolLabeledBlock(title: tool.isFailed ? "Error" : "Result", text: tool.errorText ?? tool.output ?? "",
                                 maxHeight: 240, isError: tool.isFailed)
            }
        case .skill:
            ToolSkillPanel(name: tool.skillName ?? "Unknown skill", args: tool.skillArgs, output: tool.output, isRunning: tool.isRunningLike)
        case .mcp:
            ToolMCPBody(tool: tool)
        default:
            genericBody(rawFallback: true)
        }
    }

    private func genericBody(rawFallback: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let input = tool.inputJSON {
                ToolLabeledBlock(title: "Parameters", text: input, maxHeight: 240)
            }
            if let error = tool.errorText {
                ToolLabeledBlock(title: "Error", text: error, maxHeight: 240, isError: true)
            } else if let output = tool.output, !output.isEmpty {
                ToolLabeledBlock(title: "Result", text: output, maxHeight: 240)
            }
            if rawFallback, let raw = tool.rawJSON {
                ScrollView {
                    Text(raw)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .frame(maxHeight: 200)
                .fixedSize(horizontal: false, vertical: true)
                .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

/// `EditInlineDiffContent`: unified diff, 240pt box, sequential preview line numbers, 800-line cap.
struct ToolDiffPreview: View {
    let patch: String
    let showLineNumbers: Bool
    @Environment(\.zcodePalette) private var palette

    static let maxLines = 800

    var body: some View {
        let all = patch.components(separatedBy: "\n")
        let shown = all.count > Self.maxLines ? Array(all.prefix(Self.maxLines)) : all
        let omitted = all.count - shown.count
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                    diffRow(index: index, line: line)
                }
                if omitted > 0 {
                    Text("Diff preview truncated: \(omitted) lines omitted to keep UI responsive.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 240)
        .fixedSize(horizontal: false, vertical: true)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }

    private func diffRow(index: Int, line: String) -> some View {
        let marker = line.first
        let isHunk = line.hasPrefix("@@")
        let isAdded = !isHunk && marker == "+"
        let isRemoved = !isHunk && marker == "-"
        let code = isHunk ? line : (marker == "+" || marker == "-" || marker == " " ? String(line.dropFirst()) : line)
        let tint: Color? = isAdded ? palette.success : (isRemoved ? palette.destructive : nil)
        return HStack(spacing: 0) {
            Rectangle()
                .fill(tint ?? Color.clear)
                .frame(width: 3)
            if showLineNumbers {
                Text("\(index + 1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.foregroundMuted)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, 8)
            }
            Text(code.isEmpty ? " " : code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isHunk ? palette.foregroundMuted : palette.foreground)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, showLineNumbers ? 0 : 8)
                .padding(.trailing, 10)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .background(tint.map { $0.opacity(0.14) } ?? Color.clear)
    }
}

struct ToolCodeBox: View {
    let text: String
    let maxHeight: CGFloat
    var showLineNumbers: Bool = false
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        let lines = Array(text.components(separatedBy: "\n").prefix(ToolDiffPreview.maxLines))
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(spacing: 8) {
                        if showLineNumbers {
                            Text("\(index + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.foregroundMuted)
                                .frame(width: 36, alignment: .trailing)
                        }
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }
}

/// Generic `Parameters` / `Result` / `Error` block.
struct ToolLabeledBlock: View {
    let title: String
    let text: String
    let maxHeight: CGFloat
    var isError: Bool = false
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isError ? palette.destructive : palette.foregroundMuted)
            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isError ? palette.destructive : palette.foregroundSubtle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(isError ? palette.destructive.opacity(0.1) : palette.surfaceHover,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// Bash detail: `$ command` (3 lines, "Show full command" → 10 lines) and a 5-line auto-following output viewport.
struct ToolShellPanel: View {
    let command: String
    let output: String?
    let isRunning: Bool
    @Environment(\.zcodePalette) private var palette
    @State private var showFullCommand = false

    private static let lineHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text("$")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                    if showFullCommand {
                        ScrollView { commandText }
                            .frame(maxHeight: Self.lineHeight * 10)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        commandText.lineLimit(3)
                    }
                }
                if command.components(separatedBy: "\n").count > 3 || command.count > 160 {
                    Button(showFullCommand ? "Collapse" : "Show full command") {
                        withAnimation(.easeInOut(duration: 0.15)) { showFullCommand.toggle() }
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.accentBlue)
                    .buttonStyle(.plain)
                    .padding(.leading, 18)
                }
            }

            if let output, !output.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(output)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(palette.foregroundSubtle)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 1).id("bash-end")
                        }
                    }
                    .frame(maxHeight: Self.lineHeight * 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .onAppear { if isRunning { proxy.scrollTo("bash-end", anchor: .bottom) } }
                    .onChange(of: output.count) { _, _ in
                        if isRunning { proxy.scrollTo("bash-end", anchor: .bottom) }
                    }
                }
                .accessibilityIdentifier("bash-result-output")
            } else if !isRunning {
                Text("No output.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .accessibilityIdentifier("execute-detail")
    }

    private var commandText: some View {
        Text(command)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(palette.foreground)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ToolTodoList: View {
    let items: [TodoChecklistItem]
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    statusIcon(item.status)
                        .frame(width: 14, height: 18)
                    Text(item.content)
                        .font(.system(size: 14))
                        .foregroundStyle(item.status == "completed" ? palette.foregroundMuted
                                         : (item.status == "in_progress" ? palette.foreground : palette.foregroundSubtle))
                        .strikethrough(item.status == "completed", color: palette.foregroundMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func statusIcon(_ status: String) -> some View {
        switch status {
        case "completed":
            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.success)
        case "in_progress":
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(palette.foreground)
        default:
            Image(systemName: "circle").font(.system(size: 10)).foregroundStyle(palette.foregroundMuted)
        }
    }
}

struct ToolQuestionList: View {
    let items: [ToolQuestionAnswer]
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("No answer provided")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.foregroundSubtle)
            }
            ForEach(items, id: \.self) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.question)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.foreground)
                    Text(item.answer ?? "No answer provided")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) { Rectangle().fill(palette.border).frame(width: 1) }
        .padding(.leading, 8)
    }
}

struct ToolSkillPanel: View {
    let name: String
    let args: String?
    let output: String?
    let isRunning: Bool
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Skill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.foregroundMuted)
                Text(name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(palette.foreground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 6))
            }
            if let args, !args.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Args")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.foregroundMuted)
                    Text(args)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let output, !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                .fixedSize(horizontal: false, vertical: true)
            } else if !isRunning {
                Text("No output.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }
}

/// MCP expanded content: Result first, then a "View call details" disclosure (Description, Parameters).
struct ToolMCPBody: View {
    let tool: ToolCallItem
    @Environment(\.zcodePalette) private var palette
    @State private var showDetails = false
    @State private var wrapLines = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            result
            if tool.mcpDescription != nil || tool.inputJSON != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            ToolChevron(isExpanded: showDetails)
                            Text("View call details")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.foregroundSubtle)
                        }
                    }
                    .buttonStyle(.plain)
                    if showDetails {
                        if let description = tool.mcpDescription, !description.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(palette.foregroundMuted)
                                Text(description)
                                    .font(.system(size: 13))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let input = tool.inputJSON {
                            ToolLabeledBlock(title: "Parameters", text: input, maxHeight: 288)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("mcp-expanded-content")
    }

    @ViewBuilder
    private var result: some View {
        if let error = tool.errorText {
            VStack(alignment: .leading, spacing: 4) {
                Text("Result")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.destructive)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(palette.destructive.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        } else if tool.isRunningLike {
            Text(tool.status == .pendingApproval ? "Pending" : "Running")
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundMuted)
        } else if let output = tool.output, !output.isEmpty {
            let isJSON = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) != nil
            if isJSON {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 14) {
                        Text("Result")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.foregroundMuted)
                        Spacer()
                        Button { wrapLines.toggle() } label: { Image(systemName: "text.word.spacing") }
                            .accessibilityLabel("Wrap lines")
                        Button { UIPasteboard.general.string = output } label: { Image(systemName: "doc.on.doc") }
                            .accessibilityLabel("Copy result")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(palette.foregroundSubtle)
                    .buttonStyle(.plain)
                    ScrollView(wrapLines ? .vertical : [.vertical, .horizontal]) {
                        Text(output)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.foregroundSubtle)
                            .fixedSize(horizontal: !wrapLines, vertical: false)
                            .frame(maxWidth: wrapLines ? .infinity : nil, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 288)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Text(output)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineLimit(18)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mcp-result-surface")
            }
        }
    }
}

// MARK: - File icons

struct ToolFileIconSpec {
    let symbol: String
    let color: Color?

    static func forFileName(_ name: String) -> ToolFileIconSpec {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension

        switch ext {
        case "swift": return ToolFileIconSpec(symbol: "swift", color: Color(hex: 0xF05138))
        case "ts", "tsx", "mts", "cts": return ToolFileIconSpec(symbol: "chevron.left.forwardslash.chevron.right", color: Color(hex: 0x3178C6))
        case "js", "jsx", "mjs", "cjs": return ToolFileIconSpec(symbol: "curlybraces", color: Color(hex: 0xE8C547))
        case "json", "jsonc": return ToolFileIconSpec(symbol: "curlybraces.square", color: Color(hex: 0xD9A441))
        case "md", "markdown", "mdx": return ToolFileIconSpec(symbol: "doc.richtext", color: Color(hex: 0x58A6FF))
        case "py", "pyi": return ToolFileIconSpec(symbol: "chevron.left.forwardslash.chevron.right", color: Color(hex: 0x4B8BBE))
        case "rs": return ToolFileIconSpec(symbol: "gearshape", color: Color(hex: 0xDEA584))
        case "go": return ToolFileIconSpec(symbol: "chevron.left.forwardslash.chevron.right", color: Color(hex: 0x00ADD8))
        case "sh", "zsh", "bash", "fish": return ToolFileIconSpec(symbol: "terminal", color: Color(hex: 0x46BF72))
        case "yml", "yaml", "toml", "plist", "xml", "xcconfig": return ToolFileIconSpec(symbol: "list.bullet.indent", color: Color(hex: 0xA371F7))
        case "html", "htm": return ToolFileIconSpec(symbol: "globe", color: Color(hex: 0xE34C26))
        case "css", "scss", "sass", "less": return ToolFileIconSpec(symbol: "paintbrush", color: Color(hex: 0x38BDF8))
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "ico": return ToolFileIconSpec(symbol: "photo", color: Color(hex: 0xA855F7))
        case "pdf": return ToolFileIconSpec(symbol: "doc.text.fill", color: Color(hex: 0xEF4444))
        case "csv", "tsv": return ToolFileIconSpec(symbol: "tablecells", color: Color(hex: 0x34D399))
        case "c", "h", "cpp", "cc", "hpp", "m", "mm": return ToolFileIconSpec(symbol: "doc.text", color: Color(hex: 0x60A5FA))
        case "rb": return ToolFileIconSpec(symbol: "diamond", color: Color(hex: 0xCC342D))
        case "java", "kt", "kts": return ToolFileIconSpec(symbol: "cup.and.saucer", color: Color(hex: 0xF59E0B))
        case "sql": return ToolFileIconSpec(symbol: "cylinder", color: Color(hex: 0x60A5FA))
        default:
            if lower == "dockerfile" || lower.hasPrefix("dockerfile.") {
                return ToolFileIconSpec(symbol: "shippingbox", color: Color(hex: 0x2496ED))
            }
            return ToolFileIconSpec(symbol: "doc.text", color: nil)
        }
    }
}

// MARK: - Collapsed-row presentation per family

struct ToolRowPresentation {
    enum Primary {
        case file(name: String, path: String)
        case text(String, monospaced: Bool)
    }

    enum KindDetail {
        case agentChip(String)
        case text(String)
    }

    var icon: String
    var kindLabel: String
    var kindDetail: KindDetail? = nil
    var primary: Primary? = nil
    var secondary: String? = nil
    var secondaryMonospaced = false
    var hideSecondaryWhenOpen = false
    var canToggle: Bool
    var showsFailedLabel = true
    var filePath: String? = nil

    /// One-line "what is happening" text used by running groups (`T7t`→`w7t`).
    var actionSummary: String {
        let target: String = {
            switch primary {
            case .file(let name, _): return name
            case .text(let text, _): return text
            case nil: return secondary ?? ""
            }
        }()
        return [kindLabel, target].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func make(for tool: ToolCallItem, workspacePath: String?) -> ToolRowPresentation {
        let running = tool.isRunningLike
        switch ToolFamily.of(tool) {
        case .fileRead:
            let path = tool.filePath ?? ""
            return ToolRowPresentation(
                icon: "doc.text",
                kindLabel: running ? "Reading" : "Read",
                primary: path.isEmpty ? nil : .file(name: (path as NSString).lastPathComponent, path: path),
                secondary: path.isEmpty ? nil : relativePath(path, workspacePath: workspacePath),
                canToggle: false,
                filePath: path.isEmpty ? nil : path
            )

        case .fileWrite:
            let path = tool.filePath ?? ""
            let op = writeOperation(tool)
            return ToolRowPresentation(
                icon: "pencil",
                kindLabel: running ? op.running : op.done,
                primary: path.isEmpty ? nil : .file(name: (path as NSString).lastPathComponent, path: path),
                secondary: path.isEmpty ? nil : relativePath(path, workspacePath: workspacePath),
                canToggle: true,
                filePath: path.isEmpty ? nil : path
            )

        case .shell:
            let command = singleLine(tool.command ?? "")
            return ToolRowPresentation(
                icon: "terminal",
                kindLabel: running ? "Running" : "Terminal",
                secondary: command.isEmpty ? nil : command,
                hideSecondaryWhenOpen: true,
                canToggle: true
            )

        case .search:
            let name = (tool.toolName ?? "").lowercased()
            let isToolSearch = name == "toolsearch" || name == "localtoolsearch"
            return ToolRowPresentation(
                icon: "magnifyingglass",
                kindLabel: isToolSearch ? "" : (running ? "Searching" : "Search"),
                primary: .text(singleLine(tool.searchLabel ?? "Find"), monospaced: false),
                canToggle: false
            )

        case .webFetch:
            let url = tool.webURL ?? ""
            return ToolRowPresentation(
                icon: "globe",
                kindLabel: running ? "Fetching" : "Fetch",
                primary: url.isEmpty ? nil : .text(url, monospaced: false),
                canToggle: false
            )

        case .todo:
            let items = tool.todoItems ?? []
            let current = items.first(where: { $0.status == "in_progress" })
                ?? items.first(where: { $0.status != "completed" })
                ?? items.last
            let done = items.filter { $0.status == "completed" }.count
            return ToolRowPresentation(
                icon: "checklist",
                kindLabel: "Todo",
                primary: .text(current?.content ?? "Current task", monospaced: false),
                secondary: items.isEmpty ? nil : "\(done)/\(items.count)",
                secondaryMonospaced: true,
                canToggle: true
            )

        case .agent:
            let description = tool.agentDescription ?? tool.agentName ?? "SubAgent"
            return ToolRowPresentation(
                icon: "person.2",
                kindLabel: "SubAgent",
                kindDetail: tool.agentName.map { .agentChip($0) },
                primary: .text(singleLine(description), monospaced: false),
                canToggle: false
            )

        case .askUser:
            let count = tool.questionAnswers?.count ?? 0
            return ToolRowPresentation(
                icon: "questionmark.bubble",
                kindLabel: running ? "Asking questions" : "Asked",
                secondary: running ? nil : "\(count) questions",
                canToggle: !running
            )

        case .plan:
            return ToolRowPresentation(
                icon: "list.bullet.clipboard",
                kindLabel: "Entered plan mode",
                canToggle: tool.planMarkdown != nil || tool.output?.isEmpty == false || tool.errorText != nil
            )

        case .skill:
            return ToolRowPresentation(
                icon: "sparkles",
                kindLabel: running ? "Running skill" : "Skill",
                primary: .text(tool.skillName ?? "Skill", monospaced: true),
                secondary: tool.skillArgs.map(singleLine),
                secondaryMonospaced: true,
                canToggle: true
            )

        case .mcp:
            let server = humanize(tool.mcpServer ?? "")
            var toolLabel = humanize(tool.mcpTool ?? (tool.toolName ?? ""))
            if !server.isEmpty, toolLabel.hasPrefix(server + " ") { toolLabel = String(toolLabel.dropFirst(server.count + 1)) }
            let statusText: String? = tool.rawStatus == "cancelled" ? "· Stopped" : (tool.isFailed ? "· Failed" : nil)
            return ToolRowPresentation(
                icon: "puzzlepiece.extension",
                kindLabel: "MCP",
                kindDetail: server.isEmpty ? nil : .text(server),
                primary: .text(toolLabel, monospaced: false),
                secondary: statusText,
                canToggle: !(tool.status == .pendingApproval || tool.rawStatus == "inputStreaming" || tool.rawStatus == "cancelled"),
                showsFailedLabel: false
            )

        case .subagentStandalone, .generic:
            let name = (tool.toolName ?? tool.title).trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? "Tool" : name.prefix(1).uppercased() + name.dropFirst()
            return ToolRowPresentation(
                icon: "wrench.and.screwdriver",
                kindLabel: label,
                canToggle: true,
                filePath: tool.filePath
            )
        }
    }

    /// `WZ`: Write → Writing/Write, Edit-like → Editing/Edit, deleting patches → Deleting/Delete.
    static func writeOperation(_ tool: ToolCallItem) -> (running: String, done: String) {
        let name = (tool.toolName ?? "").lowercased()
        if name == "write" { return ("Writing", "Write") }
        if name.contains("patch"), let input = tool.inputJSON?.lowercased(), input.contains("*** delete file") {
            return ("Deleting", "Delete")
        }
        return ("Editing", "Edit")
    }

    /// `X5t`: deterministic colour for the agent name chip (yellow/red/orange/green/cyan/blue/purple/pink).
    static func agentColor(_ name: String) -> Color {
        let colors: [Color] = [
            Color(hex: 0xCA8A04), Color(hex: 0xDC2626), Color(hex: 0xEA580C), Color(hex: 0x16A34A),
            Color(hex: 0x0891B2), Color(hex: 0x2563EB), Color(hex: 0x9333EA), Color(hex: 0xDB2777)
        ]
        var hash: UInt32 = 0
        for scalar in name.unicodeScalars { hash = hash &* 31 &+ scalar.value }
        return colors[Int(hash % UInt32(colors.count))]
    }

    /// `EC`: title-cases words, normalising `-` / `_`.
    static func humanize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "plugin:", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func relativePath(_ path: String, workspacePath: String?) -> String {
        guard let ws = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !ws.isEmpty else { return path }
        let root = ws.hasSuffix("/") ? String(ws.dropLast()) : ws
        if path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        return path
    }

    static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
