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
    @State private var showContextWindowPopover: Bool = false
    @State private var showAttachmentTypeDialog: Bool = false

    private enum ActivePopoverKind: Equatable {
        case none
        case plusMenu
        case modelPicker
        case contextWindow
        case slash(String)
        case mention(String)
        case skill(String)
    }

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
        let raw = store.composerText
        let trimmedLeading = raw.drop(while: { $0.isWhitespace })

        if trimmedLeading.hasPrefix("/") && !trimmedLeading.contains(" ") && !trimmedLeading.contains("\n") {
            return .slash(String(trimmedLeading.dropFirst()))
        }

        if let lastToken = raw.split(whereSeparator: { $0.isWhitespace }).last,
           !raw.hasSuffix(" "), !raw.hasSuffix("\n") {
            if lastToken.hasPrefix("@") {
                return .mention(String(lastToken.dropFirst()))
            }
            if lastToken.hasPrefix("$") {
                return .skill(String(lastToken.dropFirst()))
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

    private var filteredCommands: [SlashCommandItem] {
        guard case .slash(let q) = activePopover else { return [] }
        if q.isEmpty {
            return Array(store.slashCommands.prefix(5))
        }
        return store.slashCommands.filter {
            $0.trigger.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q)
        }
    }

    private var filteredSlashSkills: [SkillCatalogItem] {
        switch activePopover {
        case .slash(let q), .skill(let q):
            let enabled = store.skills.filter(\.enabled)
            if q.isEmpty { return enabled }
            return enabled.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q) }
        default:
            return []
        }
    }

    private var filteredSubagents: [SubagentDefinitionItem] {
        guard case .slash(let q) = activePopover else { return [] }
        let enabled = store.subagents.filter(\.enabled)
        if q.isEmpty { return enabled }
        return enabled.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.description.localizedCaseInsensitiveContains(q) }
    }

    private var officialEnabledPlugins: [PluginCatalogItem] {
        store.plugins.filter { $0.installed && $0.enabled }
    }

    private var filteredMentionPlugins: [PluginCatalogItem] {
        guard case .mention(let q) = activePopover else { return [] }
        if q.isEmpty { return officialEnabledPlugins }
        return officialEnabledPlugins.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var filteredMentionFiles: [WorkspaceFileNode] {
        guard case .mention(let q) = activePopover else { return [] }
        let files = store.flattenedFiles
        if q.isEmpty { return Array(files.prefix(6)) }
        return Array(files.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q)
        }.prefix(8))
    }

    private var filteredMentionSessions: [AgentTaskSession] {
        guard case .mention(let q) = activePopover else { return [] }
        let others = store.sessions.filter { !$0.archived && $0.id != store.activeSessionId }
        if q.isEmpty { return Array(others.prefix(3)) }
        return Array(others.filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(4))
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
                    store.showToast("Manage models on your computer")
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
                    store.showToast("Manage models on your computer")
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

    // MARK: - 3. "/" Slash Capabilities Popover (COMMANDS + SKILLS + AGENTS)

    private var slashCapabilitiesPopover: some View {
        let commands = filteredCommands
        let skills = filteredSlashSkills
        let agents = filteredSubagents

        return floatingPopoverCard(
            footerText: "Type to search commands, skills, or agents",
            accessibilityId: "slashAutocompletePopover"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !commands.isEmpty {
                        popoverSectionHeader("COMMANDS")
                        ForEach(Array(commands.enumerated()), id: \.element.id) { idx, cmd in
                            slashCommandRowView(cmd, isHighlighted: idx == 0, showSummary: cmd.trigger == "/goal" || commands.count < 5)
                        }
                    }

                    if !skills.isEmpty {
                        popoverSectionHeader("SKILLS")
                        let highlightFirstSkill = commands.isEmpty
                        ForEach(Array(skills.enumerated()), id: \.element.id) { idx, skill in
                            skillRowView(skill, prefix: "/", isHighlighted: highlightFirstSkill && idx == 0)
                        }
                    }

                    if !agents.isEmpty {
                        popoverSectionHeader("AGENTS")
                        let highlightFirstAgent = commands.isEmpty && skills.isEmpty
                        ForEach(Array(agents.enumerated()), id: \.element.id) { idx, agent in
                            subagentRowView(agent, isHighlighted: highlightFirstAgent && idx == 0)
                        }
                    }

                    if commands.isEmpty && skills.isEmpty && agents.isEmpty {
                        Text("No matching commands, skills, or agents")
                            .font(.system(size: 13.5))
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: slashScrollHeight(commands: commands.count, skills: skills.count, agents: agents.count))
        }
    }

    private func slashScrollHeight(commands: Int, skills: Int, agents: Int) -> CGFloat {
        let hasQueue = !(store.activeSession?.queuedPrompts.isEmpty ?? true)
        let cap: CGFloat = isInputFocused ? (hasQueue ? 190 : 246) : 284
        let sections = (commands > 0 ? 1 : 0) + (skills > 0 ? 1 : 0) + (agents > 0 ? 1 : 0)
        let rows = commands + skills + agents
        if rows == 0 { return 54 }
        let natural = CGFloat(sections * 28 + rows * 40 + 16)
        return min(cap, natural)
    }

    private func slashCommandRowView(_ cmd: SlashCommandItem, isHighlighted: Bool, showSummary: Bool) -> some View {
        Button {
            applySlashSelection(cmd)
        } label: {
            HStack(spacing: 10) {
                if cmd.trigger == "Plan mode" {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 20)
                } else {
                    Text(">_")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 20)
                }

                Text(cmd.trigger)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(palette.foreground)

                if showSummary && cmd.trigger != "Plan mode" {
                    Text(cmd.summary)
                        .font(.system(size: 13.5))
                        .foregroundStyle(palette.foregroundMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slashCommandRow_\(cmd.id)")
    }

    private func skillRowView(_ skill: SkillCatalogItem, prefix: String, isHighlighted: Bool) -> some View {
        Button {
            if prefix == "/" {
                store.composerText = "/\(skill.name) "
                isInputFocused = true
            } else {
                replaceTrailingToken(with: "$\(skill.name) ")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cube")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 20)

                Text(skill.name)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func subagentRowView(_ agent: SubagentDefinitionItem, isHighlighted: Bool) -> some View {
        Button {
            store.composerText = "@\(agent.name) "
            isInputFocused = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 20)

                Text(agent.name)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. "@" Mention Context Popover (PLUGINS + FILES + SESSIONS + Scroll Arrow)

    private var mentionContextPopover: some View {
        let plugins = filteredMentionPlugins
        let files = filteredMentionFiles
        let sessions = filteredMentionSessions
        let totalCount = plugins.count + files.count + sessions.count

        return floatingPopoverCard(
            footerText: "Type to search plugins, files, or conversations",
            accessibilityId: "mentionAutocompletePopover"
        ) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if !plugins.isEmpty {
                            popoverSectionHeader("PLUGINS")
                            ForEach(Array(plugins.enumerated()), id: \.element.id) { idx, plugin in
                                mentionPluginRowView(plugin, isHighlighted: idx == 0)
                            }
                        }

                        if !files.isEmpty {
                            popoverSectionHeader("FILES")
                            let highlightFirstFile = plugins.isEmpty
                            ForEach(Array(files.enumerated()), id: \.element.id) { idx, file in
                                mentionFileRowView(file, isHighlighted: highlightFirstFile && idx == 0)
                            }
                        }

                        if !sessions.isEmpty {
                            popoverSectionHeader("SESSIONS")
                            let highlightFirstSession = plugins.isEmpty && files.isEmpty
                            ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, session in
                                mentionSessionRowView(session, isHighlighted: highlightFirstSession && idx == 0)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, totalCount > 5 ? 28 : 6)
                }
                .frame(height: mentionScrollHeight(plugins: plugins.count, files: files.count, sessions: sessions.count))

                if totalCount > 5 {
                    scrollDownArrowCue
                }
            }
        }
    }

    private func mentionScrollHeight(plugins: Int, files: Int, sessions: Int) -> CGFloat {
        let hasQueue = !(store.activeSession?.queuedPrompts.isEmpty ?? true)
        let cap: CGFloat = isInputFocused ? (hasQueue ? 190 : 246) : 284
        let sections = (plugins > 0 ? 1 : 0) + (files > 0 ? 1 : 0) + (sessions > 0 ? 1 : 0)
        let rows = plugins + files + sessions
        if rows == 0 { return 54 }
        let natural = CGFloat(sections * 28 + rows * 40 + 20)
        return min(cap, natural)
    }

    private func mentionPluginRowView(_ plugin: PluginCatalogItem, isHighlighted: Bool) -> some View {
        Button {
            replaceTrailingToken(with: "@\(plugin.name.replacingOccurrences(of: " ", with: "-")) ")
        } label: {
            HStack(spacing: 10) {
                pluginColorBadge(for: plugin.name)

                Text(plugin.name)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mentionPluginRow_\(plugin.id)")
    }

    private func mentionFileRowView(_ file: WorkspaceFileNode, isHighlighted: Bool) -> some View {
        Button {
            replaceTrailingToken(with: "@\(file.path) ")
        } label: {
            HStack(spacing: 10) {
                fileLanguageBadge(for: file.name)

                Text(file.name)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                Text(file.path)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.foregroundMuted)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mentionFileRow_\(file.id)")
    }

    private func mentionSessionRowView(_ session: AgentTaskSession, isHighlighted: Bool) -> some View {
        Button {
            replaceTrailingToken(with: "@task:\(session.id) ")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 24)

                Text(session.displayTitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? popoverRowHighlight : Color.clear)
            )
        }
        .buttonStyle(.plain)
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

    // MARK: - 5. "$" Skills Popover

    private var skillsOnlyPopover: some View {
        let skills = filteredSlashSkills

        return floatingPopoverCard(
            footerText: "Type to search skills",
            accessibilityId: "skillAutocompletePopover"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    popoverSectionHeader("SKILLS")
                    ForEach(Array(skills.enumerated()), id: \.element.id) { idx, skill in
                        skillRowView(skill, prefix: "$", isHighlighted: idx == 0)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: min(isInputFocused ? 210 : 240, CGFloat(28 + max(1, skills.count) * 40 + 16)))
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

    // MARK: - Shared Popover Chrome & Icon Badges

    private func floatingPopoverCard<Content: View>(
        footerText: String,
        accessibilityId: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()

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

    private func popoverSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
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

    private func fileLanguageBadge(for fileName: String) -> some View {
        let lower = fileName.lowercased()
        let spec: (label: String, color: Color) = {
            if lower.hasSuffix(".ts") || lower.hasSuffix(".tsx") {
                return ("TS", Color(red: 0.19, green: 0.47, blue: 0.78))
            } else if lower.hasSuffix(".swift") {
                return ("SW", Color(red: 0.94, green: 0.32, blue: 0.22))
            } else if lower.hasSuffix(".rs") {
                return ("RS", Color(red: 0.82, green: 0.44, blue: 0.18))
            } else if lower.hasSuffix(".pdf") {
                return ("PDF", Color(red: 0.86, green: 0.15, blue: 0.15))
            } else if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") {
                return ("IMG", Color(red: 0.56, green: 0.35, blue: 0.94))
            } else if lower.hasSuffix(".json") {
                return ("{}", Color(red: 0.85, green: 0.68, blue: 0.16))
            } else {
                return ("MD", Color(red: 0.45, green: 0.50, blue: 0.58))
            }
        }()

        return Text(spec.label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 24, height: 18)
            .background(spec.color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func applySlashSelection(_ cmd: SlashCommandItem) {
        if cmd.trigger == "Plan mode" {
            if var s = store.activeSession {
                s.mode = .plan
                store.activeSession = s
            }
            store.composerText = ""
            store.showToast("Switched to Plan mode")
            isInputFocused = true
            return
        }
        if cmd.trigger == "/compact" || cmd.trigger == "/goal" {
            store.composerText = cmd.trigger
            store.sendPrompt()
            return
        }
        store.composerText = cmd.trigger + " "
        isInputFocused = true
    }

    private func replaceTrailingToken(with replacement: String) {
        var parts = store.composerText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !parts.isEmpty {
            parts.removeLast()
        }
        parts.append(replacement)
        store.composerText = parts.joined(separator: " ")
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
