import SwiftUI
import PDFKit

/// 100% Native File, Image, PDF (PDFKit), Markdown, CSV, and Syntax Code Viewer — ZERO WebKit!
public struct NativeMediaDocumentViewer: View {
    @Bindable var store: AppStore
    @Bindable var liveState: InspectorLiveState
    @Environment(\.zcodePalette) private var palette
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var showPixelGrid: Bool = false
    @State private var showRawTextSource: Bool = false

    @MainActor
    public init(store: AppStore, liveState: InspectorLiveState? = nil) {
        self.store = store
        self.liveState = liveState ?? InspectorLiveState()
    }

    private var switcherFiles: [WorkspaceFileNode] {
        if store.isUITestSeededMode {
            let raw = store.flattenedFiles.filter { [.image, .pdf, .markdown, .csv].contains($0.kind) }
            let priorityOrder = ["file-arch-png", "file-spec-pdf", "file-benchmarks-csv", "file-readme", "file-telemetry-png"]
            return raw.sorted { a, b in
                let ia = priorityOrder.firstIndex(of: a.id) ?? 99
                let ib = priorityOrder.firstIndex(of: b.id) ?? 99
                return ia < ib
            }
        }

        // In live mode, surface open files + currently selected file + discovered rich assets
        var ordered: [WorkspaceFileNode] = []
        var seen = Set<String>()
        if !store.selectedFileId.isEmpty, let sel = store.findFileNode(id: store.selectedFileId), !sel.isDirectory {
            ordered.append(sel)
            seen.insert(sel.id)
        }
        for id in store.openFileIds {
            if !seen.contains(id), let node = store.findFileNode(id: id), !node.isDirectory {
                ordered.append(node)
                seen.insert(node.id)
            }
        }
        for node in store.flattenedFiles where !seen.contains(node.id) {
            let kind = liveState.effectiveMediaKind(for: node)
            if kind == .image || kind == .pdf || node.kind == .markdown || node.kind == .csv {
                ordered.append(node)
                seen.insert(node.id)
            }
        }
        return ordered
    }

