import Foundation
import Observation
import SwiftUI

// MARK: - Inspector Live Models & File Classification

public enum InspectorFileMediaKind: Equatable {
    case directory
    case text
    case image
    case pdf
    case binary

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp", "ico", "tif", "tiff"
    ]

    private static let knownBinaryExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "lz4",
        "dmg", "pkg", "iso", "img", "ipa", "apk", "aab", "deb", "rpm",
        "jar", "war", "ear", "class", "dex",
        "o", "a", "dylib", "so", "dll", "exe", "msi", "bin", "elf", "wasm",
        "pyc", "pyo", "beam",
        "woff", "woff2", "ttf", "otf", "eot",
        "mp3", "mp4", "mov", "m4a", "m4v", "wav", "flac", "ogg", "aac", "avi", "mkv", "webm",
        "sqlite", "sqlite3", "db", "realm", "ldb", "sst",
        "pb", "xcuserstate", "nib", "storyboardc", "car", "icns",
        "psd", "ai", "sketch", "fig", "blend", "fbx", "usdz", "glb", "gltf",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "odt"
    ]

    public static func classify(name: String, isDirectory: Bool) -> InspectorFileMediaKind {
        if isDirectory { return .directory }
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if imageExtensions.contains(ext) { return .image }
        if knownBinaryExtensions.contains(ext) { return .binary }
        return .text
    }

    public static func workspaceFileKind(name: String, isDirectory: Bool) -> WorkspaceFileKind {
        if isDirectory { return .directory }
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        switch ext {
        case "md", "markdown", "mdx": return .markdown
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "ico", "tif", "tiff": return .image
        case "pdf": return .pdf
        case "csv", "tsv": return .csv
        case "json", "jsonc", "jsonl": return .json
        default: return .code
        }
    }
}

public struct InspectorFileLoadOutcome: Equatable {
    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var isBinary: Bool = false
    public var isTruncated: Bool = false
    public var totalBytes: Int? = nil
    public var loadedBytes: Int = 0
    public var mediaType: String? = nil
    public var didAttemptLoad: Bool = false

    public init() {}
}

public struct InspectorGitRef: Identifiable, Equatable, Hashable {
    public var id: String { "\(kind):\(name)" }
    public let name: String
    public let kind: String // "head" | "branch" | "remote" | "tag"
}

public struct InspectorCommitDetail: Identifiable, Equatable {
    public var id: String { hash }
    public let hash: String
    public let shortHash: String
    public let parents: [String]
    public let refs: [InspectorGitRef]
    public let subject: String
    public let author: String
    public let timestamp: Date?

    public var branchRefSummary: String? {
        let nonHead = refs.filter { $0.kind != "head" }.map(\.name)
        let hasHead = refs.contains { $0.kind == "head" }
        if hasHead, let first = nonHead.first {
            return "HEAD -> \(first)"
        }
        return nonHead.first ?? (hasHead ? "HEAD" : nil)
    }
}

public struct InspectorDiffDetail: Equatable {
    public let availability: String // "patch" | "binary" | "truncated" | "unavailable"
    public let patch: String?
    public let beforeContent: String?
    public let afterContent: String?
    public let summary: String?
}

// MARK: - Observable Live State Held by CodingInspectorWindowView

@Observable
@MainActor
public final class InspectorLiveState {
    public var workspacePath: String = ""
    public var includeHiddenFiles: Bool = false

    // Files
    public var isLoadingRootDirectory: Bool = false
    public var rootDirectoryError: String? = nil
    public var loadingDirectoryIds: Set<String> = []
    public var loadedDirectoryIds: Set<String> = []
    public var directoryErrors: [String: String] = [:]
    public var fileStates: [String: InspectorFileLoadOutcome] = [:]
    public var statedFileIds: Set<String> = []

    // Git
    public var isLoadingGitStatus: Bool = false
    public var gitStatusError: String? = nil
    public var isGitRepository: Bool = true
    public var isGitAvailable: Bool = true
    public var gitStatusLoaded: Bool = false
    public var gitBranchesLoaded: Bool = false
    public var loadingDiffIds: Set<String> = []
    public var diffDetails: [String: InspectorDiffDetail] = [:]
    public var diffErrors: [String: String] = [:]
    public var commitDetails: [InspectorCommitDetail] = []
    public var hasMoreCommits: Bool = false
    public var isLoadingCommits: Bool = false
    public var isLoadingMoreCommits: Bool = false
    public var commitsLoaded: Bool = false
    public var commitsError: String? = nil
    public var isMutatingGit: Bool = false
    public var isGeneratingCommitMessage: Bool = false

    // Live Terminal PTY
    public var ptyId: String? = nil
    public var ptyShell: String? = nil
    public var ptyCwd: String? = nil
    public var ptyDataSubId: Int32? = nil
    public var ptyExitSubId: Int32? = nil
    public var isConnectingPty: Bool = false
    public var ptyExited: Bool = false
    public var ptyExitCode: Int? = nil
    public var ptyError: String? = nil
    public var ptyOutput: String = ""

    public init() {}

    public func resetForWorkspace(_ newPath: String) {
        guard workspacePath != newPath else { return }
        workspacePath = newPath
        isLoadingRootDirectory = false
        rootDirectoryError = nil
        loadingDirectoryIds.removeAll()
        loadedDirectoryIds.removeAll()
        directoryErrors.removeAll()
        fileStates.removeAll()
        statedFileIds.removeAll()

        isLoadingGitStatus = false
        gitStatusError = nil
        isGitRepository = true
        isGitAvailable = true
        gitStatusLoaded = false
        gitBranchesLoaded = false
        loadingDiffIds.removeAll()
        diffDetails.removeAll()
        diffErrors.removeAll()
        commitDetails.removeAll()
        hasMoreCommits = false
        isLoadingCommits = false
        isLoadingMoreCommits = false
        commitsLoaded = false
        commitsError = nil
        isMutatingGit = false
        isGeneratingCommitMessage = false
    }

    public func effectiveMediaKind(for node: WorkspaceFileNode) -> InspectorFileMediaKind {
        if node.isDirectory { return .directory }
        if fileStates[node.id]?.isBinary == true { return .binary }
        return InspectorFileMediaKind.classify(name: node.name, isDirectory: false)
    }

