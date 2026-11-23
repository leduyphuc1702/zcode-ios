import SwiftUI

public struct ChatTurnCardView: View {
    @Bindable var store: AppStore
    let message: ChatTurnMessage
    @Environment(\.zcodePalette) private var palette
    @State private var isThoughtExpanded: Bool = false
    @State private var expandedToolIds: Set<String> = []

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
        if message.role == "user" {
            userTurnBubble
        } else {
            assistantTurnView
        }
    }

    // MARK: - User Turn Bubble

    private var userTurnBubble: some View {
        HStack {
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

                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.foreground)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
                    .textSelection(.enabled)
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
                            Text("Thought · \(String(format: "%.1fs", Double(max(100, message.thoughtDurationMs)) / 1000.0))")
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

            // Tool Execution Cards
            if !message.tools.isEmpty {
                VStack(spacing: 6) {
                    ForEach(message.tools) { tool in
                        toolCard(tool)
                    }
                }
            }

            // Structured Markdown Blocks (Blockquotes, Bullet Lists, Code Blocks, Paragraphs)
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
                                .textSelection(.enabled)
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
                                        .textSelection(.enabled)
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
                            .textSelection(.enabled)
                    }
                }
            }

            // Official ZCode Turn Action Row: Copy • Thumbs Up • Thumbs Down • Fork • Timestamp (HIG 34pt touch areas)
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

                Button {
                    if let s = store.activeSession {
                        store.forkSession(s.id)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 32, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fork session from this turn")

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

    // MARK: - Official ZCode Borderless Inline Tool Call Row

    private func toolCard(_ tool: ToolCallItem) -> some View {
        let isExpanded = expandedToolIds.contains(tool.id)
        let hasInspectableDetail = tool.diffPatch != nil || tool.output != nil || !tool.subagentSteps.isEmpty
        let parsed = toolDisplayParts(tool)

        if tool.kind == .subagent {
            return AnyView(
                Button {
                    store.openSubagentInspector(tool.subagentRunId)
                } label: {
                    HStack(spacing: 8) {
                        ZCodeRobotIconView(size: 15, color: palette.foregroundSubtle)
                        Text("SubAgent")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foregroundSubtle)
                        Text(tool.title)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foregroundMuted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("openSubagentTool_\(tool.id)")
            )
        }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(parsed.verb)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(palette.foregroundMuted)

                toolLanguageBadge(for: parsed.badgeText, color: parsed.badgeColor)

                if let path = tool.filePath {
                    Button {
                        let isVisual = path.hasSuffix(".png") || path.hasSuffix(".jpg") || path.hasSuffix(".pdf") || path.hasSuffix(".csv")
                        store.openFileInInspector(pathOrId: path, preferPreview: isVisual)
                    } label: {
                        Text(parsed.target)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("openToolFile_\(tool.id)")
                } else {
                    Text(parsed.target)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                }

                if tool.addedLines > 0 || tool.removedLines > 0 {
                    HStack(spacing: 5) {
                        if tool.addedLines > 0 {
                            Text("+\(tool.addedLines)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.success)
                        }
                        if tool.removedLines > 0 {
                            Text("-\(tool.removedLines)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.destructive)
                        }
                    }
                }

                if hasInspectableDetail {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isExpanded {
                                expandedToolIds.remove(tool.id)
                            } else {
                                expandedToolIds.insert(tool.id)
                            }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.foregroundMuted)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let patch = tool.diffPatch {
                        ForEach(Array(patch.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(diffLineColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1.5)
                                .background(diffLineBackground(line))
                        }
                    }
                    if let out = tool.output {
                        Text(out)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(palette.foregroundSubtle)
                            .padding(10)
                    }
                    if !tool.subagentSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(tool.subagentSteps, id: \.self) { step in
                                HStack(spacing: 6) {
                                    Circle().fill(palette.foregroundMuted).frame(width: 4, height: 4)
                                    Text(step)
                                        .font(.system(size: 12))
                                        .foregroundStyle(palette.foregroundSubtle)
                                }
                            }
                        }
                        .padding(10)
                    }
                }
                .background(palette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
            }
        })
    }

    private func toolDisplayParts(_ tool: ToolCallItem) -> (verb: String, target: String, badgeText: String, badgeColor: Color) {
        let fileName: String? = tool.filePath?.split(separator: "/").last.map(String.init)
        switch tool.kind {
        case .readFile:
            let name = fileName ?? tool.title.replacingOccurrences(of: "Read ", with: "")
            let badge = badgeForFileName(name)
            return ("Read", name, badge.0, badge.1)
        case .editFile:
            let name = fileName ?? tool.title.replacingOccurrences(of: "Edit ", with: "")
            let badge = badgeForFileName(name)
            return ("Edit", name, badge.0, badge.1)
        case .writeFile:
            let name = fileName ?? tool.title.replacingOccurrences(of: "Write ", with: "")
            let badge = badgeForFileName(name)
            return ("Write", name, badge.0, badge.1)
        case .bash:
            return ("Run", tool.command ?? tool.title, ">_", Color(red: 0.26, green: 0.28, blue: 0.32))
        case .subagent:
            return ("Agent", tool.title, "AI", Color(red: 0.45, green: 0.34, blue: 0.88))
        case .workflow:
            return ("Workflow", tool.title, "WF", Color(red: 0.22, green: 0.58, blue: 0.48))
        case .search, .mcp:
            return ("Search", tool.title, "MCP", Color(red: 0.18, green: 0.48, blue: 0.78))
        }
    }

    private func badgeForFileName(_ name: String) -> (String, Color) {
        let lower = name.lowercased()
        if lower.hasSuffix(".ts") || lower.hasSuffix(".tsx") {
            return ("TS", Color(red: 0.19, green: 0.47, blue: 0.78))
        } else if lower.hasSuffix(".swift") {
            return ("SW", Color(red: 0.94, green: 0.32, blue: 0.22))
        } else if lower.hasSuffix(".rs") {
            return ("RS", Color(red: 0.82, green: 0.44, blue: 0.18))
        } else if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") {
            return ("IMG", Color(red: 0.56, green: 0.35, blue: 0.94))
        } else if lower.hasSuffix(".pdf") {
            return ("PDF", Color(red: 0.86, green: 0.15, blue: 0.15))
        } else if lower.hasSuffix(".json") {
            return ("{}", Color(red: 0.78, green: 0.60, blue: 0.14))
        }
        return ("FILE", Color(red: 0.34, green: 0.38, blue: 0.45))
    }

    private func toolLanguageBadge(for text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4.5)
            .frame(height: 16)
            .background(color, in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
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

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return palette.success }
        if line.hasPrefix("-") { return palette.destructive }
        if line.hasPrefix("@@") { return palette.info }
        return palette.foregroundSubtle
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") { return palette.success.opacity(0.10) }
        if line.hasPrefix("-") { return palette.destructive.opacity(0.10) }
        return Color.clear
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
