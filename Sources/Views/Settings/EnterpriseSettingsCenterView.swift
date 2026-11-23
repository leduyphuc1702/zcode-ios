import SwiftUI

// MARK: - Exact ZCode v3.16.3 Settings Navigation Tree (3 Official Groups, 16 Official Sections)

public enum SettingsGroupKind: String, CaseIterable, Identifiable {
    case basics
    case agentCapabilities
    case dataAndStats

    public var id: String { rawValue }

    /// Exact `settings.sidebar.group.*` strings from ZCode v3.16.3 `IntlProvider`
    public var title: String {
        switch self {
        case .basics: return "Basics"
        case .agentCapabilities: return "Agent capabilities"
        case .dataAndStats: return "Data and statistics"
        }
    }

    public var sections: [SettingsSectionKind] {
        SettingsSectionKind.allCases.filter { $0.group == self }
    }
}

public enum SettingsSectionKind: String, CaseIterable, Identifiable, Hashable {
    // Group 1: Basics
    case general = "general"
    case appearance = "appearance"
    case modelProvider = "modelProvider"
    case browser = "browser"
    case remoteDevices = "remoteDevices"
    case computerUse = "computerUse"
    case shortcuts = "shortcuts"

    // Group 2: Agent capabilities
    case memory = "memory"
    case subagents = "subagents"
    case plugin = "plugin"
    case mcp = "mcp"
    case skill = "skill"
    case commands = "commands"
    case hooks = "hooks"

    // Group 3: Data and statistics
    case usage = "usage"
    case archives = "archives"

    public var id: String { rawValue }

    public var group: SettingsGroupKind {
        switch self {
        case .general, .appearance, .modelProvider, .browser, .remoteDevices, .computerUse, .shortcuts:
            return .basics
        case .memory, .subagents, .plugin, .mcp, .skill, .commands, .hooks:
            return .agentCapabilities
        case .usage, .archives:
            return .dataAndStats
        }
    }

    /// Exact ZCode v3.16.3 Sidebar Navigation Title (`settings.nav.*`)
    public var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .modelProvider: return "Model settings"
        case .browser: return "Browser Use"
        case .remoteDevices: return "Remote devices"
        case .computerUse: return "Computer Use"
        case .shortcuts: return "Keyboard Shortcuts"
        case .memory: return "Memory"
        case .subagents: return "Subagents"
        case .plugin: return "Plugins"
        case .mcp: return "MCP Servers"
        case .skill: return "Skills"
        case .commands: return "Commands"
        case .hooks: return "Hooks"
        case .usage: return "Usage stats"
        case .archives: return "Archive management"
        }
    }

    /// Exact ZCode v3.16.3 Sidebar Subtitle (`settings.nav.*`)
    public var navSubtitle: String {
        switch self {
        case .general: return "Language and current window experience"
        case .appearance: return "Theme, UI font size, and code presentation"
        case .modelProvider: return "Configure custom model providers"
        case .browser: return "Configure integrated browser behavior and permissions"
        case .remoteDevices: return "Manage SSH, WSL, and Docker connections"
        case .computerUse: return "Manage screen access and desktop automation permissions"
        case .shortcuts: return "View and customize global and composer shortcuts"
        case .memory: return "Enable or disable agent long-term memory and view memory files"
        case .subagents: return "Manage custom and plugin subagents"
        case .plugin: return "Enable or disable installed plugins"
        case .mcp: return "Manage MCP server configurations"
        case .skill: return "Manage workspace and user skills"
        case .commands: return "Manage custom slash commands"
        case .hooks: return "Manage task lifecycle hooks"
        case .usage: return "Local session token, streak, and model summaries"
        case .archives: return "Review and delete archived sessions across projects"
        }
    }

    /// Exact ZCode v3.16.3 Page Header Description (`settings.<section>.description`)
    public var headerDescription: String {
        switch self {
        case .general:
            return "Language, window, and desktop startup behavior."
        case .appearance:
            return "Customize how the interface, font size, and code diffs appear."
        case .modelProvider:
            return "Manage custom model providers. Once configured, they can be selected during chat."
        case .browser:
            return "Manage embedded browser rendering, permissions, and certificate policies."
        case .remoteDevices:
            return "Manage your ZCode Remote workstations, SSH servers, WSL distributions, and Docker containers."
        case .computerUse:
            return "Check macOS screen and Accessibility permissions and adjust Computer Use entry visibility."
        case .shortcuts:
            return "Tap any shortcut to customize the key combination for iPad Magic Keyboard and remote desktop."
        case .memory:
            return "Save and reuse long-term context in workspaces. Applies to new sessions."
        case .subagents:
            return "Manage user-level, workspace, and plugin subagent Markdown files consumed by ZCode Agent."
        case .plugin:
            return "Enable or disable installed plugins. Plugins bundle skills, commands, hooks, and MCP servers."
        case .mcp:
            return "Manage MCP server configurations used by ZCode Agent."
        case .skill:
            return "Manage workspace and user skills. Enabled skills can be referenced in chat with $skill-name."
        case .commands:
            return "Manage ZCode Agent .md command files. Commands can be invoked with /command-name in chat."
        case .hooks:
            return "Manage task lifecycle hooks to automatically execute commands on specific events."
        case .usage:
            return "Review activity, Coding Plan quotas, and model usage aggregated from sessions."
        case .archives:
            return "Review, restore, or permanently delete archived sessions."
        }
    }

    public var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintbrush"
        case .modelProvider: return "cpu"
        case .browser: return "globe"
        case .remoteDevices: return "laptopcomputer.and.iphone"
        case .computerUse: return "cursorarrow.click.2"
        case .shortcuts: return "keyboard"
        case .memory: return "brain.head.profile"
        case .subagents: return "person.2.badge.gearshape"
        case .plugin: return "puzzlepiece.extension"
        case .mcp: return "point.3.filled.connected.trianglepath.dotted"
        case .skill: return "sparkles.rectangle.stack"
        case .commands: return "slash.circle"
        case .hooks: return "bolt.horizontal.circle"
        case .usage: return "chart.bar.xaxis"
        case .archives: return "archivebox"
        }
    }
}

