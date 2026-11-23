import Foundation

// MARK: - ZCode Remote Mobile Shell Navigation & View Modes

public enum MobileShellPage: String, Codable, Equatable {
    case home
    case chat
    case automations
    case pluginMarketplace
}

public enum TaskListViewMode: String, Codable, CaseIterable, Identifiable {
    case byProject = "projects"
    case grouped = "grouped"
    case timeline = "timeline"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .byProject: return "By project"
        case .grouped: return "Grouped"
        case .timeline: return "Recently updated"
        }
    }

    public var icon: String {
        switch self {
        case .byProject: return "folder"
        case .grouped: return "square.stack.3d.up"
        case .timeline: return "clock"
        }
    }
}

// MARK: - Z.AI Account Identity & Relay Pairing State

public enum ZaiAuthRegion: String, Codable, CaseIterable, Identifiable {
    case global = "zai"
    case cn = "bigmodel"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .global: return "Z.AI Global"
        case .cn: return "Z.AI CN (BigModel)"
        }
    }

    public var zcodeOrigin: String {
        switch self {
        case .global: return "https://zcode.z.ai"
        case .cn: return "https://zcode.z.ai"
        }
    }

    public var oauthUserInfoURL: String {
        switch self {
        case .global: return "https://chat.z.ai/api/oauth/userinfo"
        case .cn: return "https://open.bigmodel.cn/api/oauth/userinfo"
        }
    }
}

public struct ZaiUserAccount: Codable, Equatable {
    public var userId: String
    public var displayName: String
    public var email: String?
    public var avatarURL: String?
    public var region: ZaiAuthRegion
    public var signedInAt: Date

    public init(
        userId: String,
        displayName: String,
        email: String? = nil,
        avatarURL: String? = nil,
        region: ZaiAuthRegion = .global,
        signedInAt: Date = Date()
    ) {
        self.userId = userId
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
        self.region = region
        self.signedInAt = signedInAt
    }
}

public struct ZaiRegisteredRemoteDevice: Identifiable, Codable, Equatable {
    public var id: String { deviceSid }
    public var deviceSid: String
    public var deviceMid: String
    public var online: Bool
    public var createdAt: Date
    public var deviceName: String
    public var platform: String
    public var version: String

    public init(
        deviceSid: String,
        deviceMid: String,
        online: Bool,
        createdAt: Date = Date(),
        deviceName: String,
        platform: String = "desktop",
        version: String = "3.16.3"
    ) {
        self.deviceSid = deviceSid
        self.deviceMid = deviceMid
        self.online = online
        self.createdAt = createdAt
        self.deviceName = deviceName
        self.platform = platform
        self.version = version
    }
}

public enum RelayPairingPhase: Equatable {
    case idle
    case connecting
    case authenticating
    case waitingPairing
    case pairedSyncing
    case connected
    case failed(String)

    public var activeStepIndex: Int {
        switch self {
        case .idle: return 0
        case .connecting: return 1
        case .authenticating: return 2
        case .waitingPairing: return 3
        case .pairedSyncing: return 4
        case .connected: return 5
        case .failed: return 0
        }
    }

    public var title: String {
        switch self {
        case .idle: return "Ready to connect"
        case .connecting: return "Connecting relay service…"
        case .authenticating: return "Authenticating device…"
        case .waitingPairing: return "Waiting for desktop pairing…"
        case .pairedSyncing: return "Paired. Loading workspace…"
        case .connected: return "Connected"
        case .failed: return "Connection failed"
        }
    }

    public var subtitle: String {
        switch self {
        case .idle:
            return "Select or enter a ZCode Remote Control URL to begin."
        case .connecting:
            return "Establishing an encrypted connection between your iPhone and ZCode Relay."
        case .authenticating:
            return "Relay connected. Verifying your Z.AI remote-control identity."
        case .waitingPairing:
            return "Phone is ready. Waiting for ZCode on your computer to match this session."
        case .pairedSyncing:
            return "Connection established. Syncing desktop workspaces and tasks."
        case .connected:
            return "Remote workspace ready."
        case .failed(let reason):
            return reason
        }
    }

    public static let standardSteps: [String] = [
        "Connect to relay service",
        "Authenticate device",
        "Wait for desktop pairing",
        "Sync workspace"
    ]
}

// MARK: - Remote Connections & Workspaces

