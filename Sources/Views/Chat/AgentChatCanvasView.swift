import SwiftUI

public struct AgentChatCanvasView: View {
    @Bindable var store: AppStore
    let isWideLayout: Bool
    @Environment(\.zcodePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTodoExpanded: Bool = false
    @State private var showTelemetrySheet: Bool = false
    @State private var showRenameTaskAlert: Bool = false
    @State private var renameDraft: String = ""

    /// Transcript stickiness: true while the reader is parked at the newest content (streaming follows it),
    /// false once the reader deliberately scrolls up into history.
    @State private var isPinnedToTranscriptBottom: Bool = true
    /// Geometry used to tell "content grew" (keep following) from "reader scrolled up" (stop following).
    @State private var transcriptViewportBottomY: CGFloat = 0
    @State private var transcriptContentBottomY: CGFloat = 0
    @State private var transcriptContentHeight: CGFloat = 0
    @State private var transcriptLastDistance: CGFloat?
    @State private var transcriptLastContentHeight: CGFloat?
    @State private var transcriptLastViewportBottomY: CGFloat?
    /// Session whose transcript the last recorded message diff belongs to (prevents cross-session id collisions).
    @State private var transcriptMessagesSessionId: String?

    public init(store: AppStore, isWideLayout: Bool) {
        self.store = store
        self.isWideLayout = isWideLayout
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    // Bar 1: Official ZCode Mobile Shell Header ("← Task chat" + Palette)
                    if !isWideLayout {
                        mobileShellTopBar
                        Rectangle()
                            .fill(palette.border)
                            .frame(height: 1)
                    }

                    // Bar 2: Workspace / Task Context Sub-header ("📁 Task... •••" + Side-Pane Toggle)
                    workspaceSubHeaderBar
                    Rectangle()
                        .fill(palette.border)
                        .frame(height: 1)

                    // Main Chat Stream + Floating "Changes +add -del" Pill
                    if let session = store.activeSession {
                        ZStack(alignment: .topTrailing) {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 18) {
                                        if session.messages.isEmpty {
                                            emptySessionHero
                                        } else {
                                            ForEach(session.messages) { message in
                                                ChatTurnCardView(store: store, message: message)
                                                    .id(message.id)
                                            }
                                        }

                                        if session.status == .running {
                                            let turnStart = AppStore.runningTurnStart(session)
                                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                                HStack(spacing: 8) {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                    Text(turnStart.map {
                                                        "Working for \(AppStore.workDurationText(milliseconds: max(0, context.date.timeIntervalSince($0)) * 1000))"
                                                    } ?? "Working…")
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(palette.foregroundSubtle)
                                                        .monospacedDigit()
                                                }
                                            }
                                            .accessibilityIdentifier("chatWorkingIndicator")
                                        }

                                        if let notice = session.statusNoticeText, !notice.isEmpty {
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: session.status == .error ? "exclamationmark.triangle.fill" : "info.circle")
                                                    .foregroundStyle(session.status == .error ? palette.destructive : palette.foregroundSubtle)
                                                Text(notice)
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(palette.foreground)
                                                    .textSelection(.enabled)
                                            }
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(palette.card, in: RoundedRectangle(cornerRadius: 10))
                                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))
                                            .accessibilityIdentifier("chatStatusNotice")
                                        }

                                        if let perm = session.pendingPermission {
                                            permissionCard(perm)
                                                .id("pending-permission")
                                        }

                                        if let question = session.pendingQuestion {
                                            questionCard(question)
                                                .id("pending-question")
                                        }

                                        if let plan = session.pendingPlan {
                                            planCard(plan)
                                                .id("pending-plan")
                                        }

                                        Color.clear
                                            .frame(height: 8)
                                            .id(Self.chatBottomAnchorID)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, store.gitChanges.isEmpty ? 14 : 46)
                                    .padding(.bottom, chatBottomContentInset(session))
                                    .frame(maxWidth: 820)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: ChatTranscriptContentMetricsKey.self,
                                                value: ChatTranscriptMetrics(
                                                    contentBottomY: proxy.frame(in: .global).maxY,
                                                    contentHeight: proxy.size.height
                                                )
                                            )
                                        }
                                    )
                                }
                                .scrollDismissesKeyboard(.interactively)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: ChatTranscriptViewportBottomKey.self,
                                            value: proxy.frame(in: .global).maxY
                                        )
                                    }
                                )
                                .onPreferenceChange(ChatTranscriptViewportBottomKey.self) { value in
                                    transcriptViewportBottomY = value
                                    refreshTranscriptPinState()
                                }
                                .onPreferenceChange(ChatTranscriptContentMetricsKey.self) { metrics in
                                    transcriptContentBottomY = metrics.contentBottomY
                                    transcriptContentHeight = metrics.contentHeight
                                    refreshTranscriptPinState()
                                    // Images / code blocks / syntax highlighting can grow the transcript without a
                                    // message delta. While parked at the bottom, keep the newest row visible.
                                    if isPinnedToTranscriptBottom, transcriptContentBottomY + chatBottomContentInset(session) - transcriptViewportBottomY > Self.transcriptPinEnterDistance {
                                        proxy.scrollTo(Self.chatBottomAnchorID, anchor: .bottom)
                                    }
                                }
                                // Session opens / re-opens: always land on the newest content when the transcript
                                // (or a late V4 snapshot) finishes laying out.
                                .task(id: session.id) {
                                    resetTranscriptScrollTracking(for: session.id)
                                    scrollTranscriptToBottom(proxy, redrawPasses: 2)
                                }
                                // Transcript changes: first load, streaming, and history-page prepends.
                                .onChange(of: session.messages) { oldMessages, newMessages in
                                    handleTranscriptMessagesChange(
                                        sessionId: session.id,
                                        from: oldMessages,
                                        to: newMessages,
                                        proxy: proxy
                                    )
                                }
                            }

                            // Official ZCode Floating "Changes +add -del" Pill (Top-Right when unified StatusPanel is collapsed)
                            if !store.gitChanges.isEmpty && !store.showTaskStatusPanel {
                                floatingChangesPill
                                    .padding(.top, 8)
                                    .padding(.trailing, 12)
                            }

                            // Official ZCode Unified Floating Task / Status Panel ("Thanh task") OR Compact Active Todo Pill
                            if store.showTaskStatusPanel {
                                VStack(spacing: 0) {
                                    Spacer()
                                    ZCodeUnifiedTaskStatusPanelView(
                                        store: store,
                                        session: session,
                                        totalAdded: store.gitTotalAddedLines,
                                        totalRemoved: store.gitTotalRemovedLines
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.top, 4)
                                    .padding(.bottom, 6)
                                    .background(palette.background)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            } else if store.showTodoTracker && !session.todos.isEmpty {
                                VStack {
                                    Spacer()
                                    HStack {
                                        floatingTodoPill(session.todos)
                                        Spacer(minLength: 12)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 6)
                                }
                            }
                        }
                        .zIndex(1)
                    }

                    // Official ZCode Rounded Composer (with Nested Prompt Queue & Floating /, @, $, + Popovers)
                    ZCodeComposerView(store: store, onTapContextGauge: {
                        showTelemetrySheet = true
                    })
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .background(palette.background)
                    .zIndex(15)
                }
                .background(palette.background)

                // Official ZCode Mobile Side-Pane Overlay (`w-[min(88vw,28rem)]` or Full Width)
                if !isWideLayout && store.showInspectorSheet {
                    Color.black.opacity(0.56)
                        .ignoresSafeArea()
                        .accessibilityIdentifier("inspectorBackdrop")
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                store.showInspectorSheet = false
                            }
                        }
                        .transition(.opacity)
                        .zIndex(20)

                    CodingInspectorWindowView(store: store, isDockedPane: true)
                        .frame(width: store.isInspectorExpandedFull ? geo.size.width : min(geo.size.width * 0.92, 448))
                        .frame(maxHeight: .infinity)
                        .background(palette.background)
                        .overlay(alignment: .leading) {
                            if !store.isInspectorExpandedFull {
                                Rectangle()
                                    .fill(palette.border)
                                    .frame(width: 1)
                            }
                        }
                        .shadow(color: .black.opacity(0.42), radius: 18, x: -6, y: 0)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 28, coordinateSpace: .local)
                                .onEnded { value in
                                    if value.translation.width > 76 && abs(value.translation.height) < 64 {
                                        store.playImpactHaptic(.light)
                                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                            store.showInspectorSheet = false
                                        }
                                    }
                                }
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                        .zIndex(25)
                }

                // Official ZCode 1:1 Slide-Over SubAgent Multi-Tab Transcript View
                if store.showSubagentDrawer {
                    Color.black.opacity(0.52)
                        .ignoresSafeArea()
                        .accessibilityIdentifier("subagentDrawerBackdrop")
                        .onTapGesture {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                store.closeSubagentSession()
                            }
                        }
                        .transition(.opacity)
                        .zIndex(26)

                    ZCodeSubagentSlideOverDrawerView(store: store)
                        .frame(width: min(geo.size.width * 0.88, 432))
                        .frame(maxHeight: .infinity)
                        .background(palette.background)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(palette.border)
                                .frame(width: 1)
                        }
                        .shadow(color: .black.opacity(0.44), radius: 18, x: -6, y: 0)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 28, coordinateSpace: .local)
                                .onEnded { value in
                                    if value.translation.width > 76 && abs(value.translation.height) < 64 {
                                        store.playImpactHaptic(.light)
                                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                            store.closeSubagentSession()
                                        }
                                    }
                                }
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                        .zIndex(28)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.showInspectorSheet)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.isInspectorExpandedFull)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.showSubagentDrawer)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: store.showTaskStatusPanel)
        }
        .sheet(isPresented: $showTelemetrySheet) {
            sessionTelemetryAndCheckpointsSheet
                .environment(\.zcodePalette, palette)
        }
        .alert("Rename task", isPresented: $showRenameTaskAlert) {
            TextField("Task name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let s = store.activeSession {
                    store.renameSession(s.id, newTitle: renameDraft)
                }
            }
        }
    }

    // MARK: - Bar 1: Mobile Shell Top Bar ("← Task chat" + Theme Palette)

    private var mobileShellTopBar: some View {
        HStack(spacing: 10) {
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                store.playImpactHaptic(.light)
                store.showInspectorSheet = false
                store.mobilePage = .home
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to task list")
            .accessibilityIdentifier("backToTaskHomeButton")

            Text(L10n.text("Task chat", vi: "Phiên tác vụ", zh: "任务会话", lang: store.language))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.foreground)
                .lineLimit(1)

            Spacer()

            Menu {
                Section("Theme") {
                    ForEach(ZCodeThemeMode.allCases) { mode in
                        Button {
                            store.themeMode = mode
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                if store.themeMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section("Code Syntax Palette") {
                    ForEach(ZCodeSyntaxTheme.allCases) { st in
                        Button {
                            store.syntaxTheme = st
                        } label: {
                            HStack {
                                Text(st.displayName)
                                if store.syntaxTheme == st {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button {
                    store.showSettingsSheet = true
                } label: {
                    Label("All Appearance & Settings…", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 16.5, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Appearance and theme")
            }
            .accessibilityIdentifier("chatThemeMenuButton")
        }
        .padding(.horizontal, 6)
        .frame(height: 44)
        .background(palette.header)
    }

    // MARK: - Bar 2: Workspace / Session Sub-header + Side-Pane Toggle

    private var workspaceSubHeaderBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(palette.foregroundSubtle)
                .padding(.leading, 4)

            Text(store.activeSession?.displayTitle ?? "New task")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
                .frame(maxWidth: 210, alignment: .leading)

            Menu {
                if let session = store.activeSession {
                    Button {
                        renameDraft = session.title
                        showRenameTaskAlert = true
                    } label: {
                        Label("Rename task", systemImage: "pencil")
                    }
                    Button {
                        store.togglePinSession(session.id)
                    } label: {
                        Label(session.pinned ? "Unpin task" : "Pin task", systemImage: session.pinned ? "pin.slash" : "pin")
                    }
                    Button {
                        showTelemetrySheet = true
                    } label: {
                        let contextPct = session.contextUsage.map { Int(($0.fraction * 100).rounded()) } ?? session.contextUsedPercent
                        Label("Context (\(contextPct)%)", systemImage: "gauge.with.dots.needle.33percent")
                    }
                }
                Divider()
                Button {
                    store.createNewSession()
                } label: {
                    Label("New task", systemImage: "plus.bubble")
                }
                Button {
                    store.showConnectionsSheet = true
                } label: {
                    Label("Switch device / Scan QR", systemImage: "qrcode.viewfinder")
                }
                Button {
                    store.showSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 38, height: 40)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Task options")
            }
            .accessibilityIdentifier("headerMoreMenuButton")

            Spacer()

            // Official ZCode Right Side-Pane Toggle Icon (`[<|]`)
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                store.playImpactHaptic(.light)
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    store.showInspectorSheet.toggle()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(store.showInspectorSheet ? palette.foreground : palette.foregroundSubtle, lineWidth: 1.3)
                        .frame(width: 17, height: 15)

                    HStack(spacing: 0) {
                        Image(systemName: store.showInspectorSheet ? "chevron.right" : "chevron.left")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(store.showInspectorSheet ? palette.foreground : palette.foregroundSubtle)
                            .frame(width: 10)
                        Rectangle()
                            .fill(store.showInspectorSheet ? palette.foreground : palette.foregroundSubtle)
                            .frame(width: 1.2, height: 15)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 17, height: 15)
                }
                .frame(width: 42, height: 38)
                .background(store.showInspectorSheet ? palette.surfaceHover : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.showInspectorSheet ? "Hide workspace inspector" : "Show workspace inspector")
            .accessibilityIdentifier("openInspectorButton")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(palette.background)
    }

    // MARK: - Official ZCode Floating "Changes +add -del" Pill

    private var floatingChangesPill: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            store.activeInspectorTab = .gitDiff
            withAnimation(.easeOut(duration: 0.2)) {
                store.showInspectorSheet = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)

                Text(L10n.text("Changes", vi: "Thay đổi", zh: "变更", lang: store.language))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.foreground)

                Text("+\(store.gitTotalAddedLines)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.success)

                Text("-\(store.gitTotalRemovedLines)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.destructive)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(palette.card.opacity(0.96))
                    .shadow(color: .black.opacity(0.32), radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .strokeBorder(palette.borderStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("floatingChangesPill")
    }

    // MARK: - Clean ZCode Empty Task State

    private var emptySessionHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 36)
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.foregroundSubtle)
                Text(store.activeProject?.name ?? "workspace")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Text("• \(store.activeProject?.gitBranch ?? "main")")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(palette.foregroundMuted)
            }

            Text("Ask ZCode anything, mention files with @, or use / for commands and skills.")
                .font(.system(size: 14.5))
                .foregroundStyle(palette.foregroundSubtle)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    // MARK: - Interactive Cards (Permission, Question, Plan)

    private func permissionCard(_ perm: PermissionPrompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(palette.warning)
                Text("Permission Required • \(perm.toolName)")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Spacer()
                Text(perm.riskLevel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(palette.warning, in: Capsule())
            }

            Text(perm.summary)
                .font(.system(size: 13.5))
                .foregroundStyle(palette.foreground)

            Text(perm.previewDiffOrCommand)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.foreground)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))

            HStack(spacing: 8) {
                Button {
                    store.respondToPermission(allow: true, rememberForSession: false)
                } label: {
                    Text("Allow Once")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.brandForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("allowOncePermissionButton")

                Button {
                    store.respondToPermission(allow: true, rememberForSession: true)
                } label: {
                    Text("Allow Session")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    store.respondToPermission(allow: false)
                } label: {
                    Text("Deny")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.destructive)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(palette.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("denyPermissionButton")
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.warning.opacity(0.6), lineWidth: 1))
    }

    private func questionCard(_ q: QuestionPrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(q.header.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.accentBlue)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(palette.accentBlue.opacity(0.15), in: Capsule())

            Text(q.question)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.foreground)

            ForEach(q.options) { opt in
                Button {
                    store.respondToQuestion(selectedLabel: opt.label)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(opt.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.foreground)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.foregroundSubtle)
                        }
                        Text(opt.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                    .padding(11)
                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderStrong, lineWidth: 1))
    }

    static func isAwaitingFirstOutput(_ session: AgentTaskSession) -> Bool {
        guard let last = session.messages.last else { return true }
        if last.role != "assistant" { return true }
        return last.content.isEmpty && (last.thought ?? "").isEmpty && last.tools.isEmpty
    }

    // MARK: - Transcript scroll anchoring

    private static let chatBottomAnchorID = "chat-bottom-anchor"
    /// Distance from the viewport bottom within which the transcript counts as parked on the newest content.
    private static let transcriptPinEnterDistance: CGFloat = 12
    /// Distance after which a deliberate scroll-up unpins streaming auto-follow (hysteresis avoids flapping).
    private static let transcriptPinExitDistance: CGFloat = 48

    private func chatBottomContentInset(_ session: AgentTaskSession) -> CGFloat {
        (store.showTodoTracker && session.todos.contains(where: { $0.status != "completed" })) ? 46 : 12
    }

    private func resetTranscriptScrollTracking(for sessionId: String) {
        isPinnedToTranscriptBottom = true
        transcriptMessagesSessionId = sessionId
        transcriptViewportBottomY = 0
        transcriptContentBottomY = 0
        transcriptContentHeight = 0
        transcriptLastDistance = nil
        transcriptLastContentHeight = nil
        transcriptLastViewportBottomY = nil
    }

    /// Distinguishes content growth (keep following the stream) from a deliberate scroll-up (stop following).
    private func refreshTranscriptPinState() {
        guard transcriptViewportBottomY > 0, transcriptContentBottomY > 0 else { return }
        let inset = store.activeSession.map(chatBottomContentInset) ?? 12
        let distance = transcriptContentBottomY + inset - transcriptViewportBottomY

        let previousDistance = transcriptLastDistance
        let previousHeight = transcriptLastContentHeight
        let previousViewport = transcriptLastViewportBottomY
        transcriptLastDistance = distance
        transcriptLastContentHeight = transcriptContentHeight
        transcriptLastViewportBottomY = transcriptViewportBottomY

        guard let previousDistance, let previousHeight, let previousViewport else {
            // First measurement after (re)opening a session: stay pinned; the open-time scroll owns the position.
            return
        }
        // Anchor movement caused by layout (new rows, images, code blocks) is not a user scroll. A user scroll-up
        // moves the content away from the viewport by more than the content itself grew.
        let heightGrowth = transcriptContentHeight - previousHeight
        let viewportDelta = transcriptViewportBottomY - previousViewport
        let readerScrollUpDelta = (distance - previousDistance) - heightGrowth + viewportDelta

        if distance <= Self.transcriptPinEnterDistance {
            isPinnedToTranscriptBottom = true
        } else if distance > Self.transcriptPinExitDistance, readerScrollUpDelta > 0.5 {
            isPinnedToTranscriptBottom = false
        }
    }

    /// Scrolls to the newest content and re-anchors once async layout settles (images, code blocks, deltas).
    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy, animated: Bool = false, redrawPasses: Int = 0) {
        let scroll = { proxy.scrollTo(Self.chatBottomAnchorID, anchor: .bottom) }
        if animated {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scroll() }
        } else {
            scroll()
        }
        guard redrawPasses > 0 else { return }
        Task { @MainActor in
            for delayMs in [140, 420].prefix(redrawPasses) {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                guard !Task.isCancelled, isPinnedToTranscriptBottom else { return }
                proxy.scrollTo(Self.chatBottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func handleTranscriptMessagesChange(
        sessionId: String,
        from oldMessages: [ChatTurnMessage],
        to newMessages: [ChatTurnMessage],
        proxy: ScrollViewProxy
    ) {
        // First diff for this session: treat it as an open/first load, never as a scrollable delta.
        if transcriptMessagesSessionId != sessionId {
            transcriptMessagesSessionId = sessionId
            isPinnedToTranscriptBottom = true
            scrollTranscriptToBottom(proxy, redrawPasses: 2)
            return
        }
        guard !newMessages.isEmpty else { return }
        // First load: an empty transcript becomes the session history (initial cache or a late V4 snapshot).
        if oldMessages.isEmpty {
            if isPinnedToTranscriptBottom {
                scrollTranscriptToBottom(proxy, redrawPasses: 2)
            }
            return
        }
        // Older history page prepended (`conversationRowsRangeV4`): hold the reader's place on the old first row.
        let prependedOlderPage = newMessages.count > oldMessages.count
            && newMessages.last?.id == oldMessages.last?.id
            && newMessages.first?.id != oldMessages.first?.id
        if prependedOlderPage {
            if let anchor = oldMessages.first?.id {
                proxy.scrollTo(anchor, anchor: .top)
            }
            return
        }
        guard isPinnedToTranscriptBottom else { return }
        let appendedRows = newMessages.count > oldMessages.count
        scrollTranscriptToBottom(proxy, animated: appendedRows, redrawPasses: appendedRows ? 2 : 0)
    }

    private func planCard(_ plan: PlanReviewPrompt) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: "map")
                    .foregroundStyle(palette.accentBlue)
                Text(plan.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Spacer()
            }
            Text(plan.summary)
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundSubtle)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.foregroundSubtle)
                        Text(step)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.foreground)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button {
                    store.respondToPlan(approved: true)
                } label: {
                    Text("Approve Plan")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.brandForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    store.respondToPlan(approved: false)
                } label: {
                    Text("Revise")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.foreground)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderStrong, lineWidth: 1))
    }

    // MARK: - Official ZCode Floating Active Todo Pill ("→ ...")

    private func floatingTodoPill(_ todos: [TodoChecklistItem]) -> some View {
        let doneCount = todos.filter { $0.status == "completed" }.count
        let activeItem = todos.first(where: { $0.status == "in_progress" }) ?? todos.last
        let allCompleted = doneCount == todos.count

        return VStack(alignment: .leading, spacing: 6) {
            if showTodoExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Tasks (\(doneCount)/\(todos.count))")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.foregroundMuted)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                showTodoExpanded = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(palette.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(todos) { item in
                        HStack(spacing: 8) {
                            if item.status == "completed" {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.success)
                            } else if item.status == "in_progress" {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                            } else {
                                Image(systemName: "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.foregroundMuted)
                            }
                            Text(item.content)
                                .font(.system(size: 12.5))
                                .foregroundStyle(item.status == "completed" ? palette.foregroundMuted : palette.foreground)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: 320, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.menuBackground.opacity(0.98))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.borderStrong, lineWidth: 1)
                )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    store.showTaskStatusPanel = true
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: allCompleted ? "checkmark" : "arrow.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(allCompleted ? palette.success : palette.foregroundSubtle)

                    Text(activeItem?.content ?? "\(doneCount)/\(todos.count) tasks")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    Capsule()
                        .fill(palette.card.opacity(0.96))
                        .shadow(color: .black.opacity(0.32), radius: 8, y: 2)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(palette.borderStrong, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("floatingTodoPillButton")
        }
    }

    private var sessionTelemetryAndCheckpointsSheet: some View {
        NavigationStack {
            List {
                if let session = store.activeSession {
                    let usage = session.contextUsage
                    let contextValue: String = {
                        if let usage {
                            let used = ContextWindowFormatting.tokens(usage.usedTokens)
                            let maxT = ContextWindowFormatting.tokens(usage.maxTokens)
                            let pct = ContextWindowFormatting.percent(usage.fraction * 100)
                            return "\(used)/\(maxT) (\(pct))"
                        }
                        return "\(session.contextUsedPercent)%"
                    }()
                    let inputTokens = usage?.cumulativeInputTokens ?? session.totalTokensIn
                    let outputTokens = usage?.cumulativeOutputTokens ?? session.totalTokensOut
                    let cachedTokens = usage.map { $0.cumulativeCacheReadTokens + $0.cumulativeCacheWriteTokens } ?? session.cachedTokens

                    Section("Context Window & Token Usage") {
                        LabeledContent("Context Used", value: contextValue)
                        LabeledContent("Input Tokens", value: inputTokens.formatted())
                        LabeledContent("Output Tokens", value: outputTokens.formatted())
                        LabeledContent("Cached Tokens", value: cachedTokens.formatted())
                        if let hitRate = usage?.cacheHitRate {
                            LabeledContent("Average Cache Hit Rate", value: ContextWindowFormatting.percent(hitRate * 100))
                        }
                        if session.costUSD > 0 || usage == nil {
                            LabeledContent("Estimated Cost", value: String(format: "$%.2f", session.costUSD))
                        }
                    }

                }
            }
            .navigationTitle("Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showTelemetrySheet = false }
                }
            }
        }
    }
}

// MARK: - Transcript geometry probes

/// Bottom edge of the transcript viewport in global coordinates.
private struct ChatTranscriptViewportBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ChatTranscriptMetrics: Equatable {
    var contentBottomY: CGFloat
    var contentHeight: CGFloat
}

/// Bottom edge and height of the transcript content (before the bottom padding), in global coordinates.
private struct ChatTranscriptContentMetricsKey: PreferenceKey {
    static var defaultValue = ChatTranscriptMetrics(contentBottomY: 0, contentHeight: 0)
    static func reduce(value: inout ChatTranscriptMetrics, nextValue: () -> ChatTranscriptMetrics) { value = nextValue() }
}

