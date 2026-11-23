import SwiftUI
import PDFKit

/// 100% Native Image, PDF (PDFKit), Markdown, and CSV Spreadsheet Viewer Window — ZERO WebView!
public struct NativeMediaDocumentViewer: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var showPixelGrid: Bool = false

    private var previewableFiles: [WorkspaceFileNode] {
        // Order key asset types (PNG, PDF, CSV, Markdown) up front so all formats are immediately accessible
        let raw = store.flattenedFiles.filter { [.image, .pdf, .markdown, .csv].contains($0.kind) }
        let priorityOrder = ["file-arch-png", "file-spec-pdf", "file-benchmarks-csv", "file-readme", "file-telemetry-png"]
        return raw.sorted { a, b in
            let ia = priorityOrder.firstIndex(of: a.id) ?? 99
            let ib = priorityOrder.firstIndex(of: b.id) ?? 99
            return ia < ib
        }
    }

    private var activePreviewFile: WorkspaceFileNode? {
        if let selected = store.selectedFile, [.image, .pdf, .markdown, .csv].contains(selected.kind) {
            return selected
        }
        return previewableFiles.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Asset Switcher Strip — Compact labels so PNG, PDF, CSV & MD fit cleanly on screen
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(previewableFiles) { item in
                        let isCurrent = item.id == activePreviewFile?.id
                        Button {
                            store.selectedFileId = item.id
                            zoomScale = 1.0
                            panOffset = .zero
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: icon(for: item.kind))
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

            if let file = activePreviewFile {
                // Toolbar with Metadata + Attach to Composer
                HStack(spacing: 8) {
                    Text(file.path)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)

                    Spacer()

                    if file.kind == .image {
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
                    }

                    Button {
                        store.composerAttachments.append(
                            ComposerAttachment(
                                id: UUID().uuidString,
                                name: "@\(file.name)",
                                kind: file.kind == .image ? "image" : "file",
                                sizeBytes: file.sizeBytes,
                                filePath: file.path,
                                lineNote: nil,
                                previewPNGData: file.binaryData
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

                // Specialized Native Renderer per Asset Type
                switch file.kind {
                case .image:
                    nativeImageCanvas(file)
                case .pdf:
                    if let pdfData = file.binaryData {
                        NativePDFKitView(data: pdfData)
                            .accessibilityIdentifier("nativePDFKitViewer")
                    }
                case .csv:
                    nativeCSVTable(file.textContent ?? "")
                case .markdown:
                    nativeMarkdownPreview(file.textContent ?? "")
                default:
                    EmptyView()
                }
            }
        }
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
            .map { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }

        return ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
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
            VStack(alignment: .leading, spacing: 10) {
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
                    } else if line.hasPrefix("- ") {
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(palette.accentBlue)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text((try? AttributedString(markdown: String(line.dropFirst(2)))) ?? AttributedString(String(line.dropFirst(2))))
                                .font(.system(size: 14))
                                .foregroundStyle(palette.foreground)
                        }
                    } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
                            .font(.system(size: 14))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func icon(for kind: WorkspaceFileKind) -> String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.viewfinder"
        case .csv: return "tablecells"
        case .markdown: return "doc.richtext"
        default: return "doc"
        }
    }
}

/// Pure Apple PDFKit UIViewRepresentable (Zero WebView)
public struct NativePDFKitView: UIViewRepresentable {
    public let data: Data

    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    public func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document == nil {
            pdfView.document = PDFDocument(data: data)
        }
    }
}
