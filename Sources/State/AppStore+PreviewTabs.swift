import Foundation

// MARK: - Inspector Preview Tabs (desktop side-pane file tabs on mobile)

/// Opens files reported anywhere in the UI (transcript tool rows, user attachments,
/// command palette) as real preview tabs. Content is read from the desktop host via
/// the same `file.*` RPC channel the Files explorer uses, so absolute paths outside
/// the workspace tree (`/tmp/shots/onb1.png`) preview exactly like workspace files.
extension AppStore {

    // MARK: Open / Activate / Close

    /// Opens (or activates) the preview tab for a path or workspace node id.
    @discardableResult
    public func openPreviewTab(path rawPath: String, workspaceNode: WorkspaceFileNode? = nil) -> InspectorPreviewTab {
        let cleaned = InspectorPreviewPath.normalizedInput(rawPath)
        guard !cleaned.isEmpty else {
            var tab = InspectorPreviewTab(path: "", displayPath: "", name: "Unknown file", kind: .text)
            tab.errorMessage = "No file path was provided."
            return previewTabs.open(tab)
        }

        let matchedNode = (workspaceNode?.isDirectory == false ? workspaceNode : nil)
            ?? workspaceFileMatch(rawPath: cleaned)
        let resolved = InspectorPreviewPath.resolve(
            matchedNode?.path ?? cleaned,
            workspacePath: inspectorWorkspacePath
        )

        let tab: InspectorPreviewTab
        if let node = matchedNode {
            tab = InspectorPreviewTab(node: node, resolvedPath: resolved)
            selectedFileId = node.id
            if !openFileIds.contains(node.id) {
                openFileIds.append(node.id)
            }
        } else {
            tab = InspectorPreviewTab(
                path: resolved,
                displayPath: InspectorPreviewPath.displayPath(
                    raw: cleaned,
                    workspacePath: inspectorWorkspacePath,
                    resolved: resolved
                ),
                name: InspectorPreviewPath.fileName(resolved)
            )
        }

        return previewTabs.open(tab)
    }

    /// Opens (or focuses) a preview tab from in-memory bytes — used by chat
    /// attachments whose content was read from the host separately
    /// (`conversationAttachmentReadV4`). No host path or `file.*` call needed.
    public func openDataPreviewTab(id: String, fileName: String, mimeType: String, data: Data) {
        let resolvedId = id.isEmpty ? UUID().uuidString : id
        let displayName = fileName.isEmpty ? "Attachment" : fileName
        let kind = InspectorPreviewPath.kind(fileName: fileName, mimeType: mimeType)
        let syntheticPath = "attachment://\(resolvedId)/\(displayName)"

        var tab = InspectorPreviewTab(
            id: resolvedId,
            path: syntheticPath,
            displayPath: displayName,
            name: displayName,
            kind: kind,
            sizeBytes: data.count,
            totalBytes: data.count,
            isDataBacked: true
        )

        switch kind {
        case .image, .pdf:
            tab.binaryData = data
        case .markdown, .csv, .code, .text:
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                tab.textContent = text
                tab.sizeBytes = max(data.count, text.utf8.count)
                tab.totalBytes = tab.sizeBytes
            } else {
                tab.isBinaryDetected = true
                tab.binaryData = data
            }
        case .binary:
            tab.isBinaryDetected = true
            tab.binaryData = data
        }

