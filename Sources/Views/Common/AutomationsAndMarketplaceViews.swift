import SwiftUI

public struct AutomationsWorkspacePageView: View {
    @Bindable var store: AppStore
    let isWideLayout: Bool
    @Environment(\.zcodePalette) private var palette
    @State private var showEditor = false
    @State private var editing: AutomationScheduleItem?
    @State private var draftTitle = ""
    @State private var draftCron = "0 9 * * 1-5"
    @State private var draftPrompt = ""
    @State private var isSaving = false
    @State private var pendingDelete: AutomationScheduleItem?
    @State private var busyAutomationId: String?

    public init(store: AppStore, isWideLayout: Bool) {
        self.store = store
        self.isWideLayout = isWideLayout
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !isWideLayout {
                    Button {
                        store.mobilePage = .home
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.foreground)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("backFromAutomationsButton")
                }

                Text(L10n.text("Automations", vi: "Tự động hóa", zh: "自动化", lang: store.language))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.foreground)

                Spacer()

                Button {
                    Task { await store.loadAutomations() }
                } label: {
                    Group {
                        if store.isLoadingAutomations {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 32, height: 32)
                    .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh scheduled tasks")

                Button {
                    beginCreate()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("New")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(palette.brandForeground)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(palette.brand, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("createAutomationButton")
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(palette.header)

            Rectangle().fill(palette.border).frame(height: 1)

            if let error = store.automationsError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.destructive)
                    Text(error)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.destructive.opacity(0.08))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Schedule recurring tasks or queue background work that runs during idle time.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(palette.foregroundSubtle)

                    if store.isLoadingAutomations && store.automations.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 40)
                    } else if store.automations.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 28))
                                .foregroundStyle(palette.foregroundMuted)
                            Text("No scheduled tasks yet.")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(palette.foreground)
                            Text("Create a task to run a prompt on a recurring schedule.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.foregroundSubtle)
                                .multilineTextAlignment(.center)
                            Button("Create scheduled task") { beginCreate() }
                                .font(.system(size: 13, weight: .semibold))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(palette.brand, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(palette.brandForeground)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    }

                    ForEach(store.automations) { auto in
                        automationCard(auto)
                    }
                }
                .padding(16)
            }
        }
        .background(palette.background)
        .task { await store.loadAutomations() }
        .sheet(isPresented: $showEditor) {
            editorSheet
        }
        .confirmationDialog(
            "Delete scheduled task",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = pendingDelete {
                    pendingDelete = nil
                    Task { await store.deleteAutomation(id: target.id) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Delete “\(pendingDelete?.name ?? "")”? This cannot be undone.")
        }
    }

    private func automationCard(_ auto: AutomationScheduleItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(auto.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text("\(auto.cronExpression) • \(auto.workspacePath.isEmpty ? "No workspace" : auto.workspacePath)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.accentBlue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if busyAutomationId == auto.id {
                    ProgressView().controlSize(.mini)
                }
                Toggle(isOn: Binding(
                    get: { auto.enabled },
                    set: { newValue in
                        busyAutomationId = auto.id
                        Task {
                            await store.setAutomationEnabled(id: auto.id, enabled: newValue)
                            busyAutomationId = nil
                        }
                    }
                )) { EmptyView() }
                .labelsHidden()
                .disabled(busyAutomationId != nil)
            }

            Text(auto.prompt)
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundSubtle)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text(auto.lastRunStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.foregroundMuted)
                Spacer()
                Button {
                    busyAutomationId = auto.id
                    Task {
                        await store.runAutomationNow(id: auto.id)
                        busyAutomationId = nil
                    }
                } label: {
                    Label("Run now", systemImage: "play.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(busyAutomationId != nil)

                Menu {
                    Button {
                        beginEdit(auto)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        pendingDelete = auto
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 30, height: 26)
                        .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border, lineWidth: 1))
    }

    private var editorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $draftTitle)
                    TextField("Schedule (cron)", text: $draftCron)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Instructions", text: $draftPrompt, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("Runs on the workspace schedule you enter, for example 0 9 * * 1-5.")
                }
                if let error = store.automationsError {
                    Section {
                        Text(error)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.destructive)
                    }
                }
            }
            .navigationTitle(editing == nil ? "New scheduled task" : "Edit scheduled task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEditor = false }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveDraft()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .presentationDetents([.medium, .large])
    }

    private func beginCreate() {
        guard store.canManageAutomations else {
            store.showToast(store.isRemoteRPCReady
                ? "Open a workspace to manage its scheduled tasks."
                : "Connect to your computer to manage scheduled tasks.")
            return
        }
        editing = nil
        draftTitle = ""
        draftCron = "0 9 * * 1-5"
        draftPrompt = ""
        store.automationsError = nil
        showEditor = true
    }

    private func beginEdit(_ auto: AutomationScheduleItem) {
        editing = auto
        draftTitle = auto.name
        draftCron = auto.cronExpression
        draftPrompt = auto.prompt
        store.automationsError = nil
        showEditor = true
    }

    private func saveDraft() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let ok: Bool
            if let editing {
                ok = await store.updateAutomation(id: editing.id, title: draftTitle, cronExpr: draftCron, prompt: draftPrompt)
            } else {
                ok = await store.createAutomation(title: draftTitle, cronExpr: draftCron, prompt: draftPrompt)
            }
            isSaving = false
            if ok { showEditor = false }
        }
    }
}

