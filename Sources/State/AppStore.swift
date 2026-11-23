import SwiftUI
import Observation
import LocalAuthentication
import UserNotifications

@MainActor
@Observable
public final class AppStore {
    // MARK: - Production vs Test Fixture Mode
    public let isUITestSeededMode: Bool

    // MARK: - Z.AI Account & Onboarding / Connection Hub State
    public var zaiAccount: ZaiUserAccount? { didSet { persistAccountMetadata() } }
    public var zaiRegion: ZaiAuthRegion = .global { didSet { persistPreferences() } }
    public var zaiRegisteredDevices: [ZaiRegisteredRemoteDevice] = []
    public var isSigningInZai: Bool = false
    public var isLoadingZaiDevices: Bool = false
    public var zaiAuthErrorMessage: String? = nil
    public var didSkipAccountStep: Bool = false { didSet { persistPreferences() } }

    public var showConnectionHub: Bool = true
    public var pairingPhase: RelayPairingPhase = .idle
    public var pairingTargetId: String = ""
    public var pairingTargetName: String = ""

    // MARK: - Appearance & Localization (Strictly English Default)
    public var language: AppLanguage = .english { didSet { persistPreferences() } }
    public var interfaceMode: String = "coding" { didSet { persistPreferences() } } // "coding" | "office"
    public var themeMode: ZCodeThemeMode = .dark { didSet { persistPreferences() } }
    public var uiFontSizePx: Double = 14.0 { didSet { persistPreferences() } }
    public var syntaxTheme: ZCodeSyntaxTheme = .githubDark { didSet { persistPreferences() } }
    public var lightSyntaxTheme: ZCodeSyntaxTheme = .githubLight { didSet { persistPreferences() } }
    public var codeFontSize: Double = 13.0 { didSet { persistPreferences() } }
    public var showLineNumbers: Bool = true { didSet { persistPreferences() } }
    public var wrapCodeLines: Bool = false { didSet { persistPreferences() } }
    public var showReasoningBlocks: Bool = true { didSet { persistPreferences() } }
    public var showTodoTracker: Bool = true { didSet { persistPreferences() } }
    public var compactToolCards: Bool = false { didSet { persistPreferences() } }
    public var toolGroupingExploreEnabled: Bool = true { didSet { persistPreferences() } }
    public var toolGroupingTerminalEnabled: Bool = true { didSet { persistPreferences() } }
    public var toolGroupingChangesEnabled: Bool = false { didSet { persistPreferences() } }
    /// Host `messageStreamShowTodos`: TodoWrite tool rows are hidden from the transcript unless enabled.
    public var messageStreamShowTodos: Bool = false { didSet { persistPreferences() } }
    public var hapticsEnabled: Bool = true { didSet { persistPreferences() } }

    // MARK: - ZCode v3.16.3 General, Terminal, Search, Interaction & Archive Settings
    public var terminalInheritSystemProfile: Bool = true { didSet { persistPreferences() } }
    public var terminalFontFamily: String = "SF Mono, Menlo, monospace" { didSet { persistPreferences() } }
    public var toolSearchMode: String = "auto" { didSet { persistPreferences() } } // "off" | "auto" | "on"
    public var nativeSearchEnhancementsEnabled: Bool = true { didSet { persistPreferences() } }
    public var zcodeInteractionBehavior: String = "queue" { didSet { persistPreferences() } } // "queue" | "guide"
    public var askUserQuestionAutoResolutionEnabled: Bool = false { didSet { persistPreferences() } }
    public var dynamicWorkflowMode: String = "auto" { didSet { persistPreferences() } } // "disabled" | "auto" | "manual"
    public var modelIoFullRetentionEnabled: Bool = false { didSet { persistPreferences() } }
    public var keepAwakeWhileRunning: Bool = true { didSet { persistPreferences() } }
    public var receivePreviewUpdates: Bool = false { didSet { persistPreferences() } }
    public var autoDownloadAndInstallUpdates: Bool = true { didSet { persistPreferences() } }
    public var dataBaseDir: String = "~/.zcode/v2" { didSet { persistPreferences() } }
    public var memoryEnabled: Bool = true { didSet { persistPreferences() } }
    public var userMemoryMarkdown: String = "" { didSet { persistPreferences() } }
    public var taskAutoArchiveEnabled: Bool = false { didSet { persistPreferences() } }
    public var taskAutoArchiveOlderThanDays: Int = 14 { didSet { persistPreferences() } } // 3 | 7 | 14 | 30

    // MARK: - Notifications & Enterprise Security Settings
    public var notificationsEnabled: Bool = true { didSet { persistPreferences() } }
    public var notificationSoundEnabled: Bool = true { didSet { persistPreferences() } }
    public var notifyApprovals: Bool = true { didSet { persistPreferences() } }
    public var notifyQuestions: Bool = true { didSet { persistPreferences() } }
    public var notifyCompletions: Bool = true { didSet { persistPreferences() } }
    public var notifyFailures: Bool = true { didSet { persistPreferences() } }

    public var appLockEnabled: Bool = false { didSet { persistPreferences() } }
    public var biometricUnlockEnabled: Bool = true { didSet { persistPreferences() } }
    public var hasPatternConfigured: Bool = false { didSet { persistPreferences() } }
    public var isLocked: Bool = false
    public var failedUnlockAttempts: Int = 0
    public var lockoutUntil: Date? = nil

    public var httpProxyURL: String = "" { didSet { persistPreferences() } }
    public var httpProxyNoProxy: String = "localhost, 127.0.0.1" { didSet { persistPreferences() } }
    public var httpProxyCaCertPath: String = "" { didSet { persistPreferences() } }
    public var workspaceHookTrustGranted: Bool = true { didSet { persistPreferences() } }
    public var offPeakWindowSchedule: String = "00:00 – 07:00 UTC" { didSet { persistPreferences() } }
    public var browserAllowedDomains: String = "localhost, 127.0.0.1, zcode.z.ai" { didSet { persistPreferences() } }
    public var embeddedBrowserAllowInsecureCertificates: Bool = false { didSet { persistPreferences() } }
    public var fileSearchIgnorePatterns: String = "node_modules/\n.git/\nDerivedData/\nbuild/\n*.ipa" { didSet { persistPreferences() } }
    public var cuaHelperEnabled: Bool = true { didSet { persistPreferences() } }
    /// Host setting `computerUseComposerEntryHidden` (desktop default: true).
    public var computerUseComposerEntryHidden: Bool = true { didSet { persistPreferences() } }
    /// No host RPC exposes macOS TCC permission state in 3.16.3; never claim "granted".
    public var cuaAccessibilityStatus: String = "unknown"
    public var cuaScreenRecordingStatus: String = "unknown"
    public var remoteStartupAutoReconnectEnabled: Bool = true { didSet { persistPreferences() } }
    /// Host setting `shortcutBindings` (`Record<string,string[]>`). Starts empty; populated only from the host.
    public var shortcutBindings: [ShortcutBindingItem] = []
    public var pluginMarketplaces: [String] = []
    public var isSyncingSettings: Bool = false
    public var lastSettingsSyncedAt: Date? = nil

    // MARK: - Live Provider/Host Settings Data (never seeded)
    /// `provider-settings.getView.providerTemplates` (host-sourced).
    public var providerTemplates: [ProviderTemplateDescriptor] = []
    public var providerOrder: [String] = []
    /// `provider-settings.getView.revision` (STRING).
    public var providerSettingsRevision: String = ""
    /// Real `usage-stats.getAppUsageSnapshot` (nil until the host answers).
    public var usageStatsSnapshot: UsageStatsSnapshot? = nil
    public var usageStatsError: String? = nil
    public var usageStatsLoading: Bool = false
    /// Real `usage-stats.getEntitlementSnapshot` (nil when unavailable).
    public var codingPlanEntitlement: CodingPlanEntitlementSnapshot? = nil
    public var codingPlanEntitlementError: String? = nil
    public var codingPlanEntitlementLoading: Bool = false
    /// Real workspace-hook trust review items from `hooks.loadHooks`.
    public var pendingHookTrustItems: [PendingHookTrustItem] = []

    // MARK: - ZCode Remote Mobile Shell Navigation & Sheet State
    public var mobilePage: MobileShellPage = .home
    public var taskListViewMode: TaskListViewMode = .byProject
    public var projectsSectionExpanded: Bool = true
    public var expandedProjectIds: Set<String> = []
    /// ZCode projects from `project.readTree`; the sidebar groups tasks by these, not by open workspace tabs.
    public var sidebarProjects: [SidebarProject] = []
    public var sidebarTreeLoaded: Bool = false
    public var tasksSectionExpanded: Bool = true
    /// Desktop default is expanded, so only collapsed ZCode projects are tracked.
    public var collapsedSidebarProjectIds: Set<String> = []
    public var taskGroups = TaskGroupsStructure()
    public var collapsedTaskGroupIds: Set<String> = []
    var projectTreeRefreshTask: Task<Void, Never>?
    public var userDisplayName: String = "ZCode User" { didSet { persistPreferences() } }
    public var isInspectorExpandedFull: Bool = false

    public var showSidebarDrawer: Bool = false
    public var showInspectorSheet: Bool = false
    public var activeInspectorTab: InspectorTab = .files
    public var showTaskStatusPanel: Bool = false
    public var hideCompletedTodosInStatusPanel: Bool = false
    public var showSubagentDrawer: Bool = false
    public var subagentPane: SubagentPaneState?
    public var subagentPaneBackStack: [SubagentPaneState] = []
    public var activeGitBranch: String = "main"
    public var showSettingsSheet: Bool = false
    public var showConnectionsSheet: Bool = false
    public var showCommandCenter: Bool = false
    public var toastMessage: String? = nil
    /// Persistent connection banner (host offline, reconnecting, taken over); `nil` when the live link is healthy.
    public var liveConnectionNotice: String? = nil

    // MARK: - Connections, Workspaces & Sessions
    public var connections: [RemoteConnection] { didSet { persistConnections() } }
    public var activeConnectionId: String
    public var projects: [WorkspaceProject]
    public var activeProjectId: String {
        didSet {
            if oldValue != activeProjectId, !activeProjectId.isEmpty {
                switchRemoteWorkspaceBridgeIfNeeded(projectId: activeProjectId)
            }
        }
    }
    public var sessions: [AgentTaskSession]
    public var activeSessionId: String

    // MARK: - Inspector State (Files, Code/Image/PDF Viewer, Git, Terminal, Workflows)
    public var fileTree: [WorkspaceFileNode]
    public var selectedFileId: String = ""
    public var openFileIds: [String] = []
    public var inlineComments: [InlineCodeComment] = []

    public var gitChanges: [GitChangedFile]
    public var gitCommits: [GitCommitRecord]
    public var gitBranches: [String] = ["main"]
    public var selectedDiffFileId: String? = nil
    public var diffSplitMode: Bool = false

    public var terminalTabs: [TerminalTabModel]
    public var activeTerminalTabId: String = ""
    public var workflowNodes: [WorkflowGraphNode]

    // MARK: - Ecosystem Catalogs
    public var providers: [ModelProviderConfig]
    public var mcpServers: [MCPServerItem]
    public var skills: [SkillCatalogItem]
    public var plugins: [PluginCatalogItem]
    public var subagents: [SubagentDefinitionItem]
    public var slashCommands: [SlashCommandItem]
    public var hooks: [HookRuleItem]
    public var memories: [MemoryNoteItem]
    public var automations: [AutomationScheduleItem]
    public var tokenUsageStats: [DailyTokenUsageItem]
    public var notificationInbox: [NotificationInboxItem] = []

    // MARK: - Live Host Automations & Plugin Marketplace (zcode-agent / plugin-management)
    public var isLoadingAutomations: Bool = false
    public var automationsError: String? = nil
    @ObservationIgnored var automationHostRows: [[String: Any]] = []
    public var isRefreshingPluginMarketplace: Bool = false
    public var pluginMarketplaceError: String? = nil

    // MARK: - Composer State
    public var composerText: String = ""
    public var composerAttachments: [ComposerAttachment] = []
    /// Quoted excerpts sent with the next prompt as host `conversationQuotes` (max 8, 16k chars total).
    public var composerQuotes: [ConversationQuote] = []

    public func addComposerQuote(_ quote: ConversationQuote) {
        let text = quote.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, composerQuotes.count < 8 else {
            if composerQuotes.count >= 8 { showToast("You can quote up to 8 excerpts per message") }
            return
        }
        let used = composerQuotes.reduce(0) { $0 + $1.text.count }
        var trimmed = quote
        trimmed.text = String(text.prefix(max(0, 16_000 - used)))
        guard !trimmed.text.isEmpty else { return }
        composerQuotes.append(trimmed)
    }