public enum ConnectionTransportKind: String, Codable, CaseIterable, Identifiable {
    case cloudRelayV2 = "relay_v2"
    case directServer = "direct_ws"
    case sshTunnel = "ssh_tunnel"
    case enterpriseSandbox = "sandbox"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cloudRelayV2: return "Z.AI Remote Control"
        case .directServer: return "ZCode Server (Direct WS)"
        case .sshTunnel: return "SSH Remote Host"
        case .enterpriseSandbox: return "Local Test Fixture"
        }
    }

    public var icon: String {
        switch self {
        case .cloudRelayV2: return "icloud.and.arrow.up.fill"
        case .directServer: return "network"
        case .sshTunnel: return "terminal.fill"
        case .enterpriseSandbox: return "cpu.fill"
        }
    }
}

public enum ConnectionState: String, Codable, Equatable {
    case connected
    case connecting
    case disconnected
    case error
}

public struct RemoteConnection: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var transport: ConnectionTransportKind
    public var url: String
    public var host: String
    public var port: Int
    public var mid: String
    public var sid: String
    public var passHash: String
    public var remoteControlToken: String
    public var serverVersion: String
    public var lastConnectedAt: Date
    public var lastTaskId: String
    public var loginGeneration: Int
    public var state: ConnectionState
    public var latencyMs: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        transport: ConnectionTransportKind,
        url: String,
        host: String = "zcode.z.ai",
        port: Int = 443,
        mid: String = "",
        sid: String = "",
        passHash: String = "",
        remoteControlToken: String = "",
        serverVersion: String = "3.16.3",
        lastConnectedAt: Date = Date(),
        lastTaskId: String = "",
        loginGeneration: Int = 0,
        state: ConnectionState = .disconnected,
        latencyMs: Int = 0
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.url = url
        self.host = host
        self.port = port
        self.mid = mid
        self.sid = sid
        self.passHash = passHash
        self.remoteControlToken = remoteControlToken
        self.serverVersion = serverVersion
        self.lastConnectedAt = lastConnectedAt
        self.lastTaskId = lastTaskId
        self.loginGeneration = loginGeneration
        self.state = state
        self.latencyMs = latencyMs
    }
}

public struct WorkspaceProject: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var rootPath: String
    public var gitBranch: String
    public var ahead: Int
    public var behind: Int
    public var isDirty: Bool
    public var isRemote: Bool
    public var pinned: Bool
}

// MARK: - Execution Modes, Models & Thought Levels

public enum AgentExecutionMode: String, Codable, CaseIterable, Identifiable {
    case ask = "default"
    case autoEdit = "edit"
    case plan = "plan"
    case build = "build"
    case guarded = "guarded"
    case yolo = "yolo"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ask: return "Ask"
        case .autoEdit: return "Auto Edit"
        case .plan: return "Plan"
        case .build: return "Build"
        case .guarded: return "Guarded"
        case .yolo: return "Full Access"
        }
    }

    public var subtitle: String {
        switch self {
        case .ask: return "Ask before file edits and shell commands"
        case .autoEdit: return "Auto-apply file edits, ask for shell commands"
        case .plan: return "Explore and present architecture plan before coding"
        case .build: return "Autonomous coding & test verification"
        case .guarded: return "Strict enterprise policy & sandboxed commands"
        case .yolo: return "Execute all tools autonomously without prompts"
        }
    }

    public var icon: String {
        switch self {
        case .ask: return "hand.raised"
        case .autoEdit: return "pencil.and.outline"
        case .plan: return "map"
        case .build: return "hammer"
        case .guarded: return "lock.shield"
        case .yolo: return "bolt.fill"
        }
    }
}

public enum ReasoningEffortLevel: String, Codable, CaseIterable, Identifiable {
    case off = "off"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case max = "max"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        case .max: return "Max"
        }
    }
}

public struct ModelDescriptor: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var providerId: String
    public var providerName: String
    public var contextWindowK: Int
    public var supportsVision: Bool
    public var supportsReasoning: Bool
    public var badge: String?
}

public struct ModelProviderConfig: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var protocolKind: String // "zai", "anthropic", "openai"
    public var enabled: Bool
    public var isBuiltin: Bool
    public var statusText: String
    public var models: [ModelDescriptor]
}

// MARK: - Sessions, Turns, Tools & Interactive Prompts

public enum TaskSessionStatus: String, Codable, Equatable {
    case idle
    case running
    case waitingApproval
    case waitingQuestion
    case waitingPlan
    case completed
    case error
}

