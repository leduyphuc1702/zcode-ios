import SwiftUI

public struct ChatTurnCardView: View {
    @Bindable var store: AppStore
    let message: ChatTurnMessage
    /// Subagent transcripts are read-only: no feedback, fork, or quote actions.
    var readOnly: Bool = false
    @Environment(\.zcodePalette) private var palette
    @State private var isThoughtExpanded: Bool = false
    @State private var showSelectTextSheet: Bool = false

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
            } else {
                assistantTurnView
            }
        }
        .sheet(isPresented: $showSelectTextSheet) {
            MessageTextSelectionSheet(
                text: message.content,
                senderName: quoteSenderName,
                onQuote: { excerpt in
                    quoteText(excerpt)
                },
                onCopy: { excerpt in
                    UIPasteboard.general.string = excerpt
                    store.showToast("Copied text")
                }
            )
            .environment(\.zcodePalette, palette)
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
                if !message.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(message.attachments) { att in
                                Button {
                                    if let path = att.filePath {
                                        store.openFileInInspector(pathOrId: path, preferPreview: att.kind == "image" || att.kind == "pdf")
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: att.kind == "comment" ? "text.bubble" : "paperclip")
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
                            }
                        }
                    }
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
                        Text(message.content)
                            .font(.system(size: 15))
                            .foregroundStyle(palette.foreground)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                )
                .contextMenu {
                    messageContextMenuItems
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

    @ViewBuilder
    private var messageContextMenuItems: some View {
        if hasQuotableContent {
            Button {
                quoteText(message.content)
            } label: {
                Label("Quote message", systemImage: "text.quote")
            }

            Button {
                showSelectTextSheet = true
            } label: {
                Label("Select text", systemImage: "selection.pin.in.out")
            }

            Button {
                UIPasteboard.general.string = message.content
                store.showToast("Copied message")
            } label: {
                Label("Copy message", systemImage: "doc.on.doc")
            }
        }
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
                                Text(renderInlineMarkdown(quoteText))
                                    .font(.system(size: 15))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
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
                                        Text(renderInlineMarkdown(item))
                                            .font(.system(size: 15.5))
                                            .foregroundStyle(palette.foreground)
                                            .lineSpacing(4)
                                            .fixedSize(horizontal: false, vertical: true)
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
                                        .padding(12)
                                }
                            }
                            .background(palette.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))

                        case .paragraph(let paragraphText):
                            Text(renderInlineMarkdown(paragraphText))
                                .font(.system(size: 15.5))
                                .foregroundStyle(palette.foreground)
                                .lineSpacing(4.5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .contextMenu {
                    messageContextMenuItems
                }
            }

            // Official ZCode Turn Action Row: Copy • Thumbs Up • Thumbs Down • Fork • Quote • Timestamp (HIG 34pt touch areas)
            HStack(spacing: 4) {
                Button {
                    UIPasteboard.general.string = message.content
                    store.showToast("Copied message")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 32, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy message")

                if !readOnly, store.v4CanTarget(messageId: message.id) {
                Button {
                    store.toggleMessageFeedback(messageId: message.id, rating: 1)
                } label: {
                    Image(systemName: message.feedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(message.feedback == 1 ? palette.foreground : palette.foregroundSubtle)
                        .frame(width: 32, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark helpful")

                Button {
                    store.toggleMessageFeedback(messageId: message.id, rating: -1)
                } label: {
                    Image(systemName: message.feedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(message.feedback == -1 ? palette.destructive : palette.foregroundSubtle)
                        .frame(width: 32, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark unhelpful")
                } else if message.feedback != 0 {
                    Image(systemName: message.feedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: 32, height: 34)
                        .accessibilityLabel(message.feedback == 1 ? "Marked helpful" : "Marked unhelpful")
                }

                if !readOnly, store.v4CanTarget(messageId: message.id) {
                    Button {
                        store.v4ForkAssistant(messageId: message.id)
                    } label: {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 32, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fork from this turn")
                }

                if !readOnly, hasQuotableContent {
                    Button {
                        quoteText(message.content)
                    } label: {
                        Image(systemName: "text.quote")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 32, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quote message")
                    .accessibilityIdentifier("quoteMessageButton_\(message.id)")
                }

                Text(formattedTurnTime(message.timestamp))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.leading, 6)

                Spacer()
            }
            .padding(.leading, -6)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func renderInlineMarkdown(_ text: String) -> AttributedString {
        if var parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            let codeBg = palette.isDark
                ? Color(red: 0.175, green: 0.175, blue: 0.175)
                : Color(red: 0.91, green: 0.91, blue: 0.92)
            for run in parsed.runs {
                if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                    parsed[run.range].font = .system(size: 13.5, weight: .regular, design: .monospaced)
                    parsed[run.range].backgroundColor = codeBg
                    parsed[run.range].foregroundColor = palette.foreground
                }
            }
            return parsed
        }
        return AttributedString(text)
    }

    private func formattedTurnTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: date)
    }
}