    public func knownSizeBytes(for node: WorkspaceFileNode) -> Int? {
        if let total = fileStates[node.id]?.totalBytes {
            return total
        }
        if node.sizeBytes > 0 {
            return node.sizeBytes
        }
        if statedFileIds.contains(node.id) {
            return node.sizeBytes
        }
        if let binary = node.binaryData, !binary.isEmpty {
            return binary.count
        }
        if let text = node.textContent {
            return text.utf8.count
        }
        return nil
    }
}

// MARK: - AppStore Live Inspector Host Integration

extension AppStore {

    // Host limits verified from ZCode Desktop 3.16.3 (/tmp/zc-asar/app/out/host/index.js):
    // - file.readTextFile: host clamps length to ode = 256 KB per call; we loop up to 1 MB total
    // - file.readFileRange: host clamps length to sde = 1 MB per call; returns VQL .buffer / .vsBuffer
    // - file.readMediaPreview: host clamps maxBytes to ide = 8 MB; returns base64 JSON
    // - file.readBinaryPreview: host clamps maxBytes to ade = 25 MB; returns base64 JSON
    static let inspectorTextChunkBytes = 256 * 1024
    static let inspectorMaxTextBytes = 1024 * 1024 // ~1 MB cap
    static let inspectorBinaryChunkBytes = 1024 * 1024
    static let inspectorMaxImagePreviewBytes = 16 * 1024 * 1024
    static let inspectorInlineMediaPreviewLimit = 8 * 1024 * 1024
    static let inspectorMaxPDFPreviewBytes = 25 * 1024 * 1024

    public var inspectorWorkspacePath: String {
        if let sessionPath = activeSession?.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionPath.isEmpty, sessionPath != "~" {
            return sessionPath
        }
        if let projectPath = activeProject?.rootPath.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectPath.isEmpty, projectPath != "~" {
            return projectPath
        }
        return ""
    }

    // MARK: - Recursive File Tree Helpers

    public func findFileNode(id: String) -> WorkspaceFileNode? {
        func search(_ nodes: [WorkspaceFileNode]) -> WorkspaceFileNode? {
            for n in nodes {
                if n.id == id { return n }
                if let children = n.children, let found = search(children) {
                    return found
                }
            }
            return nil
        }
        return search(fileTree)
    }

    @discardableResult
    public func updateFileNode(id: String, mutate: (inout WorkspaceFileNode) -> Void) -> Bool {
        func update(_ nodes: inout [WorkspaceFileNode]) -> Bool {
            for idx in nodes.indices {
                if nodes[idx].id == id {
                    mutate(&nodes[idx])
                    return true
                }
                if nodes[idx].children != nil {
                    var children = nodes[idx].children ?? []
                    if update(&children) {
                        nodes[idx].children = children
                        return true
                    }
                }
            }
            return false
        }
        return update(&fileTree)
    }

    @discardableResult
    public func setChildren(_ children: [WorkspaceFileNode], forDirectoryId dirId: String) -> Bool {
        updateFileNode(id: dirId) { node in
            node.children = children
        }
    }

    private func existingFileCacheMap() -> [String: WorkspaceFileNode] {
        var map: [String: WorkspaceFileNode] = [:]
        func collect(_ nodes: [WorkspaceFileNode]) {
            for n in nodes {
                map[n.id] = n
                if let children = n.children {
                    collect(children)
                }
            }
        }
        collect(fileTree)
        return map
    }

    // MARK: - Live File Listing & Lazy Directory Expansion

    public func loadInspectorRootDirectory(state: InspectorLiveState, force: Bool = false) async {
        guard isLiveHostConnected else { return }
        let rootPath = inspectorWorkspacePath
        guard !rootPath.isEmpty else {
            state.rootDirectoryError = "No active workspace path."
            return
        }

        if state.workspacePath != rootPath {
            state.resetForWorkspace(rootPath)
        }
        if state.isLoadingRootDirectory { return }
        if !force, !fileTree.isEmpty, state.loadedDirectoryIds.contains("__root__") {
            return
        }

        state.isLoadingRootDirectory = true
        state.rootDirectoryError = nil
        defer { state.isLoadingRootDirectory = false }

        do {
            let val = try await rpcClient.call(
                channel: "file",
                method: "readdir",
                args: [.fromJSONObject(["path": rootPath, "includeHidden": state.includeHiddenFiles])],
                timeoutSec: 8.0
            )
            let previous = existingFileCacheMap()
            let nodes = parseReaddirNodes(val, preserving: previous)
            self.fileTree = nodes
            state.loadedDirectoryIds.insert("__root__")
            applyGitStatusBadgesToFileTree(workspacePath: rootPath)
            await statInspectorFiles(nodes.filter { !$0.isDirectory }, state: state)
        } catch {
            state.rootDirectoryError = error.localizedDescription
        }
    }

    public func loadInspectorDirectoryChildren(
        dirId: String,
        dirPath: String,
        state: InspectorLiveState,
        force: Bool = false
    ) async {
        guard isLiveHostConnected else { return }
        if state.loadingDirectoryIds.contains(dirId) { return }
        if !force, state.loadedDirectoryIds.contains(dirId) { return }

        state.loadingDirectoryIds.insert(dirId)
        state.directoryErrors.removeValue(forKey: dirId)
        defer { state.loadingDirectoryIds.remove(dirId) }

        do {
            let val = try await rpcClient.call(
                channel: "file",
                method: "readdir",
                args: [.fromJSONObject(["path": dirPath, "includeHidden": state.includeHiddenFiles])],
                timeoutSec: 8.0
            )
            let previous = existingFileCacheMap()
            let children = parseReaddirNodes(val, preserving: previous)
            _ = setChildren(children, forDirectoryId: dirId)
            state.loadedDirectoryIds.insert(dirId)
            applyGitStatusBadgesToFileTree(workspacePath: inspectorWorkspacePath)
            await statInspectorFiles(children.filter { !$0.isDirectory }, state: state)
        } catch {
            state.directoryErrors[dirId] = error.localizedDescription
        }
    }

