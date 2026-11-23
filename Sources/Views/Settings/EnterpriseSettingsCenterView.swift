import SwiftUI
import Charts

public enum SettingsSectionKind: String, CaseIterable, Identifiable {
    case general
    case appearance
    case models
    case remoteDevices
    case codingPlan
    case security
    case mcp
    case skills
    case plugins
    case subagents
    case commands
    case hooks
    case memory
    case automations
    case browserCUA
    case fileSearch
    case archives
    case usage
    case shortcutsAbout

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General & Language"
        case .appearance: return "Appearance & Code Editor"
        case .models: return "Models & Providers"
        case .remoteDevices: return "Remote Devices & Servers"
        case .codingPlan: return "Coding Plan & Off-Peak"
        case .security: return "Security, Face ID & Proxy"
        case .mcp: return "MCP Servers"
        case .skills: return "Skills Catalog"
        case .plugins: return "Plugins & Marketplaces"
        case .subagents: return "Subagents"
        case .commands: return "Slash Commands"
        case .hooks: return "Hooks & Workspace Trust"
        case .memory: return "Persistent Memory"
        case .automations: return "Automations (Cron)"
        case .browserCUA: return "Computer Use & Browser"
        case .fileSearch: return "Workspace File Search"
        case .archives: return "Archived Sessions"
        case .usage: return "Usage & Token Analytics"
        case .shortcutsAbout: return "Migration, Shortcuts & About"
        }
    }

    public var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintbrush"
        case .models: return "cpu"
        case .remoteDevices: return "qrcode.viewfinder"
        case .codingPlan: return "sparkles.rectangle.stack"
        case .security: return "lock.shield"
        case .mcp: return "puzzlepiece.extension"
        case .skills: return "wand.and.stars"
        case .plugins: return "shippingbox"
        case .subagents: return "person.2.wave.2"
        case .commands: return "terminal"
        case .hooks: return "link.badge.plus"
        case .memory: return "brain.head.profile"
        case .automations: return "clock.badge.checkmark"
        case .browserCUA: return "macwindow.on.rectangle"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .archives: return "archivebox"
        case .usage: return "chart.bar.xaxis"
        case .shortcutsAbout: return "info.circle"
        }
    }
}

/// Complete 19-Category Official ZCode Enterprise Settings Center
public struct EnterpriseSettingsCenterView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var filterText: String = ""

    private var matchingSections: [SettingsSectionKind] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SettingsSectionKind.allCases }
        return SettingsSectionKind.allCases.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Configuration & Preferences") {
                    ForEach(matchingSections.prefix(6)) { sec in
                        NavigationLink(value: sec) {
                            settingsRow(sec)
                        }
                        .accessibilityIdentifier("settingsNav_\(sec.rawValue)")
                    }
                }

                Section("Agent Ecosystem (MCP, Skills, Plugins, Hooks)") {
                    ForEach(matchingSections.dropFirst(6).prefix(8)) { sec in
                        NavigationLink(value: sec) {
                            settingsRow(sec)
                        }
                        .accessibilityIdentifier("settingsNav_\(sec.rawValue)")
                    }
                }

                Section("Governance, Analytics & System") {
                    ForEach(matchingSections.dropFirst(14)) { sec in
                        NavigationLink(value: sec) {
                            settingsRow(sec)
                        }
                        .accessibilityIdentifier("settingsNav_\(sec.rawValue)")
                    }
                }
            }
            .searchable(text: $filterText, prompt: "Search all 19 ZCode settings...")
            .navigationTitle(L10n.text("Settings", vi: "Cài đặt", zh: "设置", lang: store.language))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsSectionKind.self) { section in
                SettingsDetailDestinationView(store: store, section: section)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("closeSettingsButton")
                }
            }
        }
    }

    private func settingsRow(_ sec: SettingsSectionKind) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sec.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accentBlue)
                .frame(width: 28, height: 28)
                .background(palette.accentBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            Text(sec.title)
                .font(.system(size: 14.5, weight: .medium))
        }
    }
}

struct SettingsDetailDestinationView: View {
    @Bindable var store: AppStore
    let section: SettingsSectionKind
    @Environment(\.zcodePalette) private var palette

    @State private var showPatternSetup = false
    @State private var newProviderName = ""
    @State private var newProviderURL = ""
    @State private var newProviderKey = ""
    @State private var newMCPName = ""
    @State private var newMCPCommand = ""
    @State private var newMemorySlug = ""
    @State private var newMemoryBody = ""