// MARK: - Root Settings Shell (Adaptive Mobile Stack on iPhone + 2-Column Split on iPad)

public struct EnterpriseSettingsCenterView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var searchQuery: String = ""
    @State private var navigationPath: [SettingsSectionKind] = []
    @State private var selectedSectionForSplit: SettingsSectionKind = .modelProvider

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if sizeClass == .regular {
                iPadSplitSettingsLayout
            } else {
                iPhoneCompactSettingsLayout
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .task {
            await store.syncAllSettingsFromRemoteDesktop()
        }
    }

    // MARK: - iPhone Mobile Layout (1:1 ZCode Tokens & Grouping)

    private var iPhoneCompactSettingsLayout: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ZCodeSettingsSearchBar(
                            text: $searchQuery,
                            placeholder: "Search settings, models, subagents, MCP…"
                        )

                        remoteSyncBanner

                        ForEach(SettingsGroupKind.allCases) { group in
                            let items = filteredSections(in: group)
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.title.uppercased())
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .tracking(0.6)
                                        .foregroundStyle(palette.foregroundMuted)
                                        .padding(.horizontal, 4)

                                    VStack(spacing: 0) {
                                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, sec in
                                            NavigationLink(value: sec) {
                                                settingsSidebarRow(sec, isSelected: false)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("settingsNav_\(sec.rawValue)")

                                            if idx < items.count - 1 {
                                                Divider()
                                                    .overlay(palette.border)
                                                    .padding(.leading, 50)
                                            }
                                        }
                                    }
                                    .background(palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(palette.border, lineWidth: 1)
                                    )
                                }
                            }
                        }

                        sidebarFooterQuickControls
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.text("Settings", vi: "Cài đặt", zh: "设置", lang: store.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Workspace")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(palette.foreground)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(palette.accentBlue)
                        .accessibilityIdentifier("closeSettingsButton")
                }
            }
            .navigationDestination(for: SettingsSectionKind.self) { section in
                SettingsSectionRouterView(
                    store: store,
                    section: section,
                    onJumpToSection: { target in
                        if navigationPath.last != target {
                            navigationPath.append(target)
                        }
                    }
                )
            }
        }
    }

    // MARK: - iPad / Landscape 2-Column Split Layout (Exact ZCode `268px + 1fr` Shell)

    private var iPadSplitSettingsLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back to Workspace")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(palette.foreground)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("closeSettingsButton")

                    Spacer()
                }
                .padding(14)

                ZCodeSettingsSearchBar(text: $searchQuery, placeholder: "Filter settings…")
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(SettingsGroupKind.allCases) { group in
                            let items = filteredSections(in: group)
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.title)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(palette.foregroundMuted)
                                        .padding(.horizontal, 10)

                                    ForEach(items) { sec in
                                        Button {
                                            selectedSectionForSplit = sec
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: sec.icon)
                                                    .font(.system(size: 13.5, weight: .medium))
                                                    .frame(width: 20)
                                                    .foregroundStyle(selectedSectionForSplit == sec ? palette.foreground : palette.foregroundSubtle)
                                                Text(sec.title)
                                                    .font(.system(size: 13.5, weight: selectedSectionForSplit == sec ? .semibold : .regular))
                                                    .foregroundStyle(selectedSectionForSplit == sec ? palette.foreground : palette.foregroundSubtle)
                                                Spacer()
                                                if let badge = sectionBadgeText(sec) {
                                                    ZCodeSettingsPill(text: badge, tone: sec == .remoteDevices && store.activeConnection?.state == .connected ? .success : .neutral)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(
                                                selectedSectionForSplit == sec ? palette.card : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("settingsNav_\(sec.rawValue)")
                                    }
                                }
                            }
                        }

                        sidebarFooterQuickControls
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
            }
            .frame(width: 276)
            .background(palette.sidebar)
            .overlay(alignment: .trailing) {
                Rectangle().fill(palette.border).frame(width: 1)
            }

            NavigationStack {
                SettingsSectionRouterView(
                    store: store,
                    section: selectedSectionForSplit,
                    onJumpToSection: { target in
                        selectedSectionForSplit = target
                    }
                )
            }
        }
        .background(palette.background)
    }

    // MARK: - Helpers & Footer

    private func filteredSections(in group: SettingsGroupKind) -> [SettingsSectionKind] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return group.sections }
        return group.sections.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.navSubtitle.localizedCaseInsensitiveContains(q)
                || $0.headerDescription.localizedCaseInsensitiveContains(q)
        }
    }

    private func sectionBadgeText(_ sec: SettingsSectionKind) -> String? {
        switch sec {
        case .modelProvider:
            let enabledModels = store.allModels.count
            return "\(store.providers.count) · \(enabledModels)m"
        case .remoteDevices:
            if let conn = store.activeConnection, conn.state == .connected {
                return "Online"
            }
            return store.connections.isEmpty ? nil : "\(store.connections.count)"
        case .subagents:
            return "\(store.subagents.count)"
        case .plugin:
            return "\(store.plugins.filter(\.installed).count)"
        case .mcp:
            return store.mcpServers.isEmpty ? nil : "\(store.mcpServers.count)"
        case .skill:
            return "\(store.skills.count)"
        case .commands:
            return "\(store.slashCommands.count)"
        case .hooks:
            return store.hooks.isEmpty ? nil : "\(store.hooks.count)"
        case .archives:
            let c = store.sessions.filter(\.archived).count
            return c > 0 ? "\(c)" : nil
        default:
            return nil
        }
    }

    private func settingsSidebarRow(_ sec: SettingsSectionKind, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.card)
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
                Image(systemName: sec.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.foreground)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sec.title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(palette.foreground)
                    if let badge = sectionBadgeText(sec) {
                        ZCodeSettingsPill(
                            text: badge,
                            tone: sec == .remoteDevices && store.activeConnection?.state == .connected ? .success : .neutral
                        )
                    }
                }
                Text(sec.navSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.foregroundMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var remoteSyncBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.activeConnection?.state == .connected ? palette.success : palette.foregroundMuted)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                if let conn = store.activeConnection, conn.state == .connected {
                    Text("Synced with \(conn.name)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text("Provider configs, subagents, MCPs, skills & hooks sync over ZCode V4 RPC")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                } else {
                    Text("Standalone Mobile Settings")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text("Connect a ZCode Desktop workstation to mirror host settings live")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                }
            }

            Spacer()

            if store.activeConnection?.state == .connected {
                Button {
                    Task { await store.syncAllSettingsFromRemoteDesktop() }
                } label: {
                    if store.isSyncingSettings {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 28, height: 28)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }

    /// Exact ZCode Sidebar Footer (`settings.onboarding` dashed button + Account/Theme/Locale bar)
    private var sidebarFooterQuickControls: some View {
        VStack(spacing: 10) {
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    store.openConnectionHub()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Onboarding & Z.AI Remote Pairing")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(palette.foregroundSubtle)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(palette.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(palette.accentBlue.opacity(0.2))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String((store.zaiAccount?.displayName ?? store.userDisplayName).prefix(1)).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette.accentBlue)
                        )
                    Text(store.zaiAccount?.displayName ?? "Not signed in")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)
                }

                Spacer()

                Menu {
                    ForEach(ZCodeThemeMode.allCases) { m in
                        Button {
                            store.themeMode = m
                        } label: {
                            Label(m.displayName, systemImage: store.themeMode == m ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Image(systemName: palette.isDark ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 28, height: 28)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                Menu {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            store.language = lang
                        } label: {
                            Text(lang.displayName)
                        }
                    }
                } label: {
                    Text(store.language.rawValue.uppercased())
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .padding(.horizontal, 7)
                        .frame(height: 28)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Section Router

struct SettingsSectionRouterView: View {
    @Bindable var store: AppStore
    let section: SettingsSectionKind
    var onJumpToSection: (SettingsSectionKind) -> Void

    @Environment(\.zcodePalette) private var palette

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            switch section {
            case .modelProvider:
                ModelProviderSettingsView(store: store)
            case .subagents:
                SubagentsSettingsView(store: store, onJumpToModels: {
                    onJumpToSection(.modelProvider)
                })
            default:
                SettingsPagesDetailViews(
                    store: store,
                    section: section,
                    onJumpToSection: onJumpToSection
                )
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Shared 1:1 ZCode Settings Design System Primitives

public enum ZCodePillTone {
    case neutral
    case accent
    case success
    case warning
    case danger
}

struct ZCodeSettingsPill: View {
    let text: String
    var tone: ZCodePillTone = .neutral
    @Environment(\.zcodePalette) private var palette

    private var fg: Color {
        switch tone {
        case .neutral: return palette.foregroundSubtle
        case .accent: return palette.accentBlue
        case .success: return palette.success
        case .warning: return palette.warning
        case .danger: return palette.destructive
        }
    }

    private var bg: Color {
        switch tone {
        case .neutral: return palette.card
        case .accent: return palette.accentBlue.opacity(0.14)
        case .success: return palette.success.opacity(0.15)
        case .warning: return palette.warning.opacity(0.15)
        case .danger: return palette.destructive.opacity(0.15)
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(fg.opacity(tone == .neutral ? 0.16 : 0.28), lineWidth: 0.75)
            )
    }
}

struct ZCodeSettingsPageHeader<Trailing: View>: View {
    let groupTitle: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.zcodePalette) private var palette

    init(
        groupTitle: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.groupTitle = groupTitle
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Text("Settings")
                    .foregroundStyle(palette.foregroundMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.foregroundMuted)
                Text(groupTitle)
                    .foregroundStyle(palette.foregroundSubtle)
                Spacer()
                trailing()
            }
            .font(.system(size: 11.5, weight: .medium))

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.foreground)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundSubtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}

struct ZCodeSettingsCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                .padding(.bottom, 10)

                Divider().overlay(palette.border)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }
}

struct ZCodeSettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    @ViewBuilder var control: () -> Control
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.foreground)
                    if let badge {
                        ZCodeSettingsPill(text: badge, tone: .accent)
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.foregroundSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct ZCodeSettingsSearchBar: View {
    @Binding var text: String
    let placeholder: String
    @Environment(\.zcodePalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(palette.foregroundMuted)
            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .foregroundStyle(palette.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.inputBorder, lineWidth: 1)
        )
    }
}