public struct PluginMarketplacePageView: View {
    @Bindable var store: AppStore
    let isWideLayout: Bool
    @Environment(\.zcodePalette) private var palette
    @State private var query = ""
    @State private var busyPluginId: String?

    public init(store: AppStore, isWideLayout: Bool) {
        self.store = store
        self.isWideLayout = isWideLayout
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !isWideLayout {
                    Button {
                        store.mobilePage = .home
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.foreground)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("backFromMarketplaceButton")
                }

                Text(L10n.text("Plugin Marketplace", vi: "Kho Plugin", zh: "插件市场", lang: store.language))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.foreground)

                Spacer()

                Button {
                    Task {
                        let ok = await store.refreshPluginMarketplace()
                        if ok {
                            store.showToast("Refreshed plugin catalog")
                        } else if let error = store.pluginMarketplaceError {
                            store.showToast("Couldn't refresh plugins. \(error)")
                        }
                    }
                } label: {
                    Group {
                        if store.isRefreshingPluginMarketplace {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 32, height: 32)
                    .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh plugin catalog")
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(palette.header)

            Rectangle().fill(palette.border).frame(height: 1)

            if let error = store.pluginMarketplaceError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.destructive)
                    Text(error)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.destructive.opacity(0.08))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(palette.foregroundSubtle)
                        TextField("Search plugins...", text: $query)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.foreground)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))

                    if store.plugins.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 28))
                                .foregroundStyle(palette.foregroundMuted)
                            Text("No plugins found.")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(palette.foreground)
                            Text("Connect to your computer and refresh to load the host plugin catalog.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.foregroundSubtle)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    }

                    ForEach(store.plugins) { plugin in
                        if query.isEmpty || plugin.name.localizedCaseInsensitiveContains(query) || plugin.summary.localizedCaseInsensitiveContains(query) {
                            pluginCard(plugin)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(palette.background)
        .task {
            if !store.isUITestSeededMode, store.plugins.isEmpty {
                _ = await store.refreshPluginMarketplace()
            }
        }
    }

    private func pluginCard(_ plugin: PluginCatalogItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 16))
                .foregroundStyle(palette.accentBlue)
                .frame(width: 36, height: 36)
                .background(palette.accentBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(plugin.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text("v\(plugin.version)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.foregroundMuted)
                    if !plugin.installed {
                        Text("Available")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.surfaceHover, in: Capsule())
                    }
                }
                Text(plugin.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(plugin.marketplace)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.foregroundMuted)
            }

            Spacer()

            if busyPluginId == plugin.id {
                ProgressView().controlSize(.mini)
            } else if plugin.installed {
                Toggle(isOn: Binding(
                    get: { plugin.enabled },
                    set: { newValue in
                        busyPluginId = plugin.id
                        Task {
                            _ = await store.setMarketplacePluginEnabled(id: plugin.id, enabled: newValue)
                            busyPluginId = nil
                        }
                    }
                )) { EmptyView() }
                .labelsHidden()
            } else {
                Button {
                    busyPluginId = plugin.id
                    Task {
                        _ = await store.installMarketplacePlugin(id: plugin.id)
                        busyPluginId = nil
                    }
                } label: {
                    Text("Install")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.brandForeground)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border, lineWidth: 1))
    }
}

