import PhotosUI
import SwiftUI

public struct ChatTurnCardView: View {
    @Bindable var store: AppStore
    let message: ChatTurnMessage
    /// Subagent transcripts are read-only: no feedback, fork, or quote actions.
    var readOnly: Bool = false
    /// Turn footer, present only on the last assistant segment of a finished turn.
    var actionBar: TurnActionBar? = nil
    @Environment(\.zcodePalette) private var palette
    @State private var isThoughtExpanded: Bool = false
    @State private var showEditMessageSheet: Bool = false
    @State private var editDraft: String = ""

    private enum MarkdownBlock: Identifiable {
        case paragraph(String)
        case blockquote(String)
        case bulletList([String])
        case codeBlock(String)

        var id: String {
            switch self {
            case .paragraph(let s): return "p-\(s.hashValue)"
            case .blockquote(let s): return "q-\(s.hashValue)"
            case .bulletList(let items): return "ul-\(items.joined().hashValue)"
            case .codeBlock(let c): return "code-\(c.hashValue)"
            }
        }
    }

    public var body: some View {
        Group {
            if message.role == "user" {
                userTurnBubble
                    .sheet(isPresented: $showEditMessageSheet) {
                        EditUserMessageSheet(store: store, message: message, initialText: editDraft)
                            .environment(\.zcodePalette, palette)
                    }
            } else {
                assistantTurnView
            }
        }
    }

    private var quoteSenderName: String {
        message.role == "user" ? "user" : "assistant"
    }

    private var thoughtLabel: String {
        guard message.thoughtDurationMs > 0 else { return "Thought" }
        return "Thought · \(String(format: "%.1fs", Double(message.thoughtDurationMs) / 1000.0))"
    }

    private var hasQuotableContent: Bool {
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Desktop parity: the host marks editable user rows with `actions.canEdit`; the client never guesses.
    private var canEditMessage: Bool {
        guard !readOnly, message.role == "user", message.canEdit == true else { return false }
        return store.v4CanEditUserMessage(message.id)
    }

    private func beginEditingMessage() {
        editDraft = message.content
        showEditMessageSheet = true
    }

    /// Local files open by path; host attachments are read through `conversationAttachmentReadV4` into a preview tab.
    private func openAttachment(_ attachment: ComposerAttachment, index: Int) {
        if let path = attachment.filePath {
            store.openFileInInspector(pathOrId: path, preferPreview: attachment.kind == "image" || attachment.kind == "pdf")
            return
        }
        let tabId = "attachment-\(message.id)-\(index)"
        if let data = attachment.previewPNGData {
            store.openDataPreviewTab(id: tabId, fileName: attachment.name, mimeType: attachment.kind == "image" ? "image/png" : "application/octet-stream", data: data)
            return
        }
        Task { @MainActor in
            do {
                let loaded = try await store.v4ReadUserAttachment(messageId: message.id, index: index)
                store.openDataPreviewTab(id: tabId, fileName: attachment.name, mimeType: loaded.mimeType, data: loaded.data)
            } catch {
                store.showToast("Couldn't open \(attachment.name)")
            }
        }
    }

    private func quoteText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addComposerQuote(
            ConversationQuote(
                text: trimmed,
                senderName: quoteSenderName,
                messageId: message.id
            )
        )
        store.playImpactHaptic(.light)
        store.showToast("Quoted in composer")
    }

    // MARK: - User Turn Bubble

