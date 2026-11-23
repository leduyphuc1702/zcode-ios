import SwiftUI

public struct FileExplorerAndCodeViewer: View {
    @Bindable var store: AppStore
    @Bindable var liveState: InspectorLiveState
    @Environment(\.zcodePalette) private var palette
    @State private var showFileTreeDrawer: Bool = false
    @State private var expandedDirIds: Set<String> = ["dir-src", "dir-src-rpc", "dir-assets"]
    @State private var inFileSearch: String = ""
    @State private var showSearchField: Bool = false
    @State private var commentingLineNumber: Int?
    @State private var commentDraft: String = ""

    @MainActor
    public init(store: AppStore, liveState: InspectorLiveState? = nil) {
        self.store = store
        self.liveState = liveState ?? InspectorLiveState()
    }

    private var currentFile: WorkspaceFileNode? {
        if store.isUITestSeededMode {
            return store.selectedFile
        }
        guard !store.selectedFileId.isEmpty else { return nil }
        return store.findFileNode(id: store.selectedFileId)
    }

    private var isTreeExpandedInLiveEmptyState: Bool {
        !store.isUITestSeededMode && currentFile == nil
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
                    .foregroundStyle((showFileTreeDrawer || isTreeExpandedInLiveEmptyState) ? palette.accentBlue : palette.foreground)
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
                                selectFile(file, switchToPreviewForMedia: true)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: fileIcon(for: file))
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