    public func statInspectorFiles(_ nodes: [WorkspaceFileNode], state: InspectorLiveState) async {
        guard isLiveHostConnected else { return }
        let targets = nodes.filter { !$0.isDirectory && !state.statedFileIds.contains($0.id) }.prefix(60)
        guard !targets.isEmpty else { return }

        let batchSize = 6
        let list = Array(targets)
        var index = 0
        while index < list.count {
            let end = min(index + batchSize, list.count)
            let chunk = list[index..<end]
            await withTaskGroup(of: (String, Int, Date?)?.self) { group in
                for node in chunk {
                    let nodeId = node.id
                    let nodePath = node.path
                    group.addTask { [rpcClient] in
                        guard let val = try? await rpcClient.call(
                            channel: "file",
                            method: "stat",
                            args: [.fromJSONObject(["path": nodePath])],
                            timeoutSec: 4.0
                        ),
                              let dict = val.decodeJSONDictionary(),
                              let size = Self.jsonInt(dict["size"]) else {
                            return nil
                        }
                        let mtime = Self.jsonDouble(dict["mtimeMs"]).map { Date(timeIntervalSince1970: $0 / 1000.0) }
                        return (nodeId, size, mtime)
                    }
                }
                for await result in group {
                    guard let (nodeId, size, mtime) = result else { continue }
                    state.statedFileIds.insert(nodeId)
                    var outcome = state.fileStates[nodeId] ?? InspectorFileLoadOutcome()
                    outcome.totalBytes = size
                    state.fileStates[nodeId] = outcome
                    _ = updateFileNode(id: nodeId) { n in
                        n.sizeBytes = size
                        if let mtime { n.updatedAt = mtime }
                    }
                }
            }
            index = end
        }
    }

    private func parseReaddirNodes(
        _ val: VQLValue,
        preserving previous: [String: WorkspaceFileNode]
    ) -> [WorkspaceFileNode] {
        guard case .array(let entries) = val else { return [] }
        var nodes: [WorkspaceFileNode] = []
        nodes.reserveCapacity(min(entries.count, 300))

        for entry in entries.prefix(300) {
            guard let dict = entry.decodeJSONDictionary(),
                  let name = dict["name"] as? String,
                  let fullPath = dict["path"] as? String else { continue }
            let isDir = (dict["type"] as? String) == "directory"
            let nodeId = "file-\(Self.stableProjectId(for: fullPath))"
            let existing = previous[nodeId]
            nodes.append(
                WorkspaceFileNode(
                    id: nodeId,
                    name: name,
                    path: fullPath,
                    kind: InspectorFileMediaKind.workspaceFileKind(name: name, isDirectory: isDir),
                    gitStatus: existing?.gitStatus,
                    sizeBytes: existing?.sizeBytes ?? 0,
                    updatedAt: existing?.updatedAt ?? Date(),
                    textContent: existing?.textContent,
                    binaryData: existing?.binaryData,
                    children: isDir ? (existing?.children ?? []) : nil
                )
            )
        }
        return nodes
    }

    // MARK: - Live File Content Loading (Text <= 1 MB, Images, PDFs, Non-Previewable Binaries)

    public func loadInspectorFile(
        node: WorkspaceFileNode,
        state: InspectorLiveState,
        force: Bool = false
    ) async {
        guard isLiveHostConnected, !node.isDirectory else { return }

        let currentOutcome = state.fileStates[node.id] ?? InspectorFileLoadOutcome()
        if currentOutcome.isLoading { return }
        if !force, currentOutcome.didAttemptLoad, currentOutcome.errorMessage == nil {
            let mediaKind = state.effectiveMediaKind(for: node)
            switch mediaKind {
            case .binary:
                return
            case .image, .pdf:
                if findFileNode(id: node.id)?.binaryData != nil { return }
            case .text:
                if findFileNode(id: node.id)?.textContent != nil { return }
            case .directory:
                return
            }
        }

        var outcome = currentOutcome
        outcome.isLoading = true
        outcome.errorMessage = nil
        state.fileStates[node.id] = outcome

        // Step 1: Always stat for accurate real size and mtime
        var knownSize: Int? = state.knownSizeBytes(for: node)
        do {
            let statVal = try await rpcClient.call(
                channel: "file",
                method: "stat",
                args: [.fromJSONObject(["path": node.path])],
                timeoutSec: 6.0
            )
            if let dict = statVal.decodeJSONDictionary() {
                if let type = dict["type"] as? String, type != "file" {
                    outcome.isLoading = false
                    outcome.didAttemptLoad = true
                    outcome.errorMessage = "Target path is not a regular file."
                    state.fileStates[node.id] = outcome
                    return
                }
                if let sz = Self.jsonInt(dict["size"]) {
                    knownSize = sz
                    outcome.totalBytes = sz
                    state.statedFileIds.insert(node.id)
                    let mtime = Self.jsonDouble(dict["mtimeMs"]).map { Date(timeIntervalSince1970: $0 / 1000.0) }
                    _ = updateFileNode(id: node.id) { n in
                        n.sizeBytes = sz
                        if let mtime { n.updatedAt = mtime }
                    }
                }
            }
        } catch {
            outcome.isLoading = false
            outcome.didAttemptLoad = true
            outcome.errorMessage = error.localizedDescription
            state.fileStates[node.id] = outcome
            return
        }

        let initialKind = InspectorFileMediaKind.classify(name: node.name, isDirectory: false)

        switch initialKind {
        case .directory:
            outcome.isLoading = false
            outcome.didAttemptLoad = true
            state.fileStates[node.id] = outcome

        case .binary:
            outcome.isLoading = false
            outcome.isBinary = true
            outcome.didAttemptLoad = true
            state.fileStates[node.id] = outcome

        case .image:
            let size = knownSize ?? 0
            if size > Self.inspectorMaxImagePreviewBytes {
                outcome.isLoading = false
                outcome.didAttemptLoad = true
                let sizeLabel = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                outcome.errorMessage = "Image is too large to preview (\(sizeLabel), max 16 MB)."
                state.fileStates[node.id] = outcome
                return
            }
            do {
                let (data, mediaType) = try await loadHostImageBytes(path: node.path, expectedSize: size)
                outcome.isLoading = false
                outcome.didAttemptLoad = true
                outcome.totalBytes = max(size, data.count)
                outcome.loadedBytes = data.count
                outcome.mediaType = mediaType
                state.fileStates[node.id] = outcome
                _ = updateFileNode(id: node.id) { n in
                    n.binaryData = data
                    n.sizeBytes = max(size, data.count)
                }
            } catch {
                outcome.isLoading = false
                outcome.didAttemptLoad = true
                outcome.errorMessage = error.localizedDescription
                state.fileStates[node.id] = outcome
            }

        case .pdf:
            let size = knownSize ?? 0
            if size > Self.inspectorMaxPDFPreviewBytes {
                outcome.isLoading = false
                outcome.didAttemptLoad = true
                let sizeLabel = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                outcome.errorMessage = "PDF is too large to preview (\(sizeLabel), max 25 MB)."
                state.fileStates[node.id] = outcome
                return
            }
            do {
                let data = try await loadHostPDFBytes(path: node.path, expectedSize: size)
                outcome.isLoading = false
                outcome.didAttemptLoad = true
                outcome.totalBytes = max(size, data.count)
                outcome.loadedBytes = data.count
                outcome.mediaType = "application/pdf"
                state.fileStates[node.id] = outcome
                _ = updateFileNode(id: node.id) { n in
                    n.binaryData = data
                    n.sizeBytes = max(size, data.count)
                }
            } catch {
                outcome.isLoading = false
                outcome.didAttemptLoad = true
                outcome.errorMessage = error.localizedDescription
                state.fileStates[node.id] = outcome
            }

        case .text:
            do {
                let read = try await readHostTextFile(path: node.path)

                outcome.isLoading = false
                outcome.didAttemptLoad = true
                outcome.totalBytes = read.totalBytes
                outcome.loadedBytes = read.bytesRead

                if read.isBinary {
                    outcome.isBinary = true
                    outcome.isTruncated = false
                    state.fileStates[node.id] = outcome
                    _ = updateFileNode(id: node.id) { n in
                        n.textContent = nil
                        n.sizeBytes = read.totalBytes
                    }
                } else {
                    outcome.isBinary = false
                    outcome.isTruncated = read.isTruncated
                    state.fileStates[node.id] = outcome
                    _ = updateFileNode(id: node.id) { n in
                        n.textContent = read.text
                        n.sizeBytes = read.totalBytes
                    }
                }
            } catch {
                outcome.isLoading = false
                outcome.didAttemptLoad = true
                outcome.errorMessage = error.localizedDescription
                state.fileStates[node.id] = outcome
            }
        }
    }