    private var userTurnBubble: some View {
        let quotes = message.quotes ?? []
        return HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 8) {
                let indexed = Array(message.attachments.enumerated())
                let media = indexed.filter { $0.element.kind == "image" }
                let files = indexed.filter { $0.element.kind != "image" }
                if !media.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(media, id: \.offset) { index, att in
                                Button {
                                    openAttachment(att, index: index)
                                } label: {
                                    UserAttachmentThumbnail(store: store, messageId: message.id, index: index, attachment: att, side: 72)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open \(att.name)")
                                .accessibilityIdentifier("userAttachmentThumb_\(message.id)_\(index)")
                            }
                        }
                    }
                    .defaultScrollAnchor(.trailing)
                }
                if !files.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(files, id: \.offset) { index, att in
                                Button {
                                    openAttachment(att, index: index)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: att.kind == "comment" ? "text.bubble" : (att.kind == "pdf" ? "doc.richtext" : "paperclip"))
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.foregroundSubtle)
                                        Text(att.name)
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundStyle(palette.foreground)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(palette.panel, in: Capsule())
                                    .overlay(Capsule().strokeBorder(palette.borderStrong, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("userAttachmentPill_\(message.id)_\(index)")
                            }
                        }
                    }
                    .defaultScrollAnchor(.trailing)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !quotes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(quotes) { quote in
                                userQuoteBlock(quote)
                            }
                        }
                    }

                    if !message.content.isEmpty {
                        SelectableMessageText(
                            plain: message.content,
                            font: .systemFont(ofSize: 15),
                            color: UIColor(palette.foreground),
                            lineSpacing: 3,
                            linkColor: UIColor(palette.accentBlue),
                            onQuote: selectionQuoteHandler
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                )

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if hasQuotableContent {
                        Button {
                            UIPasteboard.general.string = message.content
                            store.showToast("Copied message")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(palette.foregroundSubtle)
                                .frame(width: 32, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy message")
                        .accessibilityIdentifier("copyUserMessageButton_\(message.id)")
                    }
                    if canEditMessage {
                        Button {
                            beginEditingMessage()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(palette.foregroundSubtle)
                                .frame(width: 32, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit")
                        .accessibilityIdentifier("editUserMessageButton_\(message.id)")
                    }
                }
            }
        }
    }

    private func userQuoteBlock(_ quote: ConversationQuote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let path = quote.path, !path.isEmpty {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.foregroundMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(quote.text)
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundSubtle)
                .lineSpacing(2)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 5)
        .padding(.trailing, 8)
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(palette.foregroundMuted.opacity(0.75))
                .frame(width: 2.5)
                .padding(.vertical, 5)
                .padding(.leading, 5)
        }
        .accessibilityIdentifier("userMessageQuote_\(quote.id)")
    }

    /// Read-only transcripts (subagent pane) offer Copy only, like the desktop's read-only pane.
    private var selectionQuoteHandler: ((String) -> Void)? {
        readOnly ? nil : { excerpt in quoteText(excerpt) }
    }

    private var codeSpanBackground: UIColor {
        palette.isDark ? UIColor(red: 0.175, green: 0.175, blue: 0.175, alpha: 1) : UIColor(red: 0.91, green: 0.91, blue: 0.92, alpha: 1)
    }

    private func selectableMarkdown(_ text: String, size: CGFloat, color: Color, lineSpacing: CGFloat) -> some View {
        SelectableMessageText(
            markdown: text,
            font: .systemFont(ofSize: size),
            color: UIColor(color),
            lineSpacing: lineSpacing,
            codeBackground: codeSpanBackground,
            linkColor: UIColor(palette.accentBlue),
            onQuote: selectionQuoteHandler
        )
    }

    // MARK: - Assistant Turn (Official ZCode Editorial Typography & Action Row)

    private var assistantTurnView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subtle Collapsible Thought Row
            if store.showReasoningBlocks, let thought = message.thought, !thought.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isThoughtExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "brain")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(palette.foregroundMuted)
                            Text(thoughtLabel)
                                .font(.system(size: 13.5, weight: .regular))
                                .foregroundStyle(palette.foregroundMuted)
                            Image(systemName: isThoughtExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(palette.foregroundMuted)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    if isThoughtExpanded {
                        HStack(alignment: .top, spacing: 10) {
                            Rectangle()
                                .fill(palette.borderStrong)
                                .frame(width: 2)
                            Text(thought)
                                .font(.system(size: 13.5))
                                .foregroundStyle(palette.foregroundSubtle)
                                .lineSpacing(3)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Official Compact Tool Call Rows (with Explore grouping)
            if !message.tools.isEmpty {
                ToolCallListView(
                    store: store,
                    tools: message.tools,
                    workspacePath: store.activeSession?.workspacePath
                )
            }

            // Structured Markdown Blocks (Blockquotes, Bullet Lists, Code Blocks, Paragraphs)
            if hasQuotableContent {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(parseMarkdownBlocks(message.content).enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .blockquote(let quoteText):
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(palette.borderStrong)
                                    .frame(width: 3)
                                selectableMarkdown(quoteText, size: 15, color: palette.foregroundSubtle, lineSpacing: 4)
                            }
                            .padding(.vertical, 2)

                        case .bulletList(let items):
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                    HStack(alignment: .top, spacing: 11) {
                                        Circle()
                                            .fill(palette.foregroundMuted)
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 8)
                                        selectableMarkdown(item, size: 15.5, color: palette.foreground, lineSpacing: 4)
                                    }
                                }
                            }

                        case .codeBlock(let code):
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text("code")
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(palette.foregroundMuted)
                                    Spacer()
                                    Button {
                                        UIPasteboard.general.string = code
                                        store.showToast("Copied code block")
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 12))
                                            .foregroundStyle(palette.foregroundSubtle)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(palette.header)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(code)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(palette.foreground)
                                        .textSelection(.enabled)
                                        .padding(12)
                                }
                            }
                            .background(palette.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))

                        case .paragraph(let paragraphText):
                            selectableMarkdown(paragraphText, size: 15.5, color: palette.foreground, lineSpacing: 4.5)
                        }
                    }
                }
            }

            if let bar = actionBar {
                turnFooter(bar)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Turn Footer (desktop `Nfn`: Copy · Like · Dislike · Fork)

    private func turnFooter(_ bar: TurnActionBar) -> some View {
        let canTarget = !readOnly && store.v4CanTarget(messageId: bar.targetMessageId)
        return HStack(spacing: 2) {
            footerButton("doc.on.doc", label: "Copy", id: "turnCopyButton") {
                UIPasteboard.general.string = bar.copyText
                store.showToast("Copied")
            }
            if canTarget {
                footerButton(bar.feedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup",
                             label: bar.feedback == 1 ? "Liked" : "Like",
                             id: "turnLikeButton",
                             tint: bar.feedback == 1 ? palette.success : nil) {
                    store.toggleMessageFeedback(messageId: bar.targetMessageId, rating: 1)
                }
                footerButton(bar.feedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                             label: bar.feedback == -1 ? "Disliked" : "Dislike",
                             id: "turnDislikeButton",
                             tint: bar.feedback == -1 ? palette.warning : nil) {
                    store.toggleMessageFeedback(messageId: bar.targetMessageId, rating: -1)
                }
                if bar.canFork {
                    footerButton("arrow.triangle.branch", label: "Fork", id: "turnForkButton") {
                        store.v4ForkAssistant(messageId: bar.targetMessageId)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, -8)
        .accessibilityIdentifier("turnFooter_\(message.id)")
    }

    private func footerButton(_ icon: String, label: String, id: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tint ?? palette.foregroundSubtle)
                .frame(width: 32, height: 32)
                .background(tint.map { $0.opacity(0.1) } ?? .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(id)_\(message.id)")
    }

    // MARK: - Native Markdown Block Parser

    private func parseMarkdownBlocks(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var idx = 0

        while idx < lines.count {
            let line = lines[idx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                idx += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                idx += 1
                while idx < lines.count && !lines[idx].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[idx])
                    idx += 1
                }
                if idx < lines.count { idx += 1 }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while idx < lines.count && lines[idx].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var q = lines[idx].trimmingCharacters(in: .whitespaces)
                    q.removeFirst()
                    quoteLines.append(q.trimmingCharacters(in: .whitespaces))
                    idx += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                var items: [String] = []
                while idx < lines.count {
                    let t = lines[idx].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") {
                        items.append(String(t.dropFirst(2)))
                        idx += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items))
                continue
            }

            var paraLines: [String] = []
            while idx < lines.count {
                let t = lines[idx].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix(">") || t.hasPrefix("```") || t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") {
                    break
                }
                paraLines.append(lines[idx])
                idx += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(paraLines.joined(separator: "\n")))
            }
        }
        return blocks
    }
}

