import SwiftUI

// MARK: - Tool Call List (With Consecutive Read-Only Explore Grouping)

struct ToolCallListView: View {
    @Bindable var store: AppStore
    let tools: [ToolCallItem]
    let workspacePath: String?

    @Environment(\.zcodePalette) private var palette
    @State private var expandedToolIds: Set<String> = []
    @State private var expandedGroupIds: Set<String> = []

    private var entries: [ToolCallDisplayEntry] {
        ToolCallDisplayEntry.group(tools)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
                switch entry {
                case .single(let tool):
                    ToolCallRowView(
                        store: store,
                        tool: tool,
                        workspacePath: workspacePath,
                        isExpanded: expandedToolIds.contains(tool.id),
                        onToggleExpand: { toggleTool(tool.id) }
                    )

                case .exploreGroup(let id, let items, let searchCount, let fileCount):
                    exploreGroupView(
                        groupId: id,
                        items: items,
                        searchCount: searchCount,
                        fileCount: fileCount
                    )
                }
            }
        }
    }

    private func toggleTool(_ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedToolIds.contains(id) {
                expandedToolIds.remove(id)
            } else {
                expandedToolIds.insert(id)
            }
        }
    }

    private func toggleGroup(_ id: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if expandedGroupIds.contains(id) {
                expandedGroupIds.remove(id)
            } else {
                expandedGroupIds.insert(id)
            }
        }
    }

    private func exploreGroupView(
        groupId: String,
        items: [ToolCallItem],
        searchCount: Int,
        fileCount: Int
    ) -> some View {
        let isExpanded = expandedGroupIds.contains(groupId)
        let isRunning = items.contains { $0.status == .running }
        let hasFailure = !isRunning && items.contains { $0.status == .failed }
        let summary = ToolCallDisplayEntry.exploreSummary(searchCount: searchCount, fileCount: fileCount)

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                toggleGroup(groupId)
            } label: {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(palette.foregroundSubtle)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13.5, weight: .light))
                            .foregroundStyle(hasFailure ? palette.destructive : palette.foregroundMuted)
                            .frame(width: 16, height: 16)
                    }

                    Text("Explore")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(hasFailure ? palette.destructive : palette.foregroundSubtle)
                        .fixedSize(horizontal: true, vertical: false)

                    Text("·")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.foregroundMuted)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(summary)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(palette.foregroundMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isExpanded {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.foregroundMuted)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exploreToolGroup_\(groupId)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { tool in
                        ToolCallRowView(
                            store: store,
                            tool: tool,
                            workspacePath: workspacePath,
                            isExpanded: expandedToolIds.contains(tool.id),
                            onToggleExpand: { toggleTool(tool.id) }
                        )
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(palette.border)
                        .frame(width: 1.5)
                        .padding(.leading, 7)
                        .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Single Official Compact Tool Call Row

struct ToolCallRowView: View {
    @Bindable var store: AppStore
    let tool: ToolCallItem
    let workspacePath: String?
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    @Environment(\.zcodePalette) private var palette

    private var presentation: ToolRowPresentation {
        ToolRowPresentation.make(for: tool, workspacePath: workspacePath)
    }

    private var hasExpandableDetails: Bool {
        if let diff = tool.diffPatch, !diff.isEmpty { return true }
        if let out = tool.output, !out.isEmpty { return true }
        if !tool.subagentSteps.isEmpty { return true }
        if presentation.category == .terminal, let cmd = tool.command, !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    private var verbColor: Color {
        switch tool.status {
        case .failed:
            return palette.destructive
        case .pendingApproval:
            return palette.warning
        case .running, .completed:
            return palette.foregroundSubtle
        }
    }

    private var leadingIconColor: Color {
        switch tool.status {
        case .failed:
            return palette.destructive
        case .pendingApproval:
            return palette.warning
        case .running, .completed:
            return palette.foregroundMuted
        }
    }

    var body: some View {
        if presentation.category == .subagent {
            subagentRow
        } else {
            VStack(alignment: .leading, spacing: 6) {
                compactRowButton
                if isExpanded && hasExpandableDetails {
                    expandedDetailPanel
                }
            }
        }
    }

    // MARK: - SubAgent Row

    private var subagentRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if tool.subagentRunId != nil {
                    store.openSubagentInspector(tool.subagentRunId)
                } else if hasExpandableDetails {
                    onToggleExpand()
                }
            } label: {
                HStack(spacing: 8) {
                    if tool.status == .running {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(palette.foregroundSubtle)
                            .frame(width: 16, height: 16)
                    } else {
                        ZCodeRobotIconView(size: 14, color: leadingIconColor)
                            .frame(width: 16, height: 16)
                    }

                    Text("SubAgent")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(verbColor)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(tool.title)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(palette.foregroundMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openSubagentTool_\(tool.id)")

            if isExpanded && hasExpandableDetails {
                expandedDetailPanel
            }
        }
    }

    // MARK: - Compact Single-Line Row (No Card, Official ZCode Style)

    private var compactRowButton: some View {
        Button {
            if hasExpandableDetails {
                onToggleExpand()
            } else if let path = presentation.inspectableFilePath {
                openFileInInspector(path)
            }
        } label: {
            HStack(spacing: 7) {
                leadingIconView

                Text(presentation.verb)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(verbColor)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(4)

                switch presentation.content {
                case .file(let fileName, let parentPath, let icon):
                    HStack(spacing: 5) {
                        Image(systemName: icon.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(icon.color ?? palette.foregroundSubtle)
                            .fixedSize()

                        Text(fileName)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .layoutPriority(2)

                    if let parentPath, !parentPath.isEmpty {
                        Text(parentPath)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foregroundMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                    }

                case .command(let commandText):
                    if !commandText.isEmpty {
                        Text(commandText)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foregroundMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                    }

                case .query(let primary, let secondary):
                    if !primary.isEmpty {
                        Text(primary)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(2)
                    }
                    if let secondary, !secondary.isEmpty {
                        Text(secondary)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foregroundMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                    }
                }

                if tool.addedLines > 0 || tool.removedLines > 0 {
                    HStack(spacing: 5) {
                        if tool.addedLines > 0 {
                            Text("+\(tool.addedLines)")
                                .foregroundStyle(palette.success)
                        }
                        if tool.removedLines > 0 {
                            Text("-\(tool.removedLines)")
                                .foregroundStyle(palette.destructive)
                        }
                    }
                    .font(.system(size: 13.5, weight: .regular, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(3)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            presentation.inspectableFilePath != nil ? "openToolFile_\(tool.id)" : "toolRow_\(tool.id)"
        )
    }

    @ViewBuilder
    private var leadingIconView: some View {
        if tool.status == .running {
            ProgressView()
                .controlSize(.mini)
                .tint(palette.foregroundSubtle)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: presentation.leadingSymbol)
                .font(.system(size: 13.5, weight: .light))
                .foregroundStyle(leadingIconColor)
                .frame(width: 16, height: 16)
        }
    }

    // MARK: - Expanded Details Panel

    private var expandedDetailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let path = presentation.inspectableFilePath {
                HStack(spacing: 8) {
                    Text(path)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.foregroundMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Button {
                        openFileInInspector(path)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open")
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(palette.foregroundSubtle)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(palette.header)
            } else if presentation.category == .terminal,
                      let cmd = tool.command?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !cmd.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("$ \(cmd)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        UIPasteboard.general.string = cmd
                        store.showToast("Copied command")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(palette.header)
            }

            if let patch = tool.diffPatch, !patch.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(patch.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(diffLineColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1.5)
                                .background(diffLineBackground(line))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let out = tool.output, !out.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(out)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(tool.status == .failed ? palette.destructive : palette.foregroundSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }

            if !tool.subagentSteps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tool.subagentSteps, id: \.self) { step in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(palette.foregroundMuted)
                                .frame(width: 4, height: 4)
                            Text(step)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.foregroundSubtle)
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }

    private func openFileInInspector(_ path: String) {
        let lower = path.lowercased()
        let isVisual = lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".pdf") || lower.hasSuffix(".csv")
        store.openFileInInspector(pathOrId: path, preferPreview: isVisual)
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return palette.success }
        if line.hasPrefix("-") { return palette.destructive }
        if line.hasPrefix("@@") { return palette.info }
        return palette.foregroundSubtle
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") { return palette.success.opacity(0.10) }
        if line.hasPrefix("-") { return palette.destructive.opacity(0.10) }
        return Color.clear
    }
}

// MARK: - Grouping & Presentation Helpers

enum ToolCallDisplayEntry: Identifiable {
    case single(ToolCallItem)
    case exploreGroup(id: String, items: [ToolCallItem], searchCount: Int, fileCount: Int)

    var id: String {
        switch self {
        case .single(let item):
            return item.id
        case .exploreGroup(let id, _, _, _):
            return id
        }
    }

    private enum ExploreBucket {
        case file
        case search
    }

    static func group(_ tools: [ToolCallItem]) -> [ToolCallDisplayEntry] {
        var result: [ToolCallDisplayEntry] = []
        var pending: [(ToolCallItem, ExploreBucket)] = []

        func flushPending() {
            guard !pending.isEmpty else { return }
            if pending.count == 1 {
                result.append(.single(pending[0].0))
            } else {
                let searchCount = pending.filter { $0.1 == .search }.count
                let fileCount = pending.filter { $0.1 == .file }.count
                let groupId = "explore-\(pending[0].0.id)"
                result.append(
                    .exploreGroup(
                        id: groupId,
                        items: pending.map(\.0),
                        searchCount: searchCount,
                        fileCount: fileCount
                    )
                )
            }
            pending.removeAll(keepingCapacity: true)
        }

        for tool in tools {
            if let bucket = exploreBucket(for: tool) {
                pending.append((tool, bucket))
            } else {
                flushPending()
                result.append(.single(tool))
            }
        }
        flushPending()
        return result
    }

    static func exploreSummary(searchCount: Int, fileCount: Int) -> String {
        var parts: [String] = []
        if searchCount > 0 {
            parts.append(searchCount == 1 ? "1 search" : "\(searchCount) searches")
        }
        if fileCount > 0 {
            parts.append(fileCount == 1 ? "1 file" : "\(fileCount) files")
        }
        return parts.joined(separator: ", ")
    }

    private static func exploreBucket(for tool: ToolCallItem) -> ExploreBucket? {
        let category = ToolRowPresentation.classify(tool)
        switch category {
        case .read:
            return .file
        case .search, .list:
            return .search
        case .edit, .write, .terminal, .mcp, .subagent, .workflow, .other:
            return nil
        }
    }
}

struct ToolFileIconSpec {
    let symbol: String
    let color: Color?

    static func forFileName(_ name: String) -> ToolFileIconSpec {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension

        switch ext {
        case "swift":
            return ToolFileIconSpec(symbol: "swift", color: Color(hex: 0xF05138))
        case "ts", "tsx", "mts", "cts":
            return ToolFileIconSpec(symbol: "chevron.left.forwardslash.chevron.right", color: Color(hex: 0x3178C6))
        case "js", "jsx", "mjs", "cjs":
            return ToolFileIconSpec(symbol: "curlybraces", color: Color(hex: 0xE8C547))
        case "json", "jsonc":
            return ToolFileIconSpec(symbol: "curlybraces.square", color: Color(hex: 0xD9A441))
        case "md", "markdown", "mdx":
            return ToolFileIconSpec(symbol: "doc.richtext", color: Color(hex: 0x58A6FF))
        case "py", "pyi":
            return ToolFileIconSpec(symbol: "chevron.left.forwardslash.chevron.right", color: Color(hex: 0x4B8BBE))
        case "rs":
            return ToolFileIconSpec(symbol: "gearshape", color: Color(hex: 0xDEA584))
        case "go":
            return ToolFileIconSpec(symbol: "chevron.left.forwardslash.chevron.right", color: Color(hex: 0x00ADD8))
        case "sh", "zsh", "bash", "fish":
            return ToolFileIconSpec(symbol: "terminal", color: Color(hex: 0x46BF72))
        case "yml", "yaml", "toml", "plist", "xml", "xcconfig":
            return ToolFileIconSpec(symbol: "list.bullet.indent", color: Color(hex: 0xA371F7))
        case "html", "htm":
            return ToolFileIconSpec(symbol: "globe", color: Color(hex: 0xE34C26))
        case "css", "scss", "sass", "less":
            return ToolFileIconSpec(symbol: "paintbrush", color: Color(hex: 0x38BDF8))
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "ico":
            return ToolFileIconSpec(symbol: "photo", color: Color(hex: 0xA855F7))
        case "pdf":
            return ToolFileIconSpec(symbol: "doc.text.fill", color: Color(hex: 0xEF4444))
        case "csv", "tsv":
            return ToolFileIconSpec(symbol: "tablecells", color: Color(hex: 0x34D399))
        case "c", "h", "cpp", "cc", "hpp", "m", "mm":
            return ToolFileIconSpec(symbol: "doc.text", color: Color(hex: 0x60A5FA))
        case "rb":
            return ToolFileIconSpec(symbol: "diamond", color: Color(hex: 0xCC342D))
        case "java", "kt", "kts":
            return ToolFileIconSpec(symbol: "cup.and.saucer", color: Color(hex: 0xF59E0B))
        case "sql":
            return ToolFileIconSpec(symbol: "cylinder", color: Color(hex: 0x60A5FA))
        default:
            if lower == "dockerfile" || lower.hasPrefix("dockerfile.") {
                return ToolFileIconSpec(symbol: "shippingbox", color: Color(hex: 0x2496ED))
            }
            return ToolFileIconSpec(symbol: "doc.text", color: nil)
        }
    }
}

struct ToolRowPresentation {
    enum Category {
        case read
        case edit
        case write
        case terminal
        case search
        case list
        case mcp
        case subagent
        case workflow
        case other
    }

    enum Content {
        case file(fileName: String, parentPath: String?, icon: ToolFileIconSpec)
        case command(String)
        case query(primary: String, secondary: String?)
    }

    let category: Category
    let leadingSymbol: String
    let verb: String
    let content: Content
    let inspectableFilePath: String?

    static func classify(_ tool: ToolCallItem) -> Category {
        let raw = tool.toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lower = raw.lowercased()

        if tool.kind == .subagent || lower == "task" || lower == "agent" || lower == "subagent" {
            return .subagent
        }
        if tool.kind == .workflow {
            return .workflow
        }
        if lower.hasPrefix("mcp__") || lower.contains("__") || tool.kind == .mcp {
            return .mcp
        }
        if tool.kind == .bash || lower == "bash" || lower == "terminal" || lower == "execute" || lower == "shell" || lower == "run_command" {
            return .terminal
        }
        if lower == "write" || lower == "write_file" || lower == "writefile" || lower == "create_file" {
            return .write
        }
        if lower == "edit" || lower == "multiedit" || lower == "edit_file" || lower == "notebookedit" || lower == "apply_patch" || lower == "str_replace_editor" {
            return .edit
        }
        if lower == "read" || lower == "read_file" || lower == "readfile" || lower == "view" || lower == "view_file" || lower == "notebookread" {
            return .read
        }
        if lower == "ls" || lower == "list" || lower == "list_dir" || lower == "list_files" {
            return .list
        }
        if lower == "grep" || lower == "glob" || lower == "search" || lower == "websearch" || lower == "webfetch" || lower == "ripgrep" || lower == "find" || lower == "find_files" || lower == "search_files" || lower == "codebase_search" {
            return .search
        }

        switch tool.kind {
        case .readFile: return .read
        case .editFile: return .edit
        case .writeFile: return .write
        case .bash: return .terminal
        case .search: return .search
        case .mcp: return .mcp
        case .subagent: return .subagent
        case .workflow: return .workflow
        }
    }

    static func make(for tool: ToolCallItem, workspacePath: String?) -> ToolRowPresentation {
        let category = classify(tool)

        switch category {
        case .read:
            let path = resolvedFilePath(for: tool, stripPrefixes: ["Read ", "View "])
            let (name, parent) = splitPath(path, workspacePath: workspacePath)
            return ToolRowPresentation(
                category: .read,
                leadingSymbol: "magnifyingglass",
                verb: "Read",
                content: .file(fileName: name, parentPath: parent, icon: ToolFileIconSpec.forFileName(name)),
                inspectableFilePath: tool.filePath ?? (path.contains("/") || path.contains(".") ? path : nil)
            )

        case .edit:
            let path = resolvedFilePath(for: tool, stripPrefixes: ["Edit ", "MultiEdit ", "Patch "])
            let (name, parent) = splitPath(path, workspacePath: workspacePath)
            return ToolRowPresentation(
                category: .edit,
                leadingSymbol: "pencil",
                verb: "Edit",
                content: .file(fileName: name, parentPath: parent, icon: ToolFileIconSpec.forFileName(name)),
                inspectableFilePath: tool.filePath ?? (path.contains("/") || path.contains(".") ? path : nil)
            )

        case .write:
            let path = resolvedFilePath(for: tool, stripPrefixes: ["Write ", "Create "])
            let (name, parent) = splitPath(path, workspacePath: workspacePath)
            return ToolRowPresentation(
                category: .write,
                leadingSymbol: "pencil",
                verb: "Write",
                content: .file(fileName: name, parentPath: parent, icon: ToolFileIconSpec.forFileName(name)),
                inspectableFilePath: tool.filePath ?? (path.contains("/") || path.contains(".") ? path : nil)
            )

        case .terminal:
            let cmd = resolvedCommandText(for: tool)
            return ToolRowPresentation(
                category: .terminal,
                leadingSymbol: "terminal",
                verb: "Terminal",
                content: .command(cmd),
                inspectableFilePath: nil
            )

        case .search:
            let queryText = resolvedSearchText(for: tool, workspacePath: workspacePath)
            return ToolRowPresentation(
                category: .search,
                leadingSymbol: "magnifyingglass",
                verb: "Search",
                content: .query(primary: queryText.primary, secondary: queryText.secondary),
                inspectableFilePath: tool.filePath
            )

        case .list:
            let path = tool.filePath ?? (tool.subtitle.isEmpty ? tool.title : tool.subtitle)
            let formatted = formatDirectory(path, workspacePath: workspacePath)
            return ToolRowPresentation(
                category: .list,
                leadingSymbol: "magnifyingglass",
                verb: "List",
                content: .query(primary: formatted, secondary: nil),
                inspectableFilePath: nil
            )

        case .mcp:
            let label = formattedMCPName(for: tool)
            let secondary = tool.subtitle.isEmpty || tool.subtitle == label ? nil : singleLine(tool.subtitle)
            return ToolRowPresentation(
                category: .mcp,
                leadingSymbol: "puzzlepiece.extension",
                verb: "MCP",
                content: .query(primary: label, secondary: secondary),
                inspectableFilePath: tool.filePath
            )

        case .subagent:
            return ToolRowPresentation(
                category: .subagent,
                leadingSymbol: "person.2",
                verb: "SubAgent",
                content: .query(primary: tool.title, secondary: nil),
                inspectableFilePath: nil
            )

        case .workflow:
            return ToolRowPresentation(
                category: .workflow,
                leadingSymbol: "point.3.connected.trianglepath.dotted",
                verb: "Workflow",
                content: .query(primary: tool.title, secondary: tool.subtitle.isEmpty ? nil : singleLine(tool.subtitle)),
                inspectableFilePath: tool.filePath
            )

        case .other:
            let verb = tool.toolName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Tool"
            let target = tool.subtitle.isEmpty ? (tool.title == verb ? "" : tool.title) : singleLine(tool.subtitle)
            return ToolRowPresentation(
                category: .other,
                leadingSymbol: "wrench",
                verb: verb,
                content: .query(primary: target, secondary: nil),
                inspectableFilePath: tool.filePath
            )
        }
    }

    private static func resolvedFilePath(for tool: ToolCallItem, stripPrefixes: [String]) -> String {
        if let filePath = tool.filePath?.trimmingCharacters(in: .whitespacesAndNewlines), !filePath.isEmpty {
            return filePath
        }
        var candidate = tool.title.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in stripPrefixes {
            if candidate.hasPrefix(prefix) {
                candidate = String(candidate.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        if candidate.isEmpty, !tool.subtitle.isEmpty {
            return tool.subtitle
        }
        return candidate
    }

    private static func resolvedCommandText(for tool: ToolCallItem) -> String {
        if let cmd = tool.command?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
            return singleLine(cmd)
        }
        let sub = tool.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sub.isEmpty {
            return singleLine(sub)
        }
        let title = tool.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = title.lowercased()
        if lower == "bash" || lower == "terminal" || lower == "execute" || lower == "shell" || lower == "tool" {
            return ""
        }
        return singleLine(title)
    }

    private static func resolvedSearchText(for tool: ToolCallItem, workspacePath: String?) -> (primary: String, secondary: String?) {
        let sub = singleLine(tool.subtitle)
        let title = singleLine(tool.title)
        let lowerTitle = title.lowercased()
        let genericTitle = ["grep", "glob", "search", "websearch", "webfetch", "find", "tool"].contains(lowerTitle)

        if let path = tool.filePath, !path.isEmpty {
            let dir = formatDirectory(path, workspacePath: workspacePath)
            if !sub.isEmpty && sub != path {
                return (sub, dir)
            }
            if !genericTitle && title != path {
                return (title, dir)
            }
            return (dir, nil)
        }

        if !sub.isEmpty {
            return (sub, nil)
        }
        return (genericTitle ? "" : title, nil)
    }

    private static func formattedMCPName(for tool: ToolCallItem) -> String {
        let raw = (tool.toolName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? tool.title
        if raw.lowercased().hasPrefix("mcp__") {
            let trimmed = String(raw.dropFirst(5))
            let parts = trimmed.components(separatedBy: "__").filter { !$0.isEmpty }
            if parts.count >= 2 {
                return "\(parts[0]) · \(parts.dropFirst().joined(separator: "_"))"
            }
            return trimmed
        }
        return singleLine(raw)
    }

    private static func splitPath(_ rawPath: String, workspacePath: String?) -> (fileName: String, parentPath: String?) {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("file", nil) }

        let ns = trimmed as NSString
        let fileName = ns.lastPathComponent.isEmpty ? trimmed : ns.lastPathComponent
        let dir = ns.deletingLastPathComponent
        if dir.isEmpty || dir == "." || dir == "/" {
            return (fileName, nil)
        }
        return (fileName, formatDirectory(dir, workspacePath: workspacePath))
    }

    private static func formatDirectory(_ dir: String, workspacePath: String?) -> String {
        let normalizedDir = dir.hasSuffix("/") && dir.count > 1 ? String(dir.dropLast()) : dir

        if let ws = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !ws.isEmpty {
            let normWs = ws.hasSuffix("/") && ws.count > 1 ? String(ws.dropLast()) : ws
            let wsName = (normWs as NSString).lastPathComponent
            if normalizedDir == normWs {
                return wsName.isEmpty ? normalizedDir : wsName
            }
            if normalizedDir.hasPrefix(normWs + "/") {
                let rel = String(normalizedDir.dropFirst(normWs.count + 1))
                return wsName.isEmpty ? rel : "\(wsName)/\(rel)"
            }
        }

        if normalizedDir.hasPrefix("/") {
            let comps = normalizedDir.split(separator: "/").map(String.init)
            if comps.count > 3 {
                return comps.suffix(3).joined(separator: "/")
            }
            return comps.joined(separator: "/")
        }
        return normalizedDir
    }

    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