// MARK: - 1:1 Official ZCode Custom Vector Icons (Robot SubAgent, Git Commit Node)

public struct ZCodeRobotIconView: View {
    public var size: CGFloat = 15
    public var color: Color

    public init(size: CGFloat = 15, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = max(1.35, w * 0.10)

            // Antenna stem + tip
            var antenna = Path()
            antenna.move(to: CGPoint(x: w * 0.5, y: h * 0.08))
            antenna.addLine(to: CGPoint(x: w * 0.5, y: h * 0.27))
            context.stroke(antenna, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            let tipRect = CGRect(x: w * 0.42, y: h * 0.02, width: w * 0.16, height: w * 0.16)
            context.fill(Path(ellipseIn: tipRect), with: .color(color))

            // Rounded robot head
            let headRect = CGRect(x: w * 0.14, y: h * 0.27, width: w * 0.72, height: h * 0.58)
            let headPath = Path(roundedRect: headRect, cornerRadius: w * 0.18)
            context.stroke(headPath, with: .color(color), lineWidth: stroke)

            // Side ear ticks
            var ears = Path()
            ears.move(to: CGPoint(x: w * 0.04, y: h * 0.56))
            ears.addLine(to: CGPoint(x: w * 0.14, y: h * 0.56))
            ears.move(to: CGPoint(x: w * 0.86, y: h * 0.56))
            ears.addLine(to: CGPoint(x: w * 0.96, y: h * 0.56))
            context.stroke(ears, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            // Eyes
            let eyeR = w * 0.085
            let leftEye = CGRect(x: w * 0.34 - eyeR, y: h * 0.55 - eyeR, width: eyeR * 2, height: eyeR * 2)
            let rightEye = CGRect(x: w * 0.66 - eyeR, y: h * 0.55 - eyeR, width: eyeR * 2, height: eyeR * 2)
            context.fill(Path(ellipseIn: leftEye), with: .color(color))
            context.fill(Path(ellipseIn: rightEye), with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

public struct ZCodeCommitNodeIconView: View {
    public var size: CGFloat = 15
    public var color: Color

    public init(size: CGFloat = 15, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = max(1.35, w * 0.10)
            let r = w * 0.22

            var topLine = Path()
            topLine.move(to: CGPoint(x: w * 0.5, y: h * 0.06))
            topLine.addLine(to: CGPoint(x: w * 0.5, y: h * 0.5 - r))
            context.stroke(topLine, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            var bottomLine = Path()
            bottomLine.move(to: CGPoint(x: w * 0.5, y: h * 0.5 + r))
            bottomLine.addLine(to: CGPoint(x: w * 0.5, y: h * 0.94))
            context.stroke(bottomLine, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            let circleRect = CGRect(x: w * 0.5 - r, y: h * 0.5 - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: circleRect), with: .color(color), lineWidth: stroke)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 1:1 Official ZCode Unified Floating Task / Status Panel ("Thanh task")

public struct ZCodeUnifiedTaskStatusPanelView: View {
    @Bindable var store: AppStore
    let session: AgentTaskSession
    let totalAdded: Int
    let totalRemoved: Int
    @Environment(\.zcodePalette) private var palette

    public init(store: AppStore, session: AgentTaskSession, totalAdded: Int, totalRemoved: Int) {
        self.store = store
        self.session = session
        self.totalAdded = totalAdded
        self.totalRemoved = totalRemoved
    }

    private var completedTodoCount: Int {
        session.todos.filter { $0.status == "completed" }.count
    }

    private var visibleTodos: [TodoChecklistItem] {
        if store.hideCompletedTodosInStatusPanel {
            return session.todos.filter { $0.status != "completed" }
        }
        return session.todos
    }

    private var runningSubagentCount: Int {
        session.subagentRuns.filter(\.isRunning).count
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    gitToolsSection
                    if !session.todos.isEmpty {
                        progressSection
                    }
                    if !session.goals.isEmpty {
                        goalSection
                    }
                    if !session.subagentRuns.isEmpty {
                        agentsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 336)

            topRightControls
                .padding(.top, 10)
                .padding(.trailing, 12)
        }
        .background(store.themeMode == .light ? palette.card : Color(hex: 0x232323))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(store.themeMode == .light ? palette.border : Color(hex: 0x363636), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.42), radius: 18, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unifiedTaskStatusPanel")
    }

    private var topRightControls: some View {
        HStack(spacing: 10) {
            Menu {
                if completedTodoCount > 0 {
                    Button {
                        store.hideCompletedTodosInStatusPanel.toggle()
                    } label: {
                        Label(
                            store.hideCompletedTodosInStatusPanel ? "Show all" : "Hide \(completedTodoCount) completed",
                            systemImage: store.hideCompletedTodosInStatusPanel ? "eye" : "eye.slash"
                        )
                    }
                }
                if runningSubagentCount > 0 {
                    Button {
                        store.showTaskStatusPanel = false
                        store.openSubagentInspector(nil)
                    } label: {
                        Label("Open subagent session", systemImage: "rectangle.righthalf.inset.filled.arrow.right")
                    }
                }
                Button {
                    store.showTaskStatusPanel = false
                    store.activeInspectorTab = .gitDiff
                    store.showInspectorSheet = true
                } label: {
                    Label("Open Git Changes", systemImage: "arrow.triangle.branch")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 32, height: 32)
                    .background(
                        (store.themeMode == .light ? palette.surfaceHover : Color(hex: 0x2C2C2E)).opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(Rectangle())
                    .accessibilityLabel("Status panel options")
            }
            .accessibilityIdentifier("statusPanelMoreMenu")

            Button {
                store.playImpactHaptic(.light)
                withAnimation(.easeOut(duration: 0.16)) {
                    store.showTaskStatusPanel = false
                }
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 32, height: 32)
                    .background(
                        (store.themeMode == .light ? palette.surfaceHover : Color(hex: 0x2C2C2E)).opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse status panel")
            .accessibilityIdentifier("collapseTaskStatusPanelButton")
        }
    }

    private var gitToolsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Git tools")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.foreground)
                .padding(.trailing, 72)

            Button {
                store.showTaskStatusPanel = false
                store.activeInspectorTab = .gitDiff
                store.showInspectorSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 18)
                    Text("Changes")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.foreground)
                    Text("+\(totalAdded)")
                        .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.success)
                    Text("-\(totalRemoved)")
                        .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.destructive)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("statusPanelChangesRow")

            Menu {
                ForEach(store.gitBranches, id: \.self) { branch in
                    Button {
                        Task { await store.switchInspectorGitBranch(branch, state: InspectorLiveState()) }
                    } label: {
                        HStack {
                            Text(branch)
                            if branch == store.activeGitBranch {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 18)
                    Text(store.activeGitBranch)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("statusPanelBranchPicker")

            Button {
                store.showTaskStatusPanel = false
                store.activeInspectorTab = .gitDiff
                store.showInspectorSheet = true
            } label: {
                HStack(spacing: 10) {
                    ZCodeCommitNodeIconView(size: 16, color: palette.foregroundSubtle)
                        .frame(width: 18)
                    Text("Commit or push")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.foreground)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("statusPanelCommitRow")
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text("Progress")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Text("\(completedTodoCount)/\(session.todos.count)")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                Spacer()
            }

            ForEach(visibleTodos) { item in
                let isDone = item.status == "completed"
                let isActive = item.status == "in_progress"
                Group {
                    HStack(alignment: .top, spacing: 10) {
                        Group {
                            if isDone {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(palette.success)
                            } else if isActive {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(palette.foreground)
                            } else {
                                Image(systemName: "circle")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(palette.foregroundSubtle)
                            }
                        }
                        .frame(width: 18, height: 20)

                        Text(item.content)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(isDone ? palette.foregroundSubtle : palette.foreground)
                            .strikethrough(isDone, color: palette.foregroundSubtle)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("statusTodoRow_\(item.id)")
                }
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Goal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                if let elapsed = session.goalElapsedText {
                    Text(elapsed)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)
                    Text("·")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                Button {
                    store.toggleGoalPaused()
                } label: {
                    Image(systemName: session.goalPaused ? "play.fill" : "pause")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("goalPauseResumeButton")
                Spacer()
            }

            ForEach(session.goals) { goal in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "target")
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 18, height: 20)
                    Text(goal.title)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var agentsSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    Text("Agents")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    if runningSubagentCount > 0 {
                        let longest = session.subagentRuns.compactMap(\.startedAt).map { context.date.timeIntervalSince($0) }.max()
                        Text([longest.map(Self.compactElapsed), "\(runningSubagentCount) running"].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foregroundSubtle)
                            .monospacedDigit()
                    }
                    Spacer()
                }

                ForEach(session.subagentRuns) { run in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            store.showTaskStatusPanel = false
                            store.openSubagentSession(childSessionId: run.id, title: run.title)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                ZCodeRobotIconView(size: 16, color: palette.foregroundSubtle)
                                    .frame(width: 18, height: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(run.title)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(palette.foreground)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if let started = run.startedAt {
                                        Text(Self.runningFor(context.date.timeIntervalSince(started)))
                                            .font(.system(size: 12.5, weight: .regular))
                                            .foregroundStyle(palette.foregroundSubtle)
                                            .monospacedDigit()
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open subagent session")
                        .accessibilityIdentifier("statusSubagentRow_\(run.id)")

                        if let workId = run.controlWorkId {
                            Button {
                                store.playImpactHaptic(.light)
                                store.cancelBackgroundWork(workId: workId)
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .padding(.horizontal, 9)
                                    .frame(minHeight: 30)
                                    .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("statusSubagentStop_\(run.id)")
                        }
                    }
                }
            }
        }
    }

    /// `chat.longRunning.elapsedSeconds` / `elapsedMinutesSeconds`.
    static func runningFor(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return total < 60 ? "Running for \(total)s" : "Running for \(total / 60)m \(total % 60)s"
    }

    static func compactElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return total < 60 ? "\(total)s" : "\(total / 60)m \(total % 60)s"
    }
}

// MARK: - Subagent pane: read-only child conversation (desktop `wIn` side pane)

public struct ZCodeSubagentSlideOverDrawerView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(palette.border)
                .frame(height: 1)
            content
        }
        .background(palette.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subagentSlideOverDrawer")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                store.popSubagentSession()
            } label: {
                Image(systemName: store.subagentPaneBackStack.isEmpty ? "xmark" : "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.subagentPaneBackStack.isEmpty ? "Close" : "Back")
            .accessibilityIdentifier("subagentPaneBackButton")

            ZCodeRobotIconView(size: 15, color: palette.foregroundSubtle)
            Text(store.subagentPane?.title ?? "Subagent")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
            if store.subagentPane?.status == .running {
                ProgressView()
                    .controlSize(.mini)
                    .tint(palette.foregroundSubtle)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
        .background(palette.header)
    }

    @ViewBuilder
    private var content: some View {
        if let pane = store.subagentPane {
            if let error = pane.errorText, pane.messages.isEmpty {
                placeholder(icon: "exclamationmark.triangle", text: error)
            } else if pane.isLoading && pane.messages.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pane.messages.isEmpty {
                placeholder(icon: "text.bubble", text: "No messages yet")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(pane.messages) { message in
                                ChatTurnCardView(store: store, message: message, readOnly: true)
                                    .id(message.id)
                            }
                            if let notice = pane.statusNotice, !notice.isEmpty {
                                Text(notice)
                                    .font(.system(size: 13))
                                    .foregroundStyle(pane.status == .error ? palette.destructive : palette.foregroundSubtle)
                            }
                            Color.clear.frame(height: 8).id("subagent-bottom")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }
                    .onAppear { proxy.scrollTo("subagent-bottom", anchor: .bottom) }
                    .onChange(of: pane.messages.count) { _, _ in
                        proxy.scrollTo("subagent-bottom", anchor: .bottom)
                    }
                }
            }
        } else {
            placeholder(icon: "person.2", text: "No subagent selected")
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(palette.foregroundMuted)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(palette.foregroundSubtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
