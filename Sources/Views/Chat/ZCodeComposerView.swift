import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct ZCodeComposerView: View {
    @Bindable var store: AppStore
    var onTapContextGauge: (() -> Void)? = nil
    @Environment(\.zcodePalette) private var palette
    @FocusState private var isInputFocused: Bool
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoLibraryPicker: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showFileMentionPicker: Bool = false
    @State private var selectedWorkspaceFileIds: Set<String> = []
    @State private var showPlusMenuPopover: Bool = false
    @State private var showModelPickerPopover: Bool = false
    @State private var showModelSettingsSheet: Bool = false
    @State private var showContextWindowPopover: Bool = false
    @State private var showAttachmentTypeDialog: Bool = false

    // Desktop 1:1 composer catalogs (real host data; seeded fixtures only in `isUITestSeededMode`).
    @State private var composerCommands: [ComposerCommandItem] = []
    @State private var composerCommandRawCount: Int = 0
    @State private var composerCommandsWorkspaceKey: String = ""
    @State private var composerCommandsLoading: Bool = false
    @State private var composerSkillsLoading: Bool = false
    @State private var composerAgentsLoading: Bool = false
    @State private var composerPluginsLoading: Bool = false
    @State private var composerCatalogsRefreshedKey: String = ""
    @State private var composerCatalogsRefreshedAt: Date = .distantPast
    @State private var mentionFiles: [ComposerFileItem] = []
    @State private var mentionFilesLoading: Bool = false
    @State private var mentionFilesError: String? = nil
    @State private var mentionFileMissQuery: String = ""

    private enum ActivePopoverKind: Equatable {
        case none
        case plusMenu
        case modelPicker
        case contextWindow
        case slash(String)
        case mention(String)
        case skill(String)
        case hash(String)
    }

    private enum ComposerTriggerKind: Equatable {
        case slash
        case mention
        case skill
        case hash
    }

    /// `IK`: `(^|\s)([/@$#¥￥])([^\s/@$#¥￥]*)$` (with the CJK boundary variant for "@").
    private struct ComposerTriggerToken: Equatable {
        let kind: ComposerTriggerKind
        let query: String
        let tokenRange: Range<String.Index>
    }

    private static let composerTriggerCharacters: Set<Character> = ["/", "@", "$", "#", "¥", "￥"]

    public init(store: AppStore, onTapContextGauge: (() -> Void)? = nil) {
        self.store = store
        self.onTapContextGauge = onTapContextGauge
    }

    private var popoverCardFill: Color {
        palette.isDark ? Color(red: 0.129, green: 0.129, blue: 0.129) : palette.menuBackground
    }

    private var popoverRowHighlight: Color {
        palette.isDark ? Color(red: 0.185, green: 0.185, blue: 0.185) : palette.surfaceHover
    }

    private var activePopover: ActivePopoverKind {
        if let token = composerTriggerToken {
            switch token.kind {
            case .slash: return .slash(token.query)
            case .mention: return .mention(token.query)
            case .skill: return .skill(token.query)
            case .hash: return .hash(token.query)
            }
        }

        if showModelPickerPopover {
            return .modelPicker
        }

        if showContextWindowPopover {
            return .contextWindow
        }

        if showPlusMenuPopover {
            return .plusMenu
        }

        return .none
    }

    /// Desktop `IK` / `RUt` / `LUt`: a trigger token at the end of the composer text.
    private var composerTriggerToken: ComposerTriggerToken? {
        let text = store.composerText
        guard !text.isEmpty else { return nil }

        var index = text.endIndex
        while index > text.startIndex {
            let previous = text.index(before: index)
            let character = text[previous]
            if character.isWhitespace || Self.composerTriggerCharacters.contains(character) { break }
            index = previous
        }
        guard index > text.startIndex else { return nil }

        let triggerIndex = text.index(before: index)
        let triggerCharacter = text[triggerIndex]
        guard Self.composerTriggerCharacters.contains(triggerCharacter) else { return nil }

        let isBoundary: Bool
        if triggerIndex == text.startIndex {
            isBoundary = true
        } else {
            let before = text[text.index(before: triggerIndex)]
            if triggerCharacter == "@" {
                isBoundary = before.isWhitespace || Self.isHanBoundary(before)
            } else {
                isBoundary = before.isWhitespace
            }
        }
        guard isBoundary else { return nil }

        let query = String(text[index...])
        let kind: ComposerTriggerKind
        switch triggerCharacter {
        case "/": kind = .slash
        case "@": kind = .mention
        case "#": kind = .hash
        default: kind = .skill // `$`, `¥`, `￥`
        }

        // `IK`: a Han prefix plus a `\S.\S` query disables the "@" trigger (URLs inside CJK text).
        if kind == .mention {
            let prefix = String(text[..<triggerIndex])
            if prefix.unicodeScalars.contains(where: { $0.properties.isIdeographic }),
               Self.containsNonSpaceDotNonSpace(query) {
                return nil
            }
        }

        return ComposerTriggerToken(kind: kind, query: query, tokenRange: triggerIndex..<text.endIndex)
    }

    private static func isHanBoundary(_ character: Character) -> Bool {
        for scalar in character.unicodeScalars {
            if scalar.properties.isIdeographic { return true }
            if (0x3000...0x303F).contains(scalar.value) || (0xFF00...0xFFEF).contains(scalar.value) { return true }
        }
        return false
    }

    private static func containsNonSpaceDotNonSpace(_ text: String) -> Bool {
        let characters = Array(text)
        guard characters.count >= 3 else { return false }
        for index in 1..<(characters.count - 1) where characters[index] == "." {
            if !characters[index - 1].isWhitespace && !characters[index + 1].isWhitespace {
                return true
            }
        }
        return false
    }

    private var activeQuery: String {
        switch activePopover {
        case .slash(let query), .mention(let query), .skill(let query), .hash(let query):
            return query
        default:
            return ""
        }
    }

    private var hasActiveQuery: Bool {
        !activeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasDismissableManualPopover: Bool {
        switch activePopover {
        case .plusMenu, .modelPicker, .contextWindow:
            return true
        default:
            return false
        }
    }

    private func dismissManualPopovers() {
        showPlusMenuPopover = false
        showModelPickerPopover = false
        showContextWindowPopover = false
    }

    // MARK: - Composer catalog composition (desktop `pWt` / `YWt`)

    private var composerWorkspaceKey: String {
        let context = store.composerWorkspaceContext()
        return store.composerWorkspaceKey(path: context.path, identity: context.identity)
    }

    private var allComposerCommands: [ComposerCommandItem] {
        let host: [ComposerCommandItem]
        if store.isUITestSeededMode {
            host = store.seededComposerCommands()
        } else {
            host = composerCommands
        }
        return AppStore.composerCommands(host: host, includePlanMode: true)
    }

    /// `sWt`: raw catalog count 0 → "broadcast" empty text, otherwise "no matching".
    private var composerCommandEmptyText: String {
        let rawCount = store.isUITestSeededMode ? store.slashCommands.count : composerCommandRawCount
        return rawCount == 0
            ? "No slash commands have been broadcast for the current ZCode Agent session"
            : "No matching slash commands"
    }

    private func commandDisplayLabel(_ command: ComposerCommandItem) -> String {
        command.isAppCommand ? command.label : "/\(command.value)"
    }

    private var rankedComposerCommands: [ComposerCommandItem] {
        guard case .slash(let query) = activePopover else { return [] }
        return ComposerFuzzy.rank(allComposerCommands, query: query) { command in
            ComposerFuzzy.Candidate(
                label: command.label,
                value: command.value,
                description: command.description,
                keywords: command.keywords
            )
        }
    }

    private var allComposerSkills: [ComposerSkillItem] {
        AppStore.composerSkillItems(from: store.skills)
    }

    private var rankedSlashSkills: [ComposerSkillItem] {
        guard case .slash(let query) = activePopover else { return [] }
        return ComposerFuzzy.rank(allComposerSkills, query: query) { skill in
            ComposerFuzzy.Candidate(
                label: "$\(skill.name)",
                value: skill.name,
                description: skill.description,
                keywords: skill.keywords
            )
        }
    }

    private var rankedDollarSkills: [ComposerSkillItem] {
        guard case .skill(let query) = activePopover else { return [] }
        return ComposerFuzzy.rank(allComposerSkills, query: query) { skill in
            ComposerFuzzy.Candidate(
                label: "$\(skill.name)",
                value: skill.name,
                description: skill.description,
                keywords: skill.keywords
            )
        }
    }

    private var rankedComposerAgents: [ComposerAgentItem] {
        guard case .slash(let query) = activePopover else { return [] }
        return ComposerFuzzy.rank(AppStore.composerAgentItems(from: store.subagents), query: query) { agent in
            ComposerFuzzy.Candidate(
                label: agent.name,
                value: agent.name,
                description: agent.description,
                keywords: agent.keywords
            )
        }
    }

    private var rankedMentionPlugins: [ComposerPluginItem] {
        guard case .mention(let query) = activePopover else { return [] }
        return ComposerFuzzy.rank(AppStore.composerPluginItems(from: store.plugins), query: query, requireQuery: false) { plugin in
            ComposerFuzzy.Candidate(
                label: plugin.name,
                value: plugin.pluginId,
                description: plugin.description,
                keywords: plugin.keywords,
                isPlugin: true
            )
        }
    }

    private var rankedMentionFiles: [ComposerFileItem] {
        guard case .mention(let query) = activePopover else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ComposerFuzzy.directoryFirstStable(mentionFiles, isDirectory: { $0.isDirectory })
        }
        return mentionFiles
    }

    private var mentionSessionGroups: [ComposerSessionGroup] {
        switch activePopover {
        case .mention(let query):
            return store.composerSessionGroups(query: query, groupedByProject: false)
        case .hash(let query):
            return store.composerSessionGroups(query: query, groupedByProject: true)
        default:
            return []
        }
    }

    private var mentionSessionCount: Int {
        mentionSessionGroups.reduce(0) { $0 + $1.items.count }
    }

    private var officialEnabledPlugins: [PluginCatalogItem] {
        store.plugins.filter { $0.installed && $0.enabled }
    }

    private var placeholderString: String {
        if store.activeSession?.status == .running {
            return L10n.text(
                "Keep typing to queue follow-up changes",
                vi: "Tiếp tục nhập để xếp hàng thay đổi tiếp theo",
                zh: "继续输入以排队后续修改",
                lang: store.language
            )
        }
        let hasMessages = !(store.activeSession?.messages.isEmpty ?? true)
        if hasMessages {
            return L10n.text(
                "Ask for follow-up changes",
                vi: "Yêu cầu thay đổi tiếp theo",
                zh: "继续提出修改要求",
                lang: store.language
            )
        }
        return L10n.text(
            "Ask ZCode anything…",
            vi: "Hỏi ZCode bất cứ điều gì…",
            zh: "向 ZCode 提问…",
            lang: store.language
        )
    }

    public var body: some View {
        composerShellRegion
            .overlay(alignment: .top) {
                ZStack(alignment: .bottom) {
                    if hasDismissableManualPopover {
                        Color.clear
                            .frame(height: 1200)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.14)) {
                                    dismissManualPopovers()
                                }
                            }
                    }

                    popoverOverlayRegion
                }
                .alignmentGuide(.top) { d in
                    d[.bottom] + 6
                }
                .zIndex(50)
            }
            .animation(.easeOut(duration: 0.14), value: activePopover)
        .task(id: composerSlashTaskKey) {
            await hydrateComposerSlashCatalog()
        }
        .task(id: composerSkillCatalogTaskKey) {
            await hydrateComposerSkillCatalog()
        }
        .task(id: composerMentionSearchTaskKey) {
            await runMentionFileSearch()
        }
        .onChange(of: composerWorkspaceKey) { _, _ in
            mentionFileMissQuery = ""
        }
        .onChange(of: store.composerText) { _, newValue in
            if !newValue.isEmpty && hasDismissableManualPopover {
                dismissManualPopovers()
            }
        }
        .confirmationDialog("Add Attachment", isPresented: $showAttachmentTypeDialog, titleVisibility: .visible) {
            Button("Photo or Screenshot Library") { showPhotoLibraryPicker = true }
            Button("Files & Documents") { showFileImporter = true }
            Button("Workspace File") {
                selectedWorkspaceFileIds = []
                showFileMentionPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotoLibraryPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let picked = newItems
            selectedPhotoItems = []
            Task { @MainActor in
                for (index, item) in picked.enumerated() {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "png"
                    let suffix = String(UUID().uuidString.prefix(4)).lowercased()
                    store.composerAttachments.append(
                        ComposerAttachment(
                            id: UUID().uuidString,
                            name: "image-\(index + 1)-\(suffix).\(ext)",
                            kind: "image",
                            sizeBytes: data.count,
                            filePath: nil,
                            lineNote: nil,
                            previewPNGData: data
                        )
                    )
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
        .sheet(isPresented: $showFileMentionPicker) {
            workspaceFilePickerSheet
        }
        .sheet(isPresented: $showModelSettingsSheet) {
            NavigationStack {
                ModelProviderSettingsView(store: store)
                    .navigationTitle("Model settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showModelSettingsSheet = false }
                        }
                    }
            }
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            store.showToast("Couldn't import file: \(error.localizedDescription)")
        case .success(let urls):
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("zcode-attachments", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard let data = try? Data(contentsOf: url) else { continue }
                let fileName = url.lastPathComponent.isEmpty ? "attachment" : url.lastPathComponent
                let destURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
                let savedPath: String? = (try? data.write(to: destURL, options: .atomic)) != nil ? destURL.path : nil

                let ext = url.pathExtension.lowercased()
                let isImage: Bool = {
                    if let type = UTType(filenameExtension: ext) {
                        return type.conforms(to: .image)
                    }
                    return ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff"].contains(ext)
                }()
                let isPDF = ext == "pdf" || UTType(filenameExtension: ext)?.conforms(to: .pdf) == true
                let kind = isImage ? "image" : (isPDF ? "pdf" : "file")

                store.composerAttachments.append(
                    ComposerAttachment(
                        id: UUID().uuidString,
                        name: fileName,
                        kind: kind,
                        sizeBytes: data.count,
                        filePath: savedPath,
                        lineNote: nil,
                        previewPNGData: isImage ? data : nil
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var popoverOverlayRegion: some View {
        switch activePopover {
        case .slash:
            slashCapabilitiesPopover
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .mention:
            mentionContextPopover
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .skill:
            skillsOnlyPopover
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .hash:
            sessionHashPopover
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .plusMenu:
            plusAttachmentPopover
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .modelPicker:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                modelPickerPopoverView
                    .frame(maxWidth: 300)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .contextWindow:
            ContextWindowPopover(
                usage: store.activeSession?.contextUsage,
                fallbackUsedPercent: store.activeSession?.contextUsedPercent ?? 0
            )
            .frame(maxWidth: 340)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var composerShellRegion: some View {
        let queuedItems = store.activeSession?.queuedPrompts ?? []
        if !queuedItems.isEmpty {
            VStack(spacing: 0) {
                nestedPromptQueueSection(queuedItems)
                innerComposerBox
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(palette.isDark ? Color(red: 0.098, green: 0.098, blue: 0.098) : palette.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(palette.borderStrong.opacity(0.65), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nestedQueueComposerShell")
        } else {
            innerComposerBox
        }
    }

    // MARK: - 1. Nested Prompt Queue (1:1 ZCode Remote "↑ Steer", Edit, Delete)

    private func nestedPromptQueueSection(_ items: [QueuedPromptItem]) -> some View {
        VStack(spacing: 4) {
            ForEach(items) { item in
                queuedPromptRowView(item)
            }
        }
        .padding(.bottom, 4)
    }

    private func queuedPromptRowView(_ item: QueuedPromptItem) -> some View {
        HStack(spacing: 8) {
            dragGripDots

            VStack(alignment: .leading, spacing: 2) {
                Text(item.content)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                if !item.attachments.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: item.attachments.first?.kind == "image" ? "photo" : "paperclip")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.foregroundMuted)
                        Text(attachmentSummaryText(item.attachments))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.foregroundMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 6)

            Button {
                store.steerQueuedPrompt(item.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.text("Steer", vi: "Điều hướng", zh: "插队引导", lang: store.language))
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(palette.foreground)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(Capsule().fill(popoverRowHighlight))
                .overlay(Capsule().strokeBorder(palette.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("steerQueuedPromptButton")

            Button {
                store.editQueuedPrompt(item.id)
                isInputFocused = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit queued prompt")
            .accessibilityIdentifier("editQueuedPromptButton")

            Button {
                store.deleteQueuedPrompt(item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete queued prompt")
            .accessibilityIdentifier("deleteQueuedPromptButton")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queuedPromptRow_\(item.id)")
    }

    private var dragGripDots: some View {
        VStack(spacing: 2.5) {
            HStack(spacing: 2.5) {
                Circle().fill(palette.foregroundMuted).frame(width: 2.5, height: 2.5)
                Circle().fill(palette.foregroundMuted).frame(width: 2.5, height: 2.5)
            }
            HStack(spacing: 2.5) {
                Circle().fill(palette.foregroundMuted).frame(width: 2.5, height: 2.5)
                Circle().fill(palette.foregroundMuted).frame(width: 2.5, height: 2.5)
            }
            HStack(spacing: 2.5) {
                Circle().fill(palette.foregroundMuted).frame(width: 2.5, height: 2.5)
                Circle().fill(palette.foregroundMuted).frame(width: 2.5, height: 2.5)
            }
        }
        .frame(width: 14, height: 22)
    }

    // MARK: - 2. Inner Rounded Composer Box

    private var innerComposerBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.composerQuotes.isEmpty {
                stagedQuotesStrip
            }

            if !store.composerAttachments.isEmpty {
                stagedAttachmentsStrip
            }

            TextField(placeholderString, text: $store.composerText, axis: .vertical)
                .font(.system(size: 15.5))
                .foregroundStyle(palette.foreground)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .accessibilityIdentifier("composerTextField")

            composerBottomToolbar
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(palette.header, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isInputFocused ? palette.inputBorderFocused : palette.borderStrong.opacity(0.75), lineWidth: 1)
        )
    }

    private var stagedQuotesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.composerQuotes) { quote in
                    let firstLine = quoteFirstLine(quote.text)
                    HStack(spacing: 5) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.foregroundSubtle)

                        Text(firstLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                            .frame(maxWidth: 180, alignment: .leading)

                        if let path = quote.path, !path.isEmpty {
                            Text(shortQuotePath(path))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.foregroundMuted)
                                .lineLimit(1)
                                .frame(maxWidth: 96, alignment: .leading)
                        }

                        Button {
                            store.playSelectionHaptic()
                            store.removeComposerQuote(quote.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove quote")
                        .accessibilityIdentifier("removeComposerQuote_\(quote.id)")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(palette.inputBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("composerQuoteChip_\(quote.id)")
                }
            }
        }
        .accessibilityIdentifier("stagedQuotesStrip")
    }

    private func quoteFirstLine(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.first ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shortQuotePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed as NSString).lastPathComponent.nilIfEmpty ?? trimmed
    }

    private var stagedAttachmentsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.composerAttachments) { att in
                    HStack(spacing: 5) {
                        if att.kind == "image",
                           let data = att.previewPNGData,
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        } else {
                            Image(systemName: attachmentIconName(for: att.kind))
                                .font(.system(size: 11))
                                .foregroundStyle(palette.foregroundSubtle)
                        }
                        Text(att.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                            .frame(maxWidth: 160, alignment: .leading)
                        Button {
                            store.playSelectionHaptic()
                            store.composerAttachments.removeAll(where: { $0.id == att.id })
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(att.name)")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(palette.inputBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
                }
            }
        }
        .accessibilityIdentifier("stagedAttachmentsStrip")
    }

    private func attachmentIconName(for kind: String) -> String {
        switch kind {
        case "image": return "photo"
        case "pdf": return "doc.richtext"
        case "comment": return "text.quote"
        default: return "doc"
        }
    }

    private var composerBottomToolbar: some View {
        HStack(spacing: 6) {
            plusToolbarButton
            permissionShieldMenu
            if store.runningBackgroundWorkCount > 0 {
                backgroundWorksButton
            }
            Spacer(minLength: 2)
            contextRingButton
            modelPickerTriggerButton
            submitOrStopButton
        }
    }

    private var backgroundWorksButton: some View {
        let count = store.runningBackgroundWorkCount
        return Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.easeOut(duration: 0.16)) {
                dismissManualPopovers()
                store.showTaskStatusPanel.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(store.showTaskStatusPanel ? palette.foreground : palette.foregroundSubtle)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(store.showTaskStatusPanel ? popoverRowHighlight : (palette.isDark ? Color(hex: 0x262628) : palette.surfaceHover))
            )
            .overlay(
                Capsule()
                    .strokeBorder(palette.borderStrong.opacity(0.65), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Running background agents: \(count)")
        .accessibilityIdentifier("composerBackgroundWorksButton")
    }

    private var plusToolbarButton: some View {
        let isPlusActive = (activePopover == .plusMenu)
        return Button {
            store.playSelectionHaptic()
            withAnimation(.easeOut(duration: 0.14)) {
                if !store.composerText.isEmpty && activePopover != .plusMenu {
                    if case .slash = activePopover { store.composerText = "" }
                    if case .mention = activePopover { store.composerText = "" }
                    if case .skill = activePopover { store.composerText = "" }
                    if case .hash = activePopover { store.composerText = "" }
                }
                let nextState = !showPlusMenuPopover
                dismissManualPopovers()
                showPlusMenuPopover = nextState
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16.5, weight: .regular))
                .foregroundStyle(isPlusActive ? palette.foreground : palette.foregroundSubtle)
                .frame(width: 24, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isPlusActive ? popoverRowHighlight : Color.clear)
                )
                .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add attachment or capability")
        .accessibilityIdentifier("attachMenuButton")
    }

    private var permissionShieldMenu: some View {
        let mode = store.activeSession?.mode ?? .build
        let isElevated = (mode == .yolo || mode == .autoEdit)
        return Menu {
            Picker("Mode", selection: Binding(
                get: { store.activeSession?.mode == .ask ? .build : (store.activeSession?.mode ?? .build) },
                set: { store.selectMode($0) }
            )) {
                ForEach(AgentExecutionMode.officialCases) { itemMode in
                    Label {
                        Text(itemMode.label)
                        Text(itemMode.subtitle)
                    } icon: {
                        Image(systemName: itemMode.icon)
                    }
                    .tag(itemMode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isElevated ? palette.warning : palette.foregroundSubtle)
                .frame(width: 24, height: 30)
                .contentShape(Rectangle().inset(by: -6))
                .accessibilityLabel("Mode: \(mode.label)")
        }
        .accessibilityIdentifier("composerModePicker")
    }

    private var contextRingFraction: Double {
        if let usage = store.activeSession?.contextUsage {
            return max(0, min(1, usage.fraction))
        }
        let pct = store.activeSession?.contextUsedPercent ?? 0
        return max(0, min(1, Double(pct) / 100.0))
    }

    private var contextRingButton: some View {
        let fraction = contextRingFraction
        let pct = Int((fraction * 100).rounded())
        let isOpen = (activePopover == .contextWindow)
        return Button {
            store.playSelectionHaptic()
            withAnimation(.easeOut(duration: 0.14)) {
                let nextState = !showContextWindowPopover
                dismissManualPopovers()
                showContextWindowPopover = nextState
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(palette.borderStrong, lineWidth: 2.2)
                    .frame(width: 16, height: 16)
                if fraction > 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.04, fraction)))
                        .stroke(
                            fraction > 0.80 ? palette.warning : (isOpen ? palette.foreground : palette.foregroundSubtle),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 24, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOpen ? popoverRowHighlight : Color.clear)
            )
            .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Context window usage \(pct) percent")
        .accessibilityIdentifier("contextTelemetryButton")
    }

    private var currentLiveSelection: LiveModelSelection? {
        guard let session = store.activeSession else { return store.preferredModelSelection }
        return store.modelSelection(for: session)
    }

    private var currentTriggerModelLabel: String {
        let live = !store.isUITestSeededMode
        let currentModelId = live ? (currentLiveSelection?.modelId ?? "") : (store.activeSession?.modelId ?? "")
        return currentModelId.isEmpty ? "Select model" : modelSlug(for: currentModelId)
    }

    private var currentTriggerEffortLabel: String? {
        if store.isUITestSeededMode {
            let currentModelId = store.activeSession?.modelId ?? ""
            let descriptor = store.providers.filter(\.enabled).flatMap(\.models).first(where: { $0.id == currentModelId })
            guard descriptor?.supportsReasoning ?? true else { return nil }
            return (store.activeSession?.effort ?? .high).fullTitle
        }
        let levels = store.reasoningLevels(for: store.activeSession)
        guard !levels.isEmpty else { return nil }
        let current = currentLiveSelection?.reasoningLevel ?? levels.last ?? ""
        let title = Self.reasoningTitle(current)
        return title.isEmpty ? nil : title
    }

    private var modelPickerTriggerButton: some View {
        let isOpen = (activePopover == .modelPicker)
        let modelLabel = currentTriggerModelLabel
        let effortLabel = currentTriggerEffortLabel

        return Button {
            store.playSelectionHaptic()
            withAnimation(.easeOut(duration: 0.14)) {
                let nextState = !showModelPickerPopover
                dismissManualPopovers()
                showModelPickerPopover = nextState
            }
        } label: {
            HStack(spacing: 4) {
                Text(modelLabel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isOpen ? palette.foreground : palette.foregroundSubtle)
                    .lineLimit(1)

                if let effortLabel {
                    Text(effortLabel)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(palette.foregroundMuted)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.foregroundMuted)
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOpen ? popoverRowHighlight : Color.clear)
            )
            .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(effortLabel.map { "\(modelLabel) \($0)" } ?? modelLabel)
        .accessibilityIdentifier("composerModelPicker")
    }

    @ViewBuilder
    private var modelPickerPopoverView: some View {
        if store.isUITestSeededMode {
            let enabledProviders = store.providers.filter(\.enabled)
            let groups = enabledProviders.map { provider in
                ModelPickerProviderGroup(
                    id: provider.id,
                    name: provider.name,
                    badgeText: "API",
                    models: provider.models.map { model in
                        ModelPickerItem(
                            id: "\(provider.id)/\(model.id)",
                            providerId: provider.id,
                            providerName: provider.name,
                            modelId: model.id,
                            displayName: model.name,
                            supportsVision: model.supportsVision,
                            reasoningLevels: model.supportsReasoning ? ReasoningEffortLevel.allCases.map(\.rawValue) : []
                        )
                    }
                )
            }
            let currentModelId = store.activeSession?.modelId ?? ""
            let currentProviderId = enabledProviders.first(where: { p in
                p.models.contains(where: { $0.id == currentModelId })
            })?.id
            let activeModelDescriptor = enabledProviders.flatMap(\.models).first(where: { $0.id == currentModelId })
            let levels = (activeModelDescriptor?.supportsReasoning ?? true) ? ReasoningEffortLevel.allCases.map(\.rawValue) : []
            let currentLevel = (store.activeSession?.effort ?? .high).rawValue

            ModelPickerPopover(
                groups: groups,
                activeProviderId: currentProviderId,
                activeModelId: currentModelId,
                activeReasoningLevels: levels,
                activeReasoningLevel: currentLevel,
                isLoading: false,
                onSelectModel: { item in
                    store.playSelectionHaptic()
                    if var s = store.activeSession {
                        s.modelId = item.modelId
                        s.modelProviderId = item.providerId
                        store.activeSession = s
                    }
                    withAnimation(.easeOut(duration: 0.14)) {
                        showModelPickerPopover = false
                    }
                },
                onSelectReasoningLevel: { level in
                    guard let parsed = ReasoningEffortLevel(rawValue: level) else { return }
                    store.playSelectionHaptic()
                    if var s = store.activeSession {
                        s.effort = parsed
                        store.activeSession = s
                    }
                },
                onManageModels: {
                    withAnimation(.easeOut(duration: 0.14)) {
                        showModelPickerPopover = false
                    }
                    showModelSettingsSheet = true
                }
            )
        } else {
            let groups = store.liveModelGroups.map { group in
                ModelPickerProviderGroup(
                    id: group.id,
                    name: group.name,
                    badgeText: "API",
                    models: group.models.map { option in
                        ModelPickerItem(
                            id: option.id,
                            providerId: option.providerId,
                            providerName: option.providerName,
                            modelId: option.modelId,
                            displayName: option.modelId,
                            supportsVision: option.supportsImage,
                            reasoningLevels: option.reasoningLevels
                        )
                    }
                )
            }
            let selection = currentLiveSelection
            let levels = store.reasoningLevels(for: store.activeSession)
            let currentLevel = selection?.reasoningLevel ?? levels.last ?? ""

            ModelPickerPopover(
                groups: groups,
                activeProviderId: selection?.providerId,
                activeModelId: selection?.modelId ?? "",
                activeReasoningLevels: levels,
                activeReasoningLevel: currentLevel,
                isLoading: store.liveModelGroups.isEmpty,
                onSelectModel: { item in
                    if let option = store.liveModel(providerId: item.providerId, modelId: item.modelId) {
                        store.selectModel(option)
                    }
                    withAnimation(.easeOut(duration: 0.14)) {
                        showModelPickerPopover = false
                    }
                },
                onSelectReasoningLevel: { level in
                    store.selectReasoningLevel(level)
                },
                onManageModels: {
                    withAnimation(.easeOut(duration: 0.14)) {
                        showModelPickerPopover = false
                    }
                    showModelSettingsSheet = true
                }
            )
        }
    }

    static func reasoningTitle(_ level: String) -> String {
        switch level.lowercased() {
        case "xhigh": return "Extra High"
        case "medium", "med": return "Medium"
        case "": return "Default"
        default: return level.prefix(1).uppercased() + level.dropFirst()
        }
    }

    @ViewBuilder
    private var submitOrStopButton: some View {
        let hasDraft = !store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !store.composerAttachments.isEmpty
            || !store.composerQuotes.isEmpty
        if store.activeSession?.status == .running && !hasDraft {
            Button {
                store.stopGeneration()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(popoverRowHighlight)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(palette.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop generation")
            .accessibilityIdentifier("stopGenerationButton")
        } else {
            Button {
                store.playImpactHaptic(.medium)
                dismissManualPopovers()
                store.sendPrompt()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hasDraft ? Color(red: 0.09, green: 0.09, blue: 0.09) : Color(white: 0.14))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(hasDraft ? palette.brand : Color(white: 0.48))
                    )
                    .contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
            .disabled(!hasDraft)
            .accessibilityLabel("Send prompt")
            .accessibilityIdentifier("sendPromptButton")
        }
    }

    // MARK: - 3. "/" Slash Capabilities Popover (COMMANDS + SKILLS + AGENTS, desktop `pWt` / `sWt`)

    private var slashCapabilitiesPopover: some View {
        let commands = rankedComposerCommands
        let skills = rankedSlashSkills
        let agents = rankedComposerAgents
        let statusRows = (commands.isEmpty ? 1 : 0) + (skills.isEmpty ? 1 : 0) + (agents.isEmpty ? 1 : 0)
        return floatingPopoverCard(
            footerText: hasActiveQuery ? nil : "Type to search commands, skills, or agents",
            accessibilityId: "slashAutocompletePopover"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    popoverSectionHeader("Commands")
                    if commands.isEmpty {
                        if composerCommandsLoading {
                            popoverStatusRow(text: "Searching...", style: .loading, accessibilityId: "slashCommandsLoadingRow")
                        } else {
                            popoverStatusRow(
                                text: composerCommandEmptyText,
                                style: .empty,
                                accessibilityId: "slashCommandsEmptyRow"
                            )
                        }
                    } else {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { idx, command in
                            slashCommandRowView(command, isHighlighted: idx == 0)
                        }
                    }

                    popoverSectionHeader("Skills")
                    if skills.isEmpty {
                        if composerSkillsLoading {
                            popoverStatusRow(text: "Searching...", style: .loading, accessibilityId: "slashSkillsLoadingRow")
                        } else {
                            popoverStatusRow(text: "No matching skills", style: .empty, accessibilityId: "slashSkillsEmptyRow")
                        }
                    } else {
                        ForEach(Array(skills.enumerated()), id: \.element.id) { idx, skill in
                            skillRowView(skill, isHighlighted: commands.isEmpty && idx == 0)
                        }
                    }

                    popoverSectionHeader("Agents")
                    if agents.isEmpty {
                        if composerAgentsLoading {
                            popoverStatusRow(text: "Searching...", style: .loading, accessibilityId: "slashAgentsLoadingRow")
                        } else {
                            popoverStatusRow(text: "No matching agents", style: .empty, accessibilityId: "slashAgentsEmptyRow")
                        }
                    } else {
                        ForEach(Array(agents.enumerated()), id: \.element.id) { idx, agent in
                            subagentRowView(agent, isHighlighted: commands.isEmpty && skills.isEmpty && idx == 0)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: popoverListHeight(sections: 3, rows: commands.count + skills.count + agents.count + statusRows, extraPadding: 16))
        }
    }

    private func popoverListHeight(sections: Int, rows: Int, extraPadding: CGFloat) -> CGFloat {
        let hasQueue = !(store.activeSession?.queuedPrompts.isEmpty ?? true)
        let cap: CGFloat = isInputFocused ? (hasQueue ? 190 : 246) : 284
        if rows == 0 { return 54 }
        let natural = CGFloat(sections * 28 + rows * 36) + extraPadding
        return min(cap, natural)
    }

    private func slashCommandRowView(_ command: ComposerCommandItem, isHighlighted: Bool) -> some View {
        Button {
            applyComposerCommandSelection(command)
        } label: {
            HStack(spacing: 8) {
                Text(commandDisplayLabel(command))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)

                if command.description.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    Text(command.description)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slashCommandRow_\(command.id)")
    }

    private func skillRowView(_ skill: ComposerSkillItem, isHighlighted: Bool) -> some View {
        Button {
            replaceComposerTriggerToken(with: "$\(skill.name) ")
        } label: {
            HStack(spacing: 8) {
                Text("$\(skill.name)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)
                    .accessibilityLabel(skill.name)

                Text(skill.description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slashSkillRow_\(skill.id)")
    }

    private func subagentRowView(_ agent: ComposerAgentItem, isHighlighted: Bool) -> some View {
        Button {
            replaceComposerTriggerToken(with: "@\(agent.name) ")
        } label: {
            HStack(spacing: 8) {
                Text(agent.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)

                Text(agent.description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slashAgentRow_\(agent.id)")
    }

    // MARK: - 4. "@" Mention Context Popover (PLUGINS + FILES + SESSIONS, desktop `YWt`)

    private var mentionContextPopover: some View {
        let plugins = rankedMentionPlugins
        let files = rankedMentionFiles
        let sessions = mentionSessionGroups
        let showPlugins = !plugins.isEmpty || composerPluginsLoading
        // Desktop keeps a loading/error section visible; we also keep the completed Files section so
        // `chat.mention.files.empty` ("No matching files") is visible instead of silently dropping it.
        let showFiles = true
        let showSessions = !sessions.isEmpty
        let sectionCount = (showPlugins ? 1 : 0) + (showFiles ? 1 : 0) + (showSessions ? 1 : 0)
        let filesStatusRows = mentionFiles.isEmpty && mentionFilesError == nil ? 1 : 0
        let rowCount = plugins.count + files.count + mentionSessionCount
            + (mentionFilesLoading ? 1 : 0) + (mentionFilesError != nil ? 1 : 0) + filesStatusRows

        return floatingPopoverCard(
            footerText: hasActiveQuery ? nil : "Type to search plugins, files, or conversations",
            accessibilityId: "mentionAutocompletePopover"
        ) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if showPlugins {
                            popoverSectionHeader("Plugins")
                            if plugins.isEmpty {
                                popoverStatusRow(text: "Searching...", style: .loading, accessibilityId: "mentionPluginsLoadingRow")
                            } else {
                                ForEach(Array(plugins.enumerated()), id: \.element.id) { idx, plugin in
                                    mentionPluginRowView(plugin, isHighlighted: idx == 0)
                                }
                            }
                        }

                        if showFiles {
                            popoverSectionHeader("Files")
                            if let error = mentionFilesError {
                                popoverStatusRow(text: error, style: .error, accessibilityId: "mentionFilesErrorRow")
                            } else if mentionFilesLoading {
                                popoverStatusRow(text: "Searching...", style: .loading, accessibilityId: "mentionFilesLoadingRow")
                            } else if files.isEmpty {
                                popoverStatusRow(text: "No matching files", style: .empty, accessibilityId: "mentionFilesEmptyRow")
                            } else {
                                ForEach(Array(files.enumerated()), id: \.element.id) { idx, file in
                                    mentionFileRowView(file, isHighlighted: !showPlugins && idx == 0)
                                }
                            }
                        }

                        if showSessions {
                            popoverSectionHeader("Sessions")
                            let flatSessions = sessions.flatMap(\.items)
                            ForEach(Array(flatSessions.enumerated()), id: \.element.id) { idx, session in
                                mentionSessionRowView(session, isHighlighted: !showPlugins && !showFiles && idx == 0)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, rowCount > 5 ? 28 : 6)
                }
                .frame(height: popoverListHeight(sections: max(sectionCount, 1), rows: rowCount, extraPadding: 20))

                if rowCount > 5 {
                    scrollDownArrowCue
                }
            }
        }
    }

    private func mentionPluginRowView(_ plugin: ComposerPluginItem, isHighlighted: Bool) -> some View {
        Button {
            guard !plugin.isDisabled else { return }
            replaceComposerTriggerToken(with: "@\(plugin.name.replacingOccurrences(of: " ", with: "-")) ")
        } label: {
            HStack(spacing: 8) {
                pluginColorBadge(for: plugin.name)

                Text(plugin.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)

                Text(plugin.isDisabled ? ComposerPluginItem.conflictReason : plugin.description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(plugin.isDisabled ? palette.warning : palette.foregroundSubtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .opacity(plugin.isDisabled ? 0.55 : 1)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted && !plugin.isDisabled ? popoverRowHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(plugin.isDisabled)
        .accessibilityIdentifier("mentionPluginRow_\(plugin.id)")
    }

    private func mentionFileRowView(_ file: ComposerFileItem, isHighlighted: Bool) -> some View {
        Button {
            replaceComposerTriggerToken(with: "@\(file.mentionPath) ")
        } label: {
            HStack(spacing: 8) {
                fileTypeBadge(for: file)

                Text(file.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(file.relativePath)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(file.rootName)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.foregroundMuted)
                    .lineLimit(1)
                    .frame(maxWidth: 84, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mentionFileRow_\(file.id)")
    }

    private func mentionSessionRowView(_ session: ComposerSessionItem, isHighlighted: Bool) -> some View {
        Button {
            replaceComposerTriggerToken(with: "@task:\(session.taskId) ")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 22)

                Text(session.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .leading)

                Text(session.description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mentionSessionRow_\(session.taskId)")
    }

    private var scrollDownArrowCue: some View {
        ZStack {
            Circle()
                .fill(popoverRowHighlight)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(palette.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            Image(systemName: "arrow.down")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.foreground)
        }
        .padding(.bottom, 8)
        .allowsHitTesting(false)
    }

    // MARK: - 5. "$" Skills Popover (desktop `YWt` + `vWt`)

    private var skillsOnlyPopover: some View {
        let skills = rankedDollarSkills
        let rows = skills.count + (skills.isEmpty ? 1 : 0)

        return floatingPopoverCard(
            footerText: hasActiveQuery ? nil : "Type to search skills",
            accessibilityId: "skillAutocompletePopover"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if skills.isEmpty {
                        if composerSkillsLoading {
                            popoverStatusRow(text: "Searching...", style: .loading, accessibilityId: "skillLoadingRow")
                        } else {
                            popoverStatusRow(text: "No matching skills", style: .empty, accessibilityId: "skillEmptyRow")
                        }
                    } else {
                        ForEach(Array(skills.enumerated()), id: \.element.id) { idx, skill in
                            skillRowView(skill, isHighlighted: idx == 0)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: popoverListHeight(sections: 0, rows: rows, extraPadding: 16))
        }
    }

    // MARK: - 5b. "#" Sessions Popover (desktop `#` trigger: grouped by project)

    private var sessionHashPopover: some View {
        let groups = mentionSessionGroups
        let rowCount = groups.reduce(0) { $0 + $1.items.count }

        return floatingPopoverCard(
            footerText: hasActiveQuery ? nil : "Type to search recent sessions",
            accessibilityId: "hashSessionAutocompletePopover"
        ) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if groups.isEmpty {
                            if hasActiveQuery {
                                popoverStatusRow(
                                    text: "No matching mention results",
                                    style: .empty,
                                    accessibilityId: "hashSessionsEmptyRow"
                                )
                            }
                        } else {
                            ForEach(groups) { group in
                                popoverSectionHeader(group.title)
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, session in
                                    mentionSessionRowView(session, isHighlighted: idx == 0)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, rowCount > 5 ? 28 : 6)
                }
                .frame(height: popoverListHeight(sections: groups.count, rows: rowCount + (groups.isEmpty ? 1 : 0), extraPadding: 20))

                if rowCount > 5 {
                    scrollDownArrowCue
                }
            }
        }
    }

    // MARK: - 6. "+" Add & Plugins & Shortcut Hints Popover (1:1 Screenshot 3)

    private var plusAttachmentPopover: some View {
        floatingPopoverCard(
            footerText: "Type to search plugins, files, and chats",
            accessibilityId: "plusAttachmentPopover"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        popoverSectionHeader("ADD")

                        Button {
                            showPlusMenuPopover = false
                            showAttachmentTypeDialog = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .frame(width: 24)
                                Text("Attachments")
                                    .font(.system(size: 14.5, weight: .regular))
                                    .foregroundStyle(palette.foreground)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(popoverRowHighlight)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plusPopoverAttachmentsRow")

                        Button {
                            showPlusMenuPopover = false
                            store.composerText = "/workflow "
                            isInputFocused = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .frame(width: 24)
                                Text("Workflow")
                                    .font(.system(size: 14.5, weight: .regular))
                                    .foregroundStyle(palette.foreground)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plusPopoverWorkflowRow")

                        popoverSectionHeader("PLUGINS")

                        ForEach(officialEnabledPlugins.prefix(7)) { plugin in
                            Button {
                                showPlusMenuPopover = false
                                let prefix = store.composerText.isEmpty || store.composerText.hasSuffix(" ") ? "" : " "
                                store.composerText += "\(prefix)@\(plugin.name.replacingOccurrences(of: " ", with: "-")) "
                                isInputFocused = true
                            } label: {
                                HStack(spacing: 10) {
                                    pluginColorBadge(for: plugin.name)
                                    Text(plugin.name)
                                        .font(.system(size: 14.5, weight: .regular))
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 38)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(height: isInputFocused ? 140 : 216)

                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 2) {
                    shortcutHintRow(symbol: "@", label: "Add context", accessibilityId: "shortcutAddContextRow") {
                        showPlusMenuPopover = false
                        let prefix = store.composerText.isEmpty || store.composerText.hasSuffix(" ") ? "" : " "
                        store.composerText += "\(prefix)@"
                        isInputFocused = true
                    }

                    shortcutHintRow(symbol: "/", label: "Choose capabilities", accessibilityId: "shortcutChooseCapabilitiesRow") {
                        showPlusMenuPopover = false
                        store.composerText = "/"
                        isInputFocused = true
                    }

                    shortcutHintRow(symbol: "$", label: "Choose skills", accessibilityId: "shortcutChooseSkillsRow") {
                        showPlusMenuPopover = false
                        let prefix = store.composerText.isEmpty || store.composerText.hasSuffix(" ") ? "" : " "
                        store.composerText += "\(prefix)$"
                        isInputFocused = true
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
        }
    }

    // MARK: - Workspace File Picker Sheet (Multi-Select)

    private var workspaceFilePickerSheet: some View {
        NavigationStack {
            List(store.flattenedFiles) { file in
                let isSelected = selectedWorkspaceFileIds.contains(file.id)
                Button {
                    store.playSelectionHaptic()
                    if isSelected {
                        selectedWorkspaceFileIds.remove(file.id)
                    } else {
                        selectedWorkspaceFileIds.insert(file.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.system(size: 14, weight: .medium))
                            Text(file.path)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(palette.accentBlue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Attach Workspace Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        selectedWorkspaceFileIds = []
                        showFileMentionPicker = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Attach\(selectedWorkspaceFileIds.isEmpty ? "" : " (\(selectedWorkspaceFileIds.count))")") {
                        let picked = store.flattenedFiles.filter { selectedWorkspaceFileIds.contains($0.id) }
                        for file in picked {
                            let kind = file.kind == .image ? "image" : (file.kind == .pdf ? "pdf" : "file")
                            store.composerAttachments.append(
                                ComposerAttachment(
                                    id: UUID().uuidString,
                                    name: file.name,
                                    kind: kind,
                                    sizeBytes: file.sizeBytes,
                                    filePath: file.path,
                                    lineNote: nil,
                                    previewPNGData: file.kind == .image ? file.binaryData : nil
                                )
                            )
                        }
                        selectedWorkspaceFileIds = []
                        showFileMentionPicker = false
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedWorkspaceFileIds.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Catalog hydration (desktop `CV` cache + `AWt` debounced search)

    private var composerSlashTaskKey: String {
        let isSlashOpen: Bool
        if case .slash = activePopover { isSlashOpen = true } else { isSlashOpen = false }
        return "\(composerWorkspaceKey)|\(isSlashOpen ? "slash" : "idle")"
    }

    private var composerMentionSearchTaskKey: String {
        if case .mention(let query) = activePopover {
            return "\(composerWorkspaceKey)|mention|\(query)"
        }
        return "\(composerWorkspaceKey)|idle"
    }

    private var composerSkillCatalogTaskKey: String {
        let isSkillOpen: Bool
        if case .skill = activePopover { isSkillOpen = true } else { isSkillOpen = false }
        return "\(composerWorkspaceKey)|\(isSkillOpen ? "skill" : "idle")"
    }

    /// Refreshes `skills.list`, `subagents.list`, and `plugin-management.getPluginsOverview` for the
    /// active workspace (desktop loads these when the popovers mount), throttled to once per 20s.
    @MainActor
    private func refreshComposerCatalogsIfNeeded(workspacePath: String, workspaceIdentity: String?) async {
        guard !store.isUITestSeededMode else { return }
        let key = store.composerWorkspaceKey(path: workspacePath, identity: workspaceIdentity)
        let now = Date()
        guard composerCatalogsRefreshedKey != key || now.timeIntervalSince(composerCatalogsRefreshedAt) > 20 else { return }
        composerCatalogsRefreshedKey = key
        composerCatalogsRefreshedAt = now
        composerSkillsLoading = true
        composerAgentsLoading = true
        composerPluginsLoading = true
        async let skills: Void = store.syncSkillsRPC(workspacePath: workspacePath, workspaceIdentity: workspaceIdentity)
        async let agents: Void = store.syncSubagentsRPC(workspacePath: workspacePath, workspaceIdentity: workspaceIdentity)
        async let plugins: Void = store.syncPluginsRPC(workspacePath: workspacePath, workspaceIdentity: workspaceIdentity)
        _ = await (skills, agents, plugins)
        composerSkillsLoading = false
        composerAgentsLoading = false
        composerPluginsLoading = false
    }

    /// Reads `zcode-session.readWorkspacePresentation` per workspace (re-hydrating when the catalog is
    /// empty, like desktop `CV`), and refreshes the skill/agent/plugin catalogs from the host.
    @MainActor
    private func hydrateComposerSlashCatalog() async {
        guard case .slash = activePopover else { return }
        let context = store.composerWorkspaceContext()
        let key = store.composerWorkspaceKey(path: context.path, identity: context.identity)
        await refreshComposerCatalogsIfNeeded(workspacePath: context.path, workspaceIdentity: context.identity)
        guard !store.isUITestSeededMode else { return }

        if composerCommandsWorkspaceKey != key || composerCommands.isEmpty {
            composerCommandsLoading = true
            if let result = await store.readComposerWorkspaceCommands(
                workspacePath: context.path,
                workspaceIdentity: context.identity
            ) {
                composerCommands = result.commands
                composerCommandRawCount = result.rawCount
                composerCommandsWorkspaceKey = key
            }
            composerCommandsLoading = false
        }
    }

    @MainActor
    private func hydrateComposerSkillCatalog() async {
        guard case .skill = activePopover else { return }
        let context = store.composerWorkspaceContext()
        await refreshComposerCatalogsIfNeeded(workspacePath: context.path, workspaceIdentity: context.identity)
    }

    /// `AWt`: debounce ~150ms, search the workspace root plus additional roots, retry once with
    /// `refresh: true` when a non-empty query returns nothing, and cap at 1000 (10 when the query is empty).
    @MainActor
    private func runMentionFileSearch() async {
        guard case .mention(let rawQuery) = activePopover else {
            mentionFilesLoading = false
            mentionFilesError = nil
            return
        }

        if store.isUITestSeededMode {
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let flattened = store.flattenedFiles
            let matches: [WorkspaceFileNode]
            if query.isEmpty {
                matches = Array(flattened.prefix(10))
            } else {
                matches = flattened.filter {
                    $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)
                }
            }
            let rootPath = store.activeSession?.workspacePath ?? ""
            let rootName = AppStore.composerBasename(rootPath)
            mentionFiles = matches.prefix(1000).map { node in
                ComposerFileItem(
                    id: "file:\(node.path)",
                    name: node.name,
                    path: node.path,
                    relativePath: node.path,
                    mentionPath: node.path,
                    type: node.isDirectory ? "directory" : "file",
                    rootName: rootName,
                    rootPath: rootPath
                )
            }
            mentionFilesLoading = false
            mentionFilesError = nil
            return
        }

        mentionFilesLoading = true
        mentionFilesError = nil
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled,
              case .mention(let query) = activePopover,
              query == rawQuery else { return }
        guard store.isRemoteRPCReady else {
            mentionFiles = []
            mentionFilesLoading = false
            return
        }

        let context = store.composerWorkspaceContext()
        async let catalogRefresh: Void = refreshComposerCatalogsIfNeeded(
            workspacePath: context.path,
            workspaceIdentity: context.identity
        )
        let additionalRoots = await store.composerAdditionalRoots(for: store.activeSession)
        guard !Task.isCancelled else {
            _ = await catalogRefresh
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // `_Ut(n, E)` with `E = query.isEmpty ? 10 : 3` → 10 for an empty query, 1000 otherwise.
        let limit = trimmed.isEmpty ? 10 : 1000
        var items: [ComposerFileItem] = []
        var errorText: String?
        do {
            items = try await store.searchComposerFiles(
                mainRoot: context.path,
                additionalRoots: additionalRoots,
                workspaceIdentity: context.identity,
                query: query,
                limit: limit
            )
            let missKey = trimmed.lowercased()
            if items.isEmpty, !missKey.isEmpty, mentionFileMissQuery != missKey {
                mentionFileMissQuery = missKey
                items = try await store.searchComposerFiles(
                    mainRoot: context.path,
                    additionalRoots: additionalRoots,
                    workspaceIdentity: context.identity,
                    query: query,
                    limit: limit,
                    refresh: true
                )
            }
        } catch {
            errorText = error.localizedDescription
        }
        _ = await catalogRefresh

        guard !Task.isCancelled,
              case .mention(let latestQuery) = activePopover,
              latestQuery == rawQuery else { return }
        mentionFiles = items
        mentionFilesError = errorText
        mentionFilesLoading = false
    }

    // MARK: - Shared Popover Chrome & Icon Badges

    private func floatingPopoverCard<Content: View>(
        footerText: String?,
        accessibilityId: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()

            if let footerText {
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)

                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(palette.foregroundMuted)
                    Text(footerText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(palette.foregroundMuted)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
            }
        }
        .background(popoverCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 16, y: 4)
        .background(alignment: .bottom) {
            palette.background
                .frame(height: 10)
                .offset(y: 7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityId)
    }

    private enum PopoverStatusStyle {
        case loading
        case empty
        case error
    }

    private func popoverStatusRow(text: String, style: PopoverStatusStyle, accessibilityId: String) -> some View {
        HStack(spacing: 7) {
            if style == .loading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(palette.foregroundSubtle)
            }
            Text(text)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(style == .error ? palette.destructive : palette.foregroundMuted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .accessibilityIdentifier(accessibilityId)
    }

    private func popoverSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(palette.foregroundMuted)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func shortcutHintRow(
        symbol: String,
        label: String,
        accessibilityId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(symbol)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(popoverRowHighlight)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(palette.borderStrong, lineWidth: 1)
                    )

                Text(label)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }

    private func pluginColorBadge(for pluginName: String) -> some View {
        let lower = pluginName.lowercased()
        let spec: (bg: Color, icon: String) = {
            if lower.contains("visualize") {
                return (Color(red: 0.48, green: 0.35, blue: 0.96), "sparkles")
            } else if lower.contains("node") {
                return (Color(red: 0.18, green: 0.63, blue: 0.27), "terminal.fill")
            } else if lower.contains("browser") {
                return (Color(red: 0.18, green: 0.50, blue: 0.96), "globe")
            } else if lower.contains("document") {
                return (Color(red: 0.15, green: 0.39, blue: 0.92), "doc.text.fill")
            } else if lower == "pdf" || lower.contains("pdf") {
                return (Color(red: 0.86, green: 0.15, blue: 0.15), "doc.richtext.fill")
            } else if lower.contains("presentation") {
                return (Color(red: 0.92, green: 0.35, blue: 0.05), "play.rectangle.fill")
            } else if lower.contains("spreadsheet") {
                return (Color(red: 0.09, green: 0.64, blue: 0.29), "tablecells.fill")
            } else {
                return (Color(red: 0.32, green: 0.36, blue: 0.44), "puzzlepiece.extension.fill")
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(spec.bg)
                .frame(width: 24, height: 24)
            Image(systemName: spec.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    /// File-type badge by extension (directories get a folder glyph); a `.zip` is an archive, not "MD".
    @ViewBuilder
    private func fileTypeBadge(for file: ComposerFileItem) -> some View {
        if file.isDirectory {
            Image(systemName: "folder.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.accentBlue)
                .frame(width: 24)
        } else {
            let spec = fileBadgeSpec(for: file.name)
            Text(spec.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 24, height: 18)
                .background(spec.color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    private func fileBadgeSpec(for fileName: String) -> (label: String, color: Color) {
        let ext = ((fileName as NSString).pathExtension).lowercased()
        switch ext {
        case "swift": return ("SW", Color(red: 0.94, green: 0.32, blue: 0.22))
        case "ts", "tsx": return ("TS", Color(red: 0.19, green: 0.47, blue: 0.78))
        case "js", "jsx", "mjs", "cjs": return ("JS", Color(red: 0.85, green: 0.68, blue: 0.16))
        case "json": return ("{}", Color(red: 0.85, green: 0.68, blue: 0.16))
        case "md", "markdown", "mdx": return ("MD", Color(red: 0.45, green: 0.50, blue: 0.58))
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "rar", "7z": return ("ZIP", Color(red: 0.60, green: 0.44, blue: 0.24))
        case "pdf": return ("PDF", Color(red: 0.86, green: 0.15, blue: 0.15))
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "svg", "bmp", "tiff", "ico":
            return ("IMG", Color(red: 0.56, green: 0.35, blue: 0.94))
        case "rs": return ("RS", Color(red: 0.82, green: 0.44, blue: 0.18))
        case "py": return ("PY", Color(red: 0.19, green: 0.47, blue: 0.78))
        case "sh", "zsh", "bash", "fish": return ("SH", Color(red: 0.18, green: 0.63, blue: 0.27))
        case "html", "htm": return ("HTML", Color(red: 0.92, green: 0.35, blue: 0.05))
        case "css", "scss", "sass", "less": return ("CSS", Color(red: 0.19, green: 0.47, blue: 0.78))
        case "yml", "yaml", "toml", "ini", "conf", "cfg": return ("CFG", Color(red: 0.45, green: 0.50, blue: 0.58))
        case "txt", "log", "csv": return ("TXT", Color(red: 0.45, green: 0.50, blue: 0.58))
        default: return ("DOC", Color(red: 0.45, green: 0.50, blue: 0.58))
        }
    }

    /// Desktop `P`: app commands remove the token and run; other commands insert `/value `.
    private func applyComposerCommandSelection(_ command: ComposerCommandItem) {
        if command.isAppCommand {
            replaceComposerTriggerToken(with: "")
            store.selectMode(.plan)
            isInputFocused = true
            return
        }
        replaceComposerTriggerToken(with: "/\(command.value) ")
    }

    /// Replaces the active `IK` token (trigger + query) with the chosen completion.
    private func replaceComposerTriggerToken(with replacement: String) {
        guard let token = composerTriggerToken else {
            let prefix = store.composerText.isEmpty || store.composerText.hasSuffix(" ") ? "" : " "
            store.composerText += prefix + replacement
            isInputFocused = true
            return
        }
        var text = store.composerText
        text.replaceSubrange(token.tokenRange, with: replacement)
        store.composerText = text
        isInputFocused = true
    }

    private func attachmentSummaryText(_ attachments: [ComposerAttachment]) -> String {
        let names = attachments.map(\.name).joined(separator: ", ")
        let imagesCount = attachments.filter { $0.kind == "image" }.count
        if imagesCount == attachments.count && imagesCount > 0 {
            return "\(imagesCount) \(imagesCount == 1 ? "image" : "images") · \(names)"
        }
        return names
    }

    private func modelSlug(for modelId: String) -> String {
        let slug = modelId.split(separator: "/").last.map(String.init) ?? modelId
        if slug.count <= 16 { return slug }
        return String(slug.prefix(15)) + "…"
    }
}

private extension ReasoningEffortLevel {
    var fullTitle: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .max: return "Max"
        }
    }
}
