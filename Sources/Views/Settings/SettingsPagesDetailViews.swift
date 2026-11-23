import SwiftUI
import Charts

// MARK: - 1:1 ZCode v3.16.3 Detail Pages for All Remaining 14 Settings Sections

struct SettingsPagesDetailViews: View {
    @Bindable var store: AppStore
    let section: SettingsSectionKind
    var onJumpToSection: (SettingsSectionKind) -> Void

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    // Sub-sheets & local editors
    @State private var showPatternSheet: Bool = false
    @State private var mcpEditorMode: String = "form" // "form" | "json"
    @State private var rawMcpJSON: String = ""
    @State private var editingMCP: MCPServerItem? = nil
    @State private var showNewMCP: Bool = false
    @State private var inspectingSkill: SkillCatalogItem? = nil
    @State private var editingCommand: SlashCommandItem? = nil
    @State private var showNewCommand: Bool = false
    @State private var editingHook: HookRuleItem? = nil
    @State private var showNewHook: Bool = false
    @State private var editingShortcut: ShortcutBindingItem? = nil
    @State private var searchFilter: String = ""
    @State private var usageTab: String = "app" // "app" | "plan"
    @State private var usageRange: String = "7d" // "7d" | "30d"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch section {
                case .general:
                    generalPage
                case .appearance:
                    appearancePage
                case .browser:
                    browserUsePage
                case .remoteDevices:
                    remoteDevicesPage
                case .computerUse:
                    computerUsePage
                case .shortcuts:
                    shortcutsPage
                case .memory:
                    memoryPage
                case .plugin:
                    pluginsPage
                case .mcp:
                    mcpServersPage
                case .skill:
                    skillsPage
                case .commands:
                    commandsPage
                case .hooks:
                    hooksPage
                case .usage:
                    usageStatsPage
                case .archives:
                    archiveManagementPage
                case .modelProvider, .subagents:
                    EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(palette.background)
        .onChange(of: section) { _, _ in
            searchFilter = ""
        }
        .sheet(isPresented: $showPatternSheet) {
            PatternSetupSheetView(store: store)
        }
        .sheet(isPresented: $showNewMCP) {
            MCPServerEditorSheet(
                store: store,
                isNew: true,
                draft: MCPServerItem(
                    id: "mcp-user-\(UUID().uuidString.prefix(6).lowercased())",
                    name: "",
                    scope: "user",
                    transport: "stdio",
                    endpointOrCommand: "npx",
                    args: ["-y", "@modelcontextprotocol/server-filesystem", "."],
                    enabled: true,
                    connected: false,
                    tools: [],
                    resourcesCount: 0
                )
            )
        }
        .sheet(item: $editingMCP) { srv in
            MCPServerEditorSheet(store: store, isNew: false, draft: srv)
        }
        .sheet(item: $inspectingSkill) { sk in
            SkillMarkdownInspectorSheet(skill: sk)
        }
        .sheet(isPresented: $showNewCommand) {
            SlashCommandEditorSheet(
                store: store,
                isNew: true,
                draft: SlashCommandItem(
                    id: "cmd-\(UUID().uuidString.prefix(6).lowercased())",
                    trigger: "/audit",
                    summary: "Run targeted architecture & security check",
                    argumentHint: "[path-or-module]",
                    scope: "User",
                    promptTemplate: "Inspect $ARGUMENTS thoroughly and report concrete issues with file:line references."
                )
            )
        }
        .sheet(item: $editingCommand) { cmd in
            SlashCommandEditorSheet(store: store, isNew: false, draft: cmd)
        }
        .sheet(isPresented: $showNewHook) {
            HookRuleEditorSheet(
                store: store,
                draft: HookRuleItem(
                    id: "hk-\(UUID().uuidString.prefix(6).lowercased())",
                    event: "PreToolUse",
                    matcher: "Bash(*)",
                    hookType: "command",
                    scope: "user",
                    command: "echo 'Verifying command safety'",
                    enabled: true
                )
            )
        }
        .sheet(item: $editingHook) { hk in
            HookRuleEditorSheet(store: store, draft: hk)
        }
    }

    // MARK: - 1. General (`general`)

    private var generalPage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Basics",
                title: "General",
                subtitle: "Language, interaction behavior, tool search, terminal profile, notifications, proxy, and enterprise mobile security."
            )

            // Account & Language
            ZCodeSettingsCard(title: "Language & Workspace Mode") {
                ZCodeSettingsRow(title: "Interface Language", subtitle: "Default language across menus and agent UI (English default)") {
                    Picker("Language", selection: Binding(
                        get: { store.language },
                        set: { newLang in
                            store.language = newLang
                            store.pushDesktopSettingPatch(["locale": newLang.rawValue])
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(title: "Default Interface Mode", subtitle: "Switch between software engineering workspace and document/office mode") {
                    Picker("Mode", selection: Binding(
                        get: { store.interfaceMode },
                        set: { val in
                            store.interfaceMode = val
                            store.pushDesktopSettingPatch(["interfaceMode": val])
                        }
                    )) {
                        Text("Coding").tag("coding")
                        Text("Office").tag("office")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }

            // Agent Interaction & Search
            ZCodeSettingsCard(title: "Agent Interaction & Tool Execution") {
                ZCodeSettingsRow(
                    title: "Follow-up Prompt Behavior",
                    subtitle: "Choose whether messages sent during a running turn queue up or steer immediately"
                ) {
                    Picker("Behavior", selection: Binding(
                        get: { store.zcodeInteractionBehavior },
                        set: { val in
                            store.zcodeInteractionBehavior = val
                            store.pushDesktopSettingPatch(["zcodeInteractionBehavior": val])
                        }
                    )) {
                        Text("Queue").tag("queue")
                        Text("Steer").tag("guide")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 145)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Deferred Tool Search Mode",
                    subtitle: "Load MCP and extended tool schemas on-demand to preserve context window"
                ) {
                    Picker("Tool Search", selection: Binding(
                        get: { store.toolSearchMode },
                        set: { val in
                            store.toolSearchMode = val
                            store.pushDesktopSettingPatch(["toolSearchMode": val])
                        }
                    )) {
                        Text("Auto").tag("auto")
                        Text("On").tag("on")
                        Text("Off").tag("off")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 165)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Dynamic Multi-Agent Workflows",
                    subtitle: "Allow agent to orchestrate typed subagent fan-out workflows"
                ) {
                    Picker("Workflows", selection: Binding(
                        get: { store.dynamicWorkflowMode },
                        set: { val in
                            store.dynamicWorkflowMode = val
                            store.pushDesktopSettingPatch(["dynamicWorkflowMode": val])
                        }
                    )) {
                        Text("Auto").tag("auto")
                        Text("Manual").tag("manual")
                        Text("Off").tag("disabled")
                    }
                    .pickerStyle(.menu)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Auto-Resolve Clarifying Questions",
                    subtitle: "Let autonomous runs pick recommended defaults on AskUserQuestion"
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.askUserQuestionAutoResolutionEnabled },
                        set: { val in
                            store.askUserQuestionAutoResolutionEnabled = val
                            store.pushDesktopSettingPatch(["askUserQuestionAutoResolutionEnabled": val])
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Native Search Enhancements (ripgrep + AST)",
                    subtitle: "Accelerate @file mentions and workspace symbol search"
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.nativeSearchEnhancementsEnabled },
                        set: { val in
                            store.nativeSearchEnhancementsEnabled = val
                            store.pushDesktopSettingPatch(["nativeSearchEnhancementsEnabled": val])
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Keep Screen Awake During Active Runs",
                    subtitle: "Prevent sleep while streaming code changes or waiting on approvals"
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.keepAwakeWhileRunning },
                        set: { val in
                            store.keepAwakeWhileRunning = val
                            UIApplication.shared.isIdleTimerDisabled = val
                            store.pushDesktopSettingPatch(["keepAwakeWhileRunning": val])
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                }
            }

            // Notifications & Haptics
            ZCodeSettingsCard(title: "Notifications & Haptics") {
                ZCodeSettingsRow(title: "Push & Local Task Alerts", subtitle: "Notify when permissions, questions, or background runs complete") {
                    Toggle("", isOn: $store.notificationsEnabled)
                        .labelsHidden()
                        .tint(palette.accentBlue)
                }
                if store.notificationsEnabled {
                    Divider().overlay(palette.border)
                    ZCodeSettingsRow(title: "Tool Permission Requests") {
                        Toggle("", isOn: $store.notifyApprovals).labelsHidden().tint(palette.accentBlue)
                    }
                    Divider().overlay(palette.border)
                    ZCodeSettingsRow(title: "AskUserQuestion Prompts") {
                        Toggle("", isOn: $store.notifyQuestions).labelsHidden().tint(palette.accentBlue)
                    }
                    Divider().overlay(palette.border)
                    ZCodeSettingsRow(title: "Task Completion & Errors") {
                        Toggle("", isOn: $store.notifyCompletions).labelsHidden().tint(palette.accentBlue)
                    }
                }
                Divider().overlay(palette.border)
                ZCodeSettingsRow(title: "Tactile Haptic Feedback", subtitle: "Subtle haptics on tool approvals, checkpoints, and mode switches") {
                    Toggle("", isOn: $store.hapticsEnabled)
                        .labelsHidden()
                        .tint(palette.accentBlue)
                }
            }

            // Network Proxy & Mobile App Lock
            ZCodeSettingsCard(title: "Network Proxy & Mobile Security") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HTTP / SOCKS5 Proxy URL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    HStack(spacing: 8) {
                        TextField("http://127.0.0.1:7890 (leave empty for direct)", text: $store.httpProxyURL)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(9)
                            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))

                        Button("Apply") {
                            store.pushDesktopSettingPatch([
                                "httpProxy": [
                                    "enabled": !store.httpProxyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                    "proxyUrl": store.httpProxyURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                    "noProxy": store.httpProxyNoProxy
                                ]
                            ])
                            store.showToast("Updated network proxy")
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.brandForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)

                Divider().overlay(palette.border)

                ZCodeSettingsRow(title: "Face ID & Pattern App Lock", subtitle: "Require biometric or 3×3 pattern verification on launch") {
                    Toggle("", isOn: $store.appLockEnabled)
                        .labelsHidden()
                        .tint(palette.accentBlue)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "9-Dot Security Pattern",
                    subtitle: store.hasPatternConfigured ? "Encrypted SHA-256 pattern stored in iOS Keychain" : "Configure fallback unlock pattern"
                ) {
                    Button(store.hasPatternConfigured ? "Change Pattern" : "Set Pattern") {
                        showPatternSheet = true
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.accentBlue)
                }
            }

            // Version & Runtime Info
            ZCodeSettingsCard(title: "About ZCode Mobile") {
                ZCodeSettingsRow(title: "Version", subtitle: "100% Native SwiftUI • Zero WebView • SocketProtocol V4") {
                    ZCodeSettingsPill(text: "v3.16.3 (31606)", tone: .accent)
                }
            }
        }
    }

    // MARK: - 2. Appearance (`appearance`)

    private var appearancePage: some View {
        let sampleCode = """
        @MainActor
        func syncWorkspace(id: String) async throws -> WorkspaceSnapshot {
            let reply = try await rpc.call(channel: "zcode-task", method: "listTasks")
            return try WorkspaceSnapshot.decode(from: reply)
        }
        """
        return Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Basics",
                title: "Appearance",
                subtitle: "Color mode, Shiki-compatible syntax highlighting palettes, typography scale, and conversation card grouping."
            )

            // Theme Cards (`themeOption_dark`, `themeOption_light`, `themeOption_system`)
            ZCodeSettingsCard(title: "Color Theme") {
                HStack(spacing: 10) {
                    ForEach(ZCodeThemeMode.allCases) { mode in
                        let selected = store.themeMode == mode
                        Button {
                            store.themeMode = mode
                            store.pushDesktopSettingPatch(["theme": mode.rawValue])
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(mode == .light ? Color(white: 0.96) : Color(white: 0.11))
                                        .frame(height: 52)
                                        .overlay(
                                            HStack(spacing: 5) {
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(mode == .light ? Color(white: 0.86) : Color(white: 0.20))
                                                    .frame(width: 18, height: 34)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(Color.blue.opacity(0.8))
                                                        .frame(width: 34, height: 6)
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(mode == .light ? Color.black.opacity(0.25) : Color.white.opacity(0.28))
                                                        .frame(width: 46, height: 5)
                                                }
                                            }
                                        )
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(selected ? palette.accentBlue : palette.foregroundMuted)
                                    Text(mode.displayName)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(palette.foreground)
                                }
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity)
                            .background(selected ? palette.accentBlue.opacity(0.10) : palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selected ? palette.accentBlue : palette.border, lineWidth: selected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("themeOption_\(mode.rawValue)")
                    }
                }
                .padding(14)
            }

            // Syntax Theme + Live Native Code Preview
            ZCodeSettingsCard(title: "Code Syntax Highlighting", subtitle: "Applies across File Viewer, Diff Inspector, and Chat code blocks.") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Active Syntax Theme")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.foreground)
                        Spacer()
                        Picker("Syntax Theme", selection: $store.syntaxTheme) {
                            ForEach(ZCodeSyntaxTheme.allCases) { st in
                                Text(st.displayName).tag(st)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(sampleCode.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            Text(SyntaxHighlighter.highlightLine(line, language: "swift", theme: store.syntaxTheme, fontSize: CGFloat(store.codeFontSize)))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SyntaxColors.palette(for: store.syntaxTheme).background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.border, lineWidth: 1))

                    HStack {
                        Text("Code Font Size")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.foreground)
                        Spacer()
                        Text("\(Int(store.codeFontSize)) pt")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(palette.accentBlue)
                    }
                    Slider(value: $store.codeFontSize, in: 11...18, step: 1)
                        .tint(palette.accentBlue)

                    Toggle("Show Line Numbers in Code & Diffs", isOn: $store.showLineNumbers)
                        .font(.system(size: 13.5))
                        .tint(palette.accentBlue)
                    Toggle("Soft-Wrap Long Code Lines", isOn: $store.wrapCodeLines)
                        .font(.system(size: 13.5))
                        .tint(palette.accentBlue)
                }
                .padding(14)
            }

            // Conversation Stream & Tool Grouping
            ZCodeSettingsCard(title: "Message stream") {
                ZCodeSettingsRow(title: "Show reasoning", subtitle: "Show full reasoning inside the message stream. When off, the first reasoning item in each turn remains visible.") {
                    Toggle("", isOn: $store.showReasoningBlocks).labelsHidden().tint(palette.accentBlue)
                }
                Divider().overlay(palette.border)
                ZCodeSettingsRow(title: "Show todos", subtitle: "Show Todo tool cards inside the message stream.") {
                    Toggle("", isOn: $store.messageStreamShowTodos).labelsHidden().tint(palette.accentBlue)
                }
                Divider().overlay(palette.border)
                ZCodeSettingsRow(title: "Group exploration tools", subtitle: "Group consecutive reads and searches into an Explore section.") {
                    Toggle("", isOn: $store.toolGroupingExploreEnabled).labelsHidden().tint(palette.accentBlue)
                }
                Divider().overlay(palette.border)
                ZCodeSettingsRow(title: "Group terminal commands", subtitle: "Group consecutive non-read-only shell commands into a Terminal section.") {
                    Toggle("", isOn: $store.toolGroupingTerminalEnabled).labelsHidden().tint(palette.accentBlue)
                }
                Divider().overlay(palette.border)
                ZCodeSettingsRow(title: "Group file changes", subtitle: "Group consecutive Write, Edit, and ApplyPatch calls into a Changes section.") {
                    Toggle("", isOn: $store.toolGroupingChangesEnabled).labelsHidden().tint(palette.accentBlue)
                }
            }
        }
    }

    // MARK: - 3. Browser Use (`browser`)

    private var browserUsePage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Basics",
                title: "Browser Use",
                subtitle: "Configure ZCode Desktop's headless/CDP browser automation engine used for web UI testing and localhost verification."
            )

            ZCodeSettingsCard(title: "Browser Automation Policy", subtitle: "Executed on your paired ZCode Desktop host; mobile renders native screenshots and DOM traces.") {
                ZCodeSettingsRow(
                    title: "Allow Localhost Self-Signed Certificates",
                    subtitle: "Permit HTTPS dev servers (https://localhost, 127.0.0.1) during frontend verification"
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.embeddedBrowserAllowInsecureCertificates },
                        set: { val in
                            store.embeddedBrowserAllowInsecureCertificates = val
                            store.pushDesktopSettingPatch(["embeddedBrowserAllowInsecureCertificates": val])
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                }

                Divider().overlay(palette.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Allowed Domains & Local Targets")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    TextField("localhost, 127.0.0.1, *.vercel.app", text: $store.browserAllowedDomains, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .padding(10)
                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                }
                .padding(14)
            }
        }
    }

    // MARK: - 4. Remote Devices (`remoteDevices`)

    private var remoteDevicesPage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Basics",
                title: "Remote devices",
                subtitle: "Manage your Z.AI account session, registered ZCode Desktop workstations, and Relay V4 connections."
            ) {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        store.openConnectionHub()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Pair")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.brandForeground)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Z.AI Account Card
            ZCodeSettingsCard(title: "Z.AI Cloud Account") {
                if let acct = store.zaiAccount {
                    let emailPart = (acct.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    ZCodeSettingsRow(
                        title: acct.displayName,
                        subtitle: emailPart.isEmpty ? "Region: \(store.zaiRegion.title)" : "\(emailPart) • \(store.zaiRegion.title)"
                    ) {
                        HStack(spacing: 8) {
                            ZCodeSettingsPill(text: "Signed In", tone: .success)
                            Button("Sign Out") {
                                store.signOutZaiAccount()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.destructive)
                        }
                    }
                } else {
                    ZCodeSettingsRow(
                        title: "Not Signed In",
                        subtitle: "Sign in with Z.AI to auto-discover your online ZCode Desktop workstations"
                    ) {
                        Button("Sign In") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                store.openConnectionHub()
                            }
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.accentBlue)
                    }
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Auto-Reconnect on App Launch",
                    subtitle: "Resume the most recent workstation session automatically"
                ) {
                    Toggle("", isOn: $store.remoteStartupAutoReconnectEnabled)
                        .labelsHidden()
                        .tint(palette.accentBlue)
                }
            }

            // Saved Workstations
            ZCodeSettingsCard(
                title: "Paired Workstations (\(store.connections.count))",
                subtitle: "Tap Connect to switch active bridge or swipe/tap trash to forget."
            ) {
                if store.connections.isEmpty {
                    Text("No paired workstations yet. Tap Pair above to scan QR or paste your ZCode Remote link.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .padding(16)
                } else {
                    ForEach(Array(store.connections.enumerated()), id: \.element.id) { idx, conn in
                        HStack(spacing: 11) {
                            Circle()
                                .fill(conn.state == .connected ? palette.success : palette.foregroundMuted)
                                .frame(width: 9, height: 9)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(conn.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(palette.foreground)
                                    ZCodeSettingsPill(
                                        text: conn.transport == .cloudRelayV2 ? "Relay V4" : "Direct WS",
                                        tone: conn.state == .connected ? .success : .neutral
                                    )
                                }
                                Text("\(conn.host) • v\(conn.serverVersion)")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if conn.state == .connected && store.activeConnectionId == conn.id {
                                ZCodeSettingsPill(text: "\(max(1, conn.latencyMs))ms", tone: .success)
                            } else {
                                Button("Connect") {
                                    Task { await store.connectToWorkstation(conn.id) }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.accentBlue)
                            }

                            Button(role: .destructive) {
                                store.removeConnection(conn.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.destructive)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if idx < store.connections.count - 1 {
                            Divider().overlay(palette.border).padding(.leading, 34)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. Computer Use (`computerUse`)

    private var computerUsePage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Basics",
                title: "Computer Use",
                subtitle: "Control native desktop GUI automation permissions and composer entry visibility on your paired workstation."
            )

            ZCodeSettingsCard(title: "Desktop CUA Helper & Permissions") {
                ZCodeSettingsRow(
                    title: "Enable Computer Use Agent (CUA)",
                    subtitle: "Allow agent to inspect and interact with native desktop apps when authorized"
                ) {
                    Toggle("", isOn: $store.cuaHelperEnabled)
                        .labelsHidden()
                        .tint(palette.accentBlue)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Show Computer Use Toggle in Composer",
                    subtitle: "Display quick CUA toggle inside the task composer toolbar"
                ) {
                    Toggle("", isOn: Binding(
                        get: { !store.computerUseComposerEntryHidden },
                        set: { visible in
                            store.computerUseComposerEntryHidden = !visible
                            store.pushDesktopSettingPatch(["computerUseComposerEntryHidden": !visible])
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(title: "Host Accessibility Permission", subtitle: "macOS AXUIElement control on paired host") {
                    ZCodeSettingsPill(text: store.cuaAccessibilityStatus.capitalized, tone: .success)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(title: "Host Screen Recording Permission", subtitle: "Required for high-DPI desktop visual grounding") {
                    ZCodeSettingsPill(text: store.cuaScreenRecordingStatus.capitalized, tone: .success)
                }
            }
        }
    }

    // MARK: - 6. Keyboard Shortcuts (`shortcuts`)

    private var shortcutsPage: some View {
        let q = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.shortcutBindings.filter {
            q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || $0.category.localizedCaseInsensitiveContains(q) || $0.activeBinding.localizedCaseInsensitiveContains(q)
        }
        let categories = ["Window", "Workspace", "Composer"]

        return Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Basics",
                title: "Keyboard Shortcuts",
                subtitle: "Hardware Magic Keyboard shortcuts on iPadOS & iOS, synchronized with ZCode Desktop keybindings."
            ) {
                Button("Reset All") {
                    store.shortcutBindings = ShortcutBindingItem.officialDefaults
                    store.showToast("Reset shortcuts to defaults")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accentBlue)
            }

            ZCodeSettingsSearchBar(text: $searchFilter, placeholder: "Search 19 keyboard shortcuts…")

            ForEach(categories, id: \.self) { cat in
                let items = filtered.filter { $0.category == cat }
                if !items.isEmpty {
                    ZCodeSettingsCard(title: cat) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, sc in
                            HStack {
                                Text(sc.title)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(palette.foreground)
                                Spacer()
                                Text(sc.activeBinding)
                                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.foreground)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4.5)
                                    .background(palette.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.borderStrong, lineWidth: 1))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)

                            if idx < items.count - 1 {
                                Divider().overlay(palette.border).padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 7. Memory (`memory`)

    private var memoryPage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "Memory",
                subtitle: "Persistent cross-session instructions and project knowledge recalled automatically by ZCode."
            ) {
                Button("Save") {
                    store.saveUserMemoryMarkdown(store.userMemoryMarkdown)
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.brandForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .buttonStyle(.plain)
            }

            ZCodeSettingsCard(title: "Automatic Memory Recall") {
                ZCodeSettingsRow(
                    title: "Enable Persistent Memory",
                    subtitle: "Allow ZCode to read and update MEMORY.md across coding sessions"
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.memoryEnabled },
                        set: { val in
                            store.memoryEnabled = val
                            store.pushDesktopSettingPatch(["memoryEnabled": val])
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                }
            }

            ZCodeSettingsCard(
                title: "Global Memory Instructions (~/.zcode/MEMORY.md)",
                subtitle: "Synced live with your paired ZCode Desktop via the memory RPC channel."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $store.userMemoryMarkdown)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
                        .padding(8)
                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                }
                .padding(14)
            }

            if !store.memories.isEmpty {
                ZCodeSettingsCard(title: "Structured Workspace Memory Notes (\(store.memories.count))") {
                    ForEach(Array(store.memories.enumerated()), id: \.element.id) { idx, note in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(note.slug)
                                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.foreground)
                                ZCodeSettingsPill(text: note.type, tone: .accent)
                                Spacer()
                            }
                            Text(note.description)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.foregroundSubtle)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                        if idx < store.memories.count - 1 {
                            Divider().overlay(palette.border).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 8. Plugins (`plugin`)

    private var pluginsPage: some View {
        let q = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let installed = store.plugins.filter { $0.installed && (q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q)) }
        let marketplace = store.plugins.filter { !$0.installed && (q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q)) }

        return Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "Plugins",
                subtitle: "Extend ZCode with official bundles containing Skills, Subagents, Slash Commands, and MCP servers."
            )

            ZCodeSettingsSearchBar(text: $searchFilter, placeholder: "Search installed & official marketplace plugins…")

            ZCodeSettingsCard(
                title: "Installed Plugins (\(installed.count))",
                subtitle: "Marketplaces: \(store.pluginMarketplaces.joined(separator: ", "))"
            ) {
                if installed.isEmpty {
                    Text("No matching installed plugins.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .padding(16)
                } else {
                    ForEach(Array(installed.enumerated()), id: \.element.id) { idx, pl in
                        pluginRow(pl, isInstalled: true)
                        if idx < installed.count - 1 {
                            Divider().overlay(palette.border).padding(.horizontal, 14)
                        }
                    }
                }
            }

            if !marketplace.isEmpty {
                ZCodeSettingsCard(title: "Discover in Marketplace (\(marketplace.count))") {
                    ForEach(Array(marketplace.enumerated()), id: \.element.id) { idx, pl in
                        pluginRow(pl, isInstalled: false)
                        if idx < marketplace.count - 1 {
                            Divider().overlay(palette.border).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    private func pluginRow(_ pl: PluginCatalogItem, isInstalled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(pl.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                ZCodeSettingsPill(text: "v\(pl.version)", tone: .neutral)
                ForEach(pl.componentBadges.prefix(3), id: \.self) { b in
                    ZCodeSettingsPill(text: b, tone: .accent)
                }
                Spacer()
                if isInstalled {
                    Toggle("", isOn: Binding(
                        get: { pl.enabled },
                        set: { store.setPluginEnabled(pl, enabled: $0) }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                } else {
                    Button {
                        if let i = store.plugins.firstIndex(where: { $0.id == pl.id }) {
                            store.plugins[i].installed = true
                            store.plugins[i].enabled = true
                            store.showToast("Installed \(pl.name)")
                        }
                    } label: {
                        Text("Install")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.brandForeground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(palette.brand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(pl.summary)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.foregroundSubtle)

            Text(pl.marketplace)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.foregroundMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 9. MCP Servers (`mcp`) — Visual List + Raw JSON Editor

    private var mcpServersPage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "MCP Servers",
                subtitle: "Connect Model Context Protocol servers over stdio, Streamable HTTP, or SSE."
            ) {
                Button {
                    showNewMCP = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add MCP")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.brandForeground)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Picker("View Mode", selection: Binding(
                get: { mcpEditorMode },
                set: { mode in
                    if mode == "json" {
                        rawMcpJSON = buildRawMCPJsonString()
                    }
                    mcpEditorMode = mode
                }
            )) {
                Text("Configured Servers (\(store.mcpServers.count))").tag("form")
                Text("Raw mcpServers JSON").tag("json")
            }
            .pickerStyle(.segmented)

            if mcpEditorMode == "json" {
                ZCodeSettingsCard(
                    title: "~/.zcode/mcp.json",
                    subtitle: "Edit standard Claude/ZCode mcpServers JSON directly and apply."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $rawMcpJSON)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .padding(8)
                            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))

                        Button {
                            applyRawMCPJsonString()
                        } label: {
                            Text("Apply JSON Configuration")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(palette.brandForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(palette.brand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                }
            } else {
                ZCodeSettingsCard(
                    title: "MCP Server Endpoints",
                    subtitle: "Synced live with ~/.zcode/mcp.json and workspace .mcp.json."
                ) {
                    if store.mcpServers.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(palette.foregroundMuted)
                            Text("No MCP servers configured.")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(palette.foregroundSubtle)
                            Button("+ Add stdio or HTTP MCP Server") { showNewMCP = true }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.accentBlue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(Array(store.mcpServers.enumerated()), id: \.element.id) { idx, srv in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(srv.connected ? palette.success : (srv.enabled ? palette.warning : palette.foregroundMuted))
                                        .frame(width: 8, height: 8)
                                    Text(srv.name)
                                        .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(palette.foreground)
                                    ZCodeSettingsPill(text: srv.transport.uppercased(), tone: .accent)
                                    ZCodeSettingsPill(text: srv.statusText, tone: srv.connected ? .success : .neutral)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { srv.enabled },
                                        set: { store.setMCPServerEnabled(srv, enabled: $0) }
                                    ))
                                    .labelsHidden()
                                    .tint(palette.accentBlue)
                                }

                                Text(([srv.endpointOrCommand] + srv.args).joined(separator: " "))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .lineLimit(2)

                                if !srv.tools.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 5) {
                                            ForEach(srv.tools.prefix(8), id: \.self) { t in
                                                ZCodeSettingsPill(text: t, tone: .neutral)
                                            }
                                            if srv.tools.count > 8 {
                                                ZCodeSettingsPill(text: "+\(srv.tools.count - 8)", tone: .neutral)
                                            }
                                        }
                                    }
                                }

                                HStack(spacing: 8) {
                                    Button("Configure") { editingMCP = srv }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foreground)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    Spacer()
                                    Button(role: .destructive) {
                                        store.deleteMCPServer(srv)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundStyle(palette.destructive)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            if idx < store.mcpServers.count - 1 {
                                Divider().overlay(palette.border).padding(.horizontal, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    private func buildRawMCPJsonString() -> String {
        var serversObj: [String: Any] = [:]
        for s in store.mcpServers {
            if s.transport == "stdio" {
                serversObj[s.name] = [
                    "type": "stdio",
                    "command": s.endpointOrCommand,
                    "args": s.args
                ]
            } else {
                serversObj[s.name] = [
                    "type": s.transport,
                    "url": s.endpointOrCommand
                ]
            }
        }
        let root: [String: Any] = ["mcpServers": serversObj]
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\n  \"mcpServers\": {}\n}"
    }

    private func applyRawMCPJsonString() {
        guard let data = rawMcpJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = (obj["mcpServers"] as? [String: [String: Any]]) ?? (obj as? [String: [String: Any]]) else {
            store.showToast("Invalid JSON syntax")
            return
        }
        for (name, cfg) in servers {
            let transport = (cfg["type"] as? String) ?? ((cfg["url"] != nil) ? "http" : "stdio")
            let cmdOrUrl = (cfg["url"] as? String) ?? (cfg["command"] as? String) ?? ""
            let args = (cfg["args"] as? [String]) ?? []
            let draft = MCPServerItem(
                id: "mcp-user-\(name)",
                name: name,
                scope: "user",
                transport: transport,
                endpointOrCommand: cmdOrUrl,
                args: args,
                enabled: true,
                connected: false,
                tools: [],
                resourcesCount: 0
            )
            store.upsertMCPServer(draft, isNew: true)
        }
        mcpEditorMode = "form"
    }

    // MARK: - 10. Skills (`skill`)

    private var skillsPage: some View {
        let q = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.skills.filter {
            q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q) || $0.scope.localizedCaseInsensitiveContains(q)
        }

        return Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "Skills",
                subtitle: "Reusable SKILL.md domain workflows loaded automatically or invoked via slash commands."
            )

            ZCodeSettingsSearchBar(text: $searchFilter, placeholder: "Search skills by name, scope, or domain…")

            ZCodeSettingsCard(title: "Available Skills (\(filtered.count))") {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, sk in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(sk.name)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.foreground)
                            ZCodeSettingsPill(text: sk.scope, tone: sk.scope == "Workspace" ? .accent : .neutral)
                            Spacer()
                            Button("SKILL.md") {
                                inspectingSkill = sk
                            }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.accentBlue)

                            Toggle("", isOn: Binding(
                                get: { sk.enabled },
                                set: { store.setSkillEnabled(sk, enabled: $0) }
                            ))
                            .labelsHidden()
                            .tint(palette.accentBlue)
                        }

                        Text(sk.summary)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.foregroundSubtle)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if idx < filtered.count - 1 {
                        Divider().overlay(palette.border).padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    // MARK: - 11. Commands (`commands`)

    private var commandsPage: some View {
        let q = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let customCmds = store.slashCommands.filter { $0.scope != "System" && (q.isEmpty || $0.trigger.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q)) }
        let systemCmds = store.slashCommands.filter { $0.scope == "System" && (q.isEmpty || $0.trigger.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q)) }

        return Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "Commands",
                subtitle: "Custom Markdown slash commands (~/.zcode/commands & .zcode/commands) and built-in composer actions."
            ) {
                Button {
                    showNewCommand = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New Command")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.brandForeground)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            ZCodeSettingsSearchBar(text: $searchFilter, placeholder: "Filter /commands…")

            ZCodeSettingsCard(
                title: "Custom User & Project Commands (\(customCmds.count))",
                subtitle: "Type / in the chat composer to trigger any command."
            ) {
                if customCmds.isEmpty {
                    Text("No custom slash commands yet. Tap New Command to create one.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .padding(16)
                } else {
                    ForEach(Array(customCmds.enumerated()), id: \.element.id) { idx, cmd in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(cmd.trigger)
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(palette.accentBlue)
                                    if !cmd.argumentHint.isEmpty {
                                        Text(cmd.argumentHint)
                                            .font(.system(size: 11.5, design: .monospaced))
                                            .foregroundStyle(palette.foregroundMuted)
                                    }
                                    ZCodeSettingsPill(text: cmd.scope, tone: .neutral)
                                }
                                Text(cmd.summary)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.foregroundSubtle)
                            }
                            Spacer()
                            Button("Edit") { editingCommand = cmd }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.foreground)
                            Button(role: .destructive) {
                                store.deleteSlashCommand(cmd)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.destructive)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                        if idx < customCmds.count - 1 {
                            Divider().overlay(palette.border).padding(.horizontal, 14)
                        }
                    }
                }
            }

            ZCodeSettingsCard(title: "Built-in System Commands (\(systemCmds.count))") {
                ForEach(Array(systemCmds.enumerated()), id: \.element.id) { idx, cmd in
                    ZCodeSettingsRow(title: cmd.trigger, subtitle: cmd.summary, badge: "System") {
                        EmptyView()
                    }
                    if idx < systemCmds.count - 1 {
                        Divider().overlay(palette.border).padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    // MARK: - 12. Hooks (`hooks`)

    private var hooksPage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "Hooks",
                subtitle: "Deterministic shell/process lifecycle hooks triggered on PreToolUse, PostToolUse, SessionStart, PermissionRequest, and Stop."
            ) {
                Button {
                    showNewHook = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Hook")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.brandForeground)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            ZCodeSettingsCard(title: "Workspace Hook Execution Trust") {
                ZCodeSettingsRow(
                    title: "Allow Workspace .zcode/settings.json Hooks",
                    subtitle: "Disable if inspecting an untrusted third-party repository"
                ) {
                    Toggle("", isOn: $store.workspaceHookTrustGranted)
                        .labelsHidden()
                        .tint(palette.accentBlue)
                }
            }

            ZCodeSettingsCard(
                title: "Configured Lifecycle Hooks (\(store.hooks.count))",
                subtitle: "7 supported events: \(HookRuleItem.officialEvents.joined(separator: ", "))"
            ) {
                if store.hooks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(palette.foregroundMuted)
                        Text("No lifecycle hooks configured.")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.foregroundSubtle)
                        Button("+ Add PreToolUse or PostToolUse Hook") { showNewHook = true }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.accentBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(Array(store.hooks.enumerated()), id: \.element.id) { idx, hk in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 7) {
                                ZCodeSettingsPill(text: hk.event, tone: .accent)
                                Text(hk.matcher)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.foreground)
                                ZCodeSettingsPill(text: hk.scope, tone: .neutral)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { hk.enabled },
                                    set: { val in
                                        var updated = hk
                                        updated.enabled = val
                                        store.upsertHookRule(updated)
                                    }
                                ))
                                .labelsHidden()
                                .tint(palette.accentBlue)
                            }

                            Text(hk.command)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(palette.foregroundSubtle)
                                .lineLimit(2)

                            HStack {
                                Text("Timeout: \(hk.timeoutSec)s • \(hk.hookType)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.foregroundMuted)
                                Spacer()
                                if hk.editable {
                                    Button("Edit") { editingHook = hk }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foreground)
                                    Button(role: .destructive) {
                                        store.deleteHookRule(hk)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundStyle(palette.destructive)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if idx < store.hooks.count - 1 {
                            Divider().overlay(palette.border).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 13. Usage Stats (`usage`) — App Usage & Coding Plan + Swift Charts

    private var usageStatsPage: some View {
        let totalInK = store.tokenUsageStats.reduce(0) { $0 + $1.inputTokensK }
        let totalOutK = store.tokenUsageStats.reduce(0) { $0 + $1.outputTokensK }
        let totalCacheK = store.tokenUsageStats.reduce(0) { $0 + $1.cachedTokensK }
        let cacheHitPct = totalInK > 0 ? min(99, Int(Double(totalCacheK) / Double(totalInK) * 100.0)) : 68

        return Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Data and statistics",
                title: "Usage stats",
                subtitle: "Token consumption, prompt cache efficiency, daily activity, and Z.ai Coding Plan quota."
            ) {
                Picker("Range", selection: Binding(
                    get: { usageRange },
                    set: { r in
                        usageRange = r
                        Task { await store.syncUsageStatsRPC(range: r) }
                    }
                )) {
                    Text("7D").tag("7d")
                    Text("30D").tag("30d")
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
            }

            Picker("Usage Tab", selection: $usageTab) {
                Text("App Usage").tag("app")
                Text("Z.ai Coding Plan").tag("plan")
            }
            .pickerStyle(.segmented)

            if usageTab == "plan" {
                ZCodeSettingsCard(
                    title: "Z.ai Coding Plan Entitlement",
                    subtitle: "5-hour rolling window and monthly high-speed GLM-5.3 coding quota."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.isZaiAuthenticated ? "Active Coding Plan" : "Sign in to view live plan quota")
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(palette.foreground)
                                Text("Models: GLM-5.3, GLM-5.3-Flash, GLM-5V-Turbo")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.foregroundSubtle)
                            }
                            Spacer()
                            ZCodeSettingsPill(text: store.isZaiAuthenticated ? "Active" : "Standby", tone: store.isZaiAuthenticated ? .success : .neutral)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("5-Hour Rolling Quota")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(palette.foregroundSubtle)
                                Spacer()
                                Text("Healthy")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.success)
                            }
                            ProgressView(value: 0.24)
                                .tint(palette.accentBlue)
                        }
                    }
                    .padding(14)
                }
            } else {
                // 4 KPI Cards
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    usageKpiTile(label: "Input Tokens", value: "\(totalInK)K", badge: "Prompt")
                    usageKpiTile(label: "Output Tokens", value: "\(totalOutK)K", badge: "Completion")
                    usageKpiTile(label: "Cache Hit Rate", value: "\(cacheHitPct)%", badge: "\(totalCacheK)K cached")
                    usageKpiTile(label: "Active Sessions", value: "\(store.sessions.count)", badge: "\(store.projects.count) projects")
                }

                ZCodeSettingsCard(title: "Daily Token Throughput", subtitle: "Input vs Output tokens (in thousands) across recent coding days.") {
                    if store.tokenUsageStats.isEmpty {
                        Text("No token usage recorded in this window yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        Chart {
                            ForEach(store.tokenUsageStats) { item in
                                BarMark(
                                    x: .value("Day", item.dayLabel),
                                    y: .value("Input (K)", item.inputTokensK)
                                )
                                .foregroundStyle(palette.accentBlue)

                                BarMark(
                                    x: .value("Day", item.dayLabel),
                                    y: .value("Output (K)", item.outputTokensK)
                                )
                                .foregroundStyle(palette.success)
                            }
                        }
                        .frame(height: 190)
                        .padding(14)
                    }
                }
            }
        }
    }

    private func usageKpiTile(label: String, value: String, badge: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                Spacer()
                ZCodeSettingsPill(text: badge, tone: .neutral)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(palette.foreground)
        }
        .padding(12)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }

    // MARK: - 14. Archive Management (`archives`)

    private var archiveManagementPage: some View {
        let q = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let archivedSessions = store.sessions.filter {
            $0.archived && (q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || $0.workspacePath.localizedCaseInsensitiveContains(q))
        }

        return Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Data and statistics",
                title: "Archive management",
                subtitle: "Configure automatic session cleanup and restore or permanently remove archived conversations."
            )

            ZCodeSettingsCard(title: "Automatic Task Archiving") {
                ZCodeSettingsRow(
                    title: "Auto-Archive Inactive Tasks",
                    subtitle: "Automatically move older idle conversations out of the main sidebar"
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.taskAutoArchiveEnabled },
                        set: { val in
                            store.taskAutoArchiveEnabled = val
                            store.pushDesktopSettingPatch(["taskAutoArchive": ["enabled": val, "olderThanDays": store.taskAutoArchiveOlderThanDays]])
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                }

                if store.taskAutoArchiveEnabled {
                    Divider().overlay(palette.border)
                    ZCodeSettingsRow(title: "Archive Tasks Older Than") {
                        Picker("Days", selection: Binding(
                            get: { store.taskAutoArchiveOlderThanDays },
                            set: { days in
                                store.taskAutoArchiveOlderThanDays = days
                                store.pushDesktopSettingPatch(["taskAutoArchive": ["enabled": true, "olderThanDays": days]])
                            }
                        )) {
                            Text("3 days").tag(3)
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }
            }

            ZCodeSettingsSearchBar(text: $searchFilter, placeholder: "Search archived tasks by title or workspace…")

            ZCodeSettingsCard(title: "Archived Conversations (\(archivedSessions.count))") {
                if archivedSessions.isEmpty {
                    Text("No archived conversations.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(Array(archivedSessions.enumerated()), id: \.element.id) { idx, sess in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sess.displayTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(palette.foreground)
                                    .lineLimit(1)
                                Text(sess.workspacePath)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Restore") {
                                store.restoreArchivedSession(sess.id)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.accentBlue)

                            Button(role: .destructive) {
                                store.deleteArchivedSessionPermanently(sess.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.destructive)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if idx < archivedSessions.count - 1 {
                            Divider().overlay(palette.border).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Editor Sheets (MCP, Skill Inspector, Slash Command, Hook)

struct MCPServerEditorSheet: View {
    @Bindable var store: AppStore
    let isNew: Bool
    @State var draft: MCPServerItem
    @State private var argsText: String = ""

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ZCodeSettingsCard(title: isNew ? "Add MCP Server" : "Edit MCP Server") {
                            VStack(alignment: .leading, spacing: 13) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Server Name")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    TextField("e.g. github or postgres", text: $draft.name)
                                        .font(.system(size: 14, design: .monospaced))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(10)
                                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                                }

                                Picker("Transport", selection: $draft.transport) {
                                    Text("stdio").tag("stdio")
                                    Text("Streamable HTTP").tag("http")
                                    Text("SSE").tag("sse")
                                }
                                .pickerStyle(.segmented)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(draft.transport == "stdio" ? "Executable Command" : "Endpoint URL")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    TextField(draft.transport == "stdio" ? "npx" : "https://example.com/mcp", text: $draft.endpointOrCommand)
                                        .font(.system(size: 13.5, design: .monospaced))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(10)
                                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                                }

                                if draft.transport == "stdio" {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Arguments (one per line or space-separated)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.foregroundSubtle)
                                        TextField("-y @modelcontextprotocol/server-github", text: $argsText, axis: .vertical)
                                            .lineLimit(2...5)
                                            .font(.system(size: 13, design: .monospaced))
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .padding(10)
                                            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(draft.transport == "stdio" ? "Environment Variables (JSON)" : "HTTP Headers (JSON)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    TextField("{\"API_KEY\": \"...\"}", text: $draft.envOrHeadersJSON, axis: .vertical)
                                        .lineLimit(2...5)
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(10)
                                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(14)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isNew ? "Add MCP Server" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                argsText = draft.args.joined(separator: " ")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.args = argsText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                        store.upsertMCPServer(draft, isNew: isNew)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.endpointOrCommand.isEmpty)
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}

struct SkillMarkdownInspectorSheet: View {
    let skill: SkillCatalogItem
    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    ZCodeSettingsCard(title: skill.name, subtitle: skill.filePath) {
                        Text(skill.markdownBody)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("SKILL.md")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}

struct SlashCommandEditorSheet: View {
    @Bindable var store: AppStore
    let isNew: Bool
    @State var draft: SlashCommandItem

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    ZCodeSettingsCard(title: isNew ? "New Slash Command" : "Edit Command") {
                        VStack(alignment: .leading, spacing: 13) {
                            TextField("/command-name", text: $draft.trigger)
                                .font(.system(size: 14, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))

                            Picker("Scope", selection: $draft.scope) {
                                Text("User (~/.zcode/commands)").tag("User")
                                Text("Project (.zcode/commands)").tag("Project")
                            }
                            .pickerStyle(.segmented)

                            TextField("Short description shown in / menu", text: $draft.summary)
                                .font(.system(size: 13.5))
                                .padding(10)
                                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))

                            TextField("Argument hint (e.g. [target-branch])", text: $draft.argumentHint)
                                .font(.system(size: 13, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))

                            TextEditor(text: $draft.promptTemplate)
                                .font(.system(size: 13, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 150)
                                .padding(8)
                                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(14)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isNew ? "New Command" : draft.trigger)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if !draft.trigger.hasPrefix("/") {
                            draft.trigger = "/\(draft.trigger)"
                        }
                        store.upsertSlashCommand(draft, isNew: isNew)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.trigger.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).isEmpty)
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}

struct HookRuleEditorSheet: View {
    @Bindable var store: AppStore
    @State var draft: HookRuleItem

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    ZCodeSettingsCard(title: "Lifecycle Hook Rule") {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                Text("Lifecycle Event")
                                    .font(.system(size: 13.5, weight: .medium))
                                Spacer()
                                Picker("Event", selection: $draft.event) {
                                    ForEach(HookRuleItem.officialEvents, id: \.self) { ev in
                                        Text(ev).tag(ev)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            Picker("Scope", selection: $draft.scope) {
                                Text("User").tag("user")
                                Text("Project").tag("project")
                            }
                            .pickerStyle(.segmented)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Tool / Pattern Matcher")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                                TextField("e.g. Bash(*) or Edit(*.swift) or *", text: $draft.matcher)
                                    .font(.system(size: 13.5, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(10)
                                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Shell Command")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                                TextField("swiftformat --lint", text: $draft.command, axis: .vertical)
                                    .lineLimit(2...4)
                                    .font(.system(size: 13, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(10)
                                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                            }

                            Toggle("Run Asynchronously (Non-blocking)", isOn: $draft.runAsync)
                                .font(.system(size: 13.5))
                                .tint(palette.accentBlue)
                        }
                        .padding(14)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Hook Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.upsertHookRule(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}
