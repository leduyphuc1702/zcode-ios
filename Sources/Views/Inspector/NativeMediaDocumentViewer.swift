import SwiftUI
import PDFKit

/// 100% native file preview pane — images, PDFs (PDFKit), Markdown, CSV, and code
/// with a desktop-style tab strip. ZERO WebKit. Content comes from the host
/// `file.*` RPCs, so absolute paths outside the workspace tree preview too.
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

    private var tabs: [InspectorPreviewTab] { store.previewTabs.tabs }
    private var activeTab: InspectorPreviewTab? { store.previewTabs.activeTab }
    private var activeTabId: String { store.previewTabs.activeTabId }

    public var body: some View {
        VStack(spacing: 0) {
            if !tabs.isEmpty {
                tabStrip

                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)
            }

            if let tab = activeTab {
                viewerContent(for: tab)
                    .task(id: "\(tab.id)|\(store.isLiveHostConnected)") {
                        await store.loadPreviewTabContentIfNeeded(id: tab.id)
                    }
            } else {
                emptyState
            }
        }
        .onChange(of: activeTabId) { _, _ in
            resetViewport()
        }
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(tabs) { tab in
                    tabChip(tab)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 42)
        .background(palette.panel)
    }

    private func tabChip(_ tab: InspectorPreviewTab) -> some View {
        let isCurrent = tab.id == activeTabId
        return HStack(spacing: 2) {
            Button {
                store.activatePreviewTab(id: tab.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: icon(for: tab))
                        .font(.system(size: 11))
                        .foregroundStyle(isCurrent ? palette.accentBlue : palette.foregroundSubtle)
                    Text(tabLabel(tab))
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? palette.foreground : palette.foregroundSubtle)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.leading, 9)
                .padding(.trailing, 3)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.name)
            .accessibilityIdentifier(tabAccessibilityIdentifier(tab))

            Button {
                store.closePreviewTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isCurrent ? palette.foreground : palette.foregroundMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(tab.name)")
            .accessibilityIdentifier("closePreviewTab_\(tab.id)")
        }
        .padding(.trailing, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isCurrent ? palette.card : palette.surfaceHover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isCurrent ? palette.borderStrong : Color.clear, lineWidth: 1)
        )
    }

    /// Test-fixture chip labels stay short so the seeded preview chips remain
    /// reachable on compact simulator widths (production always shows real names).
    private func tabLabel(_ tab: InspectorPreviewTab) -> String {
        guard store.isUITestSeededMode else { return tab.name }
        switch tab.name {
        case "architecture-overview.png": return "architecture.png"
        case "ZCode-Enterprise-Spec.pdf": return "Spec.pdf"
        case "rpc-benchmarks.csv": return "benchmarks.csv"
        case "telemetry-latency-chart.png": return "telemetry.png"
        default: return tab.name
        }
    }

    private func tabAccessibilityIdentifier(_ tab: InspectorPreviewTab) -> String {
        if store.isUITestSeededMode, let nodeId = tab.workspaceNodeId {
            return "previewAssetChip_\(nodeId)"
        }
        return "previewTab_\(tab.id)"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(palette.foregroundMuted)
            Text("No file open")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.foreground)
            Text("Tap a file or image in the chat to preview it here.")
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

    // MARK: - Active Document

    @ViewBuilder
    private func viewerContent(for tab: InspectorPreviewTab) -> some View {
        let mediaKind = tab.effectiveKind
        let isRichTextFormat = mediaKind == .markdown || mediaKind == .csv

        // Toolbar: path, size, zoom/source controls, attach
        HStack(spacing: 8) {
            Text(tab.displayPath)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.foregroundSubtle)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if tab.sizeBytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: Int64(tab.sizeBytes), countStyle: .file))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.foregroundMuted)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if mediaKind == .image && tab.binaryData != nil {
                Button {
                    showPixelGrid.toggle()
                } label: {
                    Image(systemName: "grid")
                        .font(.system(size: 12.5))
                        .foregroundStyle(showPixelGrid ? palette.accentBlue : palette.foregroundSubtle)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPixelGrid ? "Hide pixel grid" : "Show pixel grid")

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
                .accessibilityLabel("Zoom out")

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
                .accessibilityLabel("Zoom in")
            } else if isRichTextFormat && tab.textContent != nil {
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
                .accessibilityLabel(showRawTextSource ? "Show rendered view" : "Show source")
            }

            Button {
                store.composerAttachments.append(
                    ComposerAttachment(
                        id: UUID().uuidString,
                        name: "@\(tab.name)",
                        kind: mediaKind == .image ? "image" : "file",
                        sizeBytes: tab.sizeBytes,
                        filePath: tab.isDataBacked ? tab.displayPath : tab.path,
                        lineNote: nil,
                        previewPNGData: mediaKind == .image ? tab.binaryData : nil
                    )
                )
                store.showToast("Attached \(tab.name) to chat composer")
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

        if tab.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(tab.name)…")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = tab.errorMessage {
            previewErrorView(tab: tab, message: error)
        } else {
            switch mediaKind {
            case .image:
                nativeImageCanvas(tab)
            case .pdf:
                if let pdfData = tab.binaryData, !pdfData.isEmpty {
                    NativePDFKitView(data: pdfData)
                        .accessibilityIdentifier("nativePDFKitViewer")
                } else if store.isLiveHostConnected {
                    loadingPlaceholder("Loading PDF…")
                } else {
                    unavailablePreviewView(tab: tab, subtitle: "Connect to a ZCode host to load this PDF.")
                }
            case .binary:
                unavailablePreviewView(tab: tab, subtitle: "Preview is not available for binary files.")
            case .markdown, .csv, .code, .text:
                if let text = tab.textContent {
                    VStack(spacing: 0) {
                        if tab.isTruncated {
                            truncationBanner(
                                loadedBytes: text.utf8.count,
                                totalBytes: tab.totalBytes ?? tab.sizeBytes
                            )
                        }
                        if !showRawTextSource && mediaKind == .csv {
                            nativeCSVTable(text)
                        } else if !showRawTextSource && mediaKind == .markdown {
                            nativeMarkdownPreview(text)
                        } else {
                            nativeTextWithLineNumbers(tab: tab, text: text)
                        }
                    }
                } else if store.isLiveHostConnected {
                    loadingPlaceholder("Loading \(tab.name)…")
                } else {
                    unavailablePreviewView(tab: tab, subtitle: "Connect to a ZCode host to load this file.")
                }
            }
        }
    }

    private func previewErrorView(tab: InspectorPreviewTab, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(palette.warning)
            Text(tab.name)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.foregroundSubtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if store.isLiveHostConnected && !store.isUITestSeededMode {
                Button {
                    Task { @MainActor in
                        await store.reloadPreviewTab(id: tab.id)
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
                .accessibilityIdentifier("retryPreviewButton")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadingPlaceholder(_ label: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundSubtle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func unavailablePreviewView(tab: InspectorPreviewTab, subtitle: String) -> some View {
        let sizeText: String = {
            if tab.sizeBytes > 0 {
                return ByteCountFormatter.string(fromByteCount: Int64(tab.sizeBytes), countStyle: .file)
            }
            return "Binary file"
        }()

        return VStack(spacing: 10) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 36))
                .foregroundStyle(palette.foregroundMuted)
            Text(tab.name)
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
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resetViewport() {
        zoomScale = 1.0
        panOffset = .zero
        showRawTextSource = false
    }

    private func swipeToAdjacentImageTab(forward: Bool) {
        let imageTabs = tabs.filter { $0.effectiveKind == .image }
        guard imageTabs.count > 1,
              let currentIndex = imageTabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        let targetIndex = forward ? currentIndex + 1 : currentIndex - 1
        guard imageTabs.indices.contains(targetIndex) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            store.activatePreviewTab(id: imageTabs[targetIndex].id)
        }
    }

    // MARK: - Native Syntax Text Viewer with Line Numbers

    private func nativeTextWithLineNumbers(tab: InspectorPreviewTab, text: String) -> some View {
        let syntaxColors = SyntaxColors.palette(for: store.syntaxTheme)
        let lines = text.components(separatedBy: "\n")
        let lang = SyntaxHighlighter.detectLanguage(for: tab.path)

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

    // MARK: - Native Pinch-Zoom Image Inspector

    private func nativeImageCanvas(_ tab: InspectorPreviewTab) -> some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0x101114)

                if let data = tab.binaryData, let uiImage = UIImage(data: data) {
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
                                .onEnded { value in
                                    // Horizontal swipe on an unzoomed image moves to the
                                    // neighboring image tab (desktop-style gallery browsing).
                                    guard zoomScale <= 1.05 else { return }
                                    let width = value.translation.width
                                    let height = value.translation.height
                                    guard abs(width) > 60, abs(width) > abs(height) else { return }
                                    swipeToAdjacentImageTab(forward: width < 0)
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

                    // Single-line image metadata HUD
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
                } else if tab.binaryData != nil {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Unable to decode \(tab.name)")
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

    private func icon(for tab: InspectorPreviewTab) -> String {
        switch tab.effectiveKind {
        case .image: return "photo"
        case .pdf: return "doc.viewfinder"
        case .binary: return "doc.zipper"
        case .csv: return "tablecells"
        case .markdown: return "doc.richtext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
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