    /// Chunked `file.readTextFile` read shared by the Files explorer and the
    /// preview tabs (works for any absolute host path, inside or outside the tree).
    public struct HostTextFileRead: Equatable {
        public var text: String
        public var bytesRead: Int
        public var totalBytes: Int
        public var isBinary: Bool
        public var isTruncated: Bool

        public init(text: String, bytesRead: Int, totalBytes: Int, isBinary: Bool, isTruncated: Bool) {
            self.text = text
            self.bytesRead = bytesRead
            self.totalBytes = totalBytes
            self.isBinary = isBinary
            self.isTruncated = isTruncated
        }
    }

    func readHostTextFile(
        path: String,
        maxBytes: Int = AppStore.inspectorMaxTextBytes,
        chunkBytes: Int = AppStore.inspectorTextChunkBytes
    ) async throws -> HostTextFileRead {
        var accumulated = ""
        var offset = 0
        var totalBytes = 0
        var hostTruncated = false
        var detectedBinary = false

        while offset < maxBytes {
            let remaining = maxBytes - offset
            let chunkLen = min(chunkBytes, remaining)
            let val = try await rpcClient.call(
                channel: "file",
                method: "readTextFile",
                args: [.fromJSONObject([
                    "path": path,
                    "offset": offset,
                    "length": chunkLen
                ])],
                timeoutSec: 8.0
            )
            guard let dict = val.decodeJSONDictionary() else {
                throw NSError(domain: "ZCodeInspector", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response from host file reader."])
            }
            if let tb = Self.jsonInt(dict["totalBytes"]) {
                totalBytes = tb
            }
            if (dict["isBinary"] as? Bool) == true {
                detectedBinary = true
                break
            }
            let chunk = (dict["content"] as? String) ?? ""
            let bytesRead = Self.jsonInt(dict["bytesRead"]) ?? chunk.utf8.count
            let truncated = (dict["truncated"] as? Bool) ?? false

            accumulated += chunk
            offset += bytesRead
            hostTruncated = truncated

            if !truncated || bytesRead <= 0 || offset >= totalBytes {
                break
            }
        }

        return HostTextFileRead(
            text: accumulated,
            bytesRead: offset,
            totalBytes: totalBytes,
            isBinary: detectedBinary,
            isTruncated: detectedBinary ? false : (hostTruncated || offset < totalBytes)
        )
    }

    func loadHostImageBytes(path: String, expectedSize: Int) async throws -> (Data, String?) {
        if expectedSize > 0 && expectedSize <= Self.inspectorInlineMediaPreviewLimit {
            if let val = try? await rpcClient.call(
                channel: "file",
                method: "readMediaPreview",
                args: [.fromJSONObject(["path": path, "maxBytes": Self.inspectorInlineMediaPreviewLimit])],
                timeoutSec: 12.0
            ),
               let dict = val.decodeJSONDictionary(),
               let b64 = dict["dataBase64"] as? String,
               let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
               !data.isEmpty {
                return (data, dict["mediaType"] as? String)
            }
        }
        let raw = try await readFileBytesInRanges(
            path: path,
            expectedSize: expectedSize,
            maxBytes: Self.inspectorMaxImagePreviewBytes
        )
        return (raw, nil)
    }

    func loadHostPDFBytes(path: String, expectedSize: Int) async throws -> Data {
        do {
            let raw = try await readFileBytesInRanges(
                path: path,
                expectedSize: expectedSize,
                maxBytes: Self.inspectorMaxPDFPreviewBytes
            )
            if !raw.isEmpty { return raw }
        } catch {
            // Fall back to readBinaryPreview below
        }

        let val = try await rpcClient.call(
            channel: "file",
            method: "readBinaryPreview",
            args: [.fromJSONObject(["path": path, "maxBytes": Self.inspectorMaxPDFPreviewBytes])],
            timeoutSec: 15.0
        )
        guard let dict = val.decodeJSONDictionary(),
              let b64 = dict["dataBase64"] as? String,
              let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
            throw NSError(domain: "ZCodeInspector", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode PDF bytes from host."])
        }
        return data
    }

    func readFileBytesInRanges(path: String, expectedSize: Int, maxBytes: Int) async throws -> Data {
        let targetLimit = expectedSize > 0 ? min(expectedSize, maxBytes) : maxBytes
        var result = Data()
        if expectedSize > 0 && expectedSize <= maxBytes {
            result.reserveCapacity(expectedSize)
        }

        var offset = 0
        while offset < targetLimit {
            let length = min(Self.inspectorBinaryChunkBytes, targetLimit - offset)
            let val = try await rpcClient.call(
                channel: "file",
                method: "readFileRange",
                args: [.fromJSONObject(["path": path, "offset": offset, "length": length])],
                timeoutSec: 12.0
            )
            let chunk: Data
            switch val {
            case .buffer(let d), .vsBuffer(let d):
                chunk = d
            case .string(let b64):
                chunk = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) ?? Data()
            default:
                if let dict = val.decodeJSONDictionary(),
                   let b64 = dict["base64"] as? String {
                    chunk = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) ?? Data()
                } else {
                    throw NSError(domain: "ZCodeInspector", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unexpected binary chunk format from host."])
                }
            }
            if chunk.isEmpty { break }
            result.append(chunk)
            offset += chunk.count
            if chunk.count < length { break }
        }
        return result
    }