    public func removeComposerQuote(_ id: String) {
        composerQuotes.removeAll { $0.id == id }
    }
    var activeStreamTask: Task<Void, Never>?
    private var activeConnectTask: Task<Void, Never>?
    var activeHydrationTask: Task<Void, Never>?
    var isBulkSyncingWorkspaces: Bool = false
    var workspaceIdentityByPath: [String: String] = [:]
    let rpcClient = ZCodeRPCClient()

    // MARK: - Live Host Model Selection (zcode `model-selection` channel)
    public var liveModelGroups: [LiveModelProviderGroup] = []
    public var preferredModelSelection: LiveModelSelection? = nil
    @ObservationIgnored let liveSync = LiveSyncState()
    @ObservationIgnored let v4Sync = V4SyncState()
    @ObservationIgnored let hostSettings = HostSettingsSyncState()

    private let prefsKey = "zcode_mobile_enterprise_prefs_v2"
    private let connectionsKey = "zcode_saved_connections_v2"
    private let accountKey = "zcode_zai_account_v1"
    private let zaiJwtKeychainKey = "zcode_zai_jwt_token_v1"
    private let zaiAccessKeychainKey = "zcode_zai_access_token_v1"
    private let patternSalt = "zcode_enterprise_salt_v3"

    public init(seedDemoWorkspace: Bool? = nil) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: prefsKey)
            UserDefaults.standard.removeObject(forKey: connectionsKey)
            UserDefaults.standard.removeObject(forKey: accountKey)
            UserDefaults.standard.removeObject(forKey: "zcode_custom_catalogs_v3")
            KeychainStore.delete(zaiJwtKeychainKey)
            KeychainStore.delete(zaiAccessKeychainKey)
        }

        let shouldSeed = seedDemoWorkspace ?? args.contains("--uitesting-seed-workspace")
        self.isUITestSeededMode = shouldSeed

        if shouldSeed {
            // Deterministic XCTest fixture mode ONLY
            self.providers = SeedWorkspaceFactory.defaultProviders()
            self.skills = SeedWorkspaceFactory.defaultSkills()
            self.plugins = SeedWorkspaceFactory.defaultPlugins()
            self.subagents = SeedWorkspaceFactory.defaultSubagents()
            self.slashCommands = SeedWorkspaceFactory.defaultSlashCommands()
            self.connections = SeedWorkspaceFactory.defaultConnections()
            self.activeConnectionId = "conn-workstation-primary"
            self.projects = SeedWorkspaceFactory.defaultProjects()
            self.activeProjectId = "proj-zcode-core"
            self.expandedProjectIds = ["proj-zcode-core", "proj-gateway-rs"]
            self.sessions = SeedWorkspaceFactory.defaultSessions()
            self.activeSessionId = "task-rpc-refactor"
            self.fileTree = SeedWorkspaceFactory.defaultFileTree()
            self.selectedFileId = "file-socket-protocol"
            self.openFileIds = ["file-socket-protocol", "file-arch-png", "file-spec-pdf"]
            self.gitChanges = SeedWorkspaceFactory.defaultGitChanges()
            self.gitCommits = SeedWorkspaceFactory.defaultGitCommits()
            self.gitBranches = ["feat/native-rpc-v4", "main", "release/3.16.3", "fix/relay-crc32"]
            self.activeGitBranch = "feat/native-rpc-v4"
            self.selectedDiffFileId = "git-1"
            self.terminalTabs = SeedWorkspaceFactory.defaultTerminalTabs()
            self.activeTerminalTabId = "term-1"
            self.workflowNodes = SeedWorkspaceFactory.defaultWorkflowNodes()
            self.mcpServers = SeedWorkspaceFactory.defaultMCPServers()
            self.hooks = SeedWorkspaceFactory.defaultHooks()
            self.memories = SeedWorkspaceFactory.defaultMemories()
            self.automations = SeedWorkspaceFactory.defaultAutomations()
            self.tokenUsageStats = SeedWorkspaceFactory.defaultTokenUsage()
            self.userDisplayName = "ZCode Operator"
            self.showConnectionHub = false
            self.pairingPhase = .connected
        } else {
            // 100% Clean Production Mode: ZERO demo screens, ZERO fake tasks/files/connections
            self.connections = Self.loadSavedConnectionsFromDisk(key: connectionsKey)
            self.activeConnectionId = ""
            self.projects = []
            self.activeProjectId = ""
            self.expandedProjectIds = []
            self.sessions = []
            self.activeSessionId = ""
            self.fileTree = []
            self.selectedFileId = ""
            self.openFileIds = []
            self.gitChanges = []
            self.gitCommits = []
            self.gitBranches = ["main"]
            self.activeGitBranch = "main"
            self.selectedDiffFileId = nil
            self.terminalTabs = []
            self.activeTerminalTabId = ""
            self.workflowNodes = []
            self.mcpServers = []
            self.hooks = []
            self.memories = []
            self.automations = []
            self.tokenUsageStats = []
            self.notificationInbox = []
            self.userDisplayName = ""
            self.providers = []
            self.skills = []
            self.plugins = []
            self.subagents = []
            self.slashCommands = []
            self.showConnectionHub = true
            self.pairingPhase = .idle
        }

        loadPreferences()
        UserDefaults.standard.removeObject(forKey: "zcode_custom_catalogs_v3")
        loadAccountMetadata()

        if let acct = zaiAccount {
            userDisplayName = acct.displayName
            if !shouldSeed {
                Task { await refreshZaiRegisteredDevices() }
            }
        }
        if appLockEnabled {
            isLocked = true
        }
    }

    // MARK: - Computed Conveniences

    public var isZaiAuthenticated: Bool {
        zaiAccount != nil && !(KeychainStore.load(zaiJwtKeychainKey) ?? "").isEmpty
    }

    public var shouldShowSignInStepFirst: Bool {
        !isZaiAuthenticated && !didSkipAccountStep
    }

    public var activeConnection: RemoteConnection? {
        connections.first(where: { $0.id == activeConnectionId }) ?? connections.first
    }

    public var activeProject: WorkspaceProject? {
        projects.first(where: { $0.id == activeProjectId }) ?? projects.first
    }

    public var activeSession: AgentTaskSession? {
        get { sessions.first(where: { $0.id == activeSessionId }) ?? sessions.first(where: { !$0.archived }) }
        set {
            guard let updated = newValue,
                  let idx = sessions.firstIndex(where: { $0.id == updated.id }) else { return }
            sessions[idx] = updated
        }
    }

    public var allModels: [ModelDescriptor] {
        providers.filter(\.enabled).flatMap { $0.models.filter(\.enabled) }
    }

    public var flattenedFiles: [WorkspaceFileNode] {
        func collect(_ nodes: [WorkspaceFileNode]) -> [WorkspaceFileNode] {
            var out: [WorkspaceFileNode] = []
            for n in nodes {
                if !n.isDirectory { out.append(n) }
                if let children = n.children {
                    out.append(contentsOf: collect(children))
                }
            }
            return out
        }
        return collect(fileTree)
    }

    public var selectedFile: WorkspaceFileNode? {
        flattenedFiles.first(where: { $0.id == selectedFileId }) ?? flattenedFiles.first
    }

    public var unreadApprovalsCount: Int {
        sessions.filter { !$0.archived && ($0.pendingPermission != nil || $0.pendingQuestion != nil || $0.pendingPlan != nil) }.count
    }

    public var gitTotalAddedLines: Int {
        gitChanges.reduce(0) { $0 + $1.added }
    }

    public var gitTotalRemovedLines: Int {
        gitChanges.reduce(0) { $0 + $1.removed }
    }

    // MARK: - Z.AI Account Authentication Actions

    public func signInWithZaiOAuth() async {
        guard !isSigningInZai else { return }
        isSigningInZai = true
        zaiAuthErrorMessage = nil
        playImpactHaptic(.light)

        do {
            let result = try await ZaiAuthAndRemoteService.shared.signInWithZaiOAuth(region: zaiRegion)
            applyAuthenticatedResult(result)
            playNotificationHaptic(.success)
            showToast("Signed in as \(result.account.displayName)")
            await refreshZaiRegisteredDevices()
            if !pairingTargetId.isEmpty {
                let targetId = pairingTargetId
                await connectToWorkstation(targetId)
            }
        } catch let err as ZaiAuthError {
            if case .cancelled = err {
                zaiAuthErrorMessage = nil
            } else {
                zaiAuthErrorMessage = err.localizedDescription
                playNotificationHaptic(.error)
            }
        } catch {
            zaiAuthErrorMessage = error.localizedDescription
            playNotificationHaptic(.error)
        }
        isSigningInZai = false
    }

    public func signInWithZaiToken(_ rawToken: String, aliasHint: String = "") async -> Bool {
        isSigningInZai = true
        zaiAuthErrorMessage = nil
        playImpactHaptic(.light)
        defer { isSigningInZai = false }

        do {
            let result = try await ZaiAuthAndRemoteService.shared.verifyAndSignInWithToken(
                rawToken,
                region: zaiRegion,
                displayNameHint: aliasHint
            )
            applyAuthenticatedResult(result)
            playNotificationHaptic(.success)
            showToast("Signed in as \(result.account.displayName)")
            await refreshZaiRegisteredDevices()
            if !pairingTargetId.isEmpty {
                let targetId = pairingTargetId
                await connectToWorkstation(targetId)
            }
            return true
        } catch {
            zaiAuthErrorMessage = error.localizedDescription
            playNotificationHaptic(.error)
            return false
        }
    }

    private func applyAuthenticatedResult(_ result: ZaiAuthResult) {
        KeychainStore.save(result.zcodeJwtToken, for: zaiJwtKeychainKey)
        KeychainStore.save(result.providerAccessToken, for: zaiAccessKeychainKey)
        zaiAccount = result.account
        userDisplayName = result.account.displayName
        didSkipAccountStep = false
        zaiAuthErrorMessage = nil
    }

    public func signOutZaiAccount() {
        ZaiAuthAndRemoteService.shared.cancelPendingSignIn()
        KeychainStore.delete(zaiJwtKeychainKey)
        KeychainStore.delete(zaiAccessKeychainKey)
        zaiAccount = nil
        zaiRegisteredDevices = []
        userDisplayName = ""
        didSkipAccountStep = false
        playImpactHaptic(.medium)
        showToast("Signed out of Z.AI")
    }

    public func refreshZaiRegisteredDevices() async {
        guard let jwt = KeychainStore.load(zaiJwtKeychainKey), !jwt.isEmpty else {
            zaiRegisteredDevices = []
            return
        }
        isLoadingZaiDevices = true
        defer { isLoadingZaiDevices = false }
        let origin = (zaiAccount?.region ?? zaiRegion).zcodeOrigin
        if let list = try? await ZaiAuthAndRemoteService.shared.fetchRegisteredDevices(zcodeJwt: jwt, origin: origin) {
            zaiRegisteredDevices = list
        }
    }

    public func connectToRegisteredZaiDevice(_ device: ZaiRegisteredRemoteDevice) async {
        let encodedName = device.deviceName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? device.deviceName
        let origin = (zaiAccount?.region ?? zaiRegion).zcodeOrigin
        let remoteURL = "\(origin)/remote/v4?sid=\(device.deviceSid)&mid=\(device.deviceMid)&name=\(encodedName)"
        _ = await addAndConnect(rawURLOrInput: remoteURL, customName: device.deviceName)
    }

    public func handleIncomingURL(_ url: URL) async {
        let str = url.absoluteString
        if url.scheme?.lowercased() == "zcode", url.host?.lowercased() == "oauth" {
            do {
                let result = try await ZaiAuthAndRemoteService.shared.exchangeCallbackURL(
                    url,
                    expectedState: nil,
                    redirectURI: "zcode://oauth/callback",
                    region: zaiRegion
                )
                applyAuthenticatedResult(result)
                showToast("Signed in as \(result.account.displayName)")
                await refreshZaiRegisteredDevices()
            } catch {
                zaiAuthErrorMessage = error.localizedDescription
            }
            return
        }
        _ = await addAndConnect(rawURLOrInput: str)
    }

    public func openConnectionHub() {
        playImpactHaptic(.light)
        showSidebarDrawer = false
        showInspectorSheet = false
        showSubagentDrawer = false
        showConnectionHub = true
    }

    public func cancelPairingAttempt() {
        activeConnectTask?.cancel()
        activeConnectTask = nil
        Task { await rpcClient.disconnect() }
        if let idx = connections.firstIndex(where: { $0.id == pairingTargetId }) {
            connections[idx].state = .disconnected
        }
        pairingPhase = .idle
        pairingTargetId = ""
    }

    // MARK: - Toast & Haptics

    public func showToast(_ text: String) {
        if hapticsEnabled {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        toastMessage = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            if self.toastMessage == text {
                self.toastMessage = nil
            }
        }
    }

    public func playImpactHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    public func playSelectionHaptic() {
        guard hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    public func playNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    public func refreshWorkspaceAndSessions() async {
        playImpactHaptic(.soft)
        if let conn = activeConnection, conn.transport != .enterpriseSandbox {
            if await syncRemoteWorkspacesFromServer(for: conn) {
                showToast("Synced with \(conn.name)")
            } else {
                showToast("\(conn.name) didn't respond. Try again in a moment.")
            }
        } else {
            showToast("Connect to your computer to sync")
        }
    }

    // MARK: - Session & Project Operations

    /// `project.saveProject({roots, name?})`: registers a folder on the computer as a ZCode project.
    public func createNewProject(name: String, rootPath: String? = nil) {
        let path = (rootPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else {
            showToast("Enter the folder's absolute path on your computer")
            return
        }
        guard !isUITestSeededMode, activeConnection?.state == .connected else {
            showToast("Connect to your computer to add a project")
            return
        }
        var args: [String: Any] = ["roots": [path]]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { args["name"] = trimmedName }
        Task { @MainActor in
            do {
                _ = try await self.rpcClient.call(channel: "project", method: "saveProject", args: [.fromJSONObject(args)], timeoutSec: 10.0)
                await self.loadProjectTree(preferredActiveTaskId: self.activeSessionId)
            } catch {
                self.showToast("Couldn't add project: \(error.localizedDescription)")
            }
        }
    }

    public func toggleProjectExpanded(_ projectId: String) {
        if expandedProjectIds.contains(projectId) {
            expandedProjectIds.remove(projectId)
        } else {
            expandedProjectIds.insert(projectId)
            activeProjectId = projectId
        }
    }

    private func switchRemoteWorkspaceBridgeIfNeeded(projectId: String) {
        guard !isUITestSeededMode,
              !isBulkSyncingWorkspaces,
              let conn = activeConnection,
              conn.state == .connected,
              let project = projects.first(where: { $0.id == projectId }) else {
            return
        }
        let wsPath = project.rootPath
        let wsIdentity = workspaceIdentityByPath[wsPath]
        let wsKey = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: wsPath, workspaceIdentity: wsIdentity)

        Task { @MainActor in
            if conn.transport == .cloudRelayV2 {
                let currentBridge = await self.rpcClient.currentBridge()
                if currentBridge?.workspaceKey != wsKey {
                    _ = try? await self.rpcClient.openWorkspaceBridge(workspaceKey: wsKey, taskId: nil, timeoutSec: 4.0)
                }
            }
            self.scheduleWorkspaceRefresh(projectId: projectId, workspacePath: wsPath, workspaceIdentity: wsIdentity)
            await self.hydrateWorkspaceFilesAndGit(workspacePath: wsPath, projectId: projectId)
        }
    }

    public func toggleAllProjectsExpanded() {
        if expandedProjectIds.count == projects.count {
            expandedProjectIds.removeAll()
        } else {
            expandedProjectIds = Set(projects.map(\.id))
        }
    }

    private func ensureActiveProjectForNewSession(requestedProjectId: String?) -> WorkspaceProject {
        if let requestedProjectId,
           let match = projects.first(where: { $0.id == requestedProjectId }) {
            return match
        }
        if let current = activeProject {
            return current
        }
        // No open workspace: the relay bridge prepares a conversation draft workspace on first send.
        return WorkspaceProject(
            id: "",
            name: "Tasks",
            rootPath: "",
            gitBranch: "",
            ahead: 0,
            behind: 0,
            isDirty: false,
            isRemote: true,
            pinned: false
        )
    }

    public func createNewSession(inProjectId: String? = nil, initialPrompt: String? = nil) {
        let project = ensureActiveProjectForNewSession(requestedProjectId: inProjectId)
        activeProjectId = project.id
        expandedProjectIds.insert(project.id)
        let newId = "task-\(UUID().uuidString.prefix(8))"
        let inheritedMode = activeSession?.mode ?? (isUITestSeededMode ? .yolo : .build)
        let inheritedModel: LiveModelSelection? = isUITestSeededMode ? nil : (activeSession.flatMap { modelSelection(for: $0) } ?? preferredModelSelection)
        let newSession = AgentTaskSession(
            id: newId,
            traceId: UUID().uuidString.lowercased(),
            projectId: project.id,
            workspacePath: project.rootPath,
            title: "",
            status: .idle,
            mode: inheritedMode,
            modelId: isUITestSeededMode ? "anthropic/claude-opus-4-7" : (inheritedModel?.modelId ?? ""),
            effort: .high,
            pinned: false,
            archived: false,
            unread: false,
            offPeakEnabled: false,
            createdAt: Date(),
            updatedAt: Date(),
            contextUsedPercent: 0,
            totalTokensIn: 0,
            totalTokensOut: 0,
            cachedTokens: 0,
            costUSD: 0,
            messages: [],
            todos: [],
            pendingPermission: nil,
            pendingQuestion: nil,
            pendingPlan: nil,
            queuedPrompts: [],
            checkpoints: [],
            modelProviderId: inheritedModel?.providerId,
            reasoningLevel: inheritedModel?.reasoningLevel
        )
        sessions.insert(newSession, at: 0)
        activeSessionId = newId
        showSidebarDrawer = false
        mobilePage = .chat
        if let prompt = initialPrompt, !prompt.isEmpty {
            composerText = prompt
            sendPrompt()
        }
    }

    public func selectSession(_ session: AgentTaskSession) {
        playSelectionHaptic()
        if session.id != activeSessionId, subagentPane != nil { closeSubagentSession() }
        activeSessionId = session.id
        if projects.contains(where: { $0.id == session.projectId }) {
            activeProjectId = session.projectId
        }
        let wasUnread = session.unread
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].unread = false
        }
        showSidebarDrawer = false
        mobilePage = .chat

        if !isUITestSeededMode,
           let conn = activeConnection,
           conn.state == .connected,
           !session.id.hasPrefix("task-") {
            let sid = session.id
            let wsPath = session.workspacePath
            let wsIdentity = session.workspaceIdentity ?? workspaceIdentityByPath[wsPath]
            let wsKey = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: wsPath, workspaceIdentity: wsIdentity)
            Task { @MainActor in
                if conn.transport == .cloudRelayV2 {
                    try? await self.openBridge(for: session)
                    await self.rpcClient.sendMobileViewStateUpdate(workspaceKey: wsKey, taskId: sid)
                }
                if wasUnread {
                    var args = self.hostTaskScope(for: session)
                    args["unread"] = false
                    _ = try? await self.rpcClient.call(channel: "zcode-task", method: "setTaskUnread", args: [.fromJSONObject(args)], timeoutSec: 8.0)
                }
                if let current = self.sessions.first(where: { $0.id == sid }) {
                    await self.subscribeActiveTask(current)
                }
                await self.hydrateWorkspaceFilesAndGit(workspacePath: wsPath, projectId: session.projectId)
            }
        }
    }

    public func toggleMessageFeedback(messageId: String, rating: Int) {
        playSelectionHaptic()
        guard let session = activeSession,
              let mIdx = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard v4CanTarget(messageId: messageId),
              let target = v4Sync.rowTargets[messageId] else {
            showToast("Feedback is unavailable for this turn")
            return
        }
        let previousRating = session.messages[mIdx].feedback
        let newRating = (previousRating == rating) ? 0 : rating
        let feedbackValue: Any = newRating == 1 ? "like" as Any : (newRating == -1 ? "dislike" as Any : NSNull())
        Task { @MainActor in
            do {
                try await self.v4Command(
                    "setAssistantFeedback",
                    payload: ["target": target, "feedback": feedbackValue],
                    sessionId: session.id,
                    workspacePath: session.workspacePath,
                    cas: true,
                    rowTarget: true
                )
                // Reflect only persisted feedback; the host snapshot confirms on publish.
                if let idx = self.sessions.firstIndex(where: { $0.id == session.id }),
                   let m = self.sessions[idx].messages.firstIndex(where: { $0.id == messageId }) {
                    self.sessions[idx].messages[m].feedback = newRating
                }
            } catch {
                self.showToast("Couldn't save feedback: \(error.localizedDescription)")
                self.v4Resync(force: false)
            }
        }
    }

    private func hostTaskScope(for session: AgentTaskSession) -> [String: Any] {
        var scope: [String: Any] = ["taskId": session.id, "workspacePath": session.workspacePath]
        if let identity = session.workspaceIdentity ?? workspaceIdentityByPath[session.workspacePath], !identity.isEmpty {
            scope["workspaceIdentity"] = identity
        }
        return scope
    }

    private var canMutateHostTasks: Bool {
        !isUITestSeededMode && activeConnection?.state == .connected
    }

    /// Draft sessions and the seeded fixtures may be changed locally; host tasks require the live RPC.
    private func canChangeSession(_ id: String) -> Bool {
        isUITestSeededMode || id.hasPrefix("task-") || canMutateHostTasks
    }

    private func requireSessionMutation(_ id: String, action: String) -> Bool {
        guard canChangeSession(id) else {
            showToast("Connect to your computer to \(action)")
            return false
        }
        return true
    }

    /// Applies `local` optimistically, sends `zcode-task.<method>`, and rolls back on failure.
    private func mutateHostTask(
        _ id: String,
        method: String,
        extra: [String: Any] = [:],
        failureMessage: String,
        local: (inout AgentTaskSession) -> Void
    ) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let before = sessions[idx]
        local(&sessions[idx])
        guard canMutateHostTasks, !id.hasPrefix("task-") else { return }
        let args = hostTaskScope(for: before).merging(extra) { _, new in new }
        Task { @MainActor in
            do {
                _ = try await self.rpcClient.call(channel: "zcode-task", method: method, args: [.fromJSONObject(args)], timeoutSec: 8.0)
            } catch {
                if let i = self.sessions.firstIndex(where: { $0.id == id }) {
                    self.sessions[i] = before
                } else {
                    self.sessions.append(before)
                }
                self.showToast("\(failureMessage): \(error.localizedDescription)")
            }
        }
    }

    public func togglePinSession(_ id: String) {
        guard requireSessionMutation(id, action: "change pinned tasks") else { return }
        guard let current = sessions.first(where: { $0.id == id }) else { return }
        let pinned = !current.pinned
        mutateHostTask(id, method: "setTaskPinned", extra: ["pinned": pinned], failureMessage: pinned ? "Couldn't pin task" : "Couldn't unpin task") {
            $0.pinned = pinned
        }
    }

    public func archiveSession(_ id: String) {
        guard requireSessionMutation(id, action: "archive tasks") else { return }
        mutateHostTask(id, method: "archiveTask", failureMessage: "Couldn't archive task") {
            $0.archived = true
            $0.pinned = false
        }
        if activeSessionId == id {
            activeSessionId = sessions.first(where: { !$0.archived })?.id ?? ""
        }
    }

    public func restoreSession(_ id: String) {
        guard requireSessionMutation(id, action: "restore tasks") else { return }
        mutateHostTask(id, method: "unarchiveTask", failureMessage: "Couldn't unarchive task") {
            $0.archived = false
        }
    }

    public func markSessionUnread(_ id: String) {
        guard requireSessionMutation(id, action: "mark tasks unread") else { return }
        mutateHostTask(id, method: "setTaskUnread", extra: ["unread": true], failureMessage: "Couldn't mark as unread") {
            $0.unread = true
        }
    }

    public func deleteSession(_ id: String) {
        guard requireSessionMutation(id, action: "delete tasks") else { return }
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let method = session.archived ? "deleteArchivedTask" : "deleteTask"
        mutateHostTask(id, method: method, failureMessage: "Couldn't delete task") { _ in }
        sessions.removeAll(where: { $0.id == id })
        if activeSessionId == id {
            activeSessionId = sessions.first(where: { !$0.archived })?.id ?? ""
        }
    }

    public func renameSession(_ id: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard requireSessionMutation(id, action: "rename tasks") else { return }
        mutateHostTask(id, method: "renameTask", extra: ["title": trimmed], failureMessage: "Couldn't rename task") {
            $0.title = trimmed
        }
    }

    // MARK: - Streaming Prompt & Agent Execution

    public func sendPrompt() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !composerAttachments.isEmpty else { return }
        guard var session = activeSession else {
            createNewSession(initialPrompt: trimmed)
            return
        }

        // Desktop 3.16.3 app-command parsing (`DX`): `/compact` + `/compress` -> V4 `compact`;
        // `/goal <objective>` / `/goal resume` -> V4 goal commands. No local mode/percent mutation.
        let loweredCommand = trimmed.lowercased()
        if (loweredCommand == "/compact" || loweredCommand == "/compress"),
           composerAttachments.isEmpty, composerQuotes.isEmpty {
            composerText = ""
            requestContextCompaction(for: session)
            return
        }
        if handleGoalSlashCommand(trimmed, session: session) {
            return
        }

        if trimmed == "/clear" || trimmed == "/new" {
            composerText = ""
            createNewSession()
            return
        }

        let outgoingQuotes = composerQuotes
        // Host-side queue: the agent drains it in order after the current turn.
        if session.status == .running, v4Owns(session.id) {
            let text = trimmed.isEmpty ? "Inspect attached files" : trimmed
            let attachments = composerAttachments
            composerText = ""
            composerAttachments = []
            composerQuotes = []
            let sid = session.id
            Task { @MainActor in
                _ = await self.v4SendPrompt(sessionId: sid, text: text, attachments: attachments, quotes: outgoingQuotes, queue: true)
            }
            showToast("Queued follow-up prompt")
            return
        }

        // If already running, enqueue prompt + attachments just like ZCode Desktop & Remote
        if session.status == .running {
            let queuedItem = QueuedPromptItem(
                id: UUID().uuidString,
                content: trimmed.isEmpty ? "Inspect attached files" : trimmed,
                attachments: composerAttachments,
                createdAt: Date()
            )
            session.queuedPrompts.append(queuedItem)
            composerText = ""
            composerAttachments = []
            activeSession = session
            showToast("Queued follow-up prompt")
            return
        }

        let outgoingAttachments = composerAttachments
        composerText = ""
        composerAttachments = []
        composerQuotes = []

        if isUITestSeededMode, session.messages.isEmpty, session.title.isEmpty {
            session.title = String(trimmed.prefix(48))
        }

        let userMsg = ChatTurnMessage(
            id: UUID().uuidString,
            role: "user",
            content: trimmed.isEmpty ? "Inspect attached files" : trimmed,
            thought: nil,
            thoughtDurationMs: 0,
            tools: [],
            attachments: outgoingAttachments,
            timestamp: Date(),
            modelLabel: nil,
            tokensIn: max(12, trimmed.count / 3),
            tokensOut: 0,
            durationMs: 0,
            feedback: 0,
            quotes: outgoingQuotes.isEmpty ? nil : outgoingQuotes
        )
        session.messages.append(userMsg)
        session.status = .running
        session.updatedAt = Date()
        activeSession = session

        let sessionId = session.id
        let traceId = session.traceId
        let mode = session.mode
        let modelLabel = currentModelDisplayName(for: session.modelId)

        // Production: zcode-task facade (createTask v4 + sendPrompt replayable); progress arrives via onDynamicTaskEvent.
        if !isUITestSeededMode {
            let userMessageId = userMsg.id
            let promptText = trimmed.isEmpty ? "Inspect attached files" : trimmed
            let legacyPromptText = outgoingQuotes.isEmpty ? promptText : outgoingQuotes
                .map { quote in quote.text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n") }
                .joined(separator: "\n\n") + "\n\n" + promptText
            activeStreamTask?.cancel()
            activeStreamTask = Task { @MainActor in
                guard let conn = activeConnection, conn.state == .connected else {
                    if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                        sessions[idx].status = .error
                        sessions[idx].statusNoticeText = "Remote workstation is disconnected. Reconnect to send prompts to your ZCode computer."
                    }
                    return
                }

                if v4Sync.available != false {
                    if conn.transport == .cloudRelayV2 {
                        do {
                            try await openBridge(for: session)
                        } catch let error where sessionId.hasPrefix("task-") && session.workspacePath.isEmpty {
                            if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                                sessions[idx].status = .error
                                sessions[idx].statusNoticeText = "Couldn't prepare a workspace on your computer: \(error.localizedDescription)"
                            }
                            return
                        } catch {}
                    }
                    v4Sync.optimistic.append((userMsg, Date()))
                    if await v4SendPrompt(sessionId: sessionId, text: promptText, attachments: outgoingAttachments, quotes: outgoingQuotes, queue: false) {
                        return
                    }
                    v4Sync.optimistic.removeAll { $0.message.id == userMessageId }
                }

                var targetSessionId = sessionId
                do {
                    let isDraft = targetSessionId.hasPrefix("task-")
                    if conn.transport == .cloudRelayV2 {
                        try await openBridge(for: sessions.first(where: { $0.id == sessionId }) ?? session)
                    }
                    let current = sessions.first(where: { $0.id == sessionId }) ?? session
                    let wsPath = current.workspacePath
                    let wsIdentity = current.workspaceIdentity ?? workspaceIdentityByPath[wsPath]

                    let selection = (sessions.first(where: { $0.id == sessionId })).flatMap { modelSelection(for: $0) }

                    if isDraft {
                        var createReq: [String: Any] = [
                            "workspacePath": wsPath,
                            "mode": mode.wireValue,
                            "v4Create": true
                        ]
                        if let wsIdentity, !wsIdentity.isEmpty { createReq["workspaceIdentity"] = wsIdentity }
                        if let selection { createReq["modelSelection"] = selection.jsonObject }
                        let created = try await rpcClient.call(
                            channel: "zcode-task",
                            method: "createTask",
                            args: [.fromJSONObject(createReq)],
                            timeoutSec: 20.0
                        )
                        let createdDict = created.decodeJSONDictionary() ?? [:]
                        let meta = (createdDict["meta"] as? [String: Any]) ?? createdDict
                        guard let realTaskId = (meta["taskId"] as? String) ?? (createdDict["taskId"] as? String), !realTaskId.isEmpty else {
                            throw NSError(domain: "ZCodeRPC", code: -2, userInfo: [NSLocalizedDescriptionKey: "Host did not return a task id."])
                        }
                        if let sIdx = sessions.firstIndex(where: { $0.id == targetSessionId }) {
                            sessions[sIdx].id = realTaskId
                            if let traceId = meta["traceId"] as? String, !traceId.isEmpty { sessions[sIdx].traceId = traceId }
                            if let selection {
                                sessions[sIdx].modelProviderId = selection.providerId
                                sessions[sIdx].modelId = selection.modelId
                                sessions[sIdx].reasoningLevel = selection.reasoningLevel
                            }
                        }
                        if activeSessionId == targetSessionId { activeSessionId = realTaskId }
                        targetSessionId = realTaskId
                    }

                    if let current = sessions.first(where: { $0.id == targetSessionId }) {
                        await subscribeActiveTask(current)
                    }

                    var promptReq: [String: Any] = [
                        "taskId": targetSessionId,
                        "traceId": sessions.first(where: { $0.id == targetSessionId })?.traceId ?? UUID().uuidString.lowercased(),
                        "queryId": UUID().uuidString.lowercased(),
                        "messageId": userMessageId,
                        "content": legacyPromptText,
                        "attachments": [Any](),
                        "clientId": Self.remoteClientId,
                        "clientMode": "web-remote-replayable"
                    ]
                    if let selection { promptReq["modelSelection"] = selection.jsonObject }
                    if let bridge = await rpcClient.currentBridge(), bridge.kind == "remote",
                       let remoteSessionId = bridge.remoteSessionId, !remoteSessionId.isEmpty {
                        promptReq["remoteSessionId"] = remoteSessionId
                    }

                    _ = try await rpcClient.call(
                        channel: "zcode-task",
                        method: "sendPrompt",
                        args: [.fromJSONObject(promptReq)],
                        timeoutSec: 30.0
                    )
                    scheduleSnapshotRefetch(taskId: targetSessionId, delay: 0.6)
                } catch {
                    if let idx = sessions.firstIndex(where: { $0.id == targetSessionId || $0.id == sessionId }) {
                        sessions[idx].status = .error
                        sessions[idx].statusNoticeText = "Couldn't send to \(conn.name): \(error.localizedDescription)"
                    }
                }
            }
            return
        }

        // Deterministic XCTest Fixture Stream (ONLY when `--uitesting-seed-workspace` is active)
        activeStreamTask?.cancel()
        activeStreamTask = Task { @MainActor in
            let assistantId = UUID().uuidString
            appendAssistantPlaceholder(sessionId: sessionId, messageId: assistantId, modelLabel: modelLabel)

            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            updateAssistantTurn(sessionId: sessionId, messageId: assistantId) { msg in
                msg.thought = "Analyzing workspace graph, symbol dependencies, and active mode (\(mode.label))..."
                msg.thoughtDurationMs = 640
                msg.tools = [
                    ToolCallItem(
                        id: UUID().uuidString,
                        kind: .readFile,
                        title: "Read src/rpc/SocketProtocol.swift",
                        subtitle: "Lines 1–32 • Verified binary header invariants",
                        status: .completed,
                        filePath: "src/rpc/SocketProtocol.swift",
                        lineRange: "1-32",
                        diffPatch: nil,
                        command: nil,
                        output: nil,
                        durationMs: 38,
                        addedLines: 0,
                        removedLines: 0,
                        subagentSteps: []
                    )
                ]
            }

            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }

            if trimmed == "/ask-permission" {
                setSessionInteractiveGate(
                    sessionId: sessionId,
                    messageId: assistantId,
                    content: "I am ready to apply the production migration script. Please approve tool execution:",
                    permission: PermissionPrompt(
                        id: UUID().uuidString,
                        toolName: "Bash",
                        summary: "Execute schema migration and zero-downtime health check",
                        commandOrPath: "zcode-server migrate --verify",
                        previewDiffOrCommand: "$ zcode-server migrate --verify --timeout 30s",
                        riskLevel: "MEDIUM"
                    )
                )
                return
            }

            if trimmed == "/ask-question" {
                if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                    updateAssistantTurn(sessionId: sessionId, messageId: assistantId) { msg in
                        msg.content = "Before generating the transport adapter, please choose your preferred serialization profile:"
                    }
                    sessions[idx].status = .waitingQuestion
                    sessions[idx].pendingQuestion = QuestionPrompt(
                        id: UUID().uuidString,
                        header: "Transport",
                        question: "Which framing strategy should we enable for remote multi-workspace streaming?",
                        multiSelect: false,
                        options: [
                            QuestionOptionItem(id: "opt-1", label: "Binary VQL + CRC32 (Recommended)", detail: "Lowest latency & 100% compatible with ZCode Server v3.16.3", previewCode: "SocketFrameHeader(messageType: 1, payloadBytes: len)"),
                            QuestionOptionItem(id: "opt-2", label: "Multiplexed SSH Duplex", detail: "Stdio proxy over existing SSH ControlMaster tunnels", previewCode: "zcode-server proxy-stdio --json")
                        ]
                    )
                }
                return
            }

            if mode == .plan || trimmed.hasPrefix("/plan") {
                if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                    updateAssistantTurn(sessionId: sessionId, messageId: assistantId) { msg in
                        msg.content = "I surveyed the codebase and prepared an execution plan for your review:"
                    }
                    sessions[idx].status = .waitingPlan
                    sessions[idx].pendingPlan = PlanReviewPrompt(
                        id: UUID().uuidString,
                        title: "Implementation Plan • \(String(trimmed.prefix(36)))",
                        summary: "Modular zero-downtime update preserving VQL wire compatibility and full test coverage.",
                        steps: [
                            "Update frame codec & validate boundary conditions in src/rpc/SocketProtocol.swift",
                            "Add concurrent stress test in SocketProtocolTests",
                            "Verify clean build & zero UI/UX regressions across Inspector panels"
                        ],
                        verification: "Run `swift test --parallel` and inspect live diff in Changes tab."
                    )
                }
                return
            }

            updateAssistantTurn(sessionId: sessionId, messageId: assistantId) { msg in
                msg.tools.append(
                    ToolCallItem(
                        id: UUID().uuidString,
                        kind: .bash,
                        title: "swift test --parallel",
                        subtitle: "Exit 0 • All workspace checks green",
                        status: .completed,
                        filePath: nil,
                        lineRange: nil,
                        diffPatch: nil,
                        command: "swift test --parallel",
                        output: "Executed 18 tests, with 0 failures in 0.21s.",
                        durationMs: 210,
                        addedLines: 0,
                        removedLines: 0,
                        subagentSteps: []
                    )
                )
                msg.content = "Completed task for: **\(trimmed)**.\n\n- Verified `src/rpc/SocketProtocol.swift` and workspace assets.\n- Executed parallel test suite (`0 failures`).\n- You can open the **Inspector** (top-right) at any time to browse code, zoom architecture diagrams/PDFs, or inspect Git diffs."
                msg.tokensIn = 6420
                msg.tokensOut = 510
                msg.durationMs = 920
            }

            if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[idx].status = .completed
                sessions[idx].totalTokensIn += 6420
                sessions[idx].totalTokensOut += 510
                sessions[idx].contextUsedPercent = min(92, sessions[idx].contextUsedPercent + 3)
                sessions[idx].checkpoints.append(
                    GitCheckpointSnapshot(
                        id: UUID().uuidString,
                        label: String(trimmed.prefix(38)),
                        commitShortHash: String(UUID().uuidString.prefix(7)).lowercased(),
                        createdAt: Date(),
                        messageIndex: sessions[idx].messages.count - 1,
                        filesChanged: 1
                    )
                )

                if !sessions[idx].queuedPrompts.isEmpty {
                    let next = sessions[idx].queuedPrompts.removeFirst()
                    composerText = next.content
                    composerAttachments = next.attachments
                    sendPrompt()
                }
            }
        }
    }

    public func stopGeneration() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        guard var session = activeSession else { return }
        if v4Owns(session.id) {
            v4Stop(sessionId: session.id, workspacePath: session.workspacePath)
            showToast("Stopping…")
            return
        }
        session.status = .idle
        activeSession = session
        if let conn = activeConnection, conn.transport != .enterpriseSandbox, conn.state == .connected {
            let sid = session.id
            let wsPath = session.workspacePath
            let wsIdentity = workspaceIdentityByPath[wsPath]
            Task {
                var stopReq: [String: Any] = [
                    "taskId": sid,
                    "workspacePath": wsPath
                ]
                if let wsIdentity, !wsIdentity.isEmpty {
                    stopReq["workspaceIdentity"] = wsIdentity
                }
                _ = try? await rpcClient.call(
                    channel: "zcode-task",
                    method: "stopGeneration",
                    args: [.fromJSONObject(stopReq)],
                    timeoutSec: 5.0
                )
            }
        }
        showToast("Generation stopped")
    }

    public func steerQueuedPrompt(_ itemId: String) {
        guard var session = activeSession,
              let qIdx = session.queuedPrompts.firstIndex(where: { $0.id == itemId }) else { return }
        if v4Owns(session.id) {
            v4Fire("sendQueuedNow", payload: ["queueItemId": itemId], session: session, failure: "Couldn't send queued prompt")
            showToast("Sending queued prompt now")
            return
        }
        let item = session.queuedPrompts.remove(at: qIdx)
        activeStreamTask?.cancel()
        activeStreamTask = nil
        session.status = .idle
        activeSession = session

        composerText = item.content
        composerAttachments = item.attachments
        showToast("Steering task with queued prompt")
        sendPrompt()
    }

    public func editQueuedPrompt(_ itemId: String) {
        guard var session = activeSession,
              let qIdx = session.queuedPrompts.firstIndex(where: { $0.id == itemId }) else { return }
        if v4Owns(session.id) {
            v4Fire("deleteQueueItem", payload: ["queueItemId": itemId], session: session, failure: "Couldn't edit queued prompt")
        }
        let item = session.queuedPrompts.remove(at: qIdx)
        activeSession = session
        composerText = item.content
        composerAttachments = item.attachments
    }

    public func deleteQueuedPrompt(_ itemId: String) {
        guard var session = activeSession else { return }
        if v4Owns(session.id) {
            v4Fire("deleteQueueItem", payload: ["queueItemId": itemId], session: session, failure: "Couldn't remove queued prompt")
        }
        session.queuedPrompts.removeAll(where: { $0.id == itemId })
        activeSession = session
    }

    // MARK: - SubAgent Slide-Over Drawer & Unified Task Status Panel Actions

    public var currentSubagentRuns: [SubagentSessionRun] {
        activeSession?.subagentRuns ?? []
    }

    public var runningBackgroundWorkCount: Int {
        currentSubagentRuns.filter(\.isRunning).count
    }

    /// Opens a running subagent's transcript; with no id, the first running subagent.
    public func openSubagentInspector(_ runId: String? = nil) {
        let runs = currentSubagentRuns
        guard let run = runId.flatMap({ id in runs.first(where: { $0.id == id }) }) ?? runs.first else {
            showToast("No running subagents")
            return
        }
        openSubagentSession(childSessionId: run.id, title: run.title)
    }

    /// Pause/resume the session goal through the real V4 goals commands (CAS, `snapshot.availability`).
    public func toggleGoalPaused() {
        guard let session = activeSession else { return }
        if isUITestSeededMode {
            var seeded = session
            seeded.goalPaused.toggle()
            activeSession = seeded
            showToast(seeded.goalPaused ? "Goal timer paused" : "Goal timer resumed")
            return
        }
        guard v4Owns(session.id) else {
            showToast("Goal controls are unavailable for this session")
            return
        }
        let paused = session.goalPaused
        let command = paused ? "resumeGoal" : "pauseGoal"
        if let availability = v4Sync.conversation?.state["availability"] as? [String: Any],
           let entry = availability[command] as? [String: Any],
           (entry["allowed"] as? Bool) == false {
            showToast(paused ? "No paused goal to resume" : "No active goal to pause")
            return
        }
        Task { @MainActor in
            do {
                try await self.v4Command(command, payload: [:], sessionId: session.id, workspacePath: session.workspacePath, cas: true)
                self.showToast(paused ? "Goal resumed" : "Goal paused")
            } catch {
                self.showToast("Couldn't change goal: \(error.localizedDescription)")
                self.v4Resync(force: false)
            }
        }
    }

    // MARK: - Desktop App Commands (/compact, /compress, /goal, /target)

    /// `/compact` and `/compress` request real host compaction; success is only reported after the RPC.
    private func requestContextCompaction(for session: AgentTaskSession) {
        if isUITestSeededMode {
            showToast("Requested context compaction")
            return
        }
        guard let conn = activeConnection, conn.state == .connected, conn.transport != .enterpriseSandbox else {
            showToast("Connect to your computer to compact the context")
            return
        }
        if v4Owns(session.id) {
            Task { @MainActor in
                do {
                    try await self.v4Command("compact", payload: [:], sessionId: session.id, workspacePath: session.workspacePath)
                    self.showToast("Requested context compaction")
                } catch {
                    let reason = (error as? V4CommandError)?.reasonCode
                    if reason == "activeTurn" {
                        self.showToast("Compact context after the current task finishes.")
                    } else if reason == "compactOperationLock" {
                        self.showToast("A compaction is already running or queued.")
                    } else {
                        self.showToast("Couldn't compact: \(error.localizedDescription)")
                    }
                }
            }
            return
        }
        guard !session.id.hasPrefix("task-") else {
            showToast("Send a message to start this session before compacting")
            return
        }
        Task { @MainActor in
            do {
                _ = try await self.rpcClient.call(
                    channel: "zcode-task",
                    method: "compactSession",
                    args: [.fromJSONObject(self.hostTaskScope(for: session))],
                    timeoutSec: 30
                )
                self.showToast("Requested context compaction")
            } catch {
                self.showToast("Couldn't compact: \(error.localizedDescription)")
            }
        }
    }

    /// Mirrors the desktop renderer's `/goal` parser (`DX`): returns true when the text was consumed.
    private func handleGoalSlashCommand(_ raw: String, session: AgentTaskSession) -> Bool {
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let command = parts.first?.lowercased(), command == "/goal" || command == "/target" else { return false }
        guard composerAttachments.isEmpty, composerQuotes.isEmpty else { return false }
        // Desktop only routes goal commands through the V4 pane; elsewhere the text stays a normal prompt.
        guard !isUITestSeededMode, v4Owns(session.id) else { return false }
        let body = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        composerText = ""
        guard !body.isEmpty else {
            showToast("Add a goal after /goal")
            return true
        }
        if session.mode == .plan {
            showToast("Goal is unavailable in Plan mode. Switch modes to continue.")
            return true
        }
        let head = body.split(separator: " ", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        if head == "resume" {
            Task { @MainActor in
                do {
                    try await self.v4Command("resumeGoal", payload: [:], sessionId: session.id, workspacePath: session.workspacePath, cas: true)
                    self.showToast("Goal resumed")
                } catch {
                    self.showToast("Couldn't resume goal: \(error.localizedDescription)")
                }
            }
            return true
        }
        if head == "pause" || head == "clear" || head == "show" {
            showToast("Use the Goal controls in the status panel")
            return true
        }
        let objective = head == "replace"
            ? String(body.dropFirst("replace".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            : body
        guard !objective.isEmpty else {
            showToast("Add a goal after /goal")
            return true
        }
        Task { @MainActor in
            do {
                _ = try await self.v4Command(
                    "sendGoalCommand",
                    payload: ["text": objective, "displayText": raw],
                    sessionId: session.id,
                    workspacePath: session.workspacePath
                )
                self.showToast("Goal set")
            } catch {
                self.showToast("Couldn't set goal: \(error.localizedDescription)")
            }
        }
        return true
    }

    public func binaryData(forPath path: String) -> Data? {
        flattenedFiles.first(where: { $0.path == path || $0.path.hasSuffix(path) })?.binaryData
    }

    // MARK: - Interactive Permission / Question / Plan Handlers

    public func respondToPermission(allow: Bool, rememberForSession: Bool = false) {
        if !isUITestSeededMode {
            if !respondToPermissionLive(allow: allow, rememberForSession: rememberForSession) {
                showToast("Not connected to the host")
            }
            return
        }
        playNotificationHaptic(allow ? .success : .warning)
        guard var session = activeSession, let perm = session.pendingPermission else { return }
        session.pendingPermission = nil
        session.status = .completed
        let decisionText = allow
            ? (rememberForSession ? "Approved (`Allow for Session`) — executed `\(perm.commandOrPath)`." : "Approved (`Allow Once`) — executed `\(perm.commandOrPath)`.")
            : "Denied execution of `\(perm.commandOrPath)`."
        session.messages.append(ChatTurnMessage(
            id: UUID().uuidString,
            role: "assistant",
            content: decisionText,
            thought: nil,
            thoughtDurationMs: 0,
            tools: allow ? [
                ToolCallItem(
                    id: UUID().uuidString,
                    kind: .bash,
                    title: perm.commandOrPath,
                    subtitle: "Approved on mobile",
                    status: .completed,
                    filePath: nil,
                    lineRange: nil,
                    diffPatch: nil,
                    command: perm.commandOrPath,
                    output: "Approval forwarded to ZCode Agent.",
                    durationMs: 120,
                    addedLines: 0,
                    removedLines: 0,
                    subagentSteps: []
                )
            ] : [],
            attachments: [],
            timestamp: Date(),
            modelLabel: currentModelDisplayName(for: session.modelId),
            tokensIn: 0,
            tokensOut: 0,
            durationMs: 120,
            feedback: 0
        ))
        for i in session.todos.indices {
            session.todos[i].status = "completed"
        }
        activeSession = session
        showToast(allow ? "Tool execution approved" : "Tool execution denied")
    }

    public func respondToQuestion(selectedLabel: String) {
        if !isUITestSeededMode {
            if !respondToQuestionLive(selectedLabel: selectedLabel) {
                showToast("Not connected to the host")
            }
            return
        }
        guard var session = activeSession else { return }
        session.pendingQuestion = nil
        session.status = .completed
        session.messages.append(ChatTurnMessage(
            id: UUID().uuidString,
            role: "assistant",
            content: "Submitted selection: **\(selectedLabel)**.",
            thought: nil,
            thoughtDurationMs: 0,
            tools: [],
            attachments: [],
            timestamp: Date(),
            modelLabel: currentModelDisplayName(for: session.modelId),
            tokensIn: 0,
            tokensOut: 0,
            durationMs: 120,
            feedback: 0
        ))
        activeSession = session
        showToast("Selection submitted")
    }

    public func respondToPlan(approved: Bool) {
        if !isUITestSeededMode {
            if !respondToPlanLive(approved: approved) {
                showToast("Not connected to the host")
            }
            return
        }
        guard var session = activeSession, let plan = session.pendingPlan else { return }
        session.pendingPlan = nil
        if approved {
            session.mode = .build
            session.status = .completed
            session.todos = plan.steps.enumerated().map { idx, step in
                TodoChecklistItem(id: "plan-td-\(idx)", content: step, status: "completed", priority: "high")
            }
            session.messages.append(ChatTurnMessage(
                id: UUID().uuidString,
                role: "assistant",
                content: "Plan approved! Switched to **Build** mode.",
                thought: nil,
                thoughtDurationMs: 0,
                tools: [],
                attachments: [],
                timestamp: Date(),
                modelLabel: currentModelDisplayName(for: session.modelId),
                tokensIn: 0,
                tokensOut: 0,
                durationMs: 150,
                feedback: 0
            ))
            showToast("Plan approved")
        } else {
            session.status = .idle
            showToast("Plan dismissed — add feedback in composer")
        }
        activeSession = session
    }

    // MARK: - Inspector Actions (Files, Inline Code Comments, Git, Terminal)

    public func openFileInInspector(pathOrId: String, preferPreview: Bool = false) {
        let all = flattenedFiles
        if let match = all.first(where: { $0.id == pathOrId || $0.path == pathOrId || $0.path.hasSuffix(pathOrId) }) {
            selectedFileId = match.id
            if !openFileIds.contains(match.id) {
                openFileIds.append(match.id)
            }
            if preferPreview || match.kind == .image || match.kind == .pdf || match.kind == .csv {
                activeInspectorTab = .preview
            } else {
                activeInspectorTab = .files
            }
            if !isUITestSeededMode, !match.isDirectory, match.textContent == nil, match.binaryData == nil {
                let targetId = match.id
                let targetPath = match.path
                Task { @MainActor in
                    await self.loadRemoteFileContentIfNeeded(fileId: targetId, filePath: targetPath)
                }
            }
        } else {
            activeInspectorTab = .files
        }
        mobilePage = .chat
        showInspectorSheet = true
    }

    public func addInlineCodeComment(filePath: String, startLine: Int, endLine: Int, comment: String, snippet: String) {
        let item = InlineCodeComment(
            id: UUID().uuidString,
            filePath: filePath,
            startLine: startLine,
            endLine: endLine,
            comment: comment,
            codeExcerpt: snippet,
            createdAt: Date()
        )
        inlineComments.insert(item, at: 0)
        let refLabel = startLine == endLine ? "\(filePath):\(startLine)" : "\(filePath):\(startLine)-\(endLine)"
        composerAttachments.append(
            ComposerAttachment(
                id: item.id,
                name: refLabel,
                kind: "comment",
                sizeBytes: comment.utf8.count,
                filePath: filePath,
                lineNote: comment,
                previewPNGData: nil
            )
        )
        showToast("Attached code comment \(refLabel) to composer")
    }

    public func toggleStageGitFile(_ id: String) {
        guard let idx = gitChanges.firstIndex(where: { $0.id == id }) else { return }
        gitChanges[idx].isStaged.toggle()
    }

    /// Seed-fixture Git mutation. Production uses `AppStore+Inspector` real `git` RPCs.
    public func stageAllGitChanges(_ staged: Bool) {
        guard isUITestSeededMode else { return }
        for idx in gitChanges.indices {
            gitChanges[idx].isStaged = staged
        }
        showToast(staged ? "Staged all changes" : "Unstaged all changes")
    }

    /// Seed-fixture Git commit. Production uses `commitInspectorStagedChanges` (`git.commit`).
    public func commitStagedChanges(message: String) {
        guard isUITestSeededMode else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let stagedItems = gitChanges.filter(\.isStaged)
        guard !stagedItems.isEmpty else {
            showToast("Stage at least one file before committing")
            return
        }
        gitChanges.removeAll(where: \.isStaged)
        let hash = String(UUID().uuidString.prefix(7)).lowercased()
        gitCommits.insert(
            GitCommitRecord(
                id: UUID().uuidString,
                shortHash: hash,
                subject: trimmed,
                author: userDisplayName,
                branchRef: "HEAD -> \(activeProject?.gitBranch ?? "main")",
                timestamp: Date()
            ),
            at: 0
        )
        if let pIdx = projects.firstIndex(where: { $0.id == activeProjectId }) {
            projects[pIdx].ahead += 1
            projects[pIdx].isDirty = !gitChanges.isEmpty
        }
        showToast("Committed \(hash)")
    }

    /// Seed-fixture branch switch. Production uses `switchInspectorGitBranch` (`git.switchBranch`).
    public func switchGitBranch(_ branch: String) {
        guard isUITestSeededMode else { return }
        activeGitBranch = branch
        if let pIdx = projects.firstIndex(where: { $0.id == activeProjectId }) {
            projects[pIdx].gitBranch = branch
        }
        showToast("Switched branch to \(branch)")
    }

    public func executeTerminalCommand(_ rawCommand: String) {
        let cmd = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        if terminalTabs.isEmpty {
            addTerminalTab()
        }
        guard let idx = terminalTabs.firstIndex(where: { $0.id == activeTerminalTabId }) ?? terminalTabs.indices.first else { return }

        if cmd == "clear" {
            terminalTabs[idx].entries.removeAll()
            return
        }

        if !isUITestSeededMode {
            let tabId = terminalTabs[idx].id
            Task { @MainActor in
                var out = "Disconnected from remote PTY."
                var isErr = true
                if let conn = activeConnection, conn.state == .connected {
                    if let resp = try? await rpcClient.call(channel: "terminal", method: "exec", args: [.fromJSONObject(["command": cmd])], timeoutSec: 8.0),
                       let dict = resp.decodeJSONDictionary(),
                       let stdout = dict["output"] as? String {
                        out = stdout
                        isErr = (dict["exitCode"] as? Int ?? 0) != 0
                    } else {
                        out = "\(conn.name) didn't run `\(cmd)`. Use the terminal tab for an interactive shell."
                    }
                }
                if let tIdx = self.terminalTabs.firstIndex(where: { $0.id == tabId }) {
                    self.terminalTabs[tIdx].entries.append(
                        TerminalEntry(id: UUID().uuidString, command: cmd, output: out, isError: isErr, timestamp: Date())
                    )
                }
            }
            return
        }

        let output: String
        switch cmd {
        case "pwd":
            output = terminalTabs[idx].cwd
        case "ls", "ls -la":
            output = "drwxr-xr-x  src/\ndrwxr-xr-x  assets/\n-rw-r--r--  README.md\n-rw-r--r--  zcode.config.json"
        case "git status":
            let summary = gitChanges.map { "\($0.isStaged ? "M " : " M") \($0.path)" }.joined(separator: "\n")
            output = "On branch \(activeProject?.gitBranch ?? "main")\n" + (summary.isEmpty ? "nothing to commit, working tree clean" : summary)
        default:
            output = "[PTY \(terminalTabs[idx].shell)] Executed: \(cmd)\nExit status: 0"
        }

        terminalTabs[idx].entries.append(
            TerminalEntry(
                id: UUID().uuidString,
                command: cmd,
                output: output,
                isError: false,
                timestamp: Date()
            )
        )
    }

    public func addTerminalTab() {
        let num = terminalTabs.count + 1
        let tab = TerminalTabModel(
            id: "term-\(UUID().uuidString.prefix(5))",
            title: "zsh #\(num)",
            cwd: activeProject?.rootPath ?? "~",
            shell: "/bin/zsh",
            isRunningJob: false,
            entries: [
                TerminalEntry(
                    id: UUID().uuidString,
                    command: nil,
                    output: "Remote PTY session #\(num) (\(activeConnection?.name ?? "workstation")).",
                    isError: false,
                    timestamp: Date()
                )
            ]
        )
        terminalTabs.append(tab)
        activeTerminalTabId = tab.id
    }

    // MARK: - Connection Management & Real Z.AI Remote Pairing

    public func addAndConnect(rawURLOrInput: String, customName: String = "", token: String = "") async -> Bool {
        guard let parsed = ConnectionURLParser.parse(rawURLOrInput) else {
            playNotificationHaptic(.error)
            showToast("Please enter a valid ZCode Remote URL (with sid & mid) or ws:// server")
            return false
        }
        let trimmedCustom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedCustom.isEmpty ? parsed.name : trimmedCustom
        let resolvedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (parsed.token ?? "") : token.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reuse existing connection if URL or (sid + mid) matches
        if let existingIdx = connections.firstIndex(where: {
            $0.url == parsed.normalizedURL || (!parsed.sid.isEmpty && $0.sid == parsed.sid && $0.mid == parsed.mid)
        }) {
            connections[existingIdx].name = finalName
            connections[existingIdx].url = parsed.normalizedURL
            connections[existingIdx].passHash = parsed.passHash
            connections[existingIdx].remoteControlToken = parsed.remoteControlToken
            if !resolvedToken.isEmpty {
                KeychainStore.save(resolvedToken, for: "conn_token_\(connections[existingIdx].id)")
            }
            let targetId = connections[existingIdx].id
            await connectToWorkstation(targetId)
            return true
        }

        let conn = RemoteConnection(
            name: finalName,
            transport: parsed.transport,
            url: parsed.normalizedURL,
            host: parsed.host,
            port: parsed.port,
            mid: parsed.mid,
            sid: parsed.sid,
            passHash: parsed.passHash,
            remoteControlToken: parsed.remoteControlToken,
            serverVersion: "",
            lastConnectedAt: Date(),
            state: .disconnected,
            latencyMs: 0
        )
        if !resolvedToken.isEmpty {
            KeychainStore.save(resolvedToken, for: "conn_token_\(conn.id)")
        }
        connections.insert(conn, at: 0)
        await connectToWorkstation(conn.id)
        return true
    }

    public func updateConnection(id: String, name: String, rawURL: String, token: String = "") {
        guard let idx = connections.firstIndex(where: { $0.id == id }),
              let parsed = ConnectionURLParser.parse(rawURL) else {
            showToast("Please enter a valid ZCode Remote URL")
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        connections[idx].name = trimmed.isEmpty ? parsed.name : trimmed
        connections[idx].transport = parsed.transport
        connections[idx].url = parsed.normalizedURL
        connections[idx].host = parsed.host
        connections[idx].port = parsed.port
        connections[idx].mid = parsed.mid
        connections[idx].sid = parsed.sid
        connections[idx].passHash = parsed.passHash
        connections[idx].remoteControlToken = parsed.remoteControlToken
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            KeychainStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines), for: "conn_token_\(id)")
        }
        showToast("Saved connection \(connections[idx].name)")
    }

    public func connectToWorkstation(_ connectionId: String, silent: Bool = false) async {
        guard let idx = connections.firstIndex(where: { $0.id == connectionId }) else { return }
        if !silent { clearReconnectBlock(for: connectionId) }
        for i in connections.indices where connections[i].id != connectionId && connections[i].transport != .enterpriseSandbox {
            connections[i].state = .disconnected
        }
        connections[idx].state = .connecting
        activeConnectionId = connectionId

        let target = connections[idx]
        if target.transport == .enterpriseSandbox {
            connections[idx].state = .connected
            connections[idx].lastConnectedAt = Date()
            pairingPhase = .connected
            showConnectionHub = false
            showToast("Connected to \(target.name)")
            return
        }

        pairingTargetId = target.id
        pairingTargetName = target.name
        pairingPhase = .connecting

        let storedConnToken = KeychainStore.load("conn_token_\(target.id)")
        let start = Date()

        do {
            if target.transport == .directServer {
                let useTLS = target.url.lowercased().hasPrefix("wss://") || target.port == 443
                if let info = try? await rpcClient.probeServerInfo(host: target.host, port: target.port, useTLS: useTLS, token: storedConnToken) {
                    if let cIdx = connections.firstIndex(where: { $0.id == connectionId }) {
                        connections[cIdx].serverVersion = info.version
                    }
                }
                try await rpcClient.connectDirectServer(wsURLString: target.url, token: storedConnToken) { [weak self] phase in
                    Task { @MainActor in
                        self?.pairingPhase = phase
                    }
                }
            } else if target.transport == .cloudRelayV2 {
                // Acquire short-lived Relay V2 terminal token via signed-in Z.AI JWT if available
                var relayToken = storedConnToken
                if (relayToken ?? "").isEmpty, !target.remoteControlToken.isEmpty {
                    relayToken = target.remoteControlToken
                }
                if let zcodeJwt = KeychainStore.load(zaiJwtKeychainKey), !zcodeJwt.isEmpty {
                    let origin = "https://\(target.host.isEmpty ? "zcode.z.ai" : target.host)"
                    if let freshRelayToken = try? await ZaiAuthAndRemoteService.shared.fetchRelayTerminalToken(zcodeJwt: zcodeJwt, origin: origin) {
                        relayToken = freshRelayToken
                    }
                }

                if (relayToken ?? "").isEmpty {
                    throw ZaiAuthError.oauthFailed("Sign in with your Z.AI account first to authorize ZCode Remote Control relay pairing.")
                }

                try await rpcClient.connectCloudRelayV2(
                    host: target.host,
                    mid: target.mid,
                    sid: target.sid,
                    passHash: target.passHash,
                    relayToken: relayToken,
                    deviceName: UIDevice.current.name
                ) { [weak self] phase in
                    Task { @MainActor in
                        self?.pairingPhase = phase
                    }
                }
            }

            await rpcClient.setWorkspaceListUpdateHandler { [weak self] summaries, activeKey, _ in
                Task { @MainActor in
                    self?.applyPushedWorkspaceListUpdate(summaries, activeWorkspaceKey: activeKey)
                }
            }
            await installLiveConnectionHandlers()

            pairingPhase = .pairedSyncing
            guard await syncRemoteWorkspacesFromServer(for: target) else {
                throw NSError(
                    domain: "ZCodeRelay",
                    code: 504,
                    userInfo: [NSLocalizedDescriptionKey: "ZCode Desktop didn't return its workspaces. Keep ZCode open on your computer and try again."]
                )
            }

            let ms = max(4, Int(Date().timeIntervalSince(start) * 1000))
            if let cIdx = connections.firstIndex(where: { $0.id == connectionId }) {
                connections[cIdx].latencyMs = ms
                connections[cIdx].state = .connected
                connections[cIdx].lastConnectedAt = Date()
            }
            pairingPhase = .connected
            showConnectionHub = false
            liveSync.reconnectAttempts = 0
            if !silent {
                mobilePage = .home
                playNotificationHaptic(.success)
                showToast("Connected to \(target.name) (\(ms)ms)")
            }
        } catch is CancellationError {
            pairingPhase = .idle
        } catch {
            if let cIdx = connections.firstIndex(where: { $0.id == connectionId }) {
                connections[cIdx].state = .error
            }
            pairingPhase = silent ? .idle : .failed(error.localizedDescription)
            if !silent { playNotificationHaptic(.error) }
        }
    }

    /// Returns `false` when the host could not be read; on a resync the current workspace state is kept untouched.
    @discardableResult
    func syncRemoteWorkspacesFromServer(for connection: RemoteConnection) async -> Bool {
        guard !isUITestSeededMode else { return true }

        let isResync = liveSync.syncedConnectionId == connection.id && !projects.isEmpty
        let previousSessions = isResync ? sessions : []
        let previousActiveSessionId = activeSessionId
        let previousActiveProjectId = activeProjectId
        let previousExpanded = expandedProjectIds
        let previousIdentities = workspaceIdentityByPath

        activeHydrationTask?.cancel()
        liveSync.reset()
        liveSync.suppressBridgeResubscribe = true
        defer { liveSync.suppressBridgeResubscribe = false }

        var nextProjects: [WorkspaceProject] = []
        var nextSessions: [AgentTaskSession] = []
        var preferredActiveWorkspaceKey: String?
        var preferredActiveTaskId: String?

        if connection.transport == .cloudRelayV2 {
            var resumeKey: String?
            var resumeTaskId: String?
            if isResync, let project = activeProject {
                resumeKey = ZCodeRPCClient.resolveWorkspaceKey(
                    workspacePath: project.rootPath,
                    workspaceIdentity: previousIdentities[project.rootPath]
                )
                if !previousActiveSessionId.hasPrefix("task-"), !previousActiveSessionId.isEmpty {
                    resumeTaskId = previousActiveSessionId
                }
            }
            let snapshot = await rpcClient.bootstrapRelayWorkspaces(
                preferredWorkspaceKey: resumeKey,
                preferredTaskId: resumeTaskId
            )
            if snapshot.desktopAppVersion == nil, snapshot.workspaces.isEmpty {
                return false
            }
            workspaceIdentityByPath.removeAll()
            if let desktopVer = snapshot.desktopAppVersion,
               !desktopVer.isEmpty,
               let cIdx = connections.firstIndex(where: { $0.id == connection.id }) {
                connections[cIdx].serverVersion = desktopVer
            }
            preferredActiveWorkspaceKey = snapshot.activeWorkspaceKey
            preferredActiveTaskId = snapshot.activeTaskId

            for ws in snapshot.workspaces {
                if let wsId = ws.workspaceIdentity, !wsId.isEmpty {
                    workspaceIdentityByPath[ws.workspacePath] = wsId
                }
                let projId = Self.stableProjectId(for: ws.workspaceKey)
                nextProjects.append(
                    WorkspaceProject(
                        id: projId,
                        name: ws.name,
                        rootPath: ws.workspacePath,
                        gitBranch: ws.branchName,
                        ahead: 0,
                        behind: 0,
                        isDirty: ws.isDirty,
                        isRemote: true,
                        pinned: false
                    )
                )
                for t in ws.tasks {
                    nextSessions.append(Self.makeAgentSession(from: t, projectId: projId))
                }
            }
        }

        if isResync {
            let previousById = Dictionary(previousSessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            nextSessions = nextSessions.map { Self.carryingLiveState(into: $0, from: previousById[$0.id]) }
            let nextIds = Set(nextSessions.map(\.id))
            nextSessions.append(contentsOf: previousSessions.filter { $0.id.hasPrefix("task-") && !nextIds.contains($0.id) })
        }

        self.isBulkSyncingWorkspaces = true
        self.projects = nextProjects
        let nextProjectIds = Set(nextProjects.map(\.id))
        if isResync {
            let known = Set(previousSessions.map(\.projectId))
            self.expandedProjectIds = previousExpanded.intersection(nextProjectIds)
                .union(nextProjectIds.filter { !known.contains($0) })
        } else {
            self.expandedProjectIds = nextProjectIds
        }
        if isResync, nextProjectIds.contains(previousActiveProjectId) {
            self.activeProjectId = previousActiveProjectId
        } else if let activeKey = preferredActiveWorkspaceKey {
            let targetProjId = Self.stableProjectId(for: activeKey)
            self.activeProjectId = nextProjects.first(where: { $0.id == targetProjId })?.id ?? nextProjects.first?.id ?? ""
        } else {
            self.activeProjectId = nextProjects.first?.id ?? ""
        }
        self.isBulkSyncingWorkspaces = false
        self.sessions = nextSessions
        if isResync, nextSessions.contains(where: { $0.id == previousActiveSessionId }) {
            preferredActiveTaskId = previousActiveSessionId
            self.activeSessionId = previousActiveSessionId
        } else {
            self.activeSessionId = preferredActiveTaskId ?? nextSessions.first?.id ?? ""
        }
        if !isResync || self.activeProjectId != previousActiveProjectId {
            self.fileTree = []
            self.openFileIds = []
            self.selectedFileId = ""
            self.gitChanges = []
            self.gitCommits = []
            self.terminalTabs = []
            self.activeTerminalTabId = ""
        }
        liveSync.syncedConnectionId = connection.id

        if connection.transport == .directServer, self.projects.isEmpty,
           let resolved = try? await self.rpcClient.call(channel: "file", method: "resolvePath", args: [.fromJSONObject(["path": "."])], timeoutSec: 3.0),
           case .string(let cwdPath) = resolved,
           !cwdPath.isEmpty {
            let projId = Self.stableProjectId(for: cwdPath)
            let folder = URL(fileURLWithPath: cwdPath).lastPathComponent
            self.isBulkSyncingWorkspaces = true
            self.projects = [
                WorkspaceProject(
                    id: projId,
                    name: folder.isEmpty ? connection.name : folder,
                    rootPath: cwdPath,
                    gitBranch: "main",
                    ahead: 0,
                    behind: 0,
                    isDirty: false,
                    isRemote: true,
                    pinned: false
                )
            ]
            self.activeProjectId = projId
            self.expandedProjectIds = [projId]
            self.isBulkSyncingWorkspaces = false
        }

        // Desktop sidebar parity: `project.readTree` covers every known workspace (projects + project-less tasks);
        // older hosts fall back to the per-open-workspace fan-out.
        if !(await loadProjectTree(preferredActiveTaskId: preferredActiveTaskId)) {
            sidebarTreeLoaded = false
            await loadAllWorkspaceTasks(preferredActiveTaskId: preferredActiveTaskId)
        }

        let primaryProject = self.activeProject
        activeHydrationTask = Task { @MainActor in
            await self.resubscribeAll(handlersCleared: false)
            if let primaryProject {
                await self.hydrateWorkspaceFilesAndGit(workspacePath: primaryProject.rootPath, projectId: primaryProject.id)
                await self.syncAllSettingsFromRemoteDesktop()
            }
        }
        return true
    }

    static func carryingLiveState(into fresh: AgentTaskSession, from existing: AgentTaskSession?) -> AgentTaskSession {
        guard let existing else { return fresh }
        var task = fresh
        task.messages = existing.messages
        task.todos = existing.todos
        task.contextUsedPercent = existing.contextUsedPercent
        task.pendingPermission = existing.pendingPermission
        task.pendingQuestion = existing.pendingQuestion
        task.pendingPlan = existing.pendingPlan
        task.queuedPrompts = existing.queuedPrompts
        return task
    }

    static func stableProjectId(for workspaceKey: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for b in workspaceKey.utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return String(format: "proj-%010llx", hash & 0xffffffffff)
    }

    static func makeAgentSession(from t: RemoteTaskSummary, projectId: String) -> AgentTaskSession {
        let selection = LiveModelSelection(pickerValue: t.model)
        return AgentTaskSession(
            id: t.id,
            traceId: UUID().uuidString.lowercased(),
            projectId: projectId,
            workspacePath: t.workspacePath,
            title: t.title,
            status: sessionStatus(t.status, pendingKind: t.pendingInteractionKind),
            mode: AgentExecutionMode(wire: t.mode),
            modelId: selection?.modelId ?? "",
            effort: .high,
            pinned: t.pinned,
            archived: t.archived,
            unread: t.unread,
            offPeakEnabled: false,
            createdAt: t.createdAt ?? t.updatedAt,
            updatedAt: t.updatedAt,
            contextUsedPercent: 0,
            totalTokensIn: 0,
            totalTokensOut: 0,
            cachedTokens: 0,
            costUSD: 0,
            messages: [],
            todos: [],
            pendingPermission: nil,
            pendingQuestion: nil,
            pendingPlan: nil,
            queuedPrompts: [],
            checkpoints: [],
            modelProviderId: selection?.providerId,
            reasoningLevel: t.thoughtLevel ?? selection?.reasoningLevel
        )
    }

    private func applyPushedWorkspaceListUpdate(
        _ summaries: [RemoteWorkspaceSummary],
        activeWorkspaceKey: String?
    ) {
        guard !isUITestSeededMode else { return }
        var updatedProjects: [WorkspaceProject] = []
        for ws in summaries {
            if let wsId = ws.workspaceIdentity, !wsId.isEmpty {
                workspaceIdentityByPath[ws.workspacePath] = wsId
            }
            let projId = Self.stableProjectId(for: ws.workspaceKey)
            let existing = projects.first(where: { $0.id == projId })
            updatedProjects.append(
                WorkspaceProject(
                    id: projId,
                    name: ws.name,
                    rootPath: ws.workspacePath,
                    gitBranch: existing?.gitBranch ?? ws.branchName,
                    ahead: existing?.ahead ?? 0,
                    behind: existing?.behind ?? 0,
                    isDirty: existing?.isDirty ?? ws.isDirty,
                    isRemote: true,
                    pinned: existing?.pinned ?? false
                )
            )
        }
        self.projects = updatedProjects
        for p in updatedProjects {
            expandedProjectIds.insert(p.id)
        }
        if let activeKey = activeWorkspaceKey {
            let pid = Self.stableProjectId(for: activeKey)
            if updatedProjects.contains(where: { $0.id == pid }) {
                activeProjectId = pid
            }
        } else if activeProjectId.isEmpty {
            activeProjectId = updatedProjects.first?.id ?? ""
        }
        let knownProjectIds = Set(sessions.map(\.projectId))
        for project in updatedProjects where !knownProjectIds.contains(project.id) {
            let identity = workspaceIdentityByPath[project.rootPath]
            scheduleWorkspaceRefresh(projectId: project.id, workspacePath: project.rootPath, workspaceIdentity: identity)
            Task { @MainActor in await self.subscribeWorkspaceEvents(project) }
        }
    }

    private func fetchTasksForWorkspace(
        workspacePath: String,
        workspaceIdentity: String?,
        projectId: String,
        timeoutSec: Double
    ) async -> [AgentTaskSession] {
        var req: [String: Any] = ["workspacePath": workspacePath]
        if let workspaceIdentity, !workspaceIdentity.isEmpty {
            req["workspaceIdentity"] = workspaceIdentity
        }
        let arg = VQLValue.fromJSONObject(req)

        async let pinnedCall = try? rpcClient.call(
            channel: "zcode-task",
            method: "listPinnedTasks",
            args: [arg],
            timeoutSec: timeoutSec
        )
        async let regularCall = try? rpcClient.call(
            channel: "zcode-task",
            method: "listTasks",
            args: [arg],
            timeoutSec: timeoutSec
        )

        let (pinnedVal, regularVal) = await (pinnedCall, regularCall)
        var seen = Set<String>()
        var out: [AgentTaskSession] = []

        for val in [pinnedVal, regularVal] {
            guard let val, case .array(let items) = val else { continue }
            for item in items {
                guard let dict = item.decodeJSONDictionary(),
                      let summary = ZCodeRPCClient.parseTaskSummary(
                          dict,
                          fallbackWorkspacePath: workspacePath,
                          fallbackWorkspaceIdentity: workspaceIdentity
                      ) else { continue }
                guard seen.insert(summary.id).inserted else { continue }
                out.append(Self.makeAgentSession(from: summary, projectId: projectId))
            }
        }

        out.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
        return out
    }

    @discardableResult
    func hydrateTaskSnapshot(
        sessionId: String,
        workspacePath: String,
        workspaceIdentity: String?
    ) async -> Bool {
        if v4Owns(sessionId) { return true }
        var req: [String: Any] = [
            "taskId": sessionId,
            "workspacePath": workspacePath,
            "messageLimit": 200,
            "clientMode": "web-remote-replayable"
        ]
        if let workspaceIdentity, !workspaceIdentity.isEmpty {
            req["workspaceIdentity"] = workspaceIdentity
        }

        guard let val = try? await rpcClient.call(
            channel: "zcode-task",
            method: "getTaskSnapshot",
            args: [.fromJSONObject(req)],
            timeoutSec: 10.0
        ),
              let dict = val.decodeJSONDictionary(),
              let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else {
            return false
        }
        applyTaskSnapshot(dict, sessionIndex: sIdx)
        return sessions[sIdx].status == .running
    }

    func hydrateWorkspaceFilesAndGit(workspacePath: String, projectId: String) async {
        guard !workspacePath.isEmpty, workspacePath != "~" else { return }

        async let dirCall = try? rpcClient.call(
            channel: "file",
            method: "readdir",
            args: [.fromJSONObject(["path": workspacePath, "includeHidden": false])],
            timeoutSec: 4.0
        )
        async let gitCall = try? rpcClient.call(
            channel: "git",
            method: "refresh",
            args: [.fromJSONObject([
                "workspacePath": workspacePath,
                "includeIdentity": false,
                "includeBranchComparison": false
            ])],
            timeoutSec: 6.0
        )

        let (dirVal, gitVal) = await (dirCall, gitCall)

        if let dirVal, case .array(let entries) = dirVal {
            var nodes: [WorkspaceFileNode] = []
            for entry in entries.prefix(200) {
                guard let d = entry.decodeJSONDictionary(),
                      let name = d["name"] as? String,
                      let fullPath = d["path"] as? String else { continue }
                let isDir = (d["type"] as? String) == "directory"
                nodes.append(
                    WorkspaceFileNode(
                        id: "file-\(Self.stableProjectId(for: fullPath))",
                        name: name,
                        path: fullPath,
                        kind: Self.inferFileKind(name: name, isDirectory: isDir),
                        gitStatus: nil,
                        sizeBytes: 0,
                        updatedAt: Date(),
                        textContent: nil,
                        binaryData: nil,
                        children: isDir ? [] : nil
                    )
                )
            }
            self.fileTree = nodes
        }

        if let gitVal, let gitDict = gitVal.decodeJSONDictionary() {
            if let summary = gitDict["summary"] as? [String: Any] {
                let branch = (summary["branchName"] as? String) ?? "main"
                let ahead = Self.jsonInt(summary["ahead"]) ?? 0
                let behind = Self.jsonInt(summary["behind"]) ?? 0
                let dirty = (summary["isDirty"] as? Bool) ?? false
                self.activeGitBranch = branch
                if let pIdx = projects.firstIndex(where: { $0.id == projectId }) {
                    projects[pIdx].gitBranch = branch
                    projects[pIdx].ahead = ahead
                    projects[pIdx].behind = behind
                    projects[pIdx].isDirty = dirty
                }
            }
            let stagedRaw = (gitDict["stagedChanges"] as? [[String: Any]]) ?? []
            let unstagedRaw = (gitDict["unstagedChanges"] as? [[String: Any]]) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: gitChanges.map { ($0.id, $0) })
            var changes: [GitChangedFile] = []
            for entry in stagedRaw {
                if let item = Self.parseHostGitChangedFile(entry, forceStaged: true, preserving: existingById) {
                    changes.append(item)
                }
            }
            for entry in unstagedRaw {
                if let item = Self.parseHostGitChangedFile(entry, forceStaged: false, preserving: existingById) {
                    changes.append(item)
                }
            }
            self.gitChanges = changes
            if let cur = selectedDiffFileId, changes.contains(where: { $0.id == cur }) {
                // preserve selection
            } else {
                self.selectedDiffFileId = changes.first?.id
            }
        }
    }

    private func loadRemoteFileContentIfNeeded(fileId: String, filePath: String) async {
        guard let val = try? await rpcClient.call(
            channel: "file",
            method: "readTextFile",
            args: [.fromJSONObject(["path": filePath, "offset": 0, "length": 131_072])],
            timeoutSec: 5.0
        ),
              let dict = val.decodeJSONDictionary(),
              let text = dict["content"] as? String else {
            return
        }
        let totalBytes = (dict["totalBytes"] as? Int) ?? text.utf8.count
        for idx in fileTree.indices where fileTree[idx].id == fileId {
            fileTree[idx].textContent = text
            fileTree[idx].sizeBytes = totalBytes
        }
    }

    private static func inferFileKind(name: String, isDirectory: Bool) -> WorkspaceFileKind {
        if isDirectory { return .directory }
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        switch ext {
        case "md", "markdown", "mdx": return .markdown
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return .image
        case "pdf": return .pdf
        case "csv", "tsv": return .csv
        case "json": return .json
        default: return .code
        }
    }

    public func removeConnection(_ id: String) {
        KeychainStore.delete("conn_token_\(id)")
        connections.removeAll(where: { $0.id == id })
        if activeConnectionId == id {
            Task { await rpcClient.disconnect() }
            activeConnectionId = connections.first?.id ?? ""
            if connections.isEmpty {
                projects = []
                sessions = []
                showConnectionHub = true
            }
        }
        showToast("Connection deleted")
    }

    // MARK: - Security Pattern & Biometrics

    public func savePattern(_ nodes: [Int]) {
        guard nodes.count >= 4 else { return }
        let hashed = KeychainStore.hashPattern(nodes, salt: patternSalt)
        KeychainStore.save(hashed, for: "zcode_pattern_lock_hash")
        hasPatternConfigured = true
        appLockEnabled = true
        showToast("Security pattern saved to Keychain")
    }

    public func verifyPattern(_ nodes: [Int]) -> Bool {
        if let until = lockoutUntil, until > Date() {
            return false
        }
        guard let stored = KeychainStore.load("zcode_pattern_lock_hash") else {
            isLocked = false
            return true
        }
        let candidate = KeychainStore.hashPattern(nodes, salt: patternSalt)
        if candidate == stored {
            failedUnlockAttempts = 0
            lockoutUntil = nil
            isLocked = false
            return true
        } else {
            failedUnlockAttempts += 1
            if failedUnlockAttempts >= 5 {
                lockoutUntil = Date().addingTimeInterval(60)
            }
            return false
        }
    }

    public func attemptBiometricUnlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            showToast("Biometrics unavailable on this device")
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock ZCode Mobile")
            if ok {
                isLocked = false
                failedUnlockAttempts = 0
            }
        } catch {
            // Keep lock screen active for pattern entry
        }
    }

    // MARK: - Helpers & Persistence

    public func currentModelDisplayName(for modelId: String) -> String {
        allModels.first(where: { $0.id == modelId })?.name ?? modelId
    }

    func appendAssistantPlaceholder(sessionId: String, messageId: String, modelLabel: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.append(
            ChatTurnMessage(
                id: messageId,
                role: "assistant",
                content: "Working on your request...",
                thought: "Connecting to ZCode execution engine...",
                thoughtDurationMs: 120,
                tools: [],
                attachments: [],
                timestamp: Date(),
                modelLabel: modelLabel,
                tokensIn: 0,
                tokensOut: 0,
                durationMs: 0,
                feedback: 0
            )
        )
    }

    func updateAssistantTurn(sessionId: String, messageId: String, mutate: (inout ChatTurnMessage) -> Void) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let mIdx = sessions[sIdx].messages.firstIndex(where: { $0.id == messageId }) else { return }
        mutate(&sessions[sIdx].messages[mIdx])
    }

    private func setSessionInteractiveGate(sessionId: String, messageId: String, content: String, permission: PermissionPrompt) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        updateAssistantTurn(sessionId: sessionId, messageId: messageId) { msg in
            msg.content = content
        }
        sessions[idx].status = .waitingApproval
        sessions[idx].pendingPermission = permission
    }

    private static func loadSavedConnectionsFromDisk(key: String) -> [RemoteConnection] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RemoteConnection].self, from: data) else {
            return []
        }
        // Filter out any test fixture entries and reset transient connection status to disconnected on fresh launch
        return decoded
            .filter { $0.transport != .enterpriseSandbox }
            .map { item in
                var copy = item
                copy.state = .disconnected
                return copy
            }
    }

    private func persistConnections() {
        guard !isUITestSeededMode else { return }
        let realOnly = connections.filter { $0.transport != .enterpriseSandbox }
        if let data = try? JSONEncoder().encode(realOnly) {
            UserDefaults.standard.set(data, forKey: connectionsKey)
        }
    }

    private func persistAccountMetadata() {
        guard !isUITestSeededMode else { return }
        if let acct = zaiAccount, let data = try? JSONEncoder().encode(acct) {
            UserDefaults.standard.set(data, forKey: accountKey)
        } else {
            UserDefaults.standard.removeObject(forKey: accountKey)
        }
    }

    private func loadAccountMetadata() {
        guard !isUITestSeededMode,
              let data = UserDefaults.standard.data(forKey: accountKey),
              let acct = try? JSONDecoder().decode(ZaiUserAccount.self, from: data),
              let jwt = KeychainStore.load(zaiJwtKeychainKey),
              !jwt.isEmpty else {
            return
        }
        zaiAccount = acct
    }

    private struct PersistedPrefs: Codable {
        var language: AppLanguage
        var themeMode: ZCodeThemeMode
        var syntaxTheme: ZCodeSyntaxTheme
        var codeFontSize: Double
        var showLineNumbers: Bool
        var wrapCodeLines: Bool
        var showReasoningBlocks: Bool
        var showTodoTracker: Bool
        var compactToolCards: Bool
        var hapticsEnabled: Bool
        var notificationsEnabled: Bool
        var notifyApprovals: Bool
        var notifyQuestions: Bool
        var notifyCompletions: Bool
        var notifyFailures: Bool
        var appLockEnabled: Bool
        var biometricUnlockEnabled: Bool
        var hasPatternConfigured: Bool
        var httpProxyURL: String
        var workspaceHookTrustGranted: Bool
        var offPeakWindowSchedule: String
        var browserAllowedDomains: String
        var fileSearchIgnorePatterns: String
        var cuaHelperEnabled: Bool
        var zaiRegion: ZaiAuthRegion?
        var didSkipAccountStep: Bool?
    }

    private func persistPreferences() {
        pushHostSettingsIfNeeded()
        let snap = PersistedPrefs(
            language: language,
            themeMode: themeMode,
            syntaxTheme: syntaxTheme,
            codeFontSize: codeFontSize,
            showLineNumbers: showLineNumbers,
            wrapCodeLines: wrapCodeLines,
            showReasoningBlocks: showReasoningBlocks,
            showTodoTracker: showTodoTracker,
            compactToolCards: compactToolCards,
            hapticsEnabled: hapticsEnabled,
            notificationsEnabled: notificationsEnabled,
            notifyApprovals: notifyApprovals,
            notifyQuestions: notifyQuestions,
            notifyCompletions: notifyCompletions,
            notifyFailures: notifyFailures,
            appLockEnabled: appLockEnabled,
            biometricUnlockEnabled: biometricUnlockEnabled,
            hasPatternConfigured: hasPatternConfigured,
            httpProxyURL: httpProxyURL,
            workspaceHookTrustGranted: workspaceHookTrustGranted,
            offPeakWindowSchedule: offPeakWindowSchedule,
            browserAllowedDomains: browserAllowedDomains,
            fileSearchIgnorePatterns: fileSearchIgnorePatterns,
            cuaHelperEnabled: cuaHelperEnabled,
            zaiRegion: zaiRegion,
            didSkipAccountStep: didSkipAccountStep
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: prefsKey)
        }
    }

    private func loadPreferences() {
        guard let data = UserDefaults.standard.data(forKey: prefsKey),
              let snap = try? JSONDecoder().decode(PersistedPrefs.self, from: data) else {
            return
        }
        language = snap.language
        themeMode = snap.themeMode
        syntaxTheme = snap.syntaxTheme
        codeFontSize = snap.codeFontSize
        showLineNumbers = snap.showLineNumbers
        wrapCodeLines = snap.wrapCodeLines
        showReasoningBlocks = snap.showReasoningBlocks
        showTodoTracker = snap.showTodoTracker
        compactToolCards = snap.compactToolCards
        hapticsEnabled = snap.hapticsEnabled
        notificationsEnabled = snap.notificationsEnabled
        notifyApprovals = snap.notifyApprovals
        notifyQuestions = snap.notifyQuestions
        notifyCompletions = snap.notifyCompletions
        notifyFailures = snap.notifyFailures
        appLockEnabled = snap.appLockEnabled
        biometricUnlockEnabled = snap.biometricUnlockEnabled
        hasPatternConfigured = snap.hasPatternConfigured
        httpProxyURL = snap.httpProxyURL
        workspaceHookTrustGranted = snap.workspaceHookTrustGranted
        offPeakWindowSchedule = snap.offPeakWindowSchedule
        browserAllowedDomains = snap.browserAllowedDomains
        fileSearchIgnorePatterns = snap.fileSearchIgnorePatterns
        cuaHelperEnabled = snap.cuaHelperEnabled
        if let reg = snap.zaiRegion { zaiRegion = reg }
        if let skip = snap.didSkipAccountStep { didSkipAccountStep = skip }
    }
}