public enum ToolCallKind: String, Codable {
    case readFile
    case editFile
    case writeFile
    case bash
    case search
    case mcp
    case subagent
    case workflow

    public var icon: String {
        switch self {
        case .readFile: return "doc.text"
        case .editFile: return "square.and.pencil"
        case .writeFile: return "doc.badge.plus"
        case .bash: return "terminal"
        case .search: return "magnifyingglass"
        case .mcp: return "puzzlepiece.extension"
        case .subagent: return "person.2.wave.2"
        case .workflow: return "point.3.connected.trianglepath.dotted"
        }
    }
}

public enum ToolCallStatus: String, Codable {
    case running
    case completed
    case failed
    case pendingApproval
}

public struct ToolCallItem: Identifiable, Codable, Equatable {
    public var id: String
    public var kind: ToolCallKind
    public var title: String
    public var subtitle: String
    public var status: ToolCallStatus
    public var filePath: String?
    public var lineRange: String?
    public var diffPatch: String?
    public var command: String?
    public var output: String?
    public var durationMs: Int
    public var addedLines: Int
    public var removedLines: Int
    public var subagentSteps: [String]
    public var subagentRunId: String?

    public init(
        id: String,
        kind: ToolCallKind,
        title: String,
        subtitle: String,
        status: ToolCallStatus,
        filePath: String?,
        lineRange: String?,
        diffPatch: String?,
        command: String?,
        output: String?,
        durationMs: Int,
        addedLines: Int,
        removedLines: Int,
        subagentSteps: [String],
        subagentRunId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.filePath = filePath
        self.lineRange = lineRange
        self.diffPatch = diffPatch
        self.command = command
        self.output = output
        self.durationMs = durationMs
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.subagentSteps = subagentSteps
        self.subagentRunId = subagentRunId
    }
}

public struct ComposerAttachment: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var kind: String // "image", "pdf", "file", "comment"
    public var sizeBytes: Int
    public var filePath: String?
    public var lineNote: String?
    public var previewPNGData: Data?
}

public struct InlineCodeComment: Identifiable, Codable, Equatable {
    public var id: String
    public var filePath: String
    public var startLine: Int
    public var endLine: Int
    public var comment: String
    public var codeExcerpt: String
    public var createdAt: Date
}

public struct TodoChecklistItem: Identifiable, Codable, Equatable {
    public var id: String
    public var content: String
    public var status: String // "completed", "in_progress", "pending"
    public var priority: String // "high", "medium", "low"
}

public struct PermissionPrompt: Identifiable, Codable, Equatable {
    public var id: String
    public var toolName: String
    public var summary: String
    public var commandOrPath: String
    public var previewDiffOrCommand: String
    public var riskLevel: String // "LOW", "MEDIUM", "HIGH"
}

public struct QuestionOptionItem: Identifiable, Codable, Equatable {
    public var id: String
    public var label: String
    public var detail: String
    public var previewCode: String?
}

public struct QuestionPrompt: Identifiable, Codable, Equatable {
    public var id: String
    public var header: String
    public var question: String
    public var multiSelect: Bool
    public var options: [QuestionOptionItem]
}

public struct PlanReviewPrompt: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var summary: String
    public var steps: [String]
    public var verification: String
}

public struct GitCheckpointSnapshot: Identifiable, Codable, Equatable {
    public var id: String
    public var label: String
    public var commitShortHash: String
    public var createdAt: Date
    public var messageIndex: Int
    public var filesChanged: Int
}

public struct ChatTurnMessage: Identifiable, Codable, Equatable {
    public var id: String
    public var role: String // "user" | "assistant"
    public var content: String
    public var thought: String?
    public var thoughtDurationMs: Int
    public var tools: [ToolCallItem]
    public var attachments: [ComposerAttachment]
    public var timestamp: Date
    public var modelLabel: String?
    public var tokensIn: Int
    public var tokensOut: Int
    public var durationMs: Int
    public var feedback: Int // 0 none, 1 up, -1 down
}

public struct QueuedPromptItem: Identifiable, Codable, Equatable {
    public var id: String
    public var content: String
    public var attachments: [ComposerAttachment]
    public var createdAt: Date