    // MARK: - Live Git Status, Diffs, Branches, Commits & Mutations

    public func refreshInspectorGitStatus(state: InspectorLiveState) async {
        guard isLiveHostConnected else { return }
        let workspacePath = inspectorWorkspacePath
        guard !workspacePath.isEmpty else {
            state.gitStatusError = "No active workspace path."
            return
        }
        if state.workspacePath != workspacePath {
            state.resetForWorkspace(workspacePath)
        }
        if state.isLoadingGitStatus { return }

        state.isLoadingGitStatus = true
        state.gitStatusError = nil
        defer { state.isLoadingGitStatus = false }

        do {
            async let refreshReq = rpcClient.call(
                channel: "git",
                method: "refresh",
                args: [.fromJSONObject([
                    "workspacePath": workspacePath,
                    "includeIdentity": false,
                    "includeBranchComparison": false
                ])],
                timeoutSec: 10.0
            )
            async let branchesReq = try? rpcClient.call(
                channel: "git",
                method: "getLocalBranches",
                args: [.fromJSONObject(["workspacePath": workspacePath])],
                timeoutSec: 8.0
            )

            let refreshVal = try await refreshReq
            let branchesVal = await branchesReq

            guard let dict = refreshVal.decodeJSONDictionary() else {
                throw NSError(domain: "ZCodeInspector", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unexpected git.refresh response."])
            }

            if let summary = dict["summary"] as? [String: Any] {
                let isGitAvailable = (summary["isGitAvailable"] as? Bool) ?? true
                let isRepository = (summary["isRepository"] as? Bool) ?? false
                state.isGitAvailable = isGitAvailable
                state.isGitRepository = isRepository

                if let branch = summary["branchName"] as? String, !branch.isEmpty {
                    self.activeGitBranch = branch
                    if let pIdx = projects.firstIndex(where: { $0.id == activeProjectId }) {
                        projects[pIdx].gitBranch = branch
                    }
                }
                if let pIdx = projects.firstIndex(where: { $0.id == activeProjectId }) {
                    projects[pIdx].ahead = Self.jsonInt(summary["ahead"]) ?? 0
                    projects[pIdx].behind = Self.jsonInt(summary["behind"]) ?? 0
                    projects[pIdx].isDirty = (summary["isDirty"] as? Bool) ?? false
                }
            }

            let stagedRaw = (dict["stagedChanges"] as? [[String: Any]]) ?? []
            let unstagedRaw = (dict["unstagedChanges"] as? [[String: Any]]) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: gitChanges.map { ($0.id, $0) })

            var parsed: [GitChangedFile] = []
            for entry in stagedRaw {
                if let item = Self.parseHostGitChangedFile(entry, forceStaged: true, preserving: existingById) {
                    parsed.append(item)
                }
            }
            for entry in unstagedRaw {
                if let item = Self.parseHostGitChangedFile(entry, forceStaged: false, preserving: existingById) {
                    parsed.append(item)
                }
            }

            self.gitChanges = parsed
            state.gitStatusLoaded = true
            state.diffDetails = state.diffDetails.filter { key, _ in parsed.contains { $0.id == key } }
            if let currentSel = selectedDiffFileId, parsed.contains(where: { $0.id == currentSel }) {
                // Keep selection
            } else {
                selectedDiffFileId = parsed.first?.id
            }

            if let branchesVal, let bDict = branchesVal.decodeJSONDictionary(),
               let rawBranches = bDict["branches"] as? [[String: Any]] {
                let names = rawBranches.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
                if !names.isEmpty {
                    self.gitBranches = names
                    state.gitBranchesLoaded = true
                }
            }

            applyGitStatusBadgesToFileTree(workspacePath: workspacePath)
        } catch {
            state.gitStatusError = error.localizedDescription
        }
    }

