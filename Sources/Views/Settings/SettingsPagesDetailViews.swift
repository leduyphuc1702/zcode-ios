import SwiftUI
import Charts

// MARK: - 1:1 ZCode v3.16.3 Detail Pages for All Remaining Settings Sections

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

    private static var appVersionLabel: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !build.isEmpty {
            return "v\(short) (\(build))"
        }
        return "v\(short)"
    }

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
                case .automations:
                    AutomationsSettingsSectionView(store: store)
                case .hooks:
                    hooksPage
                case .workspaceFileSearch:
                    WorkspaceFileSearchScopeSettingsView(store: store)
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
                ZCodeSettingsRow(title: "Language", subtitle: "Choose the display language used by the application UI.") {
                    ZCodeSettingsSelect(
                        options: [
                            ZCodeSettingsSelectOption(value: "system", label: "System default"),
                            ZCodeSettingsSelectOption(value: "zh-CN", label: "中文简体"),
                            ZCodeSettingsSelectOption(value: "en-US", label: "English")
                        ],
                        selection: Binding(
                            get: {
                                switch store.language {
                                case .chineseSimplified: return "zh-CN"
                                case .english: return "en-US"
                                case .vietnamese: return "system"
                                }
                            },
                            set: { newValue in
                                switch newValue {
                                case "zh-CN": store.language = .chineseSimplified
                                case "en-US": store.language = .english
                                default: store.language = .english
                                }
                                let resolved = newValue == "system" ? store.language.rawValue : newValue
                                Task {
                                    _ = await store.updateDesktopSetting([
                                        "localePreference": newValue,
                                        "locale": resolved
                                    ])
                                }
                            }
                        )
                    )
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(title: "Interface mode", subtitle: "Switch between software engineering workspace and document/office mode.") {
                    ZCodeSettingsSelect(
                        options: [
                            ZCodeSettingsSelectOption(value: "coding", label: "Coding mode"),
                            ZCodeSettingsSelectOption(value: "office", label: "Office mode")
                        ],
                        selection: Binding(
                            get: { store.interfaceMode },
                            set: { store.interfaceMode = $0 }
                        )
                    )
                }
            }

            // Agent Interaction & Search
            ZCodeSettingsCard(title: "Agent Interaction & Tool Execution") {
                ZCodeSettingsRow(
                    title: "Interaction behavior",
                    subtitle: "While ZCode is running, add follow-up actions to the queue or guide them to run after the next tool call."
                ) {
                    ZCodeSettingsSelect(
                        options: [
                            ZCodeSettingsSelectOption(value: "queue", label: "Queue"),
                            ZCodeSettingsSelectOption(value: "guide", label: "Guide")
                        ],
                        selection: Binding(
                            get: { store.zcodeInteractionBehavior },
                            set: { val in
                                store.zcodeInteractionBehavior = val
                                Task { _ = await store.updateDesktopSetting(["zcodeInteractionBehavior": val]) }
                            }
                        ),
                        isEnabled: store.isRemoteRPCReady
                    )
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Tool search",
                    subtitle: "Load MCP and extended tool schemas on demand to preserve context window."
                ) {
                    ZCodeSettingsSelect(
                        options: [
                            ZCodeSettingsSelectOption(value: "auto", label: "Auto"),
                            ZCodeSettingsSelectOption(value: "local", label: "Local"),
                            ZCodeSettingsSelectOption(value: "off", label: "Off")
                        ],
                        selection: Binding(
                            get: { store.toolSearchMode },
                            set: { val in
                                store.toolSearchMode = val
                                Task { _ = await store.updateDesktopSetting(["toolSearchMode": val]) }
                            }
                        ),
                        isEnabled: store.isRemoteRPCReady
                    )
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Dynamic workflows",
                    subtitle: "Allow the agent to orchestrate typed subagent fan-out workflows."
                ) {
                    ZCodeSettingsSelect(
                        options: [
                            ZCodeSettingsSelectOption(value: "disabled", label: "Off"),
                            ZCodeSettingsSelectOption(value: "onDemand", label: "On command"),
                            ZCodeSettingsSelectOption(value: "alwaysOn", label: "Always on")
                        ],
                        selection: Binding(
                            get: { store.dynamicWorkflowMode },
                            set: { val in
                                store.dynamicWorkflowMode = val
                                Task { _ = await store.updateDesktopSetting(["dynamicWorkflowMode": val]) }
                            }
                        ),
                        isEnabled: store.isRemoteRPCReady
                    )
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
                            Task { _ = await store.updateDesktopSetting(["askUserQuestionAutoResolutionEnabled": val]) }
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                    .disabled(!store.isRemoteRPCReady)
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
                            Task { _ = await store.updateDesktopSetting(["nativeSearchEnhancementsEnabled": val]) }
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                    .disabled(!store.isRemoteRPCReady)
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
                            Task { _ = await store.updateDesktopSetting(["keepAwakeWhileRunning": val]) }
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                    .disabled(!store.isRemoteRPCReady)
                }
            }

            // Haptics (client-local; notification scheduling is not implemented in this client)
            ZCodeSettingsCard(title: "Haptics") {
                ZCodeSettingsRow(title: "Tactile haptic feedback", subtitle: "Subtle haptics on tool approvals, checkpoints, and mode switches.") {
                    Toggle("", isOn: $store.hapticsEnabled)
                        .labelsHidden()
                        .tint(palette.accentBlue)
                }
            }

            // Network Proxy & Mobile App Lock
            ZCodeSettingsCard(title: "Network Proxy & Mobile Security") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HTTP Proxy")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    TextField("http://127.0.0.1:7890 (leave empty for direct)", text: $store.httpProxyURL)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(9)
                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))

                    Text("No proxy")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    TextField("localhost, 127.0.0.1", text: $store.httpProxyNoProxy)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(9)
                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))

                    Text("Custom certificate")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    TextField("Path to CA certificate", text: $store.httpProxyCaCertPath)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(9)
                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))

                    Button {
                        let proxy = store.httpProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        let noProxy = store.httpProxyNoProxy.trimmingCharacters(in: .whitespacesAndNewlines)
                        let ca = store.httpProxyCaCertPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        var patch: [String: Any] = [:]
                        patch["httpProxy"] = proxy.isEmpty ? NSNull() : proxy
                        patch["httpProxyNoProxy"] = noProxy.isEmpty ? NSNull() : noProxy
                        patch["httpProxyCaCertPath"] = ca.isEmpty ? NSNull() : ca
                        Task { _ = await store.updateDesktopSetting(patch, successMessage: "HTTP proxy saved") }
                    } label: {
                        Text("Save")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.brandForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.isRemoteRPCReady)
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
                ZCodeSettingsRow(title: "Version", subtitle: "100% native SwiftUI • no WebView") {
                    ZCodeSettingsPill(text: Self.appVersionLabel, tone: .accent)
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
                        ZCodeSettingsSelect(
                            options: ZCodeSyntaxTheme.allCases.map {
                                ZCodeSettingsSelectOption(value: $0, label: $0.displayName)
                            },
                            selection: $store.syntaxTheme
                        )
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
                            Task { _ = await store.updateDesktopSetting(["embeddedBrowserAllowInsecureCertificates": val]) }
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                    .disabled(!store.isRemoteRPCReady)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(
                    title: "Browser data",
                    subtitle: "Browser data can only be managed in the ZCode desktop app."
                ) {
                    EmptyView()
                }
            }
        }
    }

    // MARK: - 4. Remote Devices (`remoteDevices`)

    private var remoteDevicesPage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Basics",
                title: "Remote devices",
                subtitle: "Manage your servers, WSL distributions, and Docker containers."
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
                                Text(conn.serverVersion.isEmpty ? conn.host : "\(conn.host) • v\(conn.serverVersion)")
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

            ZCodeSettingsCard(title: "Computer Use") {
                ZCodeSettingsRow(
                    title: "Show Computer Use button in the composer",
                    subtitle: "When off, the composer button is hidden."
                ) {
                    Toggle("", isOn: Binding(
                        get: { !store.computerUseComposerEntryHidden },
                        set: { visible in
                            store.computerUseComposerEntryHidden = !visible
                            Task { _ = await store.updateDesktopSetting(["computerUseComposerEntryHidden": !visible]) }
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                    .disabled(!store.isRemoteRPCReady)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(title: "Accessibility permission", subtitle: "macOS AXUIElement control on the paired host. Check it in System Settings on your computer.") {
                    ZCodeSettingsPill(text: "Unknown", tone: .neutral)
                }

                Divider().overlay(palette.border)

                ZCodeSettingsRow(title: "Screen Recording permission", subtitle: "Required for high-DPI desktop visual grounding. Check it in System Settings on your computer.") {
                    ZCodeSettingsPill(text: "Unknown", tone: .neutral)
                }
            }
        }
    }

    // MARK: - 6. Keyboard Shortcuts (`shortcuts`)

    private var shortcutsPage: some View {
        let q = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostBindings = store.shortcutBindings
        let source = hostBindings.isEmpty ? ShortcutBindingItem.officialDefaults : hostBindings
        let filtered = source.filter {
            q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || $0.category.localizedCaseInsensitiveContains(q) || $0.activeBinding.localizedCaseInsensitiveContains(q)
        }
        let categories = ["Global", "Window", "Workspace", "Composer", "Desktop"]

        return Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Basics",
                title: "Keyboard Shortcuts",
                subtitle: hostBindings.isEmpty
                    ? "ZCode Desktop default shortcuts. No custom bindings are stored on the host."
                    : "Shortcuts stored on your ZCode Desktop host."
            )

            ZCodeSettingsSearchBar(text: $searchFilter, placeholder: "Search shortcuts")

            ForEach(categories, id: \.self) { cat in
                let items = filtered.filter { $0.category == cat }
                if !items.isEmpty {
                    ZCodeSettingsCard(title: cat, subtitle: "Shortcuts apply to the ZCode desktop app and are read-only here.") {
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

            if filtered.isEmpty {
                Text("No matching shortcuts")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    // MARK: - 7. Memory (`memory`)

    private var memoryPage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "Memory",
                subtitle: "Save and reuse long-term context in workspaces. Applies to new sessions and may increase model requests and token costs."
            ) {
                Button("Save") {
                    let content = store.userMemoryMarkdown
                    Task { _ = await store.saveUserMemoryMarkdown(content) }
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
                            Task { _ = await store.updateDesktopSetting(["memoryEnabled": val]) }
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                    .disabled(!store.isRemoteRPCReady)
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
                subtitle: "Enable or disable installed plugins. Plugins bundle skills, commands, hooks, and MCP servers."
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
                if !pl.version.isEmpty {
                    ZCodeSettingsPill(text: "v\(pl.version)", tone: .neutral)
                }
                ForEach(pl.componentBadges.prefix(3), id: \.self) { b in
                    ZCodeSettingsPill(text: b, tone: .accent)
                }
                Spacer()
                if isInstalled {
                    Toggle("", isOn: Binding(
                        get: { pl.enabled },
                        set: { newValue in Task { _ = await store.setPluginEnabled(pl, enabled: newValue) } }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                    .disabled(!store.isRemoteRPCReady)
                } else {
                    Button {
                        Task { _ = await store.installPlugin(pl) }
                    } label: {
                        Text("Install")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.brandForeground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(palette.brand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.isRemoteRPCReady || pl.marketplace.isEmpty)
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
                subtitle: "Manage MCP server configurations used by ZCode Agent."
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
                            Task { await applyRawMCPJsonString() }
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
                                        set: { newValue in Task { _ = await store.setMCPServerEnabled(srv, enabled: newValue) } }
                                    ))
                                    .labelsHidden()
                                    .tint(palette.accentBlue)
                                    .disabled(!store.isRemoteRPCReady)
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
                                        Task { _ = await store.deleteMCPServer(srv) }
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

    private func applyRawMCPJsonString() async {
        guard let data = rawMcpJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = (obj["mcpServers"] as? [String: [String: Any]]) ?? (obj as? [String: [String: Any]]) else {
            store.showToast("Invalid JSON syntax")
            return
        }
        let desiredNames = Set(servers.keys)
        for existing in store.mcpServers where !desiredNames.contains(existing.name) {
            _ = await store.deleteMCPServer(existing)
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
            _ = await store.upsertMCPServer(draft, isNew: true)
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
                subtitle: "Manage workspace and user skills. Enabled skills can be referenced in chat with $skill-name."
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
                                set: { newValue in Task { _ = await store.setSkillEnabled(sk, enabled: newValue) } }
                            ))
                            .labelsHidden()
                            .tint(palette.accentBlue)
                            .disabled(!store.isRemoteRPCReady)
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

        return Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "Commands",
                subtitle: "Manage ZCode Agent .md command files. Commands can be invoked with /command-name in chat."
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
                                Task { _ = await store.deleteSlashCommand(cmd) }
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

        }
    }

    // MARK: - 12. Hooks (`hooks`)

    private var hooksPage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "Hooks",
                subtitle: "Manage task lifecycle hooks to automatically execute commands on specific events."
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

            if !store.pendingHookTrustItems.isEmpty {
                ZCodeSettingsCard(
                    title: "Workspace hook trust",
                    subtitle: "This workspace declares hooks that need review before they run."
                ) {
                    ZCodeSettingsRow(
                        title: "\(store.pendingHookTrustItems.count) hook declaration\(store.pendingHookTrustItems.count == 1 ? "" : "s") pending",
                        subtitle: "Trusting runs these hooks in new sessions for this workspace."
                    ) {
                        Button("Trust") {
                            Task { _ = await store.grantPendingWorkspaceHookTrust() }
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.brandForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .buttonStyle(.plain)
                        .disabled(!store.isRemoteRPCReady)
                    }
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
                                        Task { _ = await store.upsertHookRule(updated) }
                                    }
                                ))
                                .labelsHidden()
                                .tint(palette.accentBlue)
                                .disabled(!store.isRemoteRPCReady || !hk.editable)
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
                                        Task { _ = await store.deleteHookRule(hk) }
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

    // MARK: - 13. Usage stats (`usage`) — real host snapshots only

    private var usageStatsPage: some View {
        Group {
            ZCodeSettingsPageHeader(
                groupTitle: "Data and statistics",
                title: "Usage stats",
                subtitle: "Review activity and model usage aggregated from local sessions."
            ) {
                HStack(spacing: 8) {
                    ZCodeSettingsSelect(
                        options: [
                            ZCodeSettingsSelectOption(value: "7d", label: "Last 7 days"),
                            ZCodeSettingsSelectOption(value: "30d", label: "Last 30 days")
                        ],
                        selection: Binding(
                            get: { usageRange },
                            set: { usageRange = $0 }
                        ),
                        isEnabled: store.isRemoteRPCReady
                    )

                    Button {
                        Task {
                            await store.syncUsageStatsRPC(range: usageRange)
                            if usageTab == "plan" { await store.syncCodingPlanEntitlementRPC() }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 30, height: 30)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.isRemoteRPCReady)
                    .accessibilityLabel("Refresh usage")
                }
            }

            if store.isZaiAuthenticated {
                Picker("Usage tab", selection: $usageTab) {
                    Text("App usage").tag("app")
                    Text("Individual Plan").tag("plan")
                }
                .pickerStyle(.segmented)
            } else {
                Picker("Usage tab", selection: $usageTab) {
                    Text("App usage").tag("app")
                }
                .pickerStyle(.segmented)
                .disabled(true)
            }

            if usageTab == "plan", store.isZaiAuthenticated {
                codingPlanEntitlementSection
            } else {
                appUsageSection
            }
        }
        .task(id: usageRange) {
            await store.syncUsageStatsRPC(range: usageRange)
        }
        .onChange(of: usageTab) { _, tab in
            if tab == "plan" { Task { await store.syncCodingPlanEntitlementRPC() } }
        }
    }

    @ViewBuilder
    private var appUsageSection: some View {
        if store.usageStatsLoading && store.usageStatsSnapshot == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Computing usage…")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let error = store.usageStatsError {
            ZCodeSettingsCard(title: "Usage unavailable") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                    Button("Retry") {
                        Task { await store.syncUsageStatsRPC(range: usageRange) }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.accentBlue)
                }
                .padding(14)
            }
        } else if let snapshot = store.usageStatsSnapshot {
            let totalModels = snapshot.models.reduce(0) { $0 + $1.totalTokens }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                usageKpiTile(label: "Total tokens", value: Self.compactTokenCount(snapshot.totalTokens), badge: snapshot.range)
                usageKpiTile(label: "Peak day", value: Self.compactTokenCount(snapshot.peakDayTokens), badge: "Tokens")
                usageKpiTile(label: "Longest session", value: Self.durationLabel(snapshot.longestSessionMs), badge: "Duration")
                usageKpiTile(label: "Current streak", value: "\(snapshot.currentStreakDays) days", badge: "Longest \(snapshot.longestStreakDays)")
            }

            if !snapshot.models.isEmpty {
                ZCodeSettingsCard(title: "Model usage", subtitle: "Tokens per model in the selected window.") {
                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.models.sorted { $0.totalTokens > $1.totalTokens }.enumerated()), id: \.element.id) { idx, model in
                            HStack(spacing: 8) {
                                Text(model.modelId)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(palette.foreground)
                                    .lineLimit(1)
                                Spacer()
                                Text(Self.compactTokenCount(model.totalTokens))
                                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.foreground)
                                if totalModels > 0 {
                                    Text(String(format: "%.0f%%", Double(model.totalTokens) / Double(totalModels) * 100))
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(palette.foregroundMuted)
                                        .frame(width: 42, alignment: .trailing)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            if idx < snapshot.models.count - 1 {
                                Divider().overlay(palette.border).padding(.horizontal, 14)
                            }
                        }
                    }
                }
            }

            ZCodeSettingsCard(title: "Daily token usage", subtitle: "Total tokens per day in the selected window.") {
                if snapshot.dailyModelUsage.isEmpty {
                    Text("No token usage recorded in this window.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    Chart {
                        ForEach(snapshot.dailyModelUsage) { point in
                            BarMark(
                                x: .value("Day", String(point.date.suffix(5))),
                                y: .value("Tokens", point.totalTokens)
                            )
                            .foregroundStyle(palette.accentBlue)
                        }
                    }
                    .frame(height: 190)
                    .padding(14)
                }
            }
        } else {
            Text(store.isRemoteRPCReady ? "No usage stats recorded yet." : "Connect to your computer to load usage stats.")
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundSubtle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        }
    }

    @ViewBuilder
    private var codingPlanEntitlementSection: some View {
        if store.codingPlanEntitlementLoading && store.codingPlanEntitlement == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading Coding Plan entitlement…")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let error = store.codingPlanEntitlementError {
            ZCodeSettingsCard(title: "Coding Plan entitlement") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                    Button("Retry") {
                        Task { await store.syncCodingPlanEntitlementRPC() }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.accentBlue)
                }
                .padding(14)
            }
        } else if let entitlement = store.codingPlanEntitlement {
            let noPlan = entitlement.unavailableReason == "no_plan" || (entitlement.planLevel ?? "").isEmpty && entitlement.limits.isEmpty
            ZCodeSettingsCard(
                title: "Coding Plan entitlement",
                subtitle: "Synced from your connected Coding Plan account."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entitlement.planLevel ?? (noPlan ? "No active Coding Plan" : "Coding Plan"))
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(palette.foreground)
                            if !entitlement.productNames.isEmpty {
                                Text(entitlement.productNames.joined(separator: " • "))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.foregroundSubtle)
                            }
                            if let expires = entitlement.expiresAt {
                                Text("Expires \(expires)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.foregroundMuted)
                            }
                        }
                        Spacer()
                        ZCodeSettingsPill(
                            text: noPlan ? "Not subscribed" : "Active",
                            tone: noPlan ? .neutral : .success
                        )
                    }

                    if entitlement.limits.isEmpty {
                        Text(noPlan
                             ? "No connected Coding Plan quota is available for this account."
                             : "The host did not return quota limits.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.foregroundSubtle)
                    } else {
                        ForEach(entitlement.limits) { limit in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(limit.displayTitle)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    Spacer()
                                    if let pct = limit.resolvedPercentUsed {
                                        Text(String(format: "%.0f%% used", pct * 100))
                                            .font(.system(size: 11.5, design: .monospaced))
                                            .foregroundStyle(palette.foregroundMuted)
                                    }
                                }
                                if let pct = limit.resolvedPercentUsed {
                                    ProgressView(value: max(0, min(1, pct)))
                                        .tint(palette.accentBlue)
                                }
                                if let reset = limit.nextResetTime {
                                    Text("Resets \(reset)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.foregroundMuted)
                                }
                            }
                        }
                    }

                    Text("Quota values follow the current usage guide and may change with platform policy.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.foregroundMuted)
                }
                .padding(14)
            }
        } else {
            Text("No active Coding Plan")
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundSubtle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
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

    private static func compactTokenCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        if value >= 1_000_000 {
            return (formatter.string(from: NSNumber(value: Double(value) / 1_000_000)) ?? "\(value)") + "M"
        }
        if value >= 1_000 {
            return (formatter.string(from: NSNumber(value: Double(value) / 1_000)) ?? "\(value)") + "K"
        }
        return "\(value)"
    }

    private static func durationLabel(_ ms: Int) -> String {
        let minutes = max(0, ms / 60_000)
        if minutes >= 1_440 { return "\(minutes / 1_440)d \((minutes % 1_440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
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
                            Task { _ = await store.updateDesktopSetting(["taskAutoArchiveEnabled": val]) }
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                    .disabled(!store.isRemoteRPCReady)
                }

                if store.taskAutoArchiveEnabled {
                    Divider().overlay(palette.border)
                    ZCodeSettingsRow(title: "Archive tasks older than") {
                        ZCodeSettingsSelect(
                            options: [3, 7, 14, 30].map {
                                ZCodeSettingsSelectOption(value: $0, label: "\($0) days")
                            },
                            selection: Binding(
                                get: { store.taskAutoArchiveOlderThanDays },
                                set: { days in
                                    store.taskAutoArchiveOlderThanDays = days
                                    Task { _ = await store.updateDesktopSetting(["taskAutoArchiveOlderThanDays": days]) }
                                }
                            ),
                            isEnabled: store.isRemoteRPCReady
                        )
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

                                HStack {
                                    Text("Type")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                    ZCodeSettingsSelect(
                                        options: [
                                            ZCodeSettingsSelectOption(value: "stdio", label: "stdio"),
                                            ZCodeSettingsSelectOption(value: "http", label: "Streamable HTTP"),
                                            ZCodeSettingsSelectOption(value: "sse", label: "SSE")
                                        ],
                                        selection: $draft.transport
                                    )
                                }

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
                        let snapshot = draft
                        Task {
                            if await store.upsertMCPServer(snapshot, isNew: isNew) {
                                await MainActor.run { dismiss() }
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.endpointOrCommand.isEmpty || !store.isRemoteRPCReady)
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

// MARK: - Automations (settings section, real zcode-agent RPC)

struct AutomationsSettingsSectionView: View {
    @Bindable var store: AppStore

    @Environment(\.zcodePalette) private var palette
    @State private var showNewAutomation = false
    @State private var editingAutomation: AutomationScheduleItem?
    @State private var pendingDelete: AutomationScheduleItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZCodeSettingsPageHeader(
                groupTitle: "Agent capabilities",
                title: "Automations",
                subtitle: SettingsSectionKind.automations.headerDescription
            ) {
                HStack(spacing: 8) {
                    ZCodeSettingsPill(text: "Beta", tone: .accent)
                    Button {
                        showNewAutomation = true
                    } label: {
                        Label("New scheduled task", systemImage: "plus")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!store.canManageAutomations || store.automations.count >= 20)
                }
            }

            ZCodeSettingsCard(
                title: "Scheduled tasks",
                subtitle: "Run tasks on a schedule or whenever you need them."
            ) {
                if !store.canManageAutomations {
                    Text(store.isRemoteRPCReady
                         ? "Open an available project before creating a scheduled task."
                         : "Connect to your computer to manage scheduled tasks.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else if store.isLoadingAutomations && store.automations.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else if store.automations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No scheduled tasks yet.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                        Text("Create a task to run a prompt on a recurring schedule.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.foregroundSubtle)
                        Button("Create manually") { showNewAutomation = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 4)
                    }
                    .padding(16)
                } else {
                    ForEach(Array(store.automations.enumerated()), id: \.element.id) { idx, auto in
                        automationRow(auto)
                        if idx < store.automations.count - 1 {
                            Divider().overlay(palette.border).padding(.horizontal, 14)
                        }
                    }
                }

                if let error = store.automationsError, !error.isEmpty {
                    Divider().overlay(palette.border)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.destructive)
                        .padding(14)
                }
            }

            Text("Up to 20 scheduled tasks per workspace, including paused, completed, and failed tasks.")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.foregroundMuted)
        }
        .task { await store.loadAutomations() }
        .sheet(isPresented: $showNewAutomation) {
            ZCodeSettingsAutomationEditorSheet(store: store, existing: nil)
        }
        .sheet(item: $editingAutomation) { auto in
            ZCodeSettingsAutomationEditorSheet(store: store, existing: auto)
        }
        .confirmationDialog(
            "Delete scheduled task",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { auto in
            Button("Delete", role: .destructive) {
                pendingDelete = nil
                Task { await store.deleteAutomation(id: auto.id) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { auto in
            Text("Delete “\(auto.name)”? This cannot be undone.")
        }
    }

    private func automationRow(_ auto: AutomationScheduleItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(auto.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                    Text(auto.cronExpression)
                        .font(.system(size: 11.5, design: .monospaced))
                    Text("·")
                    Text(URL(fileURLWithPath: auto.workspacePath).lastPathComponent)
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(palette.foregroundSubtle)
                Text(auto.lastRunStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.foregroundMuted)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { auto.enabled },
                set: { newValue in
                    Task { await store.setAutomationEnabled(id: auto.id, enabled: newValue) }
                }
            ))
            .labelsHidden()
            .tint(palette.accentBlue)

            Menu {
                Button {
                    Task { await store.runAutomationNow(id: auto.id) }
                } label: {
                    Label("Run now", systemImage: "play")
                }
                Button {
                    editingAutomation = auto
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    pendingDelete = auto
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct ZCodeSettingsAutomationEditorSheet: View {
    @Bindable var store: AppStore
    let existing: AutomationScheduleItem?

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var cron: String
    @State private var prompt: String
    @State private var isSaving = false

    init(store: AppStore, existing: AutomationScheduleItem?) {
        self.store = store
        self.existing = existing
        _title = State(initialValue: existing?.name ?? "")
        _cron = State(initialValue: existing?.cronExpression ?? "0 9 * * 1-5")
        _prompt = State(initialValue: existing?.prompt ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cron.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    ZCodeSettingsCard(title: existing == nil ? "New scheduled task" : "Edit scheduled task") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Task title")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                                TextField("e.g. Daily standup summary", text: $title)
                                    .font(.system(size: 13.5))
                                    .padding(10)
                                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Schedule (cron)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                                TextField("0 9 * * 1-5", text: $cron)
                                    .font(.system(size: 13.5, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(10)
                                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                                Text("Runs in the workspace’s timezone. Weekdays at 09:00 is `0 9 * * 1-5`.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.foregroundMuted)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Instruction")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                                TextEditor(text: $prompt)
                                    .font(.system(size: 13))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 150)
                                    .padding(8)
                                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                            }

                            if let error = store.automationsError, !error.isEmpty {
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.destructive)
                            }
                        }
                        .padding(14)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(existing == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving…" : "Save") {
                        let snapshotTitle = title
                        let snapshotCron = cron
                        let snapshotPrompt = prompt
                        Task {
                            isSaving = true
                            let ok: Bool
                            if let existing {
                                ok = await store.updateAutomation(
                                    id: existing.id,
                                    title: snapshotTitle,
                                    cronExpr: snapshotCron,
                                    prompt: snapshotPrompt
                                )
                            } else {
                                ok = await store.createAutomation(
                                    title: snapshotTitle,
                                    cronExpr: snapshotCron,
                                    prompt: snapshotPrompt
                                )
                            }
                            isSaving = false
                            if ok { dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}

// MARK: - Workspace Search Scope (.zcodeignore, real file-channel RPC)

struct WorkspaceFileSearchScopeSettingsView: View {
    @Bindable var store: AppStore

    @Environment(\.zcodePalette) private var palette
    @State private var content = ""
    @State private var savedContent = ""
    @State private var source: String?
    @State private var isLoading = false
    @State private var isSaving = false

    private var workspacePath: String { store.currentWorkspaceContext.path }
    private var hasUnsavedChanges: Bool { source == "file" && content != savedContent }
    private var canSave: Bool { source != nil && (source == "template" || content != savedContent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZCodeSettingsPageHeader(
                groupTitle: "Basics",
                title: "Workspace Search Scope",
                subtitle: SettingsSectionKind.workspaceFileSearch.headerDescription
            )

            if workspacePath.isEmpty {
                ZCodeSettingsCard(title: "Workspace Search Scope") {
                    Text("Open a workspace to edit its search ignore rules.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                ZCodeSettingsCard(title: ".zcodeignore", subtitle: workspacePath) {
                    VStack(alignment: .leading, spacing: 12) {
                        if isLoading && source == nil {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(28)
                        } else {
                            if source == "template" {
                                Text(".zcodeignore does not exist yet: the content below is the initial preview (.gitignore copy + default exclusions); it is written to the workspace only after saving.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.foregroundSubtle)
                            }

                            TextEditor(text: $content)
                                .font(.system(size: 12.5, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 230)
                                .padding(8)
                                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                                .disabled(isLoading || isSaving || !store.isRemoteRPCReady)

                            HStack(spacing: 8) {
                                Button {
                                    save()
                                } label: {
                                    Label("Save", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!canSave || isLoading || isSaving || !store.isRemoteRPCReady)

                                Button {
                                    apply("sync-gitignore")
                                } label: {
                                    Label("Sync from .gitignore", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isLoading || isSaving || !store.isRemoteRPCReady)

                                Button {
                                    apply("reset-defaults")
                                } label: {
                                    Label("Restore default rules", systemImage: "arrow.counterclockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isLoading || isSaving || !store.isRemoteRPCReady)

                                Spacer(minLength: 4)

                                if hasUnsavedChanges {
                                    Text("Unsaved changes")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(palette.foregroundMuted)
                                }
                            }
                        }
                    }
                    .padding(14)
                }

                Text(".zcodeignore applies to workspace file search and takes effect on the next search after saving.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.foregroundMuted)
            }
        }
        .task(id: workspacePath) { await load() }
    }

    private func load() async {
        guard !workspacePath.isEmpty, store.isRemoteRPCReady else { return }
        isLoading = true
        if let snapshot = await store.readWorkspaceFileSearchIgnore(rootPath: workspacePath) {
            content = snapshot.content
            savedContent = snapshot.content
            source = snapshot.source
        }
        isLoading = false
    }

    private func save() {
        let snapshot = content
        Task {
            isSaving = true
            if await store.writeWorkspaceFileSearchIgnore(rootPath: workspacePath, content: snapshot) {
                savedContent = snapshot
                source = "file"
            }
            isSaving = false
        }
    }

    private func apply(_ transform: String) {
        Task {
            isLoading = true
            if let transformed = await store.applyWorkspaceFileSearchIgnoreTransform(
                rootPath: workspacePath,
                transform: transform
            ) {
                content = transformed
            }
            isLoading = false
        }
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

                            HStack {
                                Text("Scope")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(palette.foreground)
                                Spacer()
                                ZCodeSettingsSelect(
                                    options: [
                                        ZCodeSettingsSelectOption(value: "User", label: "User (~/.zcode/commands)"),
                                        ZCodeSettingsSelectOption(value: "Project", label: "Project (.zcode/commands)")
                                    ],
                                    selection: $draft.scope
                                )
                            }

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
                        let snapshot = draft
                        Task {
                            if await store.upsertSlashCommand(snapshot, isNew: isNew) {
                                await MainActor.run { dismiss() }
                            }
                        }
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
                                ZCodeSettingsSelect(
                                    options: HookRuleItem.officialEvents.map {
                                        ZCodeSettingsSelectOption(value: $0, label: $0)
                                    },
                                    selection: $draft.event
                                )
                            }

                            HStack {
                                Text("Scope")
                                    .font(.system(size: 13.5, weight: .medium))
                                Spacer()
                                ZCodeSettingsSelect(
                                    options: [
                                        ZCodeSettingsSelectOption(value: "user", label: "User"),
                                        ZCodeSettingsSelectOption(value: "project", label: "Project")
                                    ],
                                    selection: $draft.scope
                                )
                            }

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
                        let snapshot = draft
                        Task {
                            if await store.upsertHookRule(snapshot) {
                                await MainActor.run { dismiss() }
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}
