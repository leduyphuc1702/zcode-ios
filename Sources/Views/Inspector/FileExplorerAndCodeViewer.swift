import SwiftUI

public struct FileExplorerAndCodeViewer: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @State private var showFileTreeDrawer: Bool = false
    @State private var expandedDirIds: Set<String> = ["dir-src", "dir-src-rpc", "dir-assets"]
    @State private var inFileSearch: String = ""
    @State private var showSearchField: Bool = false
    @State private var commentingLineNumber: Int?
    @State private var commentDraft: String = ""

    private var currentFile: WorkspaceFileNode? {
        store.selectedFile
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Open File Tabs + File Tree Toggle Bar
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showFileTreeDrawer.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Tree")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(showFileTreeDrawer ? palette.accentBlue : palette.foreground)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toggleFileTreeButton")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(store.flattenedFiles.filter { store.openFileIds.contains($0.id) }) { file in
                            let active = file.id == store.selectedFileId
                            Button {
                                store.selectedFileId = file.id
                                if file.kind == .image || file.kind == .pdf {
                                    store.activeInspectorTab = .preview
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: fileIcon(file.kind))
                                        .font(.system(size: 11))
                                        .foregroundStyle(active ? palette.accentBlue : palette.foregroundSubtle)
                                    Text(file.name)
                                        .font(.system(size: 12, weight: active ? .semibold : .regular, design: .monospaced))
                                        .foregroundStyle(active ? palette.foreground : palette.foregroundSubtle)
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 30)
                                .background(active ? palette.card : palette.surfaceHover, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(active ? palette.borderStrong : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("openFileTab_\(file.id)")
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(palette.panel)

            Rectangle().fill(palette.border).frame(height: 1)

            // Collapsible File Tree Explorer (Scrollable for deep workspaces)
            if showFileTreeDrawer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.fileTree) { node in
                            fileTreeNodeRow(node, depth: 0)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 205)
                .background(palette.panel)
                Rectangle().fill(palette.border).frame(height: 1)
            }

            // Code Viewer Toolbar (Path, Search, Font Zoom, Wrap, Syntax Palette, Preview Switch)
            if let file = currentFile {
                HStack(spacing: 8) {
                    Text(file.path)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if file.kind == .image || file.kind == .pdf || file.kind == .markdown || file.kind == .csv {
                        Button {
                            store.activeInspectorTab = .preview
                        } label: {
                            Label("Preview", systemImage: "eye.fill")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.accentBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(palette.accentBlue.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("switchToVisualPreviewButton")
                    }

                    Button {
                        showSearchField.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12.5))
                            .foregroundStyle(showSearchField ? palette.accentBlue : palette.foregroundSubtle)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("codeSearchToggleButton")

                    Button {
                        store.wrapCodeLines.toggle()
                    } label: {
                        Image(systemName: "text.word.spacing")
                            .font(.system(size: 12.5))
                            .foregroundStyle(store.wrapCodeLines ? palette.accentBlue : palette.foregroundSubtle)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Section("Syntax Theme") {
                            ForEach(ZCodeSyntaxTheme.allCases) { st in
                                Button(st.displayName) {
                                    store.syntaxTheme = st
                                }
                            }
                        }
                        Section("Font Size (\(Int(store.codeFontSize))pt)") {
                            Button("Increase Font (+)") { store.codeFontSize = min(22, store.codeFontSize + 1) }
                            Button("Decrease Font (-)") { store.codeFontSize = max(10, store.codeFontSize - 1) }
                            Button(store.showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers") {
                                store.showLineNumbers.toggle()
                            }
                        }
                    } label: {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 28, height: 28)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(palette.header)

                if showSearchField {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.foregroundSubtle)
                        TextField("Find in \(file.name)...", text: $inFileSearch)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !inFileSearch.isEmpty {
                            Button("Clear") { inFileSearch = "" }
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.accentBlue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(palette.inputBackground)
                }

                Rectangle().fill(palette.border).frame(height: 1)

                // Body: If binary image/PDF, offer direct jump to Visual Viewer; otherwise render syntax-highlighted lines
                if let codeText = file.textContent {
                    codeLinesView(file: file, text: codeText)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: file.kind == .pdf ? "doc.richtext.fill" : "photo.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(palette.accentBlue)
                        Text("\(file.name) is a binary media asset (\(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file)))")
                            .font(.system(size: 13.5))
                            .foregroundStyle(palette.foregroundSubtle)
                        Button {
                            store.activeInspectorTab = .preview
                        } label: {
                            Text("Open in Native Visual Viewer")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.brandForeground)
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .background(palette.brand, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert("Add Inline Code Comment", isPresented: Binding(
            get: { commentingLineNumber != nil },
            set: { if !$0 { commentingLineNumber = nil } }
        )) {
            TextField("Ask ZCode about this line...", text: $commentDraft)
            Button("Cancel", role: .cancel) {
                commentingLineNumber = nil
                commentDraft = ""
            }
            Button("Attach to Chat") {
                if let lineNum = commentingLineNumber, let file = currentFile {
                    let lines = (file.textContent ?? "").components(separatedBy: "\n")
                    let snippet = (lineNum - 1 < lines.count) ? lines[lineNum - 1] : ""
                    store.addInlineCodeComment(
                        filePath: file.path,
                        startLine: lineNum,
                        endLine: lineNum,
                        comment: commentDraft.isEmpty ? "Review line \(lineNum)" : commentDraft,
                        snippet: snippet
                    )
                }
                commentingLineNumber = nil
                commentDraft = ""
            }
        } message: {
            if let ln = commentingLineNumber, let file = currentFile {
                Text("\(file.path):\(ln)")
            }
        }
    }

    // MARK: - Syntax Highlighted Code Canvas

    private func codeLinesView(file: WorkspaceFileNode, text: String) -> some View {
        let syntaxColors = SyntaxColors.palette(for: store.syntaxTheme)
        let lines = text.components(separatedBy: "\n")
        let lang = SyntaxHighlighter.detectLanguage(for: file.path)

        return ScrollView([.vertical, store.wrapCodeLines ? [] : .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    let lineNo = idx + 1
                    HStack(alignment: .top, spacing: 0) {
                        if store.showLineNumbers {
                            Button {
                                commentingLineNumber = lineNo
                            } label: {
                                HStack(spacing: 3) {
                                    Text("\(lineNo)")
                                        .font(.system(size: CGFloat(store.codeFontSize - 1), design: .monospaced))
                                        .foregroundStyle(syntaxColors.gutterText)
                                        .frame(width: 34, alignment: .trailing)
                                    Image(systemName: "plus.bubble")
                                        .font(.system(size: 9))
                                        .foregroundStyle(syntaxColors.gutterText.opacity(0.6))
                                }
                                .padding(.trailing, 8)
                                .padding(.vertical, 2.5)
                                .background(syntaxColors.gutterBackground)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(SyntaxHighlighter.highlightLine(
                            line,
                            language: lang,
                            theme: store.syntaxTheme,
                            fontSize: CGFloat(store.codeFontSize),
                            searchQuery: inFileSearch
                        ))
                        .fixedSize(horizontal: !store.wrapCodeLines, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2.5)
                        .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
        }
        .background(syntaxColors.background)
    }

    // MARK: - Recursive File Tree Row

    private func fileTreeNodeRow(_ node: WorkspaceFileNode, depth: Int) -> AnyView {
        let isExpanded = expandedDirIds.contains(node.id)
        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if node.isDirectory {
                        if isExpanded { expandedDirIds.remove(node.id) }
                        else { expandedDirIds.insert(node.id) }
                    } else {
                        store.selectedFileId = node.id
                        if !store.openFileIds.contains(node.id) {
                            store.openFileIds.append(node.id)
                        }
                        showFileTreeDrawer = false
                        if node.kind == .image || node.kind == .pdf {
                            store.activeInspectorTab = .preview
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if node.isDirectory {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.foregroundMuted)
                                .frame(width: 12)
                        } else {
                            Spacer().frame(width: 12)
                        }

                        Image(systemName: fileIcon(node.kind))
                            .font(.system(size: 12.5))
                            .foregroundStyle(node.isDirectory ? palette.info : palette.foregroundSubtle)

                        Text(node.name)
                            .font(.system(size: 12.5, weight: node.id == store.selectedFileId ? .semibold : .regular))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)

                        Spacer()

                        if let git = node.gitStatus {
                            Text(git)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(git == "A" ? palette.success : palette.warning)
                        }
                    }
                    .padding(.leading, CGFloat(depth * 14))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(node.id == store.selectedFileId ? palette.card : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("treeNode_\(node.id)")

                if node.isDirectory && isExpanded, let children = node.children {
                    ForEach(children) { child in
                        fileTreeNodeRow(child, depth: depth + 1)
                    }
                }
            }
        )
    }

    private func fileIcon(_ kind: WorkspaceFileKind) -> String {
        switch kind {
        case .directory: return "folder.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .markdown: return "doc.richtext"
        case .image: return "photo"
        case .pdf: return "doc.viewfinder"
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        }
    }
}
