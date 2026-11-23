import SwiftUI

public struct WorkspaceSidebarView: View {
    @Bindable var store: AppStore
    let isEmbeddedColumn: Bool
    @Environment(\.zcodePalette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    @State private var showInlineSearch: Bool = false
    @State private var searchQuery: String = ""
    @State private var showArchivedOnly: Bool = false
    @State private var renamingSession: AgentTaskSession?
    @State private var renameText: String = ""
    @State private var showAddProjectAlert: Bool = false
    @State private var newProjectName: String = ""
    @State private var newProjectPath: String = ""

    public init(store: AppStore, isEmbeddedColumn: Bool) {
        self.store = store
        self.isEmbeddedColumn = isEmbeddedColumn
    }

    private var visibleSessions: [AgentTaskSession] {
        let base = store.sessions.filter { $0.archived == showArchivedOnly }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.workspacePath.localizedCaseInsensitiveContains(q)
        }
    }

    private var pinnedSessions: [AgentTaskSession] {
        visibleSessions
            .filter(\.pinned)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var timelineSessions: [AgentTaskSession] {
        visibleSessions
            .filter { !$0.pinned }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public var body: some View {
        VStack(spacing: 0) {
            topGlobalNavSection

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            taskListToolbarSection

            scrollableTaskListSection

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            bottomProfileFooter
        }
        .background(palette.sidebar)
        .alert("Rename task", isPresented: Binding(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )) {
            TextField("Task name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingSession = nil }
            Button("Save") {
                if let s = renamingSession {
                    store.renameSession(s.id, newTitle: renameText)
                }
                renamingSession = nil
            }
        }
        .alert("Open folder / Add workspace", isPresented: $showAddProjectAlert) {
            TextField("Folder name (e.g. zcode-ios-sdk)", text: $newProjectName)
            TextField("Workspace path (optional)", text: $newProjectPath)
            Button("Cancel", role: .cancel) {
                newProjectName = ""
                newProjectPath = ""
            }
            Button("Add") {
                store.createNewProject(name: newProjectName, rootPath: newProjectPath)
                newProjectName = ""
                newProjectPath = ""
            }
        }
    }

    private var topGlobalNavSection: some View {
        VStack(spacing: 2) {
            hostSelectorRow

            topNavActionRow(
                icon: "plus.bubble",
                title: L10n.text("New task", vi: "Tác vụ mới", zh: "新任务", lang: store.language),
                shortcut: "⌘ N",
                isSelected: false,
                accessibilityId: "newSessionButton"
            ) {
                store.createNewSession()
            }

            topNavActionRow(
                icon: "calendar.badge.clock",
                title: L10n.text("Automations", vi: "Tự động hóa", zh: "自动化", lang: store.language),
                shortcut: nil,
                isSelected: store.mobilePage == .automations && isEmbeddedColumn,
                accessibilityId: "openAutomationsRowButton"
            ) {
                store.mobilePage = .automations
            }

            topNavActionRow(
                icon: "square.grid.2x2",
                title: L10n.text("Plugin Marketplace", vi: "Kho Plugin", zh: "插件市场", lang: store.language),
                shortcut: nil,
                isSelected: store.mobilePage == .pluginMarketplace && isEmbeddedColumn,
                accessibilityId: "openPluginMarketplaceRowButton"
            ) {
                store.mobilePage = .pluginMarketplace
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var taskListToolbarSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                let headerTitle = showArchivedOnly
                    ? L10n.text("Archived tasks", vi: "Đã lưu trữ", zh: "已归档任务", lang: store.language)
                    : L10n.text("Task list", vi: "Danh sách tác vụ", zh: "任务列表", lang: store.language)
                Text(headerTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showInlineSearch.toggle()
                        if !showInlineSearch { searchQuery = "" }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(showInlineSearch ? palette.foreground : palette.foregroundSubtle)
                        .frame(width: 40, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search tasks")
                .accessibilityIdentifier("taskListSearchButton")

                Menu {
                    Picker("View Mode", selection: $store.taskListViewMode) {
                        ForEach(TaskListViewMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }

                    Divider()

                    Button {
                        showArchivedOnly.toggle()
                    } label: {
                        Label(
                            showArchivedOnly ? "Show Active Tasks" : "Show Archived Tasks",
                            systemImage: showArchivedOnly ? "tray.full" : "archivebox"
                        )
                    }

                    Button {
                        store.showCommandCenter = true
                    } label: {
                        Label("Command Center (⌘K)", systemImage: "command")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(showArchivedOnly ? palette.accentBlue : palette.foregroundSubtle)
                        .frame(width: 40, height: 38)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Task list view options")
                .accessibilityIdentifier("taskListViewMenuButton")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if showInlineSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                    TextField("Search tasks or workspaces...", text: $searchQuery)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.foreground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(palette.foregroundSubtle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.border, lineWidth: 1))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
    }

    private var scrollableTaskListSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if showArchivedOnly {
                    ForEach(visibleSessions) { session in
                        taskItemRow(session: session, isPinnedRow: false)
                    }
                } else {
                    if !pinnedSessions.isEmpty {
                        Text(L10n.text("Pinned", vi: "Đã ghim", zh: "已置顶", lang: store.language))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.horizontal, 18)
                            .padding(.top, 6)
                            .padding(.bottom, 4)

                        ForEach(pinnedSessions) { session in
                            taskItemRow(session: session, isPinnedRow: true)
                        }
                    }

                    if store.taskListViewMode == .timeline {
                        Text(L10n.text("Recently updated", vi: "Cập nhật gần đây", zh: "最近更新", lang: store.language))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                            .padding(.bottom, 4)

                        ForEach(timelineSessions) { session in
                            taskItemRow(session: session, isPinnedRow: false)
                        }
                    } else {
                        projectsSectionHeader

                        if store.projectsSectionExpanded {
                            ForEach(store.projects) { project in
                                projectGroupSection(project)
                            }
                        }
                    }
                }

                if visibleSessions.isEmpty {
                    Text(showArchivedOnly ? "No archived tasks" : "No tasks yet")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(.bottom, 16)
        }
        .refreshable {
            await store.refreshWorkspaceAndSessions()
        }
    }

    // MARK: - Top Host Switcher Row

    private var hostSelectorRow: some View {
        Menu {
            Section("Connected & Saved Devices") {
                ForEach(store.connections) { conn in
                    Button {
                        Task { await store.connectToWorkstation(conn.id) }
                    } label: {
                        let statusLabel = conn.state == .connected ? "Online" : "Offline"
                        Label("\(conn.name) (\(statusLabel))", systemImage: conn.transport == .cloudRelayV2 ? "icloud" : "apple.logo")
                    }
                }
            }

            Divider()

            Button {
                store.openConnectionHub()
            } label: {
                Label("Z.AI Account & Remote Link…", systemImage: "link.icloud")
            }

            Button {
                store.showConnectionsSheet = true
            } label: {
                Label("Manage Devices & Scan QR Code…", systemImage: "qrcode.viewfinder")
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: store.activeConnection?.transport == .cloudRelayV2 ? "icloud.fill" : "desktopcomputer")
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(store.activeConnection?.state == .connected ? palette.success : palette.foregroundSubtle)
                    .frame(width: 22)

                Text(store.activeConnection?.name ?? "Connect ZCode Remote")
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch remote workstation")
        .accessibilityIdentifier("sidebarConnectionsButton")
    }

    private func topNavActionRow(
        icon: String,
        title: String,
        shortcut: String?,
        isSelected: Bool,
        accessibilityId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isSelected ? palette.foreground : palette.foregroundSubtle)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(palette.foregroundMuted)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? palette.card : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }

    // MARK: - Projects Header & Collapsible Folder Groups

    private var projectsSectionHeader: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    store.projectsSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Text(L10n.text("Projects", vi: "Dự án", zh: "项目", lang: store.language))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(palette.foregroundMuted)
                    Image(systemName: store.projectsSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.foregroundMuted)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    store.toggleAllProjectsExpanded()
                }
            } label: {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggleExpandAllProjectsButton")

            Button {
                showAddProjectAlert = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addWorkspaceProjectButton")
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private func projectGroupSection(_ project: WorkspaceProject) -> some View {
        let isExpanded = store.expandedProjectIds.contains(project.id)
        let projectTasks = visibleSessions
            .filter { $0.projectId == project.id && (store.taskListViewMode == .grouped || !$0.pinned) }
            .sorted { $0.updatedAt > $1.updatedAt }

        return VStack(alignment: .leading, spacing: 2) {
            // Project Folder Row
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        store.toggleProjectExpanded(project.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "folder" : "folder.fill")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 18)

                        Text(project.name)
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(palette.foregroundSubtle)
                            .lineLimit(1)

                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        store.activeProjectId = project.id
                        store.activeInspectorTab = .files
                        store.mobilePage = .chat
                        store.showInspectorSheet = true
                    } label: {
                        Label("Browse Workspace Files", systemImage: "folder")
                    }
                    Button {
                        store.activeProjectId = project.id
                        store.activeInspectorTab = .gitDiff
                        store.mobilePage = .chat
                        store.showInspectorSheet = true
                    } label: {
                        Label("Review Git Changes (\(project.gitBranch))", systemImage: "arrow.triangle.branch")
                    }
                    Button {
                        store.createNewSession(inProjectId: project.id)
                    } label: {
                        Label("New Task in \(project.name)", systemImage: "plus.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: 26, height: 30)
                }

                Button {
                    store.activeProjectId = project.id
                    store.activeInspectorTab = .files
                    store.mobilePage = .chat
                    store.showInspectorSheet = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 13.5))
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: 26, height: 30)
                }
                .buttonStyle(.plain)

                Button {
                    store.createNewSession(inProjectId: project.id)
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: 28, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newProjectTask_\(project.id)")
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .frame(height: 36)

            if isExpanded {
                ForEach(projectTasks) { session in
                    taskItemRow(session: session, isPinnedRow: false)
                }
            }
        }
    }

    // MARK: - Individual Task Row (Pinned & Project Tasks)

    private func taskItemRow(session: AgentTaskSession, isPinnedRow: Bool) -> some View {
        let isSelected = session.id == store.activeSessionId && store.mobilePage == .chat
        let isCurrentSessionOnHome = session.id == store.activeSessionId && !isPinnedRow

        return HStack(spacing: 8) {
            Button {
                store.selectSession(session)
            } label: {
                HStack(spacing: 10) {
                    leadingTaskMarker(session: session, isPinnedRow: isPinnedRow)
                        .frame(width: 18, alignment: .center)

                    Text(session.title)
                        .font(.system(size: 14.5, weight: (isSelected || isCurrentSessionOnHome) ? .medium : .regular))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Text(relativeAgeString(from: session.updatedAt))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(palette.foregroundMuted)
                        .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sessionRow_\(session.id)")

            if isPinnedRow {
                Button {
                    store.selectSession(session)
                    store.activeInspectorTab = .files
                    store.showInspectorSheet = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: 24, height: 32)
                }
                .buttonStyle(.plain)
            }

            Button {
                if session.archived {
                    store.restoreSession(session.id)
                } else {
                    store.archiveSession(session.id)
                }
            } label: {
                Image(systemName: session.archived ? "tray.and.arrow.up" : "archivebox")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundMuted)
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.archived ? "Restore task" : "Archive task")
            .accessibilityIdentifier("archiveTask_\(session.id)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((isSelected || isCurrentSessionOnHome) ? palette.card : Color.clear)
        )
        .padding(.horizontal, 8)
        .contextMenu {
            Button {
                store.togglePinSession(session.id)
            } label: {
                Label(session.pinned ? "Unpin task" : "Pin task", systemImage: session.pinned ? "pin.slash" : "pin")
            }
            Button {
                renameText = session.title
                renamingSession = session
            } label: {
                Label("Rename task", systemImage: "pencil")
            }
            Button {
                store.forkSession(session.id)
            } label: {
                Label("Fork session", systemImage: "arrow.triangle.branch")
            }
            if session.archived {
                Button {
                    store.restoreSession(session.id)
                } label: {
                    Label("Unarchive task", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    store.archiveSession(session.id)
                } label: {
                    Label("Archive task", systemImage: "archivebox")
                }
            }
            Divider()
            Button(role: .destructive) {
                store.deleteSession(session.id)
            } label: {
                Label("Delete session", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func leadingTaskMarker(session: AgentTaskSession, isPinnedRow: Bool) -> some View {
        if session.status == .running {
            if differentiateWithoutColor {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.94, green: 0.34, blue: 0.33))
            } else {
                Circle()
                    .fill(Color(red: 0.94, green: 0.34, blue: 0.33))
                    .frame(width: 8, height: 8)
            }
        } else if session.pendingPermission != nil || session.pendingQuestion != nil || session.pendingPlan != nil {
            if differentiateWithoutColor {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.warning)
            } else {
                Circle()
                    .fill(palette.warning)
                    .frame(width: 8, height: 8)
            }
        } else if isPinnedRow {
            Image(systemName: "pin")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(palette.foregroundMuted)
        } else if session.unread {
            if differentiateWithoutColor {
                Image(systemName: "circle.inset.filled")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(red: 0.31, green: 0.61, blue: 1.0))
            } else {
                Circle()
                    .fill(Color(red: 0.31, green: 0.61, blue: 1.0))
                    .frame(width: 8, height: 8)
            }
        } else {
            Color.clear
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Bottom User Profile & Settings Footer

    private var bottomProfileFooter: some View {
        HStack(spacing: 11) {
            Button {
                store.showConnectionsSheet = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.16, green: 0.42, blue: 0.88), Color(red: 0.56, green: 0.22, blue: 0.72)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 30, height: 30)

                        Image("ZCodeLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())
                    }

                    Text(store.userDisplayName)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                store.showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("sidebarSettingsButton")
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(palette.sidebar)
    }

    private func relativeAgeString(from date: Date) -> String {
        let seconds = max(1, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