        previewTabs.open(tab)
        activeInspectorTab = .preview
        mobilePage = .chat
        showInspectorSheet = true
    }

    public func activatePreviewTab(id: String) {
        guard let tab = previewTabs.tab(id: id) else { return }
        previewTabs.activate(id: id)
        if let nodeId = tab.workspaceNodeId {
            selectedFileId = nodeId
        }
        guard !isUITestSeededMode else { return }
        Task { @MainActor in
            await self.loadPreviewTabContentIfNeeded(id: id)
        }
    }

    public func closePreviewTab(id: String) {
        guard let closing = previewTabs.tab(id: id) else { return }
        previewTabs.close(id: id)

        if let nodeId = closing.workspaceNodeId {
            openFileIds.removeAll { $0 == nodeId }
            if selectedFileId == nodeId {
                selectedFileId = previewTabs.activeTab?.workspaceNodeId ?? ""
            }
        }
        if let nodeId = previewTabs.activeTab?.workspaceNodeId,
           selectedFileId.isEmpty || selectedFileId == closing.workspaceNodeId {
            selectedFileId = nodeId
        }
    }

    public func closeAllPreviewTabs() {
        previewTabs.removeAll()
        openFileIds.removeAll()
        selectedFileId = ""
    }

    /// Retry button in the preview error state.
    public func reloadPreviewTab(id: String) async {
        await loadPreviewTabContentIfNeeded(id: id, force: true)
    }

    /// Maps a workspace id / relative or absolute path to a tree node. Absolute
    /// paths outside the tree deliberately do not suffix-match, so a host file
    /// like `/tmp/shots/onb1.png` cannot accidentally bind to `shots/onb1.png`
    /// cached from a different root.
    private func workspaceFileMatch(rawPath: String) -> WorkspaceFileNode? {
        let all = flattenedFiles
        if let exact = all.first(where: {
            !$0.isDirectory && ($0.id == rawPath || $0.path == rawPath)
        }) {
            return exact
        }
        guard !rawPath.hasPrefix("/"), !rawPath.hasPrefix("~") else { return nil }
        let normalized = rawPath.hasPrefix("./") ? String(rawPath.dropFirst(2)) : rawPath
        return all.first(where: {
            !$0.isDirectory && ($0.path == normalized || $0.path.hasSuffix("/" + normalized))
        })
    }

    // MARK: Host Content Loading

    /// Loads a tab's bytes/text on first display (and again on Retry). Uses
    /// `file.stat`, `file.readTextFile`, `file.readMediaPreview`,
    /// `file.readFileRange` and `file.readBinaryPreview` — the exact RPCs the
    /// Files explorer uses for tree files.
    public func loadPreviewTabContentIfNeeded(id: String, force: Bool = false) async {
        guard let index = previewTabs.tabs.firstIndex(where: { $0.id == id }) else { return }
        var tab = previewTabs.tabs[index]
        guard !tab.isLoading else { return }
        guard !tab.isDataBacked else { return }

        let kind = tab.effectiveKind
        if !force {
            switch kind {
            case .image, .pdf:
                if tab.binaryData != nil { return }
            case .markdown, .csv, .code, .text:
                if tab.textContent != nil { return }
            case .binary:
                return
            }
        }

        // Fixture content is pre-populated; never hit the network in seeded UI tests.
        guard !isUITestSeededMode else { return }

        guard isLiveHostConnected else {
            tab.isLoading = false
            tab.errorMessage = "Connect to a ZCode host to preview this file."
            previewTabs.replace(tab)
            return
        }

        // Reuse already-loaded workspace node content unless the user asked to retry.
        if !force, let nodeId = tab.workspaceNodeId, let node = findFileNode(id: nodeId) {
            switch kind {
            case .image, .pdf:
                if let data = node.binaryData, !data.isEmpty {
                    tab.binaryData = data
                    tab.sizeBytes = max(tab.sizeBytes, data.count)
                    tab.errorMessage = nil
                    previewTabs.replace(tab)
                    return
                }
            case .markdown, .csv, .code, .text:
                if let text = node.textContent {
                    tab.textContent = text
                    tab.sizeBytes = max(max(tab.sizeBytes, node.sizeBytes), text.utf8.count)
                    tab.errorMessage = nil
                    previewTabs.replace(tab)
                    return
                }
            case .binary:
                return
            }
        }

        if kind == .image {
            await loadPreviewImage(tab)
            return
        }

        tab.isLoading = true
        tab.errorMessage = nil
        previewTabs.replace(tab)

        do {
            let size = try await statHostFileSize(path: tab.path)

            switch kind {
            case .image:
                if size > Self.inspectorMaxImagePreviewBytes {
                    throw PreviewLoadError.tooLarge(limit: "16 MB")
                }
                let (data, _) = try await loadHostImageBytes(path: tab.path, expectedSize: size)
                guard !data.isEmpty else { throw PreviewLoadError.empty }
                tab.binaryData = data
                tab.textContent = nil
                tab.sizeBytes = max(size, data.count)
                tab.totalBytes = tab.sizeBytes

            case .pdf:
                if size > Self.inspectorMaxPDFPreviewBytes {
                    throw PreviewLoadError.tooLarge(limit: "25 MB")
                }
                let data = try await loadHostPDFBytes(path: tab.path, expectedSize: size)
                guard !data.isEmpty else { throw PreviewLoadError.empty }
                tab.binaryData = data
                tab.textContent = nil
                tab.sizeBytes = max(size, data.count)
                tab.totalBytes = tab.sizeBytes

            case .binary:
                tab.isLoading = false
                tab.isBinaryDetected = true
                tab.sizeBytes = size
                previewTabs.replace(tab)
                return

            case .markdown, .csv, .code, .text:
                let read = try await readHostTextFile(path: tab.path)
                tab.sizeBytes = max(size, read.totalBytes)
                tab.totalBytes = max(size, read.totalBytes)
                if read.isBinary {
                    tab.isBinaryDetected = true
                    tab.textContent = nil
                    tab.isTruncated = false
                } else {
                    tab.isBinaryDetected = false
                    tab.textContent = read.text
                    tab.isTruncated = read.isTruncated
                }
            }

            tab.isLoading = false
            tab.errorMessage = nil
            previewTabs.replace(tab)
            mirrorIntoWorkspaceNode(tab)
        } catch {
            guard previewTabs.tab(id: id) != nil else { return }
            tab.isLoading = false
            tab.errorMessage = previewErrorMessage(for: error, path: tab.displayPath)
            previewTabs.replace(tab)
        }
    }

    private enum PreviewLoadError: LocalizedError {
        case empty
        case tooLarge(limit: String)

        var errorDescription: String? {
            switch self {
            case .empty: return "The host returned no data for this file."
            case .tooLarge(let limit): return "This file is too large to preview (max \(limit))."
            }
        }
    }

    private func previewErrorMessage(for error: Error, path: String) -> String {
        if let previewError = error as? PreviewLoadError {
            return previewError.errorDescription ?? "Preview unavailable."
        }
        let detail = error.localizedDescription
        return "Couldn't read \(path) from the host. \(detail)"
    }

    /// Images render from the on-device copy at once and only re-download when `file.stat` reports a change.
    /// A miss reads the raw bytes straight away (binary frames, no base64), with `stat` running alongside for the cache stamp.
    private func loadPreviewImage(_ start: InspectorPreviewTab) async {
        var tab = start
        let path = tab.path
        let cacheKey = V4LocalCache.key("file-preview", activeConnectionId, path)
        let cached = await V4LocalCache.loadAttachment(key: cacheKey)
        if let cached {
            tab.binaryData = cached.data
            tab.textContent = nil
            tab.sizeBytes = max(tab.sizeBytes, cached.data.count)
            tab.totalBytes = tab.sizeBytes
            tab.isLoading = false
        } else {
            tab.isLoading = true
        }
        tab.errorMessage = nil
        previewTabs.replace(tab)

        let statTask = Task { @MainActor in try? await self.statHostFileInfo(path: path) }
        if let cached {
            // Unreachable host or unchanged file: the cached copy stays.
            guard let info = await statTask.value, Self.previewCacheStamp(info) != cached.mimeType else { return }
        }

        do {
            var data: Data
            do {
                data = try await readFileBytesInRanges(path: path, expectedSize: 0, maxBytes: Self.inspectorMaxImagePreviewBytes)
            } catch {
                let size = await statTask.value?.size ?? 0
                data = try await loadHostImageBytes(path: path, expectedSize: size).0
            }
            let info = await statTask.value
            if let size = info?.size, size > Self.inspectorMaxImagePreviewBytes {
                throw PreviewLoadError.tooLarge(limit: "16 MB")
            }
            guard !data.isEmpty else { throw PreviewLoadError.empty }
            guard var current = previewTabs.tab(id: tab.id) else { return }
            current.binaryData = data
            current.textContent = nil
            current.sizeBytes = max(info?.size ?? 0, data.count)
            current.totalBytes = current.sizeBytes
            current.isLoading = false
            current.errorMessage = nil
            previewTabs.replace(current)
            mirrorIntoWorkspaceNode(current)
            if let info { V4LocalCache.saveAttachment(data, mimeType: Self.previewCacheStamp(info), key: cacheKey) }
        } catch {
            guard var current = previewTabs.tab(id: tab.id) else { return }
            current.isLoading = false
            if cached == nil { current.errorMessage = previewErrorMessage(for: error, path: current.displayPath) }
            previewTabs.replace(current)
        }
    }

    private static func previewCacheStamp(_ info: (size: Int, mtimeMs: Double?)) -> String {
        "\(info.size):\(Int64(info.mtimeMs ?? 0))"
    }

    private func statHostFileSize(path: String) async throws -> Int {
        try await statHostFileInfo(path: path).size
    }

    private func statHostFileInfo(path: String) async throws -> (size: Int, mtimeMs: Double?) {
        let val = try await rpcClient.call(
            channel: "file",
            method: "stat",
            args: [.fromJSONObject(["path": path])],
            timeoutSec: 6.0
        )
        guard let dict = val.decodeJSONDictionary() else {
            throw NSError(
                domain: "ZCodePreview",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected response from the host file reader."]
            )
        }
        if let type = dict["type"] as? String, type != "file" {
            throw NSError(
                domain: "ZCodePreview",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "This path is not a regular file."]
            )
        }
        return (Self.jsonInt(dict["size"]) ?? 0, ZCodeV4.double(dict["mtimeMs"]))
    }

    /// Keeps the Files explorer in sync when a preview tab loads a tree-backed file.
    private func mirrorIntoWorkspaceNode(_ tab: InspectorPreviewTab) {
        guard let nodeId = tab.workspaceNodeId else { return }
        _ = updateFileNode(id: nodeId) { node in
            node.sizeBytes = max(node.sizeBytes, tab.sizeBytes)
            switch tab.effectiveKind {
            case .image, .pdf:
                if let data = tab.binaryData { node.binaryData = data }
            case .markdown, .csv, .code, .text:
                if let text = tab.textContent { node.textContent = text }
            case .binary:
                break
            }
        }
    }
}