    public init(id: String = UUID().uuidString, content: String, attachments: [ComposerAttachment] = [], createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

public struct GoalObjectiveItem: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var completed: Bool

    public init(id: String, title: String, completed: Bool = false) {
        self.id = id
        self.title = title
        self.completed = completed
    }
}

public struct SubagentSessionRun: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var agentType: String
    public var isRunning: Bool
    public var elapsedText: String
    public var transcriptMarkdown: String
    public var artifactImagePath: String?
    public var timestamp: Date

    public init(
        id: String,
        title: String,
        agentType: String = "Explore",
        isRunning: Bool,
        elapsedText: String,
        transcriptMarkdown: String,
        artifactImagePath: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.agentType = agentType
        self.isRunning = isRunning
        self.elapsedText = elapsedText
        self.transcriptMarkdown = transcriptMarkdown
        self.artifactImagePath = artifactImagePath
        self.timestamp = timestamp
    }
}

public struct AgentTaskSession: Identifiable, Codable, Equatable {
    public var id: String
    public var traceId: String
    public var projectId: String
    public var workspacePath: String
    public var title: String
    public var status: TaskSessionStatus
    public var mode: AgentExecutionMode
    public var modelId: String
    public var effort: ReasoningEffortLevel
    public var pinned: Bool
    public var archived: Bool
    public var unread: Bool
    public var offPeakEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var contextUsedPercent: Int
    public var totalTokensIn: Int
    public var totalTokensOut: Int
    public var cachedTokens: Int
    public var costUSD: Double
    public var messages: [ChatTurnMessage]
    public var todos: [TodoChecklistItem]
    public var pendingPermission: PermissionPrompt?
    public var pendingQuestion: QuestionPrompt?
    public var pendingPlan: PlanReviewPrompt?
    public var queuedPrompts: [QueuedPromptItem]
    public var checkpoints: [GitCheckpointSnapshot]
    public var goals: [GoalObjectiveItem]
    public var goalElapsedText: String?
    public var goalPaused: Bool
    public var subagentRuns: [SubagentSessionRun]
    public var statusNoticeText: String?

    public init(
        id: String,
        traceId: String,
        projectId: String,
        workspacePath: String,
        title: String,
        status: TaskSessionStatus,
        mode: AgentExecutionMode,
        modelId: String,
        effort: ReasoningEffortLevel,
        pinned: Bool,
        archived: Bool,
        unread: Bool,
        offPeakEnabled: Bool,
        createdAt: Date,
        updatedAt: Date,
        contextUsedPercent: Int,
        totalTokensIn: Int,
        totalTokensOut: Int,
        cachedTokens: Int,
        costUSD: Double,
        messages: [ChatTurnMessage],
        todos: [TodoChecklistItem],
        pendingPermission: PermissionPrompt?,
        pendingQuestion: QuestionPrompt?,
        pendingPlan: PlanReviewPrompt?,
        queuedPrompts: [QueuedPromptItem],
        checkpoints: [GitCheckpointSnapshot],
        goals: [GoalObjectiveItem] = [],
        goalElapsedText: String? = nil,
        goalPaused: Bool = false,
        subagentRuns: [SubagentSessionRun] = [],
        statusNoticeText: String? = nil
    ) {
        self.id = id
        self.traceId = traceId
        self.projectId = projectId
        self.workspacePath = workspacePath
        self.title = title
        self.status = status
        self.mode = mode
        self.modelId = modelId
        self.effort = effort
        self.pinned = pinned
        self.archived = archived
        self.unread = unread
        self.offPeakEnabled = offPeakEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contextUsedPercent = contextUsedPercent
        self.totalTokensIn = totalTokensIn
        self.totalTokensOut = totalTokensOut
        self.cachedTokens = cachedTokens
        self.costUSD = costUSD
        self.messages = messages
        self.todos = todos
        self.pendingPermission = pendingPermission
        self.pendingQuestion = pendingQuestion
        self.pendingPlan = pendingPlan
        self.queuedPrompts = queuedPrompts
        self.checkpoints = checkpoints
        self.goals = goals
        self.goalElapsedText = goalElapsedText
        self.goalPaused = goalPaused
        self.subagentRuns = subagentRuns
        self.statusNoticeText = statusNoticeText
    }
}

// MARK: - Inspector Window: Files, Media, Diffs, Git, Terminal, Workflows