    public func loadInspectorGitDiff(
        for file: GitChangedFile,
        state: InspectorLiveState,
        force: Bool = false
    ) async {
        guard isLiveHostConnected else { return }
        let workspacePath = inspectorWorkspacePath
        guard !workspacePath.isEmpty else { return }
        if state.loadingDiffIds.contains(file.id) { return }
        if !force, state.diffDetails[file.id] != nil { return }

        state.loadingDiffIds.insert(file.id)
        state.diffErrors.removeValue(forKey: file.id)
        defer { state.loadingDiffIds.remove(file.id) }

        do {
            let sourceId = file.isStaged ? "staged" : "unstaged"
            let val = try await rpcClient.call(
                channel: "git",
                method: "getDiff",
                args: [.fromJSONObject([
                    "workspacePath": workspacePath,
                    "path": file.path,
                    "sourceId": sourceId,
                    "staged": file.isStaged
                ])],
                timeoutSec: 10.0
            )
            guard let dict = val.decodeJSONDictionary() else {
                throw NSError(domain: "ZCodeInspector", code: -5, userInfo: [NSLocalizedDescriptionKey: "Unexpected git.getDiff response."])
            }
            let detail = InspectorDiffDetail(
                availability: (dict["availability"] as? String) ?? "unavailable",
                patch: dict["patch"] as? String,
                beforeContent: dict["beforeContent"] as? String,
                afterContent: dict["afterContent"] as? String,
                summary: dict["summary"] as? String
            )
            state.diffDetails[file.id] = detail
            if let idx = gitChanges.firstIndex(where: { $0.id == file.id }) {
                gitChanges[idx].patch = detail.patch ?? ""
                gitChanges[idx].beforeContent = detail.beforeContent ?? ""
                gitChanges[idx].afterContent = detail.afterContent ?? ""
            }
        } catch {
            state.diffErrors[file.id] = error.localizedDescription
        }
    }

    public func loadInspectorCommitLog(state: InspectorLiveState, loadMore: Bool = false) async {
        guard isLiveHostConnected else { return }
        let workspacePath = inspectorWorkspacePath
        guard !workspacePath.isEmpty else {
            state.commitsError = "No active workspace path."
            return
        }
        if state.workspacePath != workspacePath {
            state.resetForWorkspace(workspacePath)
        }
        if loadMore {
            guard !state.isLoadingMoreCommits, !state.isLoadingCommits, state.hasMoreCommits else { return }
            state.isLoadingMoreCommits = true
        } else {
            guard !state.isLoadingCommits else { return }
            state.isLoadingCommits = true
        }
        state.commitsError = nil

        defer {
            if loadMore {
                state.isLoadingMoreCommits = false
            } else {
                state.isLoadingCommits = false
            }
        }

        do {
            let skip = loadMore ? state.commitDetails.count : 0
            let val = try await rpcClient.call(
                channel: "git",
                method: "getCommitGraph",
                args: [.fromJSONObject([
                    "workspacePath": workspacePath,
                    "maxCount": 40,
                    "skip": skip
                ])],
                timeoutSec: 10.0
            )
            guard let dict = val.decodeJSONDictionary() else {
                throw NSError(domain: "ZCodeInspector", code: -6, userInfo: [NSLocalizedDescriptionKey: "Unexpected git.getCommitGraph response."])
            }
            let rawCommits = (dict["commits"] as? [[String: Any]]) ?? []
            let hasMore = (dict["hasMore"] as? Bool) ?? false

            let parsed: [InspectorCommitDetail] = rawCommits.compactMap { c in
                guard let hash = c["hash"] as? String, !hash.isEmpty else { return nil }
                let parents = (c["parents"] as? [String]) ?? []
                let rawRefs = (c["refs"] as? [[String: Any]]) ?? []
                let refs: [InspectorGitRef] = rawRefs.compactMap { r in
                    guard let name = r["name"] as? String, !name.isEmpty else { return nil }
                    let kind = (r["kind"] as? String) ?? "branch"
                    return InspectorGitRef(name: name, kind: kind)
                }
                let subject = (c["subject"] as? String) ?? ""
                let author = (c["authorName"] as? String) ?? "Unknown"
                let ts = Self.jsonDouble(c["authoredAtMs"]).map { Date(timeIntervalSince1970: $0 / 1000.0) }
                return InspectorCommitDetail(
                    hash: hash,
                    shortHash: String(hash.prefix(7)),
                    parents: parents,
                    refs: refs,
                    subject: subject,
                    author: author,
                    timestamp: ts
                )
            }

            if loadMore {
                var existing = Set(state.commitDetails.map(\.hash))
                for item in parsed where existing.insert(item.hash).inserted {
                    state.commitDetails.append(item)
                }
            } else {
                state.commitDetails = parsed
            }
            state.hasMoreCommits = hasMore
            state.commitsLoaded = true

            self.gitCommits = state.commitDetails.map { c in
                GitCommitRecord(
                    id: c.hash,
                    shortHash: c.shortHash,
                    subject: c.subject,
                    author: c.author,
                    branchRef: c.branchRefSummary,
                    timestamp: c.timestamp ?? Date()
                )
            }
        } catch {
            state.commitsError = error.localizedDescription
        }
    }

    public func toggleStageInspectorFile(_ file: GitChangedFile, state: InspectorLiveState) async {
        guard isLiveHostConnected else {
            if isUITestSeededMode {
                toggleStageGitFile(file.id)
            } else {
                showToast("Connect to host to stage changes")
            }
            return
        }
        let workspacePath = inspectorWorkspacePath
        guard !workspacePath.isEmpty, !state.isMutatingGit else { return }

        state.isMutatingGit = true
        defer { state.isMutatingGit = false }

        do {
            let method = file.isStaged ? "unstagePaths" : "stagePaths"
            _ = try await rpcClient.call(
                channel: "git",
                method: method,
                args: [.fromJSONObject([
                    "workspacePath": workspacePath,
                    "paths": [file.path]
                ])],
                timeoutSec: 8.0
            )
            state.diffDetails.removeValue(forKey: file.id)
            await refreshInspectorGitStatus(state: state)
        } catch {
            showToast("Git stage failed: \(error.localizedDescription)")
        }
    }