// MARK: - Edit Sent Prompt (desktop `editUserQuery` parity)

/// The desktop replaces the user bubble with its composer and offers Cancel / Send plus a "Reset chat + files"
/// action (`chat.message.edit`, `chat.send`, `common.cancel`, `chat.edit.resetConversationAndFiles`). The mobile
/// adaptation is a sheet with the same strings and the same host command.
private struct EditUserMessageSheet: View {
    @Bindable var store: AppStore
    let message: ChatTurnMessage
    @State private var draft: String
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @State private var blockedConflict: BlockedEdit?
    @State private var didFocusEditor: Bool = false
    /// Indices into `message.attachments` still attached; the desktop editor lets each one be removed.
    @State private var keptAttachmentIndices: [Int]
    @State private var addedAttachments: [ComposerAttachment] = []
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @FocusState private var isEditorFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zcodePalette) private var palette

    private struct BlockedEdit: Identifiable {
        let id = UUID()
        let text: String
    }

    init(store: AppStore, message: ChatTurnMessage, initialText: String) {
        self.store = store
        self.message = message
        _draft = State(initialValue: initialText)
        _keptAttachmentIndices = State(initialValue: Array(message.attachments.indices))
    }

    private var hasAttachments: Bool { !keptAttachmentIndices.isEmpty || !addedAttachments.isEmpty }

    private var rewindAvailability: String { message.editRewindAvailability ?? "unavailable" }

    private var canRewindFiles: Bool { rewindAvailability == "available" }

    private var rewindDisabledReason: String? {
        switch rewindAvailability {
        case "available":
            return nil
        case "noFiles":
            return "This turn has no reversible file changes"
        case "reverted":
            return "This turn's file changes are already undone"
        case "running":
            return "Wait for the current work to stop"
        default:
            return "File reset is unavailable while compacting or an interaction is pending"
        }
    }

    private var canSend: Bool {
        guard !isSubmitting else { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachments
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.black.opacity(0.7))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 9, y: -9)
    }

    private func filePill(_ attachment: ComposerAttachment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: attachment.kind == "pdf" ? "doc.richtext" : "paperclip")
                .font(.system(size: 11))
                .foregroundStyle(palette.foregroundSubtle)
            Text(attachment.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(palette.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.borderStrong, lineWidth: 1))
    }

    private var attachmentsEditor: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 12) {
                ForEach(keptAttachmentIndices, id: \.self) { index in
                    let attachment = message.attachments[index]
                    Group {
                        if attachment.kind == "image" {
                            UserAttachmentThumbnail(store: store, messageId: message.id, index: index, attachment: attachment, side: 64)
                        } else {
                            filePill(attachment)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        removeButton { keptAttachmentIndices.removeAll { $0 == index } }
                            .accessibilityLabel("Remove \(attachment.name)")
                            .accessibilityIdentifier("editRemoveAttachment_\(index)")
                    }
                }
                ForEach(addedAttachments) { attachment in
                    Group {
                        if let data = attachment.previewPNGData, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                        } else {
                            filePill(attachment)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        removeButton { addedAttachments.removeAll { $0.id == attachment.id } }
                            .accessibilityLabel("Remove \(attachment.name)")
                    }
                }
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 10, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 64, height: 64)
                        .background(palette.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(palette.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                }
                .accessibilityLabel("Add images")
                .accessibilityIdentifier("editAddImagesButton")
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            pickedPhotos = []
            Task { @MainActor in
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "png"
                    let suffix = String(UUID().uuidString.prefix(4)).lowercased()
                    addedAttachments.append(ComposerAttachment(
                        id: UUID().uuidString,
                        name: "image-\(addedAttachments.count + 1)-\(suffix).\(ext)",
                        kind: "image",
                        sizeBytes: data.count,
                        filePath: nil,
                        lineNote: nil,
                        previewPNGData: data
                    ))
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    attachmentsEditor

                    TextEditor(text: $draft)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.foreground)
                        .scrollContentBackground(.hidden)
                        .focused($isEditorFocused)
                        .frame(minHeight: 170, maxHeight: 320)
                        .padding(8)
                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(palette.borderStrong, lineWidth: 1)
                        )
                        .accessibilityIdentifier("editUserMessageEditor")

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("editUserMessageError")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            submit(workspaceMode: "rewind")
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Reset chat + files")
                                    .font(.system(size: 13.5, weight: .medium))
                                Spacer()
                                if isSubmitting {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                            .foregroundStyle(canRewindFiles ? palette.foreground : palette.foregroundMuted)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(palette.borderStrong, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canRewindFiles || isSubmitting)
                        .accessibilityLabel("Reset with files")
                        .accessibilityIdentifier("editUserMessageRewindButton")

                        if let rewindDisabledReason {
                            Text(rewindDisabledReason)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.foregroundMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { submit(workspaceMode: "preserve") }
                        .disabled(!canSend)
                        .accessibilityIdentifier("editUserMessageSendButton")
                }
            }
        }
        .task {
            guard !didFocusEditor else { return }
            didFocusEditor = true
            try? await Task.sleep(nanoseconds: 300_000_000)
            isEditorFocused = true
        }
        .alert("Files could not be safely reset", isPresented: blockedConflictBinding) {
            Button("Cancel", role: .cancel) { blockedConflict = nil }
            Button("Reset chat only and send") {
                let text = blockedConflict?.text ?? draft
                blockedConflict = nil
                submit(text: text, workspaceMode: "preserve")
            }
        } message: {
            Text("No conversation history was changed. Review the conflicting or ignored files, then reset only the conversation or cancel.")
        }
    }

    private var blockedConflictBinding: Binding<Bool> {
        Binding(
            get: { blockedConflict != nil },
            set: { if !$0 { blockedConflict = nil } }
        )
    }

    private func submit(workspaceMode: String) {
        submit(text: draft, workspaceMode: workspaceMode)
    }

    private func submit(text: String, workspaceMode: String) {
        guard !isSubmitting else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || hasAttachments else { return }
        isSubmitting = true
        errorText = nil
        isEditorFocused = false
        Task { @MainActor in
            do {
                let result = try await store.v4EditUserQuery(
                    messageId: message.id,
                    newText: text,
                    workspaceMode: workspaceMode,
                    quotes: message.quotes ?? [],
                    keptAttachmentIndices: keptAttachmentIndices,
                    newAttachments: addedAttachments
                )
                isSubmitting = false
                if result.isBlocked {
                    blockedConflict = BlockedEdit(text: text)
                    return
                }
                store.playImpactHaptic(.light)
                if result.disposition == .fork {
                    await store.loadAllWorkspaceTasks(preferredActiveTaskId: nil)
                }
                dismiss()
            } catch {
                isSubmitting = false
                errorText = "Couldn't edit message: \(error.localizedDescription)"
            }
        }
    }
}

/// Square media thumbnail for a user-row attachment; host attachments are read once and cached by the store.
struct UserAttachmentThumbnail: View {
    let store: AppStore
    let messageId: String
    let index: Int
    let attachment: ComposerAttachment
    var side: CGFloat = 72
    @Environment(\.zcodePalette) private var palette
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            palette.panel
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.foregroundMuted)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .task(id: "\(messageId)#\(index)") { await load() }
    }

    private func load() async {
        guard image == nil else { return }
        var data = attachment.previewPNGData
        if data == nil, let path = attachment.filePath {
            data = try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        if data == nil {
            data = try? await store.v4ReadUserAttachment(messageId: messageId, index: index).data
        }
        if let data, let decoded = UIImage(data: data) {
            let shortest = max(1, min(decoded.size.width, decoded.size.height))
            let scale = min(1, side * 3 / shortest)
            let target = CGSize(width: decoded.size.width * scale, height: decoded.size.height * scale)
            image = await decoded.byPreparingThumbnail(ofSize: target) ?? decoded
        } else {
            failed = true
        }
    }
}
