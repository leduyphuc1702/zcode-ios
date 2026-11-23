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
    @State private var listLimits: [String: Int] = [:]
    @State private var pinnedExpanded: Bool = false

    public init(store: AppStore, isEmbeddedColumn: Bool) {
        self.store = store
        self.isEmbeddedColumn = isEmbeddedColumn
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
        .alert("New project", isPresented: $showAddProjectAlert) {
            TextField("Folder path on your computer", text: $newProjectPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Project name (optional)", text: $newProjectName)
            Button("Cancel", role: .cancel) {
                newProjectName = ""
                newProjectPath = ""
            }
            Button("Create") {
                store.createNewProject(name: newProjectName, rootPath: newProjectPath)
                newProjectName = ""
                newProjectPath = ""
            }
        } message: {
            Text("Enter the absolute path of a folder on your computer, e.g. /Users/you/code/my-app")
        }
    }

    // MARK: - Data (project tree, with an open-workspace fallback when the host has no tree)

    private var treeMode: Bool { store.sidebarTreeLoaded }

    private var fallbackVisible: [AgentTaskSession] {
        store.sessions.filter { !$0.archived }
    }

    private func matchesSearch(_ task: AgentTaskSession) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return task.displayTitle.localizedCaseInsensitiveContains(q) ||
            task.workspacePath.localizedCaseInsensitiveContains(q)
    }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pinnedTasks: [AgentTaskSession] {
        let base = treeMode ? store.sidebarPinnedTasks() : AppStore.sortedForSidebar(fallbackVisible.filter(\.pinned))
        return base.filter(matchesSearch)
    }

    private var sectionProjects: [SidebarProject] {
        if treeMode { return store.sidebarProjects }
        return store.projects.map { SidebarProject(id: $0.id, name: $0.name, pinned: false, roots: [$0.rootPath]) }
    }

    private func projectTasks(_ project: SidebarProject) -> [AgentTaskSession] {
        let base = treeMode
            ? store.sidebarTasks(inProject: project.id)
            : AppStore.sortedForSidebar(fallbackVisible.filter { !$0.pinned && $0.projectId == project.id })
        return base.filter(matchesSearch)
    }

    private var projectlessTasks: [AgentTaskSession] {
        treeMode ? store.sidebarProjectlessTasks().filter(matchesSearch) : []
    }

    private var timelineTasks: [AgentTaskSession] {
        let base = treeMode ? store.sidebarTimelineTasks() : AppStore.sortedForTimeline(fallbackVisible)
        return base.filter(matchesSearch)
    }

    private var archivedTasks: [AgentTaskSession] {
        store.sidebarArchivedTasks().filter(matchesSearch)
    }

    private var groupNodes: [SidebarGroupNode] {
        let nodes = treeMode
            ? store.sidebarGroupNodes()
            : AppStore.sortedForTimeline(fallbackVisible.filter { !$0.pinned }).map { SidebarGroupNode.task($0) }
        guard isSearching else { return nodes }
        return nodes.compactMap { node in
            switch node {
            case .task(let task):
                return matchesSearch(task) ? node : nil
            case .group(let group, let tasks):
                let filtered = tasks.filter(matchesSearch)
                return filtered.isEmpty ? nil : .group(group, tasks: filtered)
            }
        }
    }

    private func isProjectExpanded(_ id: String) -> Bool {
        if isSearching { return true }
        return treeMode ? !store.collapsedSidebarProjectIds.contains(id) : store.expandedProjectIds.contains(id)
    }

    private func toggleProject(_ id: String) {
        if treeMode {
            if store.collapsedSidebarProjectIds.contains(id) {
                store.collapsedSidebarProjectIds.remove(id)
            } else {
                store.collapsedSidebarProjectIds.insert(id)
            }
        } else {
            store.toggleProjectExpanded(id)
        }
    }

    private var allProjectsExpanded: Bool {
        treeMode
            ? store.collapsedSidebarProjectIds.isEmpty
            : store.expandedProjectIds.count == store.projects.count
    }

    private func toggleAllProjects() {
        if treeMode {
            store.collapsedSidebarProjectIds = allProjectsExpanded ? Set(store.sidebarProjects.map(\.id)) : []
        } else {
            store.toggleAllProjectsExpanded()
        }
    }

    private func openWorkspace(for project: SidebarProject) -> WorkspaceProject? {
        store.projects.first { $0.id == project.id || (!project.rootPath.isEmpty && $0.rootPath == project.rootPath) }
    }

    private func newTask(in project: SidebarProject?) {
        if treeMode {
            store.createNewTask(treeProjectId: project?.id)
        } else {
            store.createNewSession(inProjectId: project.flatMap { openWorkspace(for: $0)?.id })
        }
        store.mobilePage = .chat
    }

    // MARK: - Primary navigation

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
                newTask(in: nil)
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

    // MARK: - Task list toolbar

    private var taskListToolbarSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(showArchivedOnly ? "Archived" : "Task list")
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
                    Picker("Filter view", selection: Binding(
                        get: { store.taskListViewMode },
                        set: { mode in
                            store.taskListViewMode = mode
                            showArchivedOnly = false
                        }
                    )) {
                        ForEach(TaskListViewMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Toggle(isOn: $showArchivedOnly) {
                        Label("Archived", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(showArchivedOnly ? palette.accentBlue : palette.foregroundSubtle)
                        .frame(width: 40, height: 38)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Filter view")
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
                    TextField("Search tasks", text: $searchQuery)
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
                    archivedSection
                } else {
                    switch store.taskListViewMode {
                    case .byProject:
                        pinnedSection
                        pinnedProjectsSection
                        projectsSection
                        if treeMode { tasksSection }
                    case .grouped:
                        pinnedSection
                        groupedSection
                    case .timeline:
                        timelineSection
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .refreshable {
            await store.refreshWorkspaceAndSessions()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var pinnedSection: some View {
        let tasks = pinnedTasks
        if !tasks.isEmpty {
            sectionHeading("Pinned")
            let visible = pinnedExpanded ? tasks : Array(tasks.prefix(20))
            ForEach(visible) { session in
                taskItemRow(session: session)
            }
            if tasks.count > 20 {
                showMoreButton(pinnedExpanded ? "Show less" : "Show more") {
                    pinnedExpanded.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private var pinnedProjectsSection: some View {
        let pinned = sectionProjects.filter(\.pinned)
        if !pinned.isEmpty {
            ForEach(pinned) { project in
                projectGroupSection(project)
            }
        }
    }

    @ViewBuilder
    private var projectsSection: some View {
        purposeSectionHeader(
            title: "Projects",
            expanded: store.projectsSectionExpanded,
            toggle: { store.projectsSectionExpanded.toggle() }
        ) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { toggleAllProjects() }
            } label: {
                Image(systemName: allProjectsExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 32, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(allProjectsExpanded ? "Collapse all projects" : "Expand all projects")
            .accessibilityIdentifier("toggleExpandAllProjectsButton")

            Button {
                showAddProjectAlert = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 32, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New project")
            .accessibilityIdentifier("addWorkspaceProjectButton")
        }

        if store.projectsSectionExpanded {
            ForEach(sectionProjects.filter { !$0.pinned }) { project in
                projectGroupSection(project)
            }
        }
    }

    @ViewBuilder
    private var tasksSection: some View {
        purposeSectionHeader(
            title: "Tasks",
            expanded: store.tasksSectionExpanded,
            toggle: { store.tasksSectionExpanded.toggle() }
        ) {
            Button {
                newTask(in: nil)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 32, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New task")
            .accessibilityIdentifier("newConversationTaskButton")
        }

        if store.tasksSectionExpanded {
            limitedTaskList(projectlessTasks, key: "tasks", step: 5, indent: false)
        }
    }

    @ViewBuilder
    private var groupedSection: some View {
        let nodes = groupNodes
        if nodes.isEmpty && pinnedTasks.isEmpty {
            emptyState("No tasks yet")
        }
        ForEach(nodes) { node in
            switch node {
            case .task(let task):
                taskItemRow(session: task)
            case .group(let group, let tasks):
                taskGroupSection(group, tasks: tasks)
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        let tasks = timelineTasks
        if tasks.isEmpty {
            emptyState("No tasks yet")
        } else {
            let limit = listLimits["timeline"] ?? 20
            let visible = Array(tasks.prefix(limit))
            let now = Date()
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, session in
                let bucket = Self.timelineBucket(session.updatedAt, now: now)
                if index == 0 || Self.timelineBucket(visible[index - 1].updatedAt, now: now) != bucket {
                    sectionHeading(bucket)
                }
                taskItemRow(session: session, showsWorkspaceLabel: true)
            }
            if tasks.count > limit {
                showMoreButton("Show more") { listLimits["timeline"] = limit + 20 }
            }
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        let tasks = archivedTasks
        if tasks.isEmpty {
            emptyState("No archived tasks")
        } else {
            ForEach(tasks) { session in
                taskItemRow(session: session, showsWorkspaceLabel: true)
            }
        }
    }

    // MARK: - Section building blocks

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(palette.foregroundMuted)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func purposeSectionHeader<Actions: View>(
        title: String,
        expanded: Bool,
        toggle: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(palette.foregroundMuted)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.foregroundMuted)
                    Spacer(minLength: 0)
                }
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            actions()
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.top, 12)
    }

    private func showMoreButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(palette.foregroundMuted)
                .padding(.leading, 44)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(palette.foregroundMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    @ViewBuilder
    private func limitedTaskList(_ tasks: [AgentTaskSession], key: String, step: Int, indent: Bool) -> some View {
        if tasks.isEmpty {
            Text("No tasks yet")
                .font(.system(size: 13.5))
                .foregroundStyle(palette.foregroundMuted)
                .padding(.leading, indent ? 44 : 36)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .accessibilityIdentifier("project-no-tasks")
        } else {
            let limit = isSearching ? tasks.count : (listLimits[key] ?? step)
            ForEach(tasks.prefix(limit)) { session in
                taskItemRow(session: session)
            }
            if tasks.count > limit {
                showMoreButton("Show more") { listLimits[key] = limit + step }
            }
        }
    }

    // MARK: - Project row

    private func projectGroupSection(_ project: SidebarProject) -> some View {
        let isExpanded = isProjectExpanded(project.id)
        let workspace = openWorkspace(for: project)
        let showsUnread = !isExpanded && (treeMode ? store.sidebarProjectHasUnread(project) : false)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { toggleProject(project.id) }
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
                            .truncationMode(.tail)

                        if showsUnread {
                            Circle()
                                .fill(palette.accentBlue)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel("Project has unread tasks")
                        }

                        Spacer(minLength: 4)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        newTask(in: project)
                    } label: {
                        Label("New task", systemImage: "plus.bubble")
                    }
                    if let workspace {
                        Button {
                            store.activeProjectId = workspace.id
                            store.activeInspectorTab = .files
                            store.mobilePage = .chat
                            store.showInspectorSheet = true
                        } label: {
                            Label("Show file tree", systemImage: "list.bullet.indent")
                        }
                    }
                    if !project.rootPath.isEmpty {
                        Button {
                            UIPasteboard.general.string = project.rootPath
                        } label: {
                            Label("Copy path", systemImage: "doc.on.doc")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: 32, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")

                Button {
                    newTask(in: project)
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: 32, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New task")
                .accessibilityIdentifier("newProjectTask_\(project.id)")
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .frame(height: 38)

            if isExpanded {
                limitedTaskList(projectTasks(project), key: "project:\(project.id)", step: 5, indent: true)
            }
        }
    }

    // MARK: - Task group (By group view)

    private func taskGroupSection(_ group: TaskGroupsStructure.Group, tasks: [AgentTaskSession]) -> some View {
        let collapsed = store.collapsedTaskGroupIds.contains(group.id) && !isSearching

        return VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if store.collapsedTaskGroupIds.contains(group.id) {
                        store.collapsedTaskGroupIds.remove(group.id)
                    } else {
                        store.collapsedTaskGroupIds.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: 14)
                    Circle()
                        .fill(groupColor(group.color))
                        .frame(width: 8, height: 8)
                    Text(AppStore.groupDisplayTitle(group))
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                    Text("\(tasks.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Capsule().fill(palette.card))
                    Spacer(minLength: 4)
                }
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                if tasks.isEmpty {
                    Text("Drag tasks into this group")
                        .font(.system(size: 13.5))
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.leading, 44)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                } else {
                    ForEach(tasks) { session in
                        taskItemRow(session: session)
                    }
                }
            }
        }
    }

    private func groupColor(_ name: String?) -> Color {
        switch name?.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal", "cyan": return .teal
        case "blue": return .blue
        case "purple", "violet": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        default: return palette.foregroundMuted
        }
    }

    // MARK: - Task row

    private func taskItemRow(session: AgentTaskSession, showsWorkspaceLabel: Bool = false) -> some View {
        let isSelected = session.id == store.activeSessionId

        return Button {
            store.selectSession(session)
        } label: {
            HStack(alignment: showsWorkspaceLabel ? .top : .center, spacing: 10) {
                statusSlot(session: session)
                    .frame(width: 16, height: showsWorkspaceLabel ? 20 : 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(session.displayTitle)
                            .font(.system(size: 14.5, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        taskMetadata(session: session)
                    }
                    if showsWorkspaceLabel {
                        Text(store.sidebarWorkspaceLabel(for: session))
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.foregroundMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, showsWorkspaceLabel ? 7 : 0)
            .frame(minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? palette.card : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("sessionRow_\(session.id)")
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
            if !session.unread && !session.archived {
                Button {
                    store.markSessionUnread(session.id)
                } label: {
                    Label("Mark as unread", systemImage: "circle.inset.filled")
                }
            }
            if !session.workspacePath.isEmpty {
                Divider()
                Button {
                    UIPasteboard.general.string = session.workspacePath
                } label: {
                    Label("Copy path", systemImage: "doc.on.doc")
                }
            }
            if session.archived {
                Divider()
                Button(role: .destructive) {
                    store.deleteSession(session.id)
                } label: {
                    Label("Delete task", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func statusSlot(session: AgentTaskSession) -> some View {
        switch session.sidebarIndicator {
        case .error:
            if differentiateWithoutColor {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.destructive)
            } else {
                Circle().fill(palette.destructive).frame(width: 6, height: 6)
            }
        case .unread:
            if differentiateWithoutColor {
                Image(systemName: "circle.inset.filled")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.accentBlue)
            } else {
                Circle().fill(palette.accentBlue).frame(width: 7, height: 7)
            }
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .tint(palette.foregroundSubtle)
        case .none:
            if session.pinned {
                Image(systemName: "pin")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(palette.foregroundMuted)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func taskMetadata(session: AgentTaskSession) -> some View {
        HStack(spacing: 6) {
            if let tag = session.pendingTagText {
                Text(tag)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.success)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(palette.success.opacity(0.14)))
                    .fixedSize()
            }
            if session.changeFileCount > 0 || session.changeAdded > 0 || session.changeRemoved > 0 {
                HStack(spacing: 3) {
                    Text("+\(session.changeAdded)").foregroundStyle(palette.success)
                    Text("-\(session.changeRemoved)").foregroundStyle(palette.destructive)
                }
                .font(.system(size: 12.5, weight: .regular).monospacedDigit())
                .fixedSize()
            }
            if session.cronAutomationId != nil {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.foregroundMuted)
                    .accessibilityLabel("Scheduled task")
            }
            if session.offPeakTaskId != nil {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.foregroundMuted)
                    .accessibilityLabel("Idle-time task")
            }
            Text(Self.relativeAge(from: session.updatedAt))
                .font(.system(size: 13, weight: .regular).monospacedDigit())
                .foregroundStyle(palette.foregroundMuted)
                .fixedSize()
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

                    Text(store.userDisplayName.isEmpty ? "Not signed in" : store.userDisplayName)
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

    // MARK: - Formatting

    /// `wA`: now / {m}m / {h}h / {d}d from `updatedAt`.
    static func relativeAge(from date: Date, now: Date = Date()) -> String {
        let minutes = Int(floor(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    /// `Fyt` date buckets for the Recently updated view (en-US: weeks start on Sunday).
    static func timelineBucket(_ date: Date, now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let startOfToday = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days <= 3 { return "\(days) days ago" }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            if date >= week.start { return "This week" }
            if let lastWeek = calendar.date(byAdding: .day, value: -7, to: week.start), date >= lastWeek { return "Last week" }
        }
        if let month = calendar.dateInterval(of: .month, for: now) {
            if date >= month.start { return "This month" }
            if let lastMonth = calendar.date(byAdding: .month, value: -1, to: month.start), date >= lastMonth { return "Last month" }
        }
        return "Older"
    }
}