    public func stageAllInspectorFiles(_ stage: Bool, state: InspectorLiveState) async {
        guard isLiveHostConnected else {
            if isUITestSeededMode {
                stageAllGitChanges(stage)
            } else {
                showToast("Connect to host to stage changes")
            }
            return
        }
        let workspacePath = inspectorWorkspacePath
        guard !workspacePath.isEmpty, !state.isMutatingGit else { return }

        let targetPaths = gitChanges
            .filter { stage ? !$0.isStaged : $0.isStaged }
            .map(\.path)
        guard !targetPaths.isEmpty else { return }

        state.isMutatingGit = true
        defer { state.isMutatingGit = false }

        do {
            _ = try await rpcClient.call(
                channel: "git",
                method: stage ? "stagePaths" : "unstagePaths",
                args: [.fromJSONObject([
                    "workspacePath": workspacePath,
                    "paths": targetPaths
                ])],
                timeoutSec: 10.0
            )
            state.diffDetails.removeAll()
            await refreshInspectorGitStatus(state: state)
            showToast(stage ? "Staged all changes" : "Unstaged all changes")
        } catch {
            showToast("Git operation failed: \(error.localizedDescription)")
        }
    }

    public func commitInspectorStagedChanges(message: String, state: InspectorLiveState) async -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if !isLiveHostConnected {
            if isUITestSeededMode {
                commitStagedChanges(message: trimmed)
                return true
            }
            showToast("Connect to host before committing")
            return false
        }

        let workspacePath = inspectorWorkspacePath
        guard !workspacePath.isEmpty, !state.isMutatingGit else { return false }
        let stagedPaths = gitChanges.filter(\.isStaged).map(\.path)
        guard !stagedPaths.isEmpty else {
            showToast("Stage at least one file before committing")
            return false
        }

        state.isMutatingGit = true
        defer { state.isMutatingGit = false }

