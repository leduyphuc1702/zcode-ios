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
    public var toolGroupingChangesEnabled: Bool = true { didSet { persistPreferences() } }
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
    public var computerUseComposerEntryHidden: Bool = false { didSet { persistPreferences() } }
    public var cuaAccessibilityStatus: String = "granted"
    public var cuaScreenRecordingStatus: String = "granted"
    public var remoteStartupAutoReconnectEnabled: Bool = true { didSet { persistPreferences() } }
    public var shortcutBindings: [ShortcutBindingItem] = ShortcutBindingItem.officialDefaults
    public var pluginMarketplaces: [String] = ["zcode-plugins-official"]
    public var isSyncingSettings: Bool = false
    public var lastSettingsSyncedAt: Date? = nil

    // MARK: - ZCode Remote Mobile Shell Navigation & Sheet State
    public var mobilePage: MobileShellPage = .home
    public var taskListViewMode: TaskListViewMode = .byProject
    public var projectsSectionExpanded: Bool = true
    public var expandedProjectIds: Set<String> = []
    public var userDisplayName: String = "ZCode User" { didSet { persistPreferences() } }
    public var isInspectorExpandedFull: Bool = false

    public var showSidebarDrawer: Bool = false
    public var showInspectorSheet: Bool = false
    public var activeInspectorTab: InspectorTab = .files
    public var showTaskStatusPanel: Bool = false
    public var hideCompletedTodosInStatusPanel: Bool = false
    public var showSubagentDrawer: Bool = false
    public var openSubagentTabIds: [String] = []
    public var activeSubagentId: String = ""
    public var activeGitBranch: String = "main"
    public var showSettingsSheet: Bool = false
    public var showConnectionsSheet: Bool = false
    public var showCommandCenter: Bool = false
    public var toastMessage: String? = nil

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

    // MARK: - Composer State
    public var composerText: String = ""
    public var composerAttachments: [ComposerAttachment] = []
    private var activeStreamTask: Task<Void, Never>?
    private var activeConnectTask: Task<Void, Never>?
    private var activeHydrationTask: Task<Void, Never>?
    internal var isBulkSyncingWorkspaces: Bool = false
    internal var workspaceIdentityByPath: [String: String] = [:]
    internal let rpcClient = ZCodeRPCClient()

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

        // Client capability definitions (built-in ZCode models, slash commands, skills, official plugins)
        self.providers = SeedWorkspaceFactory.defaultProviders()
        self.skills = SeedWorkspaceFactory.defaultSkills()
        self.plugins = SeedWorkspaceFactory.defaultPlugins()
        self.subagents = SeedWorkspaceFactory.defaultSubagents()
        self.slashCommands = SeedWorkspaceFactory.defaultSlashCommands()

        if shouldSeed {
            // Deterministic XCTest fixture mode ONLY
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
            self.showConnectionHub = true
            self.pairingPhase = .idle
        }

        loadPreferences()
        loadPersistedCatalogsIfAvailable()
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
        userDisplayName = "ZCode User"
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
            await syncRemoteWorkspacesFromServer(for: conn)
            showToast("Synced with \(conn.name)")
        } else {
            try? await Task.sleep(nanoseconds: 220_000_000)
            showToast("Workspace synced")
        }
    }

    // MARK: - Session & Project Operations

    public func createNewProject(name: String, rootPath: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = "proj-\(UUID().uuidString.prefix(6))"
        let path = rootPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? rootPath!
            : "~/\(trimmed)"
        let proj = WorkspaceProject(
            id: id,
            name: trimmed,
            rootPath: path,
            gitBranch: "main",
            ahead: 0,
            behind: 0,
            isDirty: false,
            isRemote: true,
            pinned: false
        )
        projects.append(proj)
        activeProjectId = id
        expandedProjectIds.insert(id)
        showToast("Added workspace \(trimmed)")
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
            let projectTasks = await self.fetchTasksForWorkspace(
                workspacePath: wsPath,
                workspaceIdentity: wsIdentity,
                projectId: projectId,
                timeoutSec: 3.5
            )
            if !projectTasks.isEmpty {
                var merged = self.sessions.filter { $0.projectId != projectId }
                merged.append(contentsOf: projectTasks)
                self.sessions = merged
                if !self.sessions.contains(where: { $0.id == self.activeSessionId }) {
                    self.activeSessionId = projectTasks.first?.id ?? ""
                }
            }
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
        let hostName = activeConnection?.name ?? "Remote Workspace"
        let fallback = WorkspaceProject(
            id: "proj-\(UUID().uuidString.prefix(6))",
            name: hostName,
            rootPath: "~",
            gitBranch: "main",
            ahead: 0,
            behind: 0,
            isDirty: false,
            isRemote: true,
            pinned: false
        )
        projects.append(fallback)
        activeProjectId = fallback.id
        expandedProjectIds.insert(fallback.id)
        return fallback
    }

    public func createNewSession(inProjectId: String? = nil, initialPrompt: String? = nil) {
        let project = ensureActiveProjectForNewSession(requestedProjectId: inProjectId)
        activeProjectId = project.id
        expandedProjectIds.insert(project.id)
        let newId = "task-\(UUID().uuidString.prefix(8))"
        let newSession = AgentTaskSession(
            id: newId,
            traceId: "trc_\(UUID().uuidString.prefix(8))",
            projectId: project.id,
            workspacePath: project.rootPath,
            title: "New task",
            status: .idle,
            mode: .yolo,
            modelId: "anthropic/claude-opus-4-7",
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
            checkpoints: []
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
        activeSessionId = session.id
        activeProjectId = session.projectId
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
            let wsIdentity = workspaceIdentityByPath[wsPath]
            let wsKey = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: wsPath, workspaceIdentity: wsIdentity)
            Task { @MainActor in
                if conn.transport == .cloudRelayV2 {
                    _ = try? await self.rpcClient.openWorkspaceBridge(workspaceKey: wsKey, taskId: sid, timeoutSec: 4.0)
                    await self.rpcClient.sendMobileViewStateUpdate(workspaceKey: wsKey, taskId: sid)
                }
                await self.hydrateTaskSnapshot(sessionId: sid, workspacePath: wsPath, workspaceIdentity: wsIdentity)
                await self.hydrateWorkspaceFilesAndGit(workspacePath: wsPath, projectId: session.projectId)
            }
        }
    }

    public func toggleMessageFeedback(messageId: String, rating: Int) {
        playSelectionHaptic()
        guard var session = activeSession,
              let mIdx = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
        session.messages[mIdx].feedback = (session.messages[mIdx].feedback == rating) ? 0 : rating
        activeSession = session
    }

    public func togglePinSession(_ id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].pinned.toggle()
        showToast(sessions[idx].pinned ? "Session pinned" : "Session unpinned")
    }

    public func archiveSession(_ id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].archived = true
        if activeSessionId == id {
            activeSessionId = sessions.first(where: { !$0.archived })?.id ?? ""
        }
        showToast("Session archived")
    }

    public func restoreSession(_ id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].archived = false
        activeSessionId = id
        showToast("Session restored")
    }

    public func deleteSession(_ id: String) {
        sessions.removeAll(where: { $0.id == id })
        if activeSessionId == id {
            activeSessionId = sessions.first(where: { !$0.archived })?.id ?? ""
        }
        showToast("Session deleted")
    }

    public func renameSession(_ id: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].title = trimmed
    }

    public func forkSession(_ id: String) {
        guard let source = sessions.first(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = "task-fork-\(UUID().uuidString.prefix(6))"
        copy.title = "\(source.title) (Fork)"
        copy.updatedAt = Date()
        sessions.insert(copy, at: 0)
        activeSessionId = copy.id
        showToast("Forked session created")
    }

    public func rewindToCheckpoint(_ checkpoint: GitCheckpointSnapshot) {
        guard var session = activeSession else { return }
        if checkpoint.messageIndex + 1 < session.messages.count {
            session.messages = Array(session.messages.prefix(checkpoint.messageIndex + 1))
        }
        session.updatedAt = Date()
        activeSession = session
        showToast("Rewound to \(checkpoint.commitShortHash)")
    }

    // MARK: - Streaming Prompt & Agent Execution

    public func sendPrompt() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !composerAttachments.isEmpty else { return }
        guard var session = activeSession else {
            createNewSession(initialPrompt: trimmed)
            return
        }

        if trimmed == "/compact" {
            composerText = ""
            session.contextUsedPercent = max(0, session.contextUsedPercent / 3)
            activeSession = session
            if let conn = activeConnection, conn.transport != .enterpriseSandbox, conn.state == .connected {
                Task {
                    _ = try? await rpcClient.call(channel: "zcode-task", method: "compactSession", args: [.fromJSONObject(["taskId": session.id])])
                }
            }
            showToast("Requested context compaction")
            return
        }

        if trimmed == "/goal" {
            composerText = ""
            session.mode = .yolo
            activeSession = session
            showToast("Auto-mode (/goal) enabled")
            return
        }

        if trimmed == "/clear" || trimmed == "/new" {
            composerText = ""
            createNewSession()
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

        if session.messages.isEmpty && (session.title == "New Coding Session" || session.title == "New task") {
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
            feedback: 0
        )
        session.messages.append(userMsg)
        session.status = .running
        session.updatedAt = Date()
        activeSession = session

        let sessionId = session.id
        let traceId = session.traceId
        let mode = session.mode
        let modelLabel = currentModelDisplayName(for: session.modelId)

        // Production Mode: Dispatch strictly over live ZCode Remote RPC (Zero fake demo output)
        if !isUITestSeededMode {
            activeStreamTask?.cancel()
            activeStreamTask = Task { @MainActor in
                let assistantId = UUID().uuidString
                appendAssistantPlaceholder(sessionId: sessionId, messageId: assistantId, modelLabel: modelLabel)

                guard let conn = activeConnection, conn.state == .connected else {
                    updateAssistantTurn(sessionId: sessionId, messageId: assistantId) { msg in
                        msg.thought = nil
                        msg.content = "Remote workstation is disconnected. Tap the host header or reconnect to send prompts to your ZCode computer."
                    }
                    if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                        sessions[idx].status = .error
                    }
                    return
                }

                do {
                    var targetSessionId = sessionId
                    let wsPath = session.workspacePath
                    let wsIdentity = workspaceIdentityByPath[wsPath]
                    let wsKey = ZCodeRPCClient.resolveWorkspaceKey(workspacePath: wsPath, workspaceIdentity: wsIdentity)

                    if conn.transport == .cloudRelayV2 {
                        _ = try await rpcClient.openWorkspaceBridge(workspaceKey: wsKey, taskId: targetSessionId.hasPrefix("task-") ? nil : targetSessionId, timeoutSec: 5.0)
                    }

                    // If this is a newly drafted mobile session, create the real task on ZCode Desktop first
                    if targetSessionId.hasPrefix("task-") {
                        var createReq: [String: Any] = [
                            "workspacePath": wsPath,
                            "mode": mode.rawValue,
                            "v4Create": true
                        ]
                        if let wsIdentity, !wsIdentity.isEmpty {
                            createReq["workspaceIdentity"] = wsIdentity
                        }
                        let created = try await rpcClient.call(
                            channel: "zcode-task",
                            method: "createTask",
                            args: [.fromJSONObject(createReq)],
                            timeoutSec: 8.0
                        )
                        if let createdDict = created.decodeJSONDictionary(),
                           let realTaskId = (createdDict["taskId"] as? String) ?? (createdDict["id"] as? String),
                           !realTaskId.isEmpty {
                            if let sIdx = sessions.firstIndex(where: { $0.id == targetSessionId }) {
                                sessions[sIdx].id = realTaskId
                            }
                            if activeSessionId == targetSessionId {
                                activeSessionId = realTaskId
                            }
                            targetSessionId = realTaskId
                        }
                    }

                    var promptReq: [String: Any] = [
                        "taskId": targetSessionId,
                        "traceId": traceId,
                        "content": trimmed.isEmpty ? "Inspect attached files" : trimmed,
                        "mode": mode.rawValue,
                        "clientMode": "web-remote-replayable"
                    ]
                    if let wsIdentity, !wsIdentity.isEmpty {
                        promptReq["workspaceIdentity"] = wsIdentity
                    }

                    _ = try await rpcClient.call(
                        channel: "zcode-task",
                        method: "sendPrompt",
                        args: [.fromJSONObject(promptReq)],
                        timeoutSec: 12.0
                    )

                    // Stream live snapshot updates until Desktop agent finishes the turn
                    for _ in 0..<90 {
                        guard !Task.isCancelled else { break }
                        let stillRunning = await hydrateTaskSnapshot(
                            sessionId: targetSessionId,
                            workspacePath: wsPath,
                            workspaceIdentity: wsIdentity
                        )
                        if !stillRunning {
                            break
                        }
                        try? await Task.sleep(nanoseconds: 550_000_000)
                    }

                    await hydrateWorkspaceFilesAndGit(workspacePath: wsPath, projectId: session.projectId)
                } catch {
                    updateAssistantTurn(sessionId: activeSessionId, messageId: assistantId) { msg in
                        msg.thought = nil
                        msg.content = "Remote RPC error on `\(conn.name)`: \(error.localizedDescription)"
                    }
                    if let idx = sessions.firstIndex(where: { $0.id == activeSessionId || $0.id == sessionId }) {
                        sessions[idx].status = .error
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
        let item = session.queuedPrompts.remove(at: qIdx)
        activeSession = session
        composerText = item.content
        composerAttachments = item.attachments
    }

    public func deleteQueuedPrompt(_ itemId: String) {
        guard var session = activeSession else { return }
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

    public func openSubagentInspector(_ runId: String? = nil) {
        let runs = currentSubagentRuns
        guard !runs.isEmpty else {
            spawnInteractiveSubagentTab()
            return
        }
        for r in runs where !openSubagentTabIds.contains(r.id) {
            openSubagentTabIds.append(r.id)
        }
        if let runId, runs.contains(where: { $0.id == runId }) {
            activeSubagentId = runId
        } else if activeSubagentId.isEmpty || !runs.contains(where: { $0.id == activeSubagentId }) {
            activeSubagentId = runs[0].id
        }
        showInspectorSheet = false
        showSubagentDrawer = true
    }

    public func closeSubagentTab(_ runId: String) {
        openSubagentTabIds.removeAll(where: { $0 == runId })
        if openSubagentTabIds.isEmpty {
            showSubagentDrawer = false
            activeSubagentId = ""
        } else if activeSubagentId == runId {
            activeSubagentId = openSubagentTabIds[0]
        }
    }

    public func spawnInteractiveSubagentTab() {
        guard var session = activeSession else { return }
        let idx = session.subagentRuns.count + 1
        let newId = "sub-spawn-\(idx)-\(UUID().uuidString.prefix(4))"
        let newRun = SubagentSessionRun(
            id: newId,
            title: "Explore workspace #\(idx)",
            agentType: "Explore",
            isRunning: true,
            elapsedText: "Running for 0m 02s",
            transcriptMarkdown: "Connected to subagent session for `\(session.title)`. Waiting for remote agent events…",
            artifactImagePath: nil,
            timestamp: Date()
        )
        session.subagentRuns.append(newRun)
        activeSession = session
        openSubagentTabIds.append(newId)
        activeSubagentId = newId
        showInspectorSheet = false
        showSubagentDrawer = true
    }

    public func toggleGoalPaused() {
        guard var session = activeSession else { return }
        session.goalPaused.toggle()
        activeSession = session
        showToast(session.goalPaused ? "Goal timer paused" : "Goal timer resumed")
    }

    public func binaryData(forPath path: String) -> Data? {
        flattenedFiles.first(where: { $0.path == path || $0.path.hasSuffix(path) })?.binaryData
    }

    // MARK: - Interactive Permission / Question / Plan Handlers

    public func respondToPermission(allow: Bool, rememberForSession: Bool = false) {
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

    public func stageAllGitChanges(_ staged: Bool) {
        for idx in gitChanges.indices {
            gitChanges[idx].isStaged = staged
        }
        showToast(staged ? "Staged all changes" : "Unstaged all changes")
    }

    public func commitStagedChanges(message: String) {
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

    public func switchGitBranch(_ branch: String) {
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
                        out = "Dispatched `\(cmd)` to \(conn.name) PTY."
                        isErr = false
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
            serverVersion: "3.16.3",
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

    public func connectToWorkstation(_ connectionId: String) async {
        guard let idx = connections.firstIndex(where: { $0.id == connectionId }) else { return }
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

            pairingPhase = .pairedSyncing
            await syncRemoteWorkspacesFromServer(for: target)

            let ms = max(4, Int(Date().timeIntervalSince(start) * 1000))
            if let cIdx = connections.firstIndex(where: { $0.id == connectionId }) {
                connections[cIdx].latencyMs = ms
                connections[cIdx].state = .connected
                connections[cIdx].lastConnectedAt = Date()
            }
            pairingPhase = .connected
            showConnectionHub = false
            mobilePage = .home
            playNotificationHaptic(.success)
            showToast("Connected to \(target.name) (\(ms)ms)")
        } catch is CancellationError {
            pairingPhase = .idle
        } catch {
            if let cIdx = connections.firstIndex(where: { $0.id == connectionId }) {
                connections[cIdx].state = .error
            }
            pairingPhase = .failed(error.localizedDescription)
            playNotificationHaptic(.error)
        }
    }

    private func syncRemoteWorkspacesFromServer(for connection: RemoteConnection) async {
        guard !isUITestSeededMode else { return }

        activeHydrationTask?.cancel()
        workspaceIdentityByPath.removeAll()

        var nextProjects: [WorkspaceProject] = []
        var nextSessions: [AgentTaskSession] = []
        var preferredActiveWorkspaceKey: String?
        var preferredActiveTaskId: String?

        if connection.transport == .cloudRelayV2 {
            let snapshot = await rpcClient.bootstrapRelayWorkspaces()
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

        self.isBulkSyncingWorkspaces = true
        self.projects = nextProjects
        self.expandedProjectIds = Set(nextProjects.map(\.id))
        if let activeKey = preferredActiveWorkspaceKey {
            let targetProjId = Self.stableProjectId(for: activeKey)
            self.activeProjectId = nextProjects.first(where: { $0.id == targetProjId })?.id ?? nextProjects.first?.id ?? ""
        } else {
            self.activeProjectId = nextProjects.first?.id ?? ""
        }
        self.isBulkSyncingWorkspaces = false
        self.sessions = nextSessions
        self.activeSessionId = preferredActiveTaskId ?? nextSessions.first?.id ?? ""
        self.fileTree = []
        self.openFileIds = []
        self.selectedFileId = ""
        self.gitChanges = []
        self.gitCommits = []
        self.terminalTabs = []
        self.activeTerminalTabId = ""

        // Hydrate tasks immediately (capped to sub-second / 1.5s fast path) and run deeper file/git/snapshot hydration concurrently in background
        let primaryProject = self.projects.first(where: { $0.id == self.activeProjectId }) ?? self.projects.first
        if let primaryProject {
            let wsPath = primaryProject.rootPath
            let wsIdentity = workspaceIdentityByPath[wsPath]
            let fetchedTasks = await fetchTasksForWorkspace(
                workspacePath: wsPath,
                workspaceIdentity: wsIdentity,
                projectId: primaryProject.id,
                timeoutSec: 1.8
            )
            if !fetchedTasks.isEmpty {
                self.sessions = fetchedTasks
                if let prefTask = preferredActiveTaskId,
                   fetchedTasks.contains(where: { $0.id == prefTask }) {
                    self.activeSessionId = prefTask
                } else {
                    self.activeSessionId = fetchedTasks.first?.id ?? ""
                }
            }
        }

        let targetSessionId = self.activeSessionId
        let allProjectsSnapshot = self.projects
        activeHydrationTask = Task { @MainActor in
            if let primaryProject {
                let wsPath = primaryProject.rootPath
                let wsIdentity = self.workspaceIdentityByPath[wsPath]
                if self.sessions.isEmpty {
                    let retryTasks = await self.fetchTasksForWorkspace(
                        workspacePath: wsPath,
                        workspaceIdentity: wsIdentity,
                        projectId: primaryProject.id,
                        timeoutSec: 4.5
                    )
                    if !retryTasks.isEmpty {
                        self.sessions = retryTasks
                        if self.activeSessionId.isEmpty {
                            self.activeSessionId = retryTasks.first?.id ?? ""
                        }
                    }
                }
                await self.hydrateWorkspaceFilesAndGit(workspacePath: wsPath, projectId: primaryProject.id)
                let sidToLoad = !targetSessionId.isEmpty ? targetSessionId : self.activeSessionId
                if !sidToLoad.isEmpty, !sidToLoad.hasPrefix("task-") {
                    _ = await self.hydrateTaskSnapshot(
                        sessionId: sidToLoad,
                        workspacePath: wsPath,
                        workspaceIdentity: wsIdentity
                    )
                }
                await self.syncAllSettingsFromRemoteDesktop()
            } else if connection.transport == .directServer {
                // Direct server fallback when workspace path was not pre-announced
                if let resolved = try? await self.rpcClient.call(channel: "file", method: "resolvePath", args: [.fromJSONObject(["path": "."])], timeoutSec: 3.0),
                   case .string(let cwdPath) = resolved,
                   !cwdPath.isEmpty {
                    let projId = Self.stableProjectId(for: cwdPath)
                    let folder = URL(fileURLWithPath: cwdPath).lastPathComponent
                    let proj = WorkspaceProject(
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
                    self.projects = [proj]
                    self.activeProjectId = projId
                    self.expandedProjectIds = [projId]
                    let tasks = await self.fetchTasksForWorkspace(workspacePath: cwdPath, workspaceIdentity: nil, projectId: projId, timeoutSec: 4.0)
                    self.sessions = tasks
                    self.activeSessionId = tasks.first?.id ?? ""
                    await self.hydrateWorkspaceFilesAndGit(workspacePath: cwdPath, projectId: projId)
                }
            }

            // Also fetch tasks for any secondary opened Desktop workspaces sequentially without stealing primary bridge unless needed
            if allProjectsSnapshot.count > 1, connection.transport == .directServer {
                for extra in allProjectsSnapshot.dropFirst() {
                    guard !Task.isCancelled else { break }
                    let extraTasks = await self.fetchTasksForWorkspace(
                        workspacePath: extra.rootPath,
                        workspaceIdentity: self.workspaceIdentityByPath[extra.rootPath],
                        projectId: extra.id,
                        timeoutSec: 3.0
                    )
                    for t in extraTasks where !self.sessions.contains(where: { $0.id == t.id }) {
                        self.sessions.append(t)
                    }
                }
            }
        }
    }

    private static func stableProjectId(for workspaceKey: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for b in workspaceKey.utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return String(format: "proj-%010llx", hash & 0xffffffffff)
    }

    private static func makeAgentSession(from t: RemoteTaskSummary, projectId: String) -> AgentTaskSession {
        let mappedStatus = TaskSessionStatus(rawValue: t.status) ?? .idle
        return AgentTaskSession(
            id: t.id,
            traceId: "trc_\(t.id.prefix(8))",
            projectId: projectId,
            workspacePath: t.workspacePath,
            title: t.title,
            status: mappedStatus,
            mode: .ask,
            modelId: "anthropic/claude-opus-4-7",
            effort: .high,
            pinned: t.pinned,
            archived: t.archived,
            unread: t.unread,
            offPeakEnabled: false,
            createdAt: t.updatedAt,
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
            checkpoints: []
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
    private func hydrateTaskSnapshot(
        sessionId: String,
        workspacePath: String,
        workspaceIdentity: String?
    ) async -> Bool {
        var req: [String: Any] = [
            "taskId": sessionId,
            "workspacePath": workspacePath,
            "messageLimit": 60,
            "clientMode": "web-remote-replayable"
        ]
        if let workspaceIdentity, !workspaceIdentity.isEmpty {
            req["workspaceIdentity"] = workspaceIdentity
        }

        guard let val = try? await rpcClient.call(
            channel: "zcode-task",
            method: "getTaskSnapshot",
            args: [.fromJSONObject(req)],
            timeoutSec: 5.0
        ),
              let dict = val.decodeJSONDictionary() else {
            return false
        }

        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else {
            return false
        }

        if let meta = dict["meta"] as? [String: Any] {
            if let title = (meta["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                sessions[sIdx].title = title
            }
            if let statusRaw = meta["status"] as? String,
               let mapped = TaskSessionStatus(rawValue: statusRaw) {
                sessions[sIdx].status = mapped
            }
        }

        if let rawMessages = dict["messages"] as? [[String: Any]] {
            var parsedTurns: [ChatTurnMessage] = []
            parsedTurns.reserveCapacity(rawMessages.count)

            for m in rawMessages {
                if m["syntheticTimeline"] != nil { continue }
                let mid = (m["id"] as? String) ?? UUID().uuidString
                let role = (m["role"] as? String) ?? "assistant"
                let content = (m["content"] as? String) ?? ""
                let thought = m["thought"] as? String
                let rawTs = (m["timestamp"] as? Double)
                    ?? (m["timestamp"] as? Int).map(Double.init)
                    ?? (Date().timeIntervalSince1970 * 1000)
                let tsDate = Date(timeIntervalSince1970: rawTs > 9_999_999_999 ? rawTs / 1000.0 : rawTs)

                var parsedTools: [ToolCallItem] = []
                if let rawTools = m["tools"] as? [[String: Any]] {
                    for t in rawTools {
                        let tid = (t["id"] as? String) ?? UUID().uuidString
                        let rawName = ((t["name"] as? String) ?? (t["toolName"] as? String) ?? "Tool")
                        let lower = rawName.lowercased()
                        let kind: ToolCallKind = {
                            if lower.contains("bash") || lower.contains("exec") || lower.contains("terminal") { return .bash }
                            if lower.contains("edit") || lower.contains("patch") { return .editFile }
                            if lower.contains("write") { return .writeFile }
                            if lower.contains("search") || lower.contains("grep") || lower.contains("glob") { return .search }
                            if lower.contains("agent") || lower.contains("task") { return .subagent }
                            if lower.contains("mcp") || lower.contains("__") { return .mcp }
                            return .readFile
                        }()
                        let rawStatus = ((t["status"] as? String) ?? "completed").lowercased()
                        let status: ToolCallStatus = rawStatus.contains("run") ? .running : (rawStatus.contains("err") || rawStatus.contains("fail") ? .failed : .completed)
                        let inputDict = t["input"] as? [String: Any]
                        let filePath = (t["filePath"] as? String) ?? (inputDict?["file_path"] as? String) ?? (inputDict?["path"] as? String)
                        let command = (t["command"] as? String) ?? (inputDict?["command"] as? String)
                        let outputStr = (t["output"] as? String) ?? (t["result"] as? String)
                        let subtitle = filePath ?? command ?? status.rawValue.capitalized

                        parsedTools.append(
                            ToolCallItem(
                                id: tid,
                                kind: kind,
                                title: rawName,
                                subtitle: String(subtitle.prefix(96)),
                                status: status,
                                filePath: filePath,
                                lineRange: nil,
                                diffPatch: t["diff"] as? String,
                                command: command,
                                output: outputStr,
                                durationMs: (t["durationMs"] as? Int) ?? 0,
                                addedLines: (t["addedLines"] as? Int) ?? 0,
                                removedLines: (t["removedLines"] as? Int) ?? 0,
                                subagentSteps: []
                            )
                        )
                    }
                }

                if content.isEmpty && (thought ?? "").isEmpty && parsedTools.isEmpty {
                    continue
                }

                parsedTurns.append(
                    ChatTurnMessage(
                        id: mid,
                        role: role,
                        content: content,
                        thought: thought,
                        thoughtDurationMs: 0,
                        tools: parsedTools,
                        attachments: [],
                        timestamp: tsDate,
                        modelLabel: role == "assistant" ? currentModelDisplayName(for: sessions[sIdx].modelId) : nil,
                        tokensIn: 0,
                        tokensOut: 0,
                        durationMs: 0,
                        feedback: 0
                    )
                )
            }

            if !parsedTurns.isEmpty {
                sessions[sIdx].messages = parsedTurns
            }
        }

        return sessions[sIdx].status == .running
    }

    private func hydrateWorkspaceFilesAndGit(workspacePath: String, projectId: String) async {
        guard !workspacePath.isEmpty, workspacePath != "~" else { return }

        async let dirCall = try? rpcClient.call(
            channel: "file",
            method: "readdir",
            args: [.fromJSONObject(["path": workspacePath, "includeHidden": false])],
            timeoutSec: 4.0
        )
        async let gitCall = try? rpcClient.call(
            channel: "git",
            method: "getStatus",
            args: [.string(workspacePath)],
            timeoutSec: 4.0
        )

        let (dirVal, gitVal) = await (dirCall, gitCall)

        if let dirVal, case .array(let entries) = dirVal {
            var nodes: [WorkspaceFileNode] = []
            for entry in entries.prefix(120) {
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
                let ahead = (summary["ahead"] as? Int) ?? 0
                let behind = (summary["behind"] as? Int) ?? 0
                let dirty = (summary["isDirty"] as? Bool) ?? false
                self.activeGitBranch = branch
                if let pIdx = projects.firstIndex(where: { $0.id == projectId }) {
                    projects[pIdx].gitBranch = branch
                    projects[pIdx].ahead = ahead
                    projects[pIdx].behind = behind
                    projects[pIdx].isDirty = dirty
                }
            }
            if let rawEntries = gitDict["entries"] as? [[String: Any]] {
                var changes: [GitChangedFile] = []
                for (i, e) in rawEntries.prefix(100).enumerated() {
                    guard let relPath = (e["path"] as? String) ?? (e["repoRelativePath"] as? String) else { continue }
                    let rawStatus = ((e["worktreeStatus"] as? String) ?? (e["indexStatus"] as? String) ?? (e["status"] as? String) ?? "M")
                    let staged = ((e["indexStatus"] as? String) ?? " ").trimmingCharacters(in: .whitespaces) != "" && ((e["indexStatus"] as? String) != "?")
                    changes.append(
                        GitChangedFile(
                            id: "git-live-\(i)-\(relPath)",
                            path: relPath,
                            status: String(rawStatus.prefix(1)).uppercased(),
                            isStaged: staged,
                            added: 0,
                            removed: 0,
                            patch: "",
                            beforeContent: "",
                            afterContent: ""
                        )
                    )
                }
                self.gitChanges = changes
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

    private func appendAssistantPlaceholder(sessionId: String, messageId: String, modelLabel: String) {
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

    private func updateAssistantTurn(sessionId: String, messageId: String, mutate: (inout ChatTurnMessage) -> Void) {
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