    private var activePreviewFile: WorkspaceFileNode? {
        if store.isUITestSeededMode {
            if let selected = store.selectedFile, [.image, .pdf, .markdown, .csv].contains(selected.kind) {
                return selected
            }
            return switcherFiles.first
        }
        if !store.selectedFileId.isEmpty, let sel = store.findFileNode(id: store.selectedFileId), !sel.isDirectory {
            return sel
        }
        return switcherFiles.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            // File / Asset Switcher Strip
            if !switcherFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(switcherFiles) { item in
                            let isCurrent = item.id == activePreviewFile?.id
                            Button {
                                store.selectedFileId = item.id
                                if !store.openFileIds.contains(item.id) {
                                    store.openFileIds.append(item.id)
                                }
                                zoomScale = 1.0
                                panOffset = .zero
                                showRawTextSource = false
                                if store.isLiveHostConnected {
                                    Task { @MainActor in
                                        await store.loadInspectorFile(node: item, state: liveState)
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: icon(for: item))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(isCurrent ? palette.accentBlue : palette.foregroundSubtle)
                                    Text(compactAssetName(item.name))
                                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                                        .foregroundStyle(isCurrent ? palette.foreground : palette.foregroundSubtle)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 30)
                                .background(isCurrent ? palette.card : palette.surfaceHover, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isCurrent ? palette.borderStrong : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("previewAssetChip_\(item.id)")
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 42)
                .background(palette.panel)

                Rectangle().fill(palette.border).frame(height: 1)
            }

            if let file = activePreviewFile {
                viewerContent(for: file)
                    .task(id: "\(file.id)-\(store.isLiveHostConnected)") {
                        guard store.isLiveHostConnected else { return }
                        await store.loadInspectorFile(node: file, state: liveState)
                    }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(palette.foregroundMuted)
                    Text("No file selected")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text("Choose a file from the Files tab to inspect its contents, image, or PDF.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button {
                        store.activeInspectorTab = .files
                    } label: {
                        Text("Browse Files")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(palette.accentBlue)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(palette.accentBlue.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func viewerContent(for file: WorkspaceFileNode) -> some View {
        let outcome = liveState.fileStates[file.id]
        let mediaKind = liveState.effectiveMediaKind(for: file)
        let isRichTextFormat = mediaKind == .text && (file.kind == .markdown || file.kind == .csv)

        // Toolbar with Path, Size, Controls, Attach
        HStack(spacing: 8) {
            Text(file.path)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.foregroundSubtle)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let bytes = liveState.knownSizeBytes(for: file) {
                Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.foregroundMuted)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if mediaKind == .image && file.binaryData != nil {
                Button {
                    showPixelGrid.toggle()
                } label: {
                    Image(systemName: "grid")
                        .font(.system(size: 12.5))
                        .foregroundStyle(showPixelGrid ? palette.accentBlue : palette.foregroundSubtle)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.25)) {
                        zoomScale = max(0.5, zoomScale - 0.25)
                    }
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .buttonStyle(.plain)

                Text("\(Int(zoomScale * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.foreground)

                Button {
                    withAnimation(.spring(response: 0.25)) {
                        zoomScale = min(5.0, zoomScale + 0.25)
                    }
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .buttonStyle(.plain)
            } else if isRichTextFormat && file.textContent != nil {
                Button {
                    showRawTextSource.toggle()
                } label: {
                    Text(showRawTextSource ? "Rendered" : "Source")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Button {
                let realBytes = liveState.knownSizeBytes(for: file) ?? file.sizeBytes
                store.composerAttachments.append(
                    ComposerAttachment(
                        id: UUID().uuidString,
                        name: "@\(file.name)",
                        kind: mediaKind == .image ? "image" : "file",
                        sizeBytes: realBytes,
                        filePath: file.path,
                        lineNote: nil,
                        previewPNGData: mediaKind == .image ? file.binaryData : nil
                    )
                )
                store.showToast("Attached \(file.name) to chat composer")
            } label: {
                Text("Attach")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.accentBlue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(palette.accentBlue.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("attachPreviewToChatButton")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(palette.header)

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
        } else {
            switch mediaKind {
            case .image:
                nativeImageCanvas(file)
            case .pdf:
                if let pdfData = file.binaryData, !pdfData.isEmpty {
                    NativePDFKitView(data: pdfData)
                        .accessibilityIdentifier("nativePDFKitViewer")
                } else if store.isLiveHostConnected {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading PDF…")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    unavailablePreviewView(file: file, subtitle: "PDF data not loaded.")
                }
            case .binary, .directory:
                unavailablePreviewView(file: file, subtitle: "Preview not available")
            case .text:
                if let text = file.textContent {
                    VStack(spacing: 0) {
                        if outcome?.isTruncated == true {
                            truncationBanner(
                                loadedBytes: outcome?.loadedBytes ?? text.utf8.count,
                                totalBytes: outcome?.totalBytes ?? file.sizeBytes
                            )
                        }
                        if !showRawTextSource && file.kind == .csv {
                            nativeCSVTable(text)
                        } else if !showRawTextSource && file.kind == .markdown {
                            nativeMarkdownPreview(text)
                        } else {
                            nativeTextWithLineNumbers(file: file, text: text)
                        }
                    }
                } else if store.isLiveHostConnected {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading \(file.name)…")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    unavailablePreviewView(file: file, subtitle: "Preview not available")
                }
            }
        }
    }

    private func truncationBanner(loadedBytes: Int, totalBytes: Int) -> some View {
        let loadedStr = ByteCountFormatter.string(fromByteCount: Int64(loadedBytes), countStyle: .file)
        let totalStr = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        return HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(palette.warning)
            Text("Showing first \(loadedStr) of \(totalStr) — text capped at 1 MB.")
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

    private func unavailablePreviewView(file: WorkspaceFileNode, subtitle: String) -> some View {
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
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Native Syntax Text Viewer with Line Numbers

    private func nativeTextWithLineNumbers(file: WorkspaceFileNode, text: String) -> some View {
        let syntaxColors = SyntaxColors.palette(for: store.syntaxTheme)
        let lines = text.components(separatedBy: "\n")
        let lang = SyntaxHighlighter.detectLanguage(for: file.path)

        return ScrollView([.vertical, store.wrapCodeLines ? [] : .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 0) {
                        Text("\(idx + 1)")
                            .font(.system(size: CGFloat(store.codeFontSize - 1), design: .monospaced))
                            .foregroundStyle(syntaxColors.gutterText)
                            .frame(width: 42, alignment: .trailing)
                            .padding(.trailing, 8)
                            .padding(.vertical, 2.5)
                            .background(syntaxColors.gutterBackground)

                        Text(SyntaxHighlighter.highlightLine(
                            line,
                            language: lang,
                            theme: store.syntaxTheme,
                            fontSize: CGFloat(store.codeFontSize),
                            searchQuery: ""
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

    private func compactAssetName(_ name: String) -> String {
        switch name {
        case "architecture-overview.png": return "architecture.png"
        case "ZCode-Enterprise-Spec.pdf": return "Spec.pdf"
        case "rpc-benchmarks.csv": return "benchmarks.csv"
        case "telemetry-latency-chart.png": return "telemetry.png"
        default: return name
        }
    }

    // MARK: - Native Pinch-Zoom Image Inspector

    private func nativeImageCanvas(_ file: WorkspaceFileNode) -> some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0x101114)

                if let data = file.binaryData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            if showPixelGrid {
                                Canvas { context, size in
                                    var path = Path()
                                    for x in stride(from: 0, to: size.width, by: 24) {
                                        path.move(to: CGPoint(x: x, y: 0))
                                        path.addLine(to: CGPoint(x: x, y: size.height))
                                    }
                                    for y in stride(from: 0, to: size.height, by: 24) {
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: size.width, y: y))
                                    }
                                    context.stroke(path, with: .color(.cyan.opacity(0.28)), lineWidth: 0.6)
                                }
                            }
                        }
                        .padding(16)
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomScale = min(6.0, max(0.6, value))
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if zoomScale > 1.05 {
                                        panOffset = value.translation
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.25)) {
                                if zoomScale > 1.1 {
                                    zoomScale = 1.0
                                    panOffset = .zero
                                } else {
                                    zoomScale = 2.0
                                }
                            }
                        }

                    // Crisp Single-Line Image Metadata HUD
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(Int(uiImage.size.width * uiImage.scale))×\(Int(uiImage.size.height * uiImage.scale))px")
                            Text("•")
                            Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                            Text("•")
                            Text("Pinch / 2× Tap Zoom")
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.68), in: Capsule())
                        .padding(.bottom, 14)
                    }
                } else if file.binaryData != nil {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Unable to decode \(file.name)")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                } else if store.isLiveHostConnected {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading image…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                } else {
                    Text("Preview not available")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .accessibilityIdentifier("nativeImageCanvas")
    }

    // MARK: - Native CSV Data Table Grid

    private func nativeCSVTable(_ csvText: String) -> some View {
        let rows = csvText
            .split(whereSeparator: \.isNewline)
            .prefix(500)
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) } }

        return ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, cols in
                    HStack(spacing: 0) {
                        ForEach(Array(cols.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.system(size: 12.5, weight: rIdx == 0 ? .bold : .regular, design: rIdx == 0 ? .default : .monospaced))
                                .foregroundStyle(rIdx == 0 ? palette.foreground : palette.foregroundSubtle)
                                .frame(width: 155, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                        }
                    }
                    .background(rIdx == 0 ? palette.card : (rIdx.isMultiple(of: 2) ? palette.background : palette.panel))
                    Rectangle().fill(palette.border).frame(height: 1)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Native Markdown Rich Renderer

    private func nativeMarkdownPreview(_ md: String) -> some View {
        let lines = md.components(separatedBy: "\n")
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.hasPrefix("# ") {
                        Text(String(line.dropFirst(2)))
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(palette.foreground)
                    } else if line.hasPrefix("## ") {
                        Text(String(line.dropFirst(3)))
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                            .padding(.top, 4)
                    } else if line.hasPrefix("### ") {
                        Text(String(line.dropFirst(4)))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                            .padding(.top, 2)
                    } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(palette.accentBlue)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text((try? AttributedString(markdown: String(line.dropFirst(2)))) ?? AttributedString(String(line.dropFirst(2))))
                                .font(.system(size: 14))
                                .foregroundStyle(palette.foreground)
                                .textSelection(.enabled)
                        }
                    } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
                            .font(.system(size: 14))
                            .foregroundStyle(palette.foregroundSubtle)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func icon(for node: WorkspaceFileNode) -> String {
        let mediaKind = liveState.effectiveMediaKind(for: node)
        switch mediaKind {
        case .image: return "photo"
        case .pdf: return "doc.viewfinder"
        case .binary: return "doc.zipper"
        case .directory: return "folder"
        case .text:
            switch node.kind {
            case .csv: return "tablecells"
            case .markdown: return "doc.richtext"
            case .json: return "curlybraces"
            default: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }
}

/// Pure Apple PDFKit UIViewRepresentable (Zero WebKit)
public struct NativePDFKitView: UIViewRepresentable {
    public let data: Data

    public final class Coordinator {
        var loadedDataCount: Int = -1
        var loadedDataPrefix: Data = Data()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        pdfView.document = PDFDocument(data: data)
        context.coordinator.loadedDataCount = data.count
        context.coordinator.loadedDataPrefix = data.prefix(64)
        return pdfView
    }

    public func updateUIView(_ pdfView: PDFView, context: Context) {
        let prefix = data.prefix(64)
        if pdfView.document == nil ||
            context.coordinator.loadedDataCount != data.count ||
            context.coordinator.loadedDataPrefix != prefix {
            pdfView.document = PDFDocument(data: data)
            context.coordinator.loadedDataCount = data.count
            context.coordinator.loadedDataPrefix = prefix
        }
    }
}