        do {
            let val = try await rpcClient.call(
                channel: "git",
                method: "commit",
                args: [.fromJSONObject([
                    "workspacePath": workspacePath,
                    "message": trimmed,
                    "stagedOnly": true
                ])],
                timeoutSec: 12.0
            )
            let commitHash = (val.decodeJSONDictionary()?["commitHash"] as? String).map { String($0.prefix(7)) }
            state.diffDetails.removeAll()
            await refreshInspectorGitStatus(state: state)
            await loadInspectorCommitLog(state: state, loadMore: false)
            if let commitHash, !commitHash.isEmpty {
                showToast("Committed \(commitHash)")
            } else {
                showToast("Committed staged changes")
            }
            return true
        } catch {
            showToast("Commit failed: \(error.localizedDescription)")
            return false
        }
    }

    public func generateInspectorCommitMessage(state: InspectorLiveState) async -> String? {
        guard isLiveHostConnected else { return nil }
        let workspacePath = inspectorWorkspacePath
        guard !workspacePath.isEmpty, !state.isGeneratingCommitMessage else { return nil }

        state.isGeneratingCommitMessage = true
        defer { state.isGeneratingCommitMessage = false }

        do {
            let hasStaged = gitChanges.contains(where: \.isStaged)
            var payload: [String: Any] = [
                "workspacePath": workspacePath,
                "includeUnstaged": !hasStaged
            ]
            if let identity = workspaceIdentityByPath[workspacePath], !identity.isEmpty {
                payload["workspaceIdentity"] = identity
            }
            let val = try await rpcClient.call(
                channel: "git",
                method: "generateCommitMessage",
                args: [.fromJSONObject(payload)],
                timeoutSec: 25.0
            )
            if let msg = val.decodeJSONDictionary()?["message"] as? String,
               !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return msg
            }
            showToast("Host did not return a commit message")
            return nil
        } catch {
            showToast("Commit message generation unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    public func switchInspectorGitBranch(_ branch: String, state: InspectorLiveState) async {
        guard isLiveHostConnected else {
            if isUITestSeededMode {
                switchGitBranch(branch)
            } else {
                showToast("Connect to host to switch branches")
            }
            return
        }
        let workspacePath = inspectorWorkspacePath
        guard !workspacePath.isEmpty, !state.isMutatingGit else { return }

        state.isMutatingGit = true
        defer { state.isMutatingGit = false }

        do {
            let val = try await rpcClient.call(
                channel: "git",
                method: "switchBranch",
                args: [.fromJSONObject([
                    "workspacePath": workspacePath,
                    "targetBranchName": branch
                ])],
                timeoutSec: 12.0
            )
            if let dict = val.decodeJSONDictionary(), (dict["ok"] as? Bool) == false {
                let issues = (dict["issues"] as? [[String: Any]]) ?? []
                let detail = issues.compactMap { ($0["message"] as? String) ?? ($0["title"] as? String) }.first
                    ?? "Unable to switch branch to \(branch)"
                showToast(detail)
                return
            }
            state.diffDetails.removeAll()
            await refreshInspectorGitStatus(state: state)
            await loadInspectorCommitLog(state: state, loadMore: false)
            showToast("Switched branch to \(branch)")
        } catch {
            showToast("Branch switch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Live Terminal PTY (`terminal` channel)

    public func startInspectorLiveTerminal(state: InspectorLiveState) async {
        guard isLiveHostConnected else { return }
        if state.isConnectingPty || (state.ptyId != nil && !state.ptyExited) { return }

        await disposeInspectorLiveTerminal(state: state)

        let cwd = inspectorWorkspacePath
        state.isConnectingPty = true
        state.ptyError = nil
        state.ptyExited = false
        state.ptyExitCode = nil
        defer { state.isConnectingPty = false }

        do {
            var req: [String: Any] = ["cols": 80, "rows": 24]
            if !cwd.isEmpty {
                req["cwd"] = cwd
            }
            let val = try await rpcClient.call(
                channel: "terminal",
                method: "create",
                args: [.fromJSONObject(req)],
                timeoutSec: 8.0
            )
            guard let dict = val.decodeJSONDictionary(),
                  let ptyId = dict["id"] as? String, !ptyId.isEmpty else {
                throw NSError(domain: "ZCodeInspector", code: -7, userInfo: [NSLocalizedDescriptionKey: "Host did not return a terminal session ID."])
            }
            state.ptyId = ptyId
            state.ptyShell = dict["shell"] as? String
            state.ptyCwd = cwd.isEmpty ? "~" : cwd

            let dataSub = try await rpcClient.listen(
                channel: "terminal",
                event: "onDynamicData",
                arg: .string(ptyId)
            ) { [weak state] chunkVal in
                guard case .string(let raw) = chunkVal else { return }
                let cleaned = Self.stripANSIControlSequences(raw)
                guard !cleaned.isEmpty else { return }
                Task { @MainActor [weak state] in
                    guard let state else { return }
                    state.ptyOutput += cleaned
                    let maxChars = 120_000
                    if state.ptyOutput.count > maxChars {
                        state.ptyOutput = String(state.ptyOutput.suffix(maxChars))
                    }
                }
            }
            state.ptyDataSubId = dataSub

            let exitSub = try await rpcClient.listen(
                channel: "terminal",
                event: "onDynamicExit",
                arg: .string(ptyId)
            ) { [weak state] exitVal in
                let code: Int?
                switch exitVal {
                case .int32(let i): code = Int(i)
                default: code = Self.jsonInt(exitVal.decodeJSONValue())
                }
                Task { @MainActor [weak state] in
                    guard let state else { return }
                    state.ptyExited = true
                    state.ptyExitCode = code
                }
            }
            state.ptyExitSubId = exitSub
        } catch {
            state.ptyError = error.localizedDescription
        }
    }

    public func sendInspectorTerminalInput(_ rawData: String, state: InspectorLiveState) async {
        guard isLiveHostConnected, let ptyId = state.ptyId, !state.ptyExited else { return }
        do {
            _ = try await rpcClient.call(
                channel: "terminal",
                method: "write",
                args: [.fromJSONObject(["id": ptyId, "data": rawData])],
                timeoutSec: 5.0
            )
        } catch {
            state.ptyError = error.localizedDescription
        }
    }

    public func disposeInspectorLiveTerminal(state: InspectorLiveState) async {
        if let dataSub = state.ptyDataSubId {
            state.ptyDataSubId = nil
            await rpcClient.unlisten(dataSub)
        }
        if let exitSub = state.ptyExitSubId {
            state.ptyExitSubId = nil
            await rpcClient.unlisten(exitSub)
        }
        if let ptyId = state.ptyId {
            state.ptyId = nil
            if isLiveHostConnected {
                _ = try? await rpcClient.call(
                    channel: "terminal",
                    method: "dispose",
                    args: [.fromJSONObject(["id": ptyId])],
                    timeoutSec: 3.0
                )
            }
        }
    }

    // MARK: - Helpers

    private func applyGitStatusBadgesToFileTree(workspacePath: String) {
        guard !fileTree.isEmpty else { return }
        var statusByRelPath: [String: String] = [:]
        for change in gitChanges {
            let normalized = change.path.hasPrefix("/") ? change.path : change.path
            statusByRelPath[normalized] = change.status
        }
        let prefix = workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/"

        func apply(_ nodes: inout [WorkspaceFileNode]) {
            for idx in nodes.indices {
                if !nodes[idx].isDirectory {
                    let full = nodes[idx].path
                    let rel = full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
                    nodes[idx].gitStatus = statusByRelPath[rel] ?? statusByRelPath[full]
                } else if nodes[idx].children != nil {
                    var children = nodes[idx].children ?? []
                    apply(&children)
                    nodes[idx].children = children
                }
            }
        }
        apply(&fileTree)
    }

    static func parseHostGitChangedFile(
        _ entry: [String: Any],
        forceStaged: Bool,
        preserving existingById: [String: GitChangedFile]
    ) -> GitChangedFile? {
        let displayPath = (entry["workspaceRelativePath"] as? String)
            ?? (entry["repoRelativePath"] as? String)
            ?? (entry["path"] as? String)
        guard let displayPath, !displayPath.isEmpty else { return nil }

        let isStaged = (entry["isStaged"] as? Bool) ?? forceStaged
        let isUntracked = (entry["isUntracked"] as? Bool) ?? false
        let isConflicted = (entry["isConflicted"] as? Bool) ?? false
        let status = mapGitStatusLetter(
            kind: entry["kind"] as? String,
            x: entry["x"] as? String,
            y: entry["y"] as? String,
            isStaged: isStaged,
            isUntracked: isUntracked,
            isConflicted: isConflicted
        )
        let added = jsonInt(entry["added"]) ?? 0
        let removed = jsonInt(entry["removed"]) ?? 0
        let id = "git-live-\(isStaged ? "staged" : "unstaged")-\(displayPath)"
        let existing = existingById[id]

        return GitChangedFile(
            id: id,
            path: displayPath,
            status: status,
            isStaged: isStaged,
            added: added,
            removed: removed,
            patch: existing?.patch ?? "",
            beforeContent: existing?.beforeContent ?? "",
            afterContent: existing?.afterContent ?? ""
        )
    }

    private static func mapGitStatusLetter(
        kind: String?,
        x: String?,
        y: String?,
        isStaged: Bool,
        isUntracked: Bool,
        isConflicted: Bool
    ) -> String {
        if isConflicted { return "!" }
        if isUntracked { return "U" }
        switch kind?.lowercased() {
        case "added": return "A"
        case "deleted": return "D"
        case "renamed": return "R"
        case "copied": return "C"
        case "untracked": return "U"
        case "conflicted": return "!"
        case "modified": return "M"
        default: break
        }
        let raw = isStaged ? (x ?? y ?? "M") : (y ?? x ?? "M")
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." { return "M" }
        if trimmed == "?" { return "U" }
        return String(trimmed.prefix(1)).uppercased()
    }

    nonisolated static func jsonInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        return nil
    }

    nonisolated static func jsonDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    nonisolated static func stableInspectorId(for input: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    nonisolated static func stripANSIControlSequences(_ text: String) -> String {
        // Strip CSI (\x1b[...cmd) and OSC (\x1b]...\x07 or \x1b\\) sequences while keeping newlines/tabs
        var out = text.replacingOccurrences(of: "\r\n", with: "\n")
        out = out.replacingOccurrences(
            of: "\u{1B}\\][^\\u{07}\\u{1B}]*(?:\\u{07}|\u{1B}\\\\)",
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(of: "\r", with: "")
        return out
    }
}