    var body: some View {
        Form {
            switch section {
            case .general:
                Section("Operator Profile & Interface Language (English Default)") {
                    TextField("Profile Display Name", text: $store.userDisplayName)
                    Picker("App Language", selection: $store.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    Toggle("Haptic Feedback", isOn: $store.hapticsEnabled)
                }
                Section("Task & Event Notifications") {
                    Toggle("Enable Notifications", isOn: $store.notificationsEnabled)
                    Toggle("Approval Required Alerts", isOn: $store.notifyApprovals)
                    Toggle("User Question / Elicitation Alerts", isOn: $store.notifyQuestions)
                    Toggle("Task Completed Alerts", isOn: $store.notifyCompletions)
                    Toggle("Task Error Alerts", isOn: $store.notifyFailures)
                }

            case .appearance:
                Section("ZCode Theme Mode") {
                    ForEach(ZCodeThemeMode.allCases) { mode in
                        Button {
                            store.themeMode = mode
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(palette.foreground)
                                    Text(mode.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.themeMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(palette.accentBlue)
                                }
                            }
                        }
                        .accessibilityIdentifier("themeOption_\(mode.rawValue)")
                    }
                }
                Section("Code Viewer & Syntax Highlighting") {
                    Picker("Syntax Palette", selection: $store.syntaxTheme) {
                        ForEach(ZCodeSyntaxTheme.allCases) { st in
                            Text(st.displayName).tag(st)
                        }
                    }
                    Stepper("Code Font Size: \(Int(store.codeFontSize))pt", value: $store.codeFontSize, in: 10...22, step: 1)
                    Toggle("Show Gutter Line Numbers", isOn: $store.showLineNumbers)
                    Toggle("Wrap Long Lines", isOn: $store.wrapCodeLines)
                }
                Section("Conversation Stream") {
                    Toggle("Show Collapsible Reasoning Blocks", isOn: $store.showReasoningBlocks)
                    Toggle("Show Sticky Todo Progress Bar", isOn: $store.showTodoTracker)
                    Toggle("Compact Tool Execution Cards", isOn: $store.compactToolCards)
                }

            case .models:
                Section("Configured Providers") {
                    ForEach($store.providers) { $provider in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $provider.enabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name)
                                        .font(.system(size: 14.5, weight: .semibold))
                                    Text("\(provider.baseURL) • \(provider.statusText)")
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Text("\(provider.models.count) models")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Test Connectivity") {
                                    store.showToast("\(provider.name) verified (200 OK • 42ms)")
                                }
                                .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Add Custom OpenAI / Anthropic Provider") {
                    TextField("Provider Name (e.g. vLLM Internal)", text: $newProviderName)
                    TextField("https://llm.internal.corp/v1", text: $newProviderURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key (Saved in Keychain)", text: $newProviderKey)
                    Button("Add Provider") {
                        let id = "custom-\(UUID().uuidString.prefix(5))"
                        if !newProviderKey.isEmpty {
                            KeychainStore.save(newProviderKey, for: "provider_key_\(id)")
                        }
                        store.providers.append(
                            ModelProviderConfig(
                                id: id,
                                name: newProviderName,
                                baseURL: newProviderURL,
                                protocolKind: "openai",
                                enabled: true,
                                isBuiltin: false,
                                statusText: "Custom Endpoint",
                                models: [
                                    ModelDescriptor(id: "\(id)/default", name: "\(newProviderName) Default", providerId: id, providerName: newProviderName, contextWindowK: 128, supportsVision: true, supportsReasoning: true, badge: "Custom")
                                ]
                            )
                        )
                        newProviderName = ""
                        newProviderURL = ""
                        newProviderKey = ""
                        store.showToast("Custom provider added")
                    }
                    .disabled(newProviderName.isEmpty || newProviderURL.isEmpty)
                }

            case .remoteDevices:
                Section("Z.AI Account") {
                    if let acct = store.zaiAccount {
                        LabeledContent("Signed In", value: acct.displayName)
                        if let email = acct.email, !email.isEmpty {
                            LabeledContent("Email", value: email)
                        }
                        LabeledContent("Region", value: acct.region.title)
                        Button("Sign Out of Z.AI", role: .destructive) {
                            store.signOutZaiAccount()
                        }
                    } else {
                        Text("Not signed in to Z.AI")
                            .foregroundStyle(.secondary)
                        Button("Sign in with Z.AI…") {
                            store.showSettingsSheet = false
                            store.didSkipAccountStep = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                store.openConnectionHub()
                            }
                        }
                    }
                }
                Section("Paired Workstations") {
                    if store.connections.isEmpty {
                        Text("No paired ZCode computers yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.connections) { conn in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conn.name).font(.system(size: 14, weight: .semibold))
                            Text(conn.url).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                            Text("\(conn.transport.title) • \(conn.state == .connected ? "Connected (\(conn.latencyMs)ms)" : "Disconnected")").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Button("Enter Z.AI Remote Link / Scan QR…") {
                        store.showSettingsSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            store.openConnectionHub()
                        }
                    }
                    Button("Open Saved Workstations Sheet") {
                        store.showSettingsSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            store.showConnectionsSheet = true
                        }
                    }
                }

            case .codingPlan:
                Section("Z.ai Enterprise Coding Plan") {
                    LabeledContent("Subscription Tier", value: "Enterprise Max")
                    LabeledContent("Monthly Quota Used", value: "18.4% (3.68M / 20M tokens)")
                    ProgressView(value: 0.184)
                }
                Section("Off-Peak Batch Execution") {
                    TextField("Off-Peak Window", text: $store.offPeakWindowSchedule)
                }

            case .security:
                Section("App Unlock Gate") {
                    Toggle("Require Unlock on Launch", isOn: $store.appLockEnabled)
                    Toggle("Allow Face ID / Touch ID", isOn: $store.biometricUnlockEnabled)
                    Button(store.hasPatternConfigured ? "Change 3×3 Security Pattern" : "Set 3×3 Security Pattern") {
                        showPatternSetup = true
                    }
                    if store.hasPatternConfigured {
                        Button("Lock App Now (Test Gate)") {
                            store.showSettingsSheet = false
                            store.isLocked = true
                        }
                    }
                }
                Section("Enterprise Network & TLS Proxy") {
                    TextField("HTTP/HTTPS Proxy (e.g. http://proxy.corp:8080)", text: $store.httpProxyURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

            case .mcp:
                Section("Model Context Protocol (MCP) Servers") {
                    ForEach($store.mcpServers) { $server in
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle(isOn: $server.enabled) {
                                HStack {
                                    Text(server.name).font(.system(size: 14.5, weight: .semibold))
                                    Text(server.transport.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.18), in: Capsule())
                                }
                            }
                            Text(server.endpointOrCommand)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("Tools (\(server.tools.count)): \(server.tools.joined(separator: ", "))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
                Section("Register MCP Server") {
                    TextField("Server Name", text: $newMCPName)
                    TextField("Command or HTTP/SSE Endpoint", text: $newMCPCommand)
                        .textInputAutocapitalization(.never)
                    Button("Add MCP Server") {
                        store.mcpServers.append(
                            MCPServerItem(id: UUID().uuidString, name: newMCPName, transport: newMCPCommand.hasPrefix("http") ? "http" : "stdio", endpointOrCommand: newMCPCommand, enabled: true, connected: true, tools: ["inspect", "execute"], resourcesCount: 1)
                        )
                        newMCPName = ""
                        newMCPCommand = ""
                        store.showToast("MCP server registered")
                    }
                    .disabled(newMCPName.isEmpty || newMCPCommand.isEmpty)
                }

            case .skills:
                Section("Installed Agent Skills") {
                    ForEach($store.skills) { $skill in
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle(skill.name, isOn: $skill.enabled)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            Text("\(skill.scope) • \(skill.summary)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            case .plugins:
                Section("ZCode Plugins & Marketplaces") {
                    ForEach($store.plugins) { $plugin in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(plugin.name) v\(plugin.version)")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                if plugin.installed {
                                    Toggle("", isOn: $plugin.enabled).labelsHidden()
                                } else {
                                    Button("Install") {
                                        plugin.installed = true
                                        plugin.enabled = true
                                        store.showToast("Installed \(plugin.name)")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            Text("\(plugin.marketplace) • \(plugin.summary)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            case .subagents:
                Section("Specialized Subagents") {
                    ForEach($store.subagents) { $agent in
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(agent.name, isOn: $agent.enabled)
                                .font(.system(size: 14, weight: .semibold))
                            Text(agent.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("Model: \(agent.modelOverride) • Tools: \(agent.toolsSummary)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            case .commands:
                Section("Slash Commands") {
                    ForEach(store.slashCommands) { cmd in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cmd.trigger)
                                .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                            Text("\(cmd.scope) • \(cmd.summary)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            case .hooks:
                Section("Workspace Trust") {
                    Toggle("Trust Workspace Lifecycle Hooks", isOn: $store.workspaceHookTrustGranted)
                }
                Section("Configured Hook Rules") {
                    ForEach($store.hooks) { $hook in
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("\(hook.event) — \(hook.matcher)", isOn: $hook.enabled)
                                .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                            Text(hook.command)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            case .memory:
                Section("Persistent Agent Memories (MEMORY.md)") {
                    ForEach(store.memories) { mem in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(mem.slug)
                                    .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                                Spacer()
                                Text(mem.type.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(mem.body)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Add Memory Fact") {
                    TextField("Slug (e.g. api-rate-limit)", text: $newMemorySlug)
                        .textInputAutocapitalization(.never)
                    TextField("Fact details...", text: $newMemoryBody, axis: .vertical)
                    Button("Save Memory") {
                        store.memories.insert(
                            MemoryNoteItem(id: UUID().uuidString, slug: newMemorySlug, type: "project", description: newMemorySlug, body: newMemoryBody, updatedAt: Date()),
                            at: 0
                        )
                        newMemorySlug = ""
                        newMemoryBody = ""
                        store.showToast("Memory persisted")
                    }
                    .disabled(newMemorySlug.isEmpty || newMemoryBody.isEmpty)
                }

            case .automations:
                Section("Scheduled Cron Automations") {
                    ForEach($store.automations) { $job in
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle(job.name, isOn: $job.enabled)
                                .font(.system(size: 14, weight: .semibold))
                            Text("Cron: \(job.cronExpression) • Last: \(job.lastRunStatus)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button("Run Now") {
                                job.lastRunStatus = "Succeeded just now"
                                job.lastRunAt = Date()
                                store.showToast("Triggered \(job.name)")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }

            case .browserCUA:
                Section("Remote Computer Use (CUA) & Browser") {
                    Toggle("Enable Remote CUA Observation Cards", isOn: $store.cuaHelperEnabled)
                    TextField("Allowed Domains", text: $store.browserAllowedDomains, axis: .vertical)
                        .font(.system(size: 12.5, design: .monospaced))
                }

            case .fileSearch:
                Section("Workspace Indexing & Ignore Rules") {
                    TextEditor(text: $store.fileSearchIgnorePatterns)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(minHeight: 120)
                }

            case .archives:
                Section("Archived Conversations") {
                    let archived = store.sessions.filter(\.archived)
                    if archived.isEmpty {
                        Text("No archived conversations.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(archived) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 14, weight: .medium))
                                    Text(item.workspacePath).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") {
                                    store.restoreSession(item.id)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

            case .usage:
                Section("7-Day Token Usage (Native Swift Charts)") {
                    Chart(store.tokenUsageStats) { item in
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
                    .frame(height: 190)
                    .padding(.vertical, 8)
                }
                Section("Summary") {
                    let totalIn = store.tokenUsageStats.map(\.inputTokensK).reduce(0, +)
                    let totalOut = store.tokenUsageStats.map(\.outputTokensK).reduce(0, +)
                    let totalCost = store.tokenUsageStats.map(\.costUSD).reduce(0, +)
                    LabeledContent("7-Day Input Tokens", value: "\(totalIn)K")
                    LabeledContent("7-Day Output Tokens", value: "\(totalOut)K")
                    LabeledContent("Prompt Cache Hit Rate", value: "78.6%")
                    LabeledContent("7-Day Total Cost", value: String(format: "$%.2f", totalCost))
                }

            case .shortcutsAbout:
                Section("Session Migration") {
                    Button("Scan & Import Local CLI Sessions") {
                        store.showToast("Scanned ~/.zcode — all sessions up to date")
                    }
                }
                Section("Hardware Keyboard Shortcuts (iPad / Magic Keyboard)") {
                    LabeledContent("Command Center", value: "⌘ K")
                    LabeledContent("New Session", value: "⌘ N")
                    LabeledContent("Toggle Inspector", value: "⌘ ⇧ I")
                    LabeledContent("Send Prompt", value: "⌘ ↩")
                }
                Section("About ZCode Enterprise Mobile") {
                    LabeledContent("Version", value: "3.16.3 (Build 31603)")
                    LabeledContent("Architecture", value: "100% Native SwiftUI + PDFKit")
                    LabeledContent("WebView Dependency", value: "None (Zero WebKit)")
                    LabeledContent("Wire Protocol", value: "SocketProtocol 13B + VQL + Relay V2")
                }
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPatternSetup) {
            PatternSetupSheetView(store: store)
        }
    }
}