                if store.isLiveHostConnected {
                    Button {
                        liveState.includeHiddenFiles.toggle()
                        liveState.loadedDirectoryIds.removeAll()
                        Task { @MainActor in
                            await store.loadInspectorRootDirectory(state: liveState, force: true)
                        }
                    } label: {
                        Image(systemName: liveState.includeHiddenFiles ? "eye" : "eye.slash")
                            .font(.system(size: 12))
                            .foregroundStyle(liveState.includeHiddenFiles ? palette.accentBlue : palette.foregroundSubtle)
                            .frame(width: 28, height: 28)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(liveState.includeHiddenFiles ? "Hide hidden files" : "Show hidden files")

                    Button {
                        liveState.loadedDirectoryIds.removeAll()
                        Task { @MainActor in
                            await store.loadInspectorRootDirectory(state: liveState, force: true)
                            if let file = currentFile {
                                await store.loadInspectorFile(node: file, state: liveState, force: true)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 28, height: 28)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh files")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(palette.panel)

            Rectangle().fill(palette.border).frame(height: 1)

            // File Tree Explorer (full height when no file selected in live mode, drawer otherwise)
            if showFileTreeDrawer || isTreeExpandedInLiveEmptyState {
                fileTreeContainer(isFullHeight: isTreeExpandedInLiveEmptyState)
                if !isTreeExpandedInLiveEmptyState {
                    Rectangle().fill(palette.border).frame(height: 1)
                }
            }

            // Code / File Content Viewer
            if let file = currentFile {
                fileContentSection(for: file)
            }
        }
        .task(id: "\(store.isLiveHostConnected)-\(store.inspectorWorkspacePath)") {
            guard store.isLiveHostConnected else { return }
            await store.loadInspectorRootDirectory(state: liveState)
            if let file = currentFile {
                await store.loadInspectorFile(node: file, state: liveState)
            }
        }
        .onChange(of: store.selectedFileId) { _, _ in
            guard store.isLiveHostConnected, let file = currentFile else { return }
            Task { @MainActor in
                await store.loadInspectorFile(node: file, state: liveState)
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

    // MARK: - File Tree Container

    @ViewBuilder
    private func fileTreeContainer(isFullHeight: Bool) -> some View {
        Group {
            if !store.isUITestSeededMode && !store.isLiveHostConnected && store.fileTree.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 26))
                        .foregroundStyle(palette.foregroundMuted)
                    Text("Connect to a ZCode host to browse workspace files.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: isFullHeight ? .infinity : 160)
            } else if liveState.isLoadingRootDirectory && store.fileTree.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading workspace files…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .frame(maxWidth: .infinity, maxHeight: isFullHeight ? .infinity : 160)
            } else if let err = liveState.rootDirectoryError, store.fileTree.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22))
                        .foregroundStyle(palette.warning)
                    Text(err)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { @MainActor in
                            await store.loadInspectorRootDirectory(state: liveState, force: true)
                        }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.accentBlue)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: isFullHeight ? .infinity : 160)
            } else if store.fileTree.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 24))
                        .foregroundStyle(palette.foregroundMuted)
                    Text("Workspace directory is empty.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .frame(maxWidth: .infinity, maxHeight: isFullHeight ? .infinity : 140)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(store.fileTree) { node in
                            fileTreeNodeRow(node, depth: 0)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: isFullHeight ? .infinity : 225)
            }
        }
        .background(palette.panel)
    }

    // MARK: - Selected File Section

    @ViewBuilder
    private func fileContentSection(for file: WorkspaceFileNode) -> some View {
        let outcome = liveState.fileStates[file.id]
        let mediaKind = liveState.effectiveMediaKind(for: file)
        let isPreviewableRich = mediaKind == .image || mediaKind == .pdf || file.kind == .markdown || file.kind == .csv

        // Toolbar (Path, Size, Viewer Switch, Search, Wrap, Syntax Palette)
        HStack(spacing: 8) {
            Text(file.path)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.foregroundSubtle)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let size = liveState.knownSizeBytes(for: file) {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.foregroundMuted)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if isPreviewableRich {
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

            if mediaKind == .text {
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
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(palette.header)

        if showSearchField && mediaKind == .text {
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

        if outcome?.isLoading == true {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(file.name)…")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = outcome?.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                    .foregroundStyle(palette.warning)
                Text(file.name)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.foreground)
                Text(err)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.foregroundSubtle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if store.isLiveHostConnected {
                    Button {
                        Task { @MainActor in
                            await store.loadInspectorFile(node: file, state: liveState, force: true)
                        }
                    } label: {
                        Text("Retry")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.brandForeground)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(palette.brand, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if mediaKind == .binary {
            binaryUnavailableView(file: file)
        } else if mediaKind == .image || mediaKind == .pdf {
            mediaRedirectView(file: file, mediaKind: mediaKind)
        } else if let codeText = file.textContent {
            VStack(spacing: 0) {
                if outcome?.isTruncated == true {
                    truncationBanner(
                        loadedBytes: outcome?.loadedBytes ?? codeText.utf8.count,
                        totalBytes: outcome?.totalBytes ?? file.sizeBytes
                    )
                }
                codeLinesView(file: file, text: codeText)
            }
        } else if store.isLiveHostConnected {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(file.name)…")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: file.id) {
                await store.loadInspectorFile(node: file, state: liveState)
            }
        } else {
            binaryUnavailableView(file: file)
        }
    }

    private func truncationBanner(loadedBytes: Int, totalBytes: Int) -> some View {
        let loadedStr = ByteCountFormatter.string(fromByteCount: Int64(loadedBytes), countStyle: .file)
        let totalStr = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        return HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(palette.warning)
            Text("Showing first \(loadedStr) of \(totalStr) (capped at 1 MB).")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.foreground)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(palette.warning.opacity(0.14))
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    private func binaryUnavailableView(file: WorkspaceFileNode) -> some View {
        let sizeText: String = {
            if let bytes = liveState.knownSizeBytes(for: file) {
                return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            }
            return "Binary file"
        }()

        return VStack(spacing: 10) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 36))
                .foregroundStyle(palette.foregroundMuted)
            Text(file.name)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Text(sizeText)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(palette.foregroundSubtle)
            Text("Preview not available")
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mediaRedirectView(file: WorkspaceFileNode, mediaKind: InspectorFileMediaKind) -> some View {
        let sizeSuffix: String = {
            if let bytes = liveState.knownSizeBytes(for: file) {
                return " (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))"
            }
            return ""
        }()

        return VStack(spacing: 12) {
            Image(systemName: mediaKind == .pdf ? "doc.richtext.fill" : "photo.fill")
                .font(.system(size: 36))
                .foregroundStyle(palette.accentBlue)
            Text("\(file.name)\(sizeSuffix)")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(palette.foregroundSubtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button {
                store.activeInspectorTab = .preview
            } label: {
                Text("Open in Viewer")
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
                                        .frame(width: 38, alignment: .trailing)
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
        let isLoadingDir = liveState.loadingDirectoryIds.contains(node.id)
        let dirError = liveState.directoryErrors[node.id]
        let isDirLoaded = liveState.loadedDirectoryIds.contains(node.id)

        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if node.isDirectory {
                        if isExpanded {
                            expandedDirIds.remove(node.id)
                        } else {
                            expandedDirIds.insert(node.id)
                            if store.isLiveHostConnected {
                                Task { @MainActor in
                                    await store.loadInspectorDirectoryChildren(
                                        dirId: node.id,
                                        dirPath: node.path,
                                        state: liveState
                                    )
                                }
                            }
                        }
                    } else {
                        selectFile(node, switchToPreviewForMedia: true)
                        showFileTreeDrawer = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if node.isDirectory {
                            if isLoadingDir {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(palette.foregroundMuted)
                                    .frame(width: 12)
                            }
                        } else {
                            Spacer().frame(width: 12)
                        }

                        Image(systemName: fileIcon(for: node))
                            .font(.system(size: 12.5))
                            .foregroundStyle(node.isDirectory ? palette.info : palette.foregroundSubtle)

                        Text(node.name)
                            .font(.system(size: 12.5, weight: node.id == store.selectedFileId ? .semibold : .regular))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        if !node.isDirectory, let bytes = liveState.knownSizeBytes(for: node) {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(palette.foregroundMuted)
                        }

                        if let git = node.gitStatus {
                            Text(git)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(git == "A" || git == "U" ? palette.success : (git == "D" ? palette.destructive : palette.warning))
                        }
                    }
                    .padding(.leading, CGFloat(depth * 14))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(node.id == store.selectedFileId ? palette.card : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("treeNode_\(node.id)")

                if node.isDirectory && isExpanded {
                    if let dirError {
                        HStack(spacing: 6) {
                            Text(dirError)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.destructive)
                                .lineLimit(2)
                            Button("Retry") {
                                Task { @MainActor in
                                    await store.loadInspectorDirectoryChildren(
                                        dirId: node.id,
                                        dirPath: node.path,
                                        state: liveState,
                                        force: true
                                    )
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.accentBlue)
                        }
                        .padding(.leading, CGFloat((depth + 1) * 14 + 18))
                        .padding(.vertical, 3)
                    } else if let children = node.children, !children.isEmpty {
                        ForEach(children) { child in
                            fileTreeNodeRow(child, depth: depth + 1)
                        }
                    } else if !isLoadingDir && (isDirLoaded || store.isUITestSeededMode) {
                        Text("Empty folder")
                            .font(.system(size: 11))
                            .italic()
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.leading, CGFloat((depth + 1) * 14 + 18))
                            .padding(.vertical, 3)
                    }
                }
            }
        )
    }

    private func selectFile(_ node: WorkspaceFileNode, switchToPreviewForMedia: Bool) {
        store.selectedFileId = node.id
        if !store.openFileIds.contains(node.id) {
            store.openFileIds.append(node.id)
        }
        let mediaKind = liveState.effectiveMediaKind(for: node)
        if switchToPreviewForMedia && (mediaKind == .image || mediaKind == .pdf) {
            store.activeInspectorTab = .preview
        }
        if store.isLiveHostConnected {
            Task { @MainActor in
                await store.loadInspectorFile(node: node, state: liveState)
            }
        }
    }

    private func fileIcon(for node: WorkspaceFileNode) -> String {
        if node.isDirectory { return "folder.fill" }
        let mediaKind = liveState.effectiveMediaKind(for: node)
        switch mediaKind {
        case .directory: return "folder.fill"
        case .image: return "photo"
        case .pdf: return "doc.viewfinder"
        case .binary: return "doc.zipper"
        case .text:
            switch node.kind {
            case .markdown: return "doc.richtext"
            case .csv: return "tablecells"
            case .json: return "curlybraces"
            default: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }
}
