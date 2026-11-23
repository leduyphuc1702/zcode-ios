import Foundation

// MARK: - Preview Kind

/// What native renderer a preview tab should use. Mirrors the desktop side-pane
/// "open code viewer" routing (`onOpenCodeViewer({type:"file",path,title})`).
public enum InspectorPreviewKind: String, Equatable, Sendable {
    case image
    case pdf
    case markdown
    case csv
    case code
    case text
    case binary
}

// MARK: - Path Rules

/// Pure path handling for preview tabs: transcript tool rows may report bare
/// workspace-relative paths (`README.md`), absolute host paths (`/tmp/shots/x.png`),
/// quoted/backticked markdown paths, or `file://` URLs. Paths may also carry a
/// trailing `:line` / `:line-column` range from editor-style references.
public enum InspectorPreviewPath {
    private static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx", "cs", "java", "kt", "kts",
        "scala", "go", "rs", "rb", "php", "py", "pyi", "pl", "lua", "r", "jl", "dart",
        "js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts", "vue", "svelte", "astro",
        "json", "jsonc", "jsonl", "yaml", "yml", "toml", "ini", "cfg", "conf", "properties",
        "env", "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "sql", "graphql", "gql",
        "html", "htm", "xml", "xsl", "svg", "css", "scss", "sass", "less", "styl",
        "gradle", "cmake", "mk", "makefile", "dockerfile", "proto", "thrift", "tf", "tfvars",
        "lock", "plist", "entitlements", "xcconfig", "pbxproj", "strings", "resx"
    ]

    /// Trims whitespace, matching quotes/backticks, `file://` scheme, and a trailing line reference.
    public static func normalizedInput(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        if value.hasPrefix("file://") {
            value = String(value.dropFirst("file://".count))
            value = value.removingPercentEncoding ?? value
        }
        return strippingLineSuffix(value)
    }

    /// `Sources/App.swift:42`, `App.swift:42:7` and `App.swift:42-57` → `Sources/App.swift`.
    public static func strippingLineSuffix(_ value: String) -> String {
        guard !value.contains("://") else { return value }
        var candidate = value
        while let colon = candidate.lastIndex(of: ":") {
            let suffix = candidate[candidate.index(after: colon)...]
            guard !suffix.isEmpty,
                  suffix.allSatisfy({ $0.isNumber || $0 == "-" }),
                  suffix.contains(where: \.isNumber) else { return value }
            let base = String(candidate[..<colon])
            if hasFileExtension(base) {
                return base
            }
            candidate = base
        }
        return value
    }

    private static func hasFileExtension(_ path: String) -> Bool {
        guard let lastComponent = path.split(separator: "/").last,
              let dot = lastComponent.lastIndex(of: "."),
              dot != lastComponent.startIndex else { return false }
        let ext = lastComponent[lastComponent.index(after: dot)...]
        return !ext.isEmpty && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Resolves a transcript path against the active workspace. Absolute paths are
    /// preserved (outside-tree host paths such as `/tmp/shots/a.png` stay valid),
    /// `~` paths are forwarded to the host untouched, and relative paths are joined
    /// onto the workspace root.
    public static func resolve(_ raw: String, workspacePath: String) -> String {
        let value = normalizedInput(raw)
        guard !value.isEmpty else { return value }
        if value.hasPrefix("/") {
            return standardize(value)
        }
        if value.hasPrefix("~") {
            return value
        }
        let workspace = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !workspace.isEmpty, workspace != "~", workspace.hasPrefix("/") {
            return standardize(workspace + "/" + value)
        }
        return standardize(value)
    }

    public static func standardize(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// Case-insensitive identity used to dedupe tabs (macOS volumes are typically
    /// case-insensitive, and the desktop side pane reuses an existing tab by path).
    public static func canonicalKey(_ path: String) -> String {
        standardize(path).lowercased()
    }

    public static func fileName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    /// Kind for in-memory attachment bytes (no host path), using MIME type first
    /// and the file extension as fallback.
    public static func kind(fileName: String, mimeType: String) -> InspectorPreviewKind {
        let mime = mimeType
            .lowercased()
            .split(separator: ";", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if mime.hasPrefix("image/") { return .image }
        if mime == "application/pdf" || mime == "application/x-pdf" { return .pdf }
        switch mime {
        case "text/markdown", "text/x-markdown": return .markdown
        case "text/csv": return .csv
        default: break
        }
        let byExtension = kind(forPath: fileName)
        if mime.hasPrefix("text/") {
            switch byExtension {
            case .image, .pdf, .binary: return .text
            default: return byExtension
            }
        }
        if mime.contains("json") || mime.contains("xml") || mime.contains("javascript") {
            return .code
        }
        return byExtension
    }

    public static func kind(forPath path: String) -> InspectorPreviewKind {
        let mediaKind = InspectorFileMediaKind.classify(name: fileName(path), isDirectory: false)
        switch mediaKind {
        case .image: return .image
        case .pdf: return .pdf
        case .binary: return .binary
        case .directory: return .binary
        case .text:
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            switch ext {
            case "md", "markdown", "mdx": return .markdown
            case "csv", "tsv": return .csv
            default:
                return codeExtensions.contains(ext) ? .code : .text
            }
        }
    }

    /// Display path for the preview header: absolute stays absolute, workspace-relative
    /// keeps its short form (matching the desktop tab/header behavior).
    public static func displayPath(raw: String, workspacePath: String, resolved: String) -> String {
        let value = normalizedInput(raw)
        if value.isEmpty || value.hasPrefix("/") || value.hasPrefix("~") {
            return value.isEmpty ? resolved : value
        }
        return value
    }
}

// MARK: - Preview Tab

/// One open document in the inspector "Viewer" pane. Content is cached on the tab
/// so tabs are cheap to switch and survive workspace tree refreshes.
public struct InspectorPreviewTab: Identifiable, Equatable, Sendable {
    public var id: String
    /// Absolute (or host-resolvable) path used for `file.*` RPC reads.
    public var path: String
    /// Short path shown to the user (workspace-relative when applicable).
    public var displayPath: String
    public var name: String
    public var kind: InspectorPreviewKind
    /// Workspace tree node backing this tab, when the file exists in the tree.
    public var workspaceNodeId: String?
    public var textContent: String?
    public var binaryData: Data?
    public var sizeBytes: Int
    public var totalBytes: Int?
    public var isLoading: Bool
    public var errorMessage: String?
    public var isTruncated: Bool
    public var isBinaryDetected: Bool
    /// Bytes came from the caller (chat attachment) instead of a host path.
    public var isDataBacked: Bool

    public init(
        id: String? = nil,
        path: String,
        displayPath: String? = nil,
        name: String? = nil,
        kind: InspectorPreviewKind? = nil,
        workspaceNodeId: String? = nil,
        textContent: String? = nil,
        binaryData: Data? = nil,
        sizeBytes: Int = 0,
        totalBytes: Int? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        isTruncated: Bool = false,
        isBinaryDetected: Bool = false,
        isDataBacked: Bool = false
    ) {
        self.path = path
        self.displayPath = displayPath ?? path
        self.name = name ?? InspectorPreviewPath.fileName(path)
        self.kind = kind ?? InspectorPreviewPath.kind(forPath: path)
        self.workspaceNodeId = workspaceNodeId
        self.textContent = textContent
        self.binaryData = binaryData
        self.sizeBytes = sizeBytes
        self.totalBytes = totalBytes
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.isTruncated = isTruncated
        self.isBinaryDetected = isBinaryDetected
        self.isDataBacked = isDataBacked
        self.id = id ?? InspectorPreviewTab.makeId(path: path)
    }

    public init(node: WorkspaceFileNode, resolvedPath: String? = nil) {
        let path = resolvedPath ?? node.path
        let kind: InspectorPreviewKind
        switch node.kind {
        case .image: kind = .image
        case .pdf: kind = .pdf
        case .markdown: kind = .markdown
        case .csv: kind = .csv
        case .json, .code: kind = .code
        case .directory: kind = .binary
        }
        self.init(
            path: path,
            displayPath: node.path,
            name: node.name,
            kind: kind,
            workspaceNodeId: node.id,
            textContent: node.textContent,
            binaryData: node.binaryData,
            sizeBytes: node.sizeBytes,
            totalBytes: node.sizeBytes > 0 ? node.sizeBytes : nil
        )
    }

    public var canonicalKey: String { InspectorPreviewPath.canonicalKey(path) }

    public var effectiveKind: InspectorPreviewKind {
        if isBinaryDetected { return .binary }
        return kind
    }

    /// FNV-1a keeps tab identifiers stable across launches and cheap to compare.
    public static func makeId(path: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in InspectorPreviewPath.canonicalKey(path).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "preview-%016llx", hash)
    }
}

// MARK: - Tab Container

/// Pure open/activate/close tab state. Mirrors ZCode Desktop's side-pane editor
/// tabs: each opened file is a tab, re-opening a path activates its tab, and
/// closing picks the adjacent tab.
public struct InspectorPreviewTabs: Equatable, Sendable {
    public private(set) var tabs: [InspectorPreviewTab]
    public private(set) var activeTabId: String

    public init(tabs: [InspectorPreviewTab] = [], activeTabId: String = "") {
        self.tabs = tabs
        if tabs.contains(where: { $0.id == activeTabId }) {
            self.activeTabId = activeTabId
        } else {
            self.activeTabId = tabs.first?.id ?? ""
        }
    }

    public var isEmpty: Bool { tabs.isEmpty }

    public var activeTab: InspectorPreviewTab? {
        tabs.first(where: { $0.id == activeTabId })
    }

    public func tab(id: String) -> InspectorPreviewTab? {
        tabs.first(where: { $0.id == id })
    }

    public func tab(matchingPath path: String) -> InspectorPreviewTab? {
        let key = InspectorPreviewPath.canonicalKey(path)
        return tabs.first(where: { $0.canonicalKey == key })
    }

    /// Adds a tab or activates the existing tab for the same file. Returns the
    /// tab that is now active.
    @discardableResult
    public mutating func open(_ incoming: InspectorPreviewTab) -> InspectorPreviewTab {
        let matchesPath = !incoming.path.isEmpty
            && tabs.contains(where: { !$0.path.isEmpty && $0.canonicalKey == incoming.canonicalKey })
        if let index = tabs.firstIndex(where: { $0.id == incoming.id })
            ?? (matchesPath ? tabs.firstIndex(where: { !$0.path.isEmpty && $0.canonicalKey == incoming.canonicalKey }) : nil) {
            var existing = tabs[index]
            if incoming.isDataBacked {
                // Attachment bytes are authoritative: a re-open may carry fresh data.
                existing.path = incoming.path
                existing.displayPath = incoming.displayPath
                existing.name = incoming.name
                existing.kind = incoming.kind
                existing.workspaceNodeId = nil
                existing.textContent = incoming.textContent
                existing.binaryData = incoming.binaryData
                existing.sizeBytes = incoming.sizeBytes
                existing.totalBytes = incoming.totalBytes
                existing.isLoading = false
                existing.errorMessage = nil
                existing.isTruncated = false
                existing.isBinaryDetected = incoming.isBinaryDetected
                existing.isDataBacked = true
            } else {
                if existing.workspaceNodeId == nil { existing.workspaceNodeId = incoming.workspaceNodeId }
                if existing.textContent == nil { existing.textContent = incoming.textContent }
                if existing.binaryData == nil { existing.binaryData = incoming.binaryData }
                if existing.sizeBytes == 0 { existing.sizeBytes = incoming.sizeBytes }
            }
            tabs[index] = existing
            activeTabId = existing.id
            return existing
        }
        tabs.append(incoming)
        activeTabId = incoming.id
        return incoming
    }

    public mutating func activate(id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    public mutating func replace(_ tab: InspectorPreviewTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs[index] = tab
    }

    /// Removes a tab and returns the id that should be active afterwards.
    @discardableResult
    public mutating func close(id: String) -> String {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return activeTabId }
        let wasActive = activeTabId == id
        tabs.remove(at: index)
        if tabs.isEmpty {
            activeTabId = ""
            return activeTabId
        }
        if wasActive {
            activeTabId = tabs[min(index, tabs.count - 1)].id
        } else if !tabs.contains(where: { $0.id == activeTabId }) {
            activeTabId = tabs[min(index, tabs.count - 1)].id
        }
        return activeTabId
    }

    public mutating func removeAll() {
        tabs.removeAll()
        activeTabId = ""
    }

    /// Test-fixture seeding only (`isUITestSeededMode`). Keeps the seeded viewer
    /// chips (`previewAssetChip_<nodeId>`) deterministic and orders the rich asset
    /// chips first so they stay on-screen on compact widths; the selected tab (often
    /// a code fixture) is added last but stays active.
    public static func fixtureTabs(from tree: [WorkspaceFileNode], selecting nodeId: String) -> InspectorPreviewTabs {
        func flatten(_ nodes: [WorkspaceFileNode]) -> [WorkspaceFileNode] {
            var out: [WorkspaceFileNode] = []
            for node in nodes {
                if !node.isDirectory { out.append(node) }
                if let children = node.children { out.append(contentsOf: flatten(children)) }
            }
            return out
        }
        let priorityOrder = ["file-arch-png", "file-spec-pdf", "file-benchmarks-csv", "file-readme", "file-telemetry-png"]
        let all = flatten(tree)
        var ordered: [WorkspaceFileNode] = []
        for id in priorityOrder {
            if let node = all.first(where: { $0.id == id }) { ordered.append(node) }
        }
        for node in all where [.image, .pdf, .markdown, .csv].contains(node.kind) {
            if !ordered.contains(where: { $0.id == node.id }) {
                ordered.append(node)
            }
        }
        var selectedTabId = ""
        if let selected = all.first(where: { $0.id == nodeId }) {
            let tab = InspectorPreviewTab(node: selected)
            selectedTabId = tab.id
            if !ordered.contains(where: { $0.id == selected.id }) {
                ordered.append(selected)
            }
        }
        let tabs = ordered.map { InspectorPreviewTab(node: $0) }
        return InspectorPreviewTabs(
            tabs: tabs,
            activeTabId: selectedTabId.isEmpty ? (tabs.first?.id ?? "") : selectedTabId
        )
    }
}