public enum InspectorTab: String, CaseIterable, Identifiable, Codable {
    case files = "files"
    case preview = "preview"
    case gitDiff = "git"
    case terminal = "terminal"
    case workflows = "workflows"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .files: return "Files"
        case .preview: return "Viewer"
        case .gitDiff: return "Changes"
        case .terminal: return "Terminal"
        case .workflows: return "Graph"
        }
    }

    public var icon: String {
        switch self {
        case .files: return "folder"
        case .preview: return "eye"
        case .gitDiff: return "arrow.triangle.branch"
        case .terminal: return "greaterthan.square"
        case .workflows: return "point.3.connected.trianglepath.dotted"
        }
    }
}

public enum WorkspaceFileKind: String, Codable, Equatable {
    case directory
    case code
    case markdown
    case image
    case pdf
    case csv
    case json
}

public struct WorkspaceFileNode: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var path: String
    public var kind: WorkspaceFileKind
    public var gitStatus: String? // "M", "A", "U", "D"
    public var sizeBytes: Int
    public var updatedAt: Date
    public var textContent: String?
    public var binaryData: Data?
    public var children: [WorkspaceFileNode]?

    public var isDirectory: Bool { kind == .directory }
}

public struct DiffLineItem: Identifiable, Equatable {
    public let id = UUID()
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let kind: String // "context", "add", "remove", "hunk"
    public let content: String
}

public struct GitChangedFile: Identifiable, Codable, Equatable {
    public var id: String
    public var path: String
    public var status: String // "M", "A", "U", "D"
    public var isStaged: Bool
    public var added: Int
    public var removed: Int
    public var patch: String
    public var beforeContent: String
    public var afterContent: String
}

public struct GitCommitRecord: Identifiable, Codable, Equatable {
    public var id: String
    public var shortHash: String
    public var subject: String
    public var author: String
    public var branchRef: String?
    public var timestamp: Date
}

public struct TerminalEntry: Identifiable, Codable, Equatable {
    public var id: String
    public var command: String?
    public var output: String
    public var isError: Bool
    public var timestamp: Date
}

public struct TerminalTabModel: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var cwd: String
    public var shell: String
    public var isRunningJob: Bool
    public var entries: [TerminalEntry]
}

public struct WorkflowGraphNode: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var role: String
    public var status: String // "completed", "running", "queued"
    public var durationText: String
    public var xRatio: Double
    public var yRatio: Double
}

// MARK: - Enterprise Ecosystem & Settings Models

public struct MCPServerItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var transport: String // "stdio", "http", "sse"
    public var endpointOrCommand: String
    public var enabled: Bool
    public var connected: Bool
    public var tools: [String]
    public var resourcesCount: Int
}

public struct SkillCatalogItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var summary: String
    public var scope: String // "Built-in", "User", "Workspace", "Plugin"
    public var enabled: Bool
    public var markdownBody: String
}

public struct PluginCatalogItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var version: String
    public var marketplace: String
    public var summary: String
    public var installed: Bool
    public var enabled: Bool
}

public struct SubagentDefinitionItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var modelOverride: String
    public var toolsSummary: String
    public var enabled: Bool
}

public struct SlashCommandItem: Identifiable, Codable, Equatable {
    public var id: String
    public var trigger: String // e.g. "/compact"
    public var summary: String
    public var scope: String // "System", "User", "Project"
    public var promptTemplate: String
}

public struct HookRuleItem: Identifiable, Codable, Equatable {
    public var id: String
    public var event: String // "PreToolUse", "PostToolUse", "Stop"
    public var matcher: String
    public var command: String
    public var enabled: Bool
}

public struct MemoryNoteItem: Identifiable, Codable, Equatable {
    public var id: String
    public var slug: String
    public var type: String // "user", "feedback", "project", "reference"
    public var description: String
    public var body: String
    public var updatedAt: Date
}

public struct AutomationScheduleItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var cronExpression: String
    public var workspacePath: String
    public var prompt: String
    public var enabled: Bool
    public var lastRunStatus: String
    public var lastRunAt: Date?
}

public struct DailyTokenUsageItem: Identifiable, Codable, Equatable {
    public var id: String
    public var dayLabel: String
    public var inputTokensK: Int
    public var outputTokensK: Int
    public var cachedTokensK: Int
    public var costUSD: Double
}

public struct NotificationInboxItem: Identifiable, Codable, Equatable {
    public var id: String
    public var category: String // "approval", "question", "completed", "error"
    public var title: String
    public var detail: String
    public var sessionId: String
    public var createdAt: Date
    public var isRead: Bool
}
