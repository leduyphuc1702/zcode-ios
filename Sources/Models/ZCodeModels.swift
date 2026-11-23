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

    /// Modes offered by the official ZCode composer, in menu order.
    public static let officialCases: [AgentExecutionMode] = [.build, .autoEdit, .plan, .yolo]

    /// Maps a ZCode task mode string (including legacy aliases) to a mode.
    public init(wire: String?) {
        switch wire {
        case "edit": self = .autoEdit
        case "plan": self = .plan
        case "guarded": self = .guarded
        case "yolo", "bypassPermissions", "dontAsk": self = .yolo
        default: self = .build
        }
    }

    /// Value sent to `zcode-task.setMode` / `createTask`.
    public var wireValue: String {
        switch self {
        case .ask, .build: return "build"
        case .autoEdit: return "edit"
        case .plan: return "plan"
        case .guarded: return "guarded"
        case .yolo: return "yolo"
        }
    }

    public var label: String {
        switch self {
        case .ask, .build: return "Ask before changes"
        case .autoEdit: return "Edit automatically"
        case .plan: return "Plan mode"
        case .guarded: return "Guarded"
        case .yolo: return "Full access"
        }
    }

    public var subtitle: String {
        switch self {
        case .ask, .build: return "Ask before each file changes."
        case .autoEdit: return "Edit selected files or relevant workspace files automatically."
        case .plan: return "Inspect the code and present a plan before editing."
        case .guarded: return "Strict policy with sandboxed commands."
        case .yolo: return "Edit and run commands with fewer confirmations."
        }
    }

    public var icon: String {
        switch self {
        case .ask, .build: return "hand.raised"
        case .autoEdit: return "pencil.line"
        case .plan: return "list.bullet.clipboard"
        case .guarded: return "lock.shield"
        case .yolo: return "exclamationmark.shield"
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

public enum ProviderAPIFormat: String, Codable, CaseIterable, Identifiable {
    case anthropicMessages = "anthropic-messages"
    case openaiChatCompletions = "openai-chat-completions"
    case openaiResponses = "openai-responses"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropicMessages: return "Anthropic Messages"
        case .openaiChatCompletions: return "OpenAI Chat Completions"
        case .openaiResponses: return "OpenAI Responses"
        }
    }

    public var shortBadge: String {
        switch self {
        case .anthropicMessages: return "Anthropic API"
        case .openaiChatCompletions: return "Chat Completions"
        case .openaiResponses: return "Responses API"
        }
    }
}

public enum ModelConnectivityState: String, Codable, Equatable {
    case untested
    case testing
    case connected
    case failed
}

public struct ModelDescriptor: Identifiable, Codable, Equatable {
    public var id: String
    public var modelId: String
    public var name: String
    public var providerId: String
    public var providerName: String
    public var enabled: Bool
    public var builtin: Bool
    public var useRecommendedConfig: Bool
    public var contextWindowTokens: Int
    public var maxOutputTokens: Int
    public var supportsVision: Bool
    public var supportsVideo: Bool
    public var supportsAudio: Bool
    public var supportsPdf: Bool
    public var supportsToolCall: Bool
    public var supportsReasoning: Bool
    public var supportsJsonSchemaOutput: Bool
    public var supportsNativeWebSearch: Bool
    public var supportsMidConversationSystem: Bool
    public var reasoningLevels: [String]
    public var badge: String?
    public var connectivityState: ModelConnectivityState
    public var connectivityMessage: String?

    public var contextWindowK: Int {
        get { max(1, contextWindowTokens / 1000) }
        set { contextWindowTokens = max(1024, newValue * 1000) }
    }

    public var formattedContextWindow: String {
        if contextWindowTokens >= 1_000_000 {
            let m = Double(contextWindowTokens) / 1_000_000.0
            return m.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(m))M" : String(format: "%.1fM", m)
        }
        return "\(max(1, contextWindowTokens / 1000))K"
    }

    public init(
        id: String,
        modelId: String? = nil,
        name: String,
        providerId: String,
        providerName: String,
        enabled: Bool = true,
        builtin: Bool = true,
        useRecommendedConfig: Bool = true,
        contextWindowK: Int = 200,
        contextWindowTokens: Int? = nil,
        maxOutputTokens: Int = 16_384,
        supportsVision: Bool = true,
        supportsVideo: Bool = false,
        supportsAudio: Bool = false,
        supportsPdf: Bool = false,
        supportsToolCall: Bool = true,
        supportsReasoning: Bool = true,
        supportsJsonSchemaOutput: Bool = true,
        supportsNativeWebSearch: Bool = false,
        supportsMidConversationSystem: Bool = true,
        reasoningLevels: [String] = ["off", "low", "medium", "high", "max"],
        badge: String? = nil,
        connectivityState: ModelConnectivityState = .untested,
        connectivityMessage: String? = nil
    ) {
        self.id = id
        let resolvedRawId = modelId ?? (id.contains("/") ? String(id.split(separator: "/", maxSplits: 1).last ?? Substring(id)) : id)
        self.modelId = resolvedRawId
        self.name = name
        self.providerId = providerId
        self.providerName = providerName
        self.enabled = enabled
        self.builtin = builtin
        self.useRecommendedConfig = useRecommendedConfig
        self.contextWindowTokens = contextWindowTokens ?? (contextWindowK * 1000)
        self.maxOutputTokens = maxOutputTokens
        self.supportsVision = supportsVision
        self.supportsVideo = supportsVideo
        self.supportsAudio = supportsAudio
        self.supportsPdf = supportsPdf
        self.supportsToolCall = supportsToolCall
        self.supportsReasoning = supportsReasoning
        self.supportsJsonSchemaOutput = supportsJsonSchemaOutput
        self.supportsNativeWebSearch = supportsNativeWebSearch
        self.supportsMidConversationSystem = supportsMidConversationSystem
        self.reasoningLevels = reasoningLevels
        self.badge = badge
        self.connectivityState = connectivityState
        self.connectivityMessage = connectivityMessage
    }
}

public struct ModelProviderConfig: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var protocolKind: String // "anthropic-messages", "openai-chat-completions", "openai-responses", "zhipu-account"
    public var group: String // "zai-family", "bigmodel-family", "standard-personal"
    public var templateId: String?
    public var apiKeyManagementURL: String?
    public var hasConfiguredAPIKey: Bool
    public var enabled: Bool
    public var isBuiltin: Bool
    public var entitled: Bool
    public var accountAvailability: String // "available", "unavailable", "pending"
    public var statusText: String
    public var logoKey: String
    public var revision: Int
    public var models: [ModelDescriptor]

    public var apiFormat: ProviderAPIFormat {
        get {
            switch protocolKind {
            case "anthropic", "anthropic-messages", "zai":
                return .anthropicMessages
            case "openai-responses":
                return .openaiResponses
            default:
                return .openaiChatCompletions
            }
        }
        set {
            protocolKind = newValue.rawValue
        }
    }

    public var isAccountProvider: Bool {
        id.hasPrefix("account:") || group == "zai-family" || group == "bigmodel-family" || isBuiltin
    }

    public init(
        id: String,
        name: String,
        baseURL: String,
        protocolKind: String = ProviderAPIFormat.anthropicMessages.rawValue,
        group: String? = nil,
        templateId: String? = nil,
        apiKeyManagementURL: String? = nil,
        hasConfiguredAPIKey: Bool = false,
        enabled: Bool = true,
        isBuiltin: Bool = false,
        entitled: Bool = true,
        accountAvailability: String = "available",
        statusText: String = "Ready",
        logoKey: String = "custom",
        revision: Int = 1,
        models: [ModelDescriptor] = []
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.protocolKind = protocolKind
        self.group = group ?? (isBuiltin ? "zai-family" : "standard-personal")
        self.templateId = templateId
        self.apiKeyManagementURL = apiKeyManagementURL
        self.hasConfiguredAPIKey = hasConfiguredAPIKey
        self.enabled = enabled
        self.isBuiltin = isBuiltin
        self.entitled = entitled
        self.accountAvailability = accountAvailability
        self.statusText = statusText
        self.logoKey = logoKey
        self.revision = revision
        self.models = models
    }
}

public struct ProviderTemplateDescriptor: Identifiable, Equatable {
    public let id: String // exact templateId in zcode-builtin.json
    public let name: String
    public let category: String // "zhipu" | "other"
    public let apiFormat: ProviderAPIFormat
    public let defaultBaseURL: String
    public let apiKeyURL: String?
    public let logoSymbol: String
    public let accentHex: UInt32
    public let defaultModelIds: [String]

    public static let officialCatalog: [ProviderTemplateDescriptor] = [
        // Z.ai & BigModel Official Group
        ProviderTemplateDescriptor(
            id: "zai-api",
            name: "Z.ai Coding Plan",
            category: "zhipu",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://api.z.ai/api/anthropic",
            apiKeyURL: "https://z.ai/manage-apikey/apikey-list",
            logoSymbol: "sparkles",
            accentHex: 0x3B82F6,
            defaultModelIds: ["GLM-5.3", "GLM-5.3-Flash"]
        ),
        ProviderTemplateDescriptor(
            id: "zai-standard-api",
            name: "Z.ai API",
            category: "zhipu",
            apiFormat: .openaiChatCompletions,
            defaultBaseURL: "https://api.z.ai/api/paas/v4",
            apiKeyURL: "https://z.ai/manage-apikey/apikey-list",
            logoSymbol: "bolt.horizontal.circle.fill",
            accentHex: 0x2563EB,
            defaultModelIds: ["GLM-5.3", "GLM-5.3-Flash", "GLM-5V-Turbo", "GLM-5.1", "GLM-5.1-Highspeed", "GLM-5", "GLM-5-Turbo", "GLM-4.7"]
        ),
        ProviderTemplateDescriptor(
            id: "bigmodel-api",
            name: "BigModel Coding Plan",
            category: "zhipu",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://open.bigmodel.cn/api/anthropic",
            apiKeyURL: "https://bigmodel.cn/coding-plan/personal/overview",
            logoSymbol: "cpu.fill",
            accentHex: 0x4F46E5,
            defaultModelIds: ["GLM-5.3", "GLM-5.3-Flash"]
        ),
        ProviderTemplateDescriptor(
            id: "bigmodel-standard-api",
            name: "BigModel API",
            category: "zhipu",
            apiFormat: .openaiChatCompletions,
            defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4",
            apiKeyURL: "https://bigmodel.cn/usercenter/proj-mgmt/apikeys",
            logoSymbol: "server.rack",
            accentHex: 0x6366F1,
            defaultModelIds: ["GLM-5.3", "GLM-5.3-Flash", "GLM-5V-Turbo", "GLM-5.1", "GLM-5-Turbo", "GLM-4.7"]
        ),
        // Other Official Provider Templates (zcode-builtin.json)
        ProviderTemplateDescriptor(
            id: "anthropic",
            name: "Anthropic",
            category: "other",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://api.anthropic.com/v1",
            apiKeyURL: "https://console.anthropic.com/settings/keys",
            logoSymbol: "a.circle.fill",
            accentHex: 0xD97757,
            defaultModelIds: ["claude-fable-5-1", "claude-fable-5", "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001"]
        ),
        ProviderTemplateDescriptor(
            id: "openai",
            name: "OpenAI",
            category: "other",
            apiFormat: .openaiResponses,
            defaultBaseURL: "https://api.openai.com/v1",
            apiKeyURL: "https://platform.openai.com/api-keys",
            logoSymbol: "circle.hexagongrid.fill",
            accentHex: 0x10A37F,
            defaultModelIds: ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6", "gpt-5.4", "gpt-5.4-pro", "gpt-5.4-mini", "gpt-5.3-codex"]
        ),
        ProviderTemplateDescriptor(
            id: "openrouter",
            name: "OpenRouter",
            category: "other",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://openrouter.ai/api",
            apiKeyURL: "https://openrouter.ai/keys",
            logoSymbol: "arrow.triangle.branch",
            accentHex: 0x8B5CF6,
            defaultModelIds: ["anthropic/claude-opus-5", "anthropic/claude-sonnet-5", "openai/gpt-5.6", "deepseek/deepseek-v4-pro", "z-ai/glm-5.3", "moonshotai/kimi-k3", "qwen/qwen3.8-max"]
        ),
        ProviderTemplateDescriptor(
            id: "deepseek",
            name: "DeepSeek",
            category: "other",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://api.deepseek.com/anthropic",
            apiKeyURL: "https://platform.deepseek.com/api_keys",
            logoSymbol: "waveform.path.ecg",
            accentHex: 0x3B82F6,
            defaultModelIds: ["deepseek-v4-pro", "deepseek-flash"]
        ),
        ProviderTemplateDescriptor(
            id: "moonshot-kimi",
            name: "Kimi (Moonshot)",
            category: "other",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://api.moonshot.cn/anthropic",
            apiKeyURL: "https://platform.kimi.com/console/api-keys",
            logoSymbol: "moon.stars.fill",
            accentHex: 0x0EA5E9,
            defaultModelIds: ["kimi-k3", "kimi-k2.7-code", "kimi-k2.7-code-highspeed", "kimi-k2.6", "k3-256k"]
        ),
        ProviderTemplateDescriptor(
            id: "minimax",
            name: "MiniMax",
            category: "other",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://api.minimaxi.com/anthropic",
            apiKeyURL: "https://platform.minimaxi.com/console/access?tab=api-keys",
            logoSymbol: "waveform.circle.fill",
            accentHex: 0xEC4899,
            defaultModelIds: ["MiniMax-M3", "MiniMax-M2.7", "MiniMax-M2.7-highspeed", "MiniMax-M2.5"]
        ),
        ProviderTemplateDescriptor(
            id: "xai",
            name: "xAI (Grok)",
            category: "other",
            apiFormat: .openaiResponses,
            defaultBaseURL: "https://api.x.ai/v1",
            apiKeyURL: "https://console.x.ai",
            logoSymbol: "xmark.diamond.fill",
            accentHex: 0xA1A1AA,
            defaultModelIds: ["grok-4.6", "grok-build-0.1", "grok-4.3"]
        ),
        ProviderTemplateDescriptor(
            id: "qwen-alibaba-model-studio-intl",
            name: "Alibaba Cloud (Global)",
            category: "other",
            apiFormat: .openaiChatCompletions,
            defaultBaseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
            apiKeyURL: "https://modelstudio.console.aliyun.com/ap-southeast-1?tab=dashboard",
            logoSymbol: "cloud.fill",
            accentHex: 0xF97316,
            defaultModelIds: ["qwen3.8-max", "qwen3.8-flash", "qwen3.7-max", "qwen3.7-plus", "qwen3-vl-plus"]
        ),
        ProviderTemplateDescriptor(
            id: "qwen-alibaba-model-studio-cn",
            name: "Alibaba Cloud (China)",
            category: "other",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://dashscope.aliyuncs.com/apps/anthropic",
            apiKeyURL: "https://bailian.console.aliyun.com/cn-beijing?tab=model",
            logoSymbol: "cloud.bolt.fill",
            accentHex: 0xFB923C,
            defaultModelIds: ["qwen3.8-max", "qwen3.8-flash", "qwen3.7-max", "qwen3.7-plus", "qwen3-vl-plus"]
        ),
        ProviderTemplateDescriptor(
            id: "xiaomi-mimo",
            name: "Xiaomi MiMo API",
            category: "other",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://api.xiaomimimo.com/anthropic",
            apiKeyURL: "https://platform.xiaomimimo.com/",
            logoSymbol: "bolt.circle.fill",
            accentHex: 0xFF6900,
            defaultModelIds: ["mimo-v2.6-pro", "mimo-v2.6-flash", "mimo-v2.5-pro", "mimo-v2.5"]
        ),
        ProviderTemplateDescriptor(
            id: "xiaomi-mimo-token-plan",
            name: "Xiaomi MiMo Token Plan",
            category: "other",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://token-plan-cn.xiaomimimo.com/anthropic",
            apiKeyURL: "https://platform.xiaomimimo.com/",
            logoSymbol: "bolt.badge.clock.fill",
            accentHex: 0xFB923C,
            defaultModelIds: ["mimo-v2.6-pro", "mimo-v2.6-flash"]
        ),
        ProviderTemplateDescriptor(
            id: "opencode-zen-messages",
            name: "OpenCode Zen (Anthropic)",
            category: "other",
            apiFormat: .anthropicMessages,
            defaultBaseURL: "https://opencode.ai/zen/v1",
            apiKeyURL: "https://opencode.ai/zen",
            logoSymbol: "terminal.fill",
            accentHex: 0x14B8A6,
            defaultModelIds: ["claude-sonnet-5", "claude-opus-5"]
        ),
        ProviderTemplateDescriptor(
            id: "opencode-zen-responses",
            name: "OpenCode Zen (Responses)",
            category: "other",
            apiFormat: .openaiResponses,
            defaultBaseURL: "https://opencode.ai/zen/v1",
            apiKeyURL: "https://opencode.ai/zen",
            logoSymbol: "terminal",
            accentHex: 0x0D9488,
            defaultModelIds: ["gpt-5.4", "gpt-5.3-codex"]
        )
    ]
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
    /// Raw host tool name (e.g. "Read", "Edit", "Bash", "Grep", "mcp__x__y") for 1:1 labels and grouping.
    public var toolName: String? = nil

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
        subagentRunId: String? = nil,
        toolName: String? = nil
    ) {
        self.toolName = toolName
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
    public var quotes: [ConversationQuote]? = nil
}

/// Host `snapshot.usage.contextWindow` (+ cumulative totals). Breakdown fractions sum to ~1.
public struct ContextUsageSnapshot: Codable, Equatable {
    public struct Slice: Codable, Equatable, Identifiable {
        /// Host source key: messages, mcp_tool_schemas, system_tool_schemas, tool_prompt, skills, system_prompt, meta_user_context.
        public var source: String
        public var label: String
        public var fraction: Double
        public var id: String { source }

        public init(source: String, label: String, fraction: Double) {
            self.source = source
            self.label = label
            self.fraction = fraction
        }
    }

    public var usedTokens: Int
    public var maxTokens: Int
    public var autoCompactThresholdTokens: Int?
    public var breakdown: [Slice]
    /// 0...1, nil when the host has no cache statistics yet.
    public var cacheHitRate: Double?
    public var cumulativeInputTokens: Int
    public var cumulativeOutputTokens: Int
    public var cumulativeCacheReadTokens: Int
    public var cumulativeCacheWriteTokens: Int

    public init(
        usedTokens: Int,
        maxTokens: Int,
        autoCompactThresholdTokens: Int? = nil,
        breakdown: [Slice] = [],
        cacheHitRate: Double? = nil,
        cumulativeInputTokens: Int = 0,
        cumulativeOutputTokens: Int = 0,
        cumulativeCacheReadTokens: Int = 0,
        cumulativeCacheWriteTokens: Int = 0
    ) {
        self.usedTokens = usedTokens
        self.maxTokens = maxTokens
        self.autoCompactThresholdTokens = autoCompactThresholdTokens
        self.breakdown = breakdown
        self.cacheHitRate = cacheHitRate
        self.cumulativeInputTokens = cumulativeInputTokens
        self.cumulativeOutputTokens = cumulativeOutputTokens
        self.cumulativeCacheReadTokens = cumulativeCacheReadTokens
        self.cumulativeCacheWriteTokens = cumulativeCacheWriteTokens
    }

    public var fraction: Double { maxTokens > 0 ? min(1, Double(usedTokens) / Double(maxTokens)) : 0 }
}

/// A quoted excerpt attached to a prompt (host `conversationQuotes`, max 8 per prompt, 16k chars total).
public struct ConversationQuote: Codable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var path: String?
    public var senderName: String?
    public var messageId: String?

    public init(id: String = UUID().uuidString, text: String, path: String? = nil, senderName: String? = nil, messageId: String? = nil) {
        self.id = id
        self.text = text
        self.path = path
        self.senderName = senderName
        self.messageId = messageId
    }
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
    /// Provider of `modelId` as reported by the host model selection.
    public var modelProviderId: String?
    /// Host reasoning level string (values come from the model's option specs).
    public var reasoningLevel: String?
    /// Live context window usage from the host (`snapshot.usage`); nil until the host reports it.
    public var contextUsage: ContextUsageSnapshot? = nil

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
        statusNoticeText: String? = nil,
        modelProviderId: String? = nil,
        reasoningLevel: String? = nil
    ) {
        self.modelProviderId = modelProviderId
        self.reasoningLevel = reasoningLevel
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

// MARK: - Enterprise Ecosystem & Settings Models (1:1 ZCode v3.16.3)

public enum SubagentColor: String, Codable, CaseIterable, Identifiable {
    case yellow
    case red
    case orange
    case green
    case cyan
    case blue
    case purple
    case pink

    public var id: String { rawValue }

    public var hex: UInt32 {
        switch self {
        case .yellow: return 0xEAB308
        case .red: return 0xEF4444
        case .orange: return 0xF97316
        case .green: return 0x22C55E
        case .cyan: return 0x06B6D4
        case .blue: return 0x3B82F6
        case .purple: return 0xA855F7
        case .pink: return 0xEC4899
        }
    }
}

public enum SubagentPermissionMode: String, Codable, CaseIterable, Identifiable {
    case `default` = "default"
    case acceptEdits = "acceptEdits"
    case plan = "plan"
    case auto = "auto"
    case dontAsk = "dontAsk"
    case bypassPermissions = "bypassPermissions"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .default: return "Default"
        case .acceptEdits: return "Accept Edits"
        case .plan: return "Plan Only"
        case .auto: return "Auto"
        case .dontAsk: return "Don't Ask"
        case .bypassPermissions: return "Bypass Permissions"
        }
    }
}

public struct SubagentBuiltInToolSpec: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let summary: String
    public let isDestructiveOrMutating: Bool

    /// Exact ZCode v3.16.3 `J7` built-in subagent tool catalog
    public static let officialTools: [SubagentBuiltInToolSpec] = [
        SubagentBuiltInToolSpec(id: "Read", name: "Read", summary: "Read files, images, and PDFs", isDestructiveOrMutating: false),
        SubagentBuiltInToolSpec(id: "Grep", name: "Grep", summary: "Fast regex content search", isDestructiveOrMutating: false),
        SubagentBuiltInToolSpec(id: "Glob", name: "Glob", summary: "Find files by path pattern", isDestructiveOrMutating: false),
        SubagentBuiltInToolSpec(id: "Bash", name: "Bash", summary: "Execute shell commands", isDestructiveOrMutating: true),
        SubagentBuiltInToolSpec(id: "Edit", name: "Edit", summary: "Modify existing files", isDestructiveOrMutating: true),
        SubagentBuiltInToolSpec(id: "Write", name: "Write", summary: "Create or overwrite files", isDestructiveOrMutating: true),
        SubagentBuiltInToolSpec(id: "WebFetch", name: "WebFetch", summary: "Fetch web documentation", isDestructiveOrMutating: false),
        SubagentBuiltInToolSpec(id: "WebSearch", name: "WebSearch", summary: "Search live web sources", isDestructiveOrMutating: false),
        SubagentBuiltInToolSpec(id: "TodoWrite", name: "TodoWrite", summary: "Track multi-step checklists", isDestructiveOrMutating: false)
    ]
}

public struct SubagentDefinitionItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var systemPrompt: String
    public var color: SubagentColor
    public var scope: String // "built-in" | "user" | "workspace"
    public var source: String // "built-in" | "user" | "plugin"
    public var readOnly: Bool
    public var enabled: Bool
    /// Empty or `"inherit"` means inherit main conversation model
    public var modelOverride: String
    public var reasoningOverride: String // "inherit" | "off" | "low" | "medium" | "high" | "max"
    /// Empty or contains `"*"` means All tools
    public var allowedTools: [String]
    public var permissionMode: SubagentPermissionMode
    public var injectAgentsMd: Bool
    public var runInBackground: Bool
    public var filePath: String
    public var pluginId: String?
    public var pluginName: String?

    public var isAllTools: Bool {
        allowedTools.isEmpty || allowedTools.contains("*")
    }

    public var toolsSummary: String {
        if isAllTools {
            return "All tools"
        }
        if allowedTools.count <= 3 {
            return allowedTools.joined(separator: ", ")
        }
        return "\(allowedTools.count) tools"
    }

    public var canOverrideModelInline: Bool {
        if source == "built-in" {
            let lower = name.lowercased()
            return lower == "general-purpose" || lower == "explore"
        }
        return source == "plugin"
    }

    public var displayName: String {
        if source == "plugin", let colonIdx = name.lastIndex(of: ":") {
            return String(name[name.index(after: colonIdx)...])
        }
        return name
    }

    public init(
        id: String,
        name: String,
        description: String,
        systemPrompt: String = "You are a focused specialist subagent invoked by ZCode.",
        color: SubagentColor = .blue,
        scope: String = "user",
        source: String = "user",
        readOnly: Bool = false,
        enabled: Bool = true,
        modelOverride: String = "inherit",
        reasoningOverride: String = "inherit",
        allowedTools: [String] = ["*"],
        toolsSummary: String? = nil,
        permissionMode: SubagentPermissionMode = .default,
        injectAgentsMd: Bool = true,
        runInBackground: Bool = false,
        filePath: String = "",
        pluginId: String? = nil,
        pluginName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.color = color
        self.scope = scope
        self.source = source
        self.readOnly = readOnly
        self.enabled = enabled
        self.modelOverride = modelOverride.isEmpty ? "inherit" : modelOverride
        self.reasoningOverride = reasoningOverride
        if let toolsSummary, allowedTools == ["*"], toolsSummary != "All tools" {
            self.allowedTools = toolsSummary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            self.allowedTools = allowedTools
        }
        self.permissionMode = permissionMode
        self.injectAgentsMd = injectAgentsMd
        self.runInBackground = runInBackground
        self.filePath = filePath.isEmpty ? "~/.zcode/agents/\(name).md" : filePath
        self.pluginId = pluginId
        self.pluginName = pluginName
    }
}

public struct MCPServerItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var scope: String // "user" | "workspace" | "plugin"
    public var transport: String // "stdio", "http", "sse"
    public var endpointOrCommand: String
    public var args: [String]
    public var protocolVersion: String // "auto" | "legacy" | "2026-07-28"
    public var timeoutMs: Int
    public var envOrHeadersJSON: String
    public var enabled: Bool
    public var connected: Bool
    public var statusText: String
    public var tools: [String]
    public var resourcesCount: Int

    public init(
        id: String,
        name: String,
        scope: String = "user",
        transport: String,
        endpointOrCommand: String,
        args: [String] = [],
        protocolVersion: String = "auto",
        timeoutMs: Int = 30_000,
        envOrHeadersJSON: String = "{}",
        enabled: Bool,
        connected: Bool,
        statusText: String? = nil,
        tools: [String],
        resourcesCount: Int
    ) {
        self.id = id
        self.name = name
        self.scope = scope
        self.transport = transport
        self.endpointOrCommand = endpointOrCommand
        self.args = args
        self.protocolVersion = protocolVersion
        self.timeoutMs = timeoutMs
        self.envOrHeadersJSON = envOrHeadersJSON
        self.enabled = enabled
        self.connected = connected
        self.statusText = statusText ?? (connected ? "Connected" : (enabled ? "Disconnected" : "Disabled"))
        self.tools = tools
        self.resourcesCount = resourcesCount
    }
}

public struct SkillCatalogItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var summary: String
    public var scope: String // "Workspace", "User", "Plugin", "Built-in"
    public var pluginName: String?
    public var filePath: String
    public var diagnosticWarning: String?
    public var enabled: Bool
    public var markdownBody: String

    public init(
        id: String,
        name: String,
        summary: String,
        scope: String,
        pluginName: String? = nil,
        filePath: String = "",
        diagnosticWarning: String? = nil,
        enabled: Bool,
        markdownBody: String
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.scope = scope
        self.pluginName = pluginName
        self.filePath = filePath.isEmpty ? "~/.zcode/skills/\(name)/SKILL.md" : filePath
        self.diagnosticWarning = diagnosticWarning
        self.enabled = enabled
        self.markdownBody = markdownBody
    }
}

public struct PluginCatalogItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var version: String
    public var marketplace: String
    public var scope: String // "user" | "workspace"
    public var author: String
    public var summary: String
    public var componentBadges: [String] // e.g. ["Skills", "MCP", "Commands"]
    public var updateAvailableVersion: String?
    public var installed: Bool
    public var enabled: Bool

    public init(
        id: String,
        name: String,
        version: String,
        marketplace: String,
        scope: String = "user",
        author: String = "ZCode Official",
        summary: String,
        componentBadges: [String] = ["Skills", "MCP"],
        updateAvailableVersion: String? = nil,
        installed: Bool,
        enabled: Bool
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.marketplace = marketplace
        self.scope = scope
        self.author = author
        self.summary = summary
        self.componentBadges = componentBadges
        self.updateAvailableVersion = updateAvailableVersion
        self.installed = installed
        self.enabled = enabled
    }
}

public struct SlashCommandItem: Identifiable, Codable, Equatable {
    public var id: String
    public var trigger: String // e.g. "/compact"
    public var summary: String
    public var argumentHint: String
    public var scope: String // "System", "User", "Project", "Plugin"
    public var enabled: Bool
    public var filePath: String
    public var promptTemplate: String

    public init(
        id: String,
        trigger: String,
        summary: String,
        argumentHint: String = "",
        scope: String,
        enabled: Bool = true,
        filePath: String = "",
        promptTemplate: String
    ) {
        self.id = id
        self.trigger = trigger.hasPrefix("/") || scope == "System" ? trigger : "/\(trigger)"
        self.summary = summary
        self.argumentHint = argumentHint
        self.scope = scope
        self.enabled = enabled
        let cleanSlug = trigger.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        self.filePath = filePath.isEmpty ? "~/.zcode/commands/\(cleanSlug).md" : filePath
        self.promptTemplate = promptTemplate
    }
}

public struct HookRuleItem: Identifiable, Codable, Equatable {
    public static let officialEvents: [String] = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "PostToolUseFailure",
        "Stop"
    ]

    public var id: String
    public var event: String
    public var matcher: String
    public var hookType: String // "command" | "process"
    public var scope: String // "user" | "project" | "plugin"
    public var command: String
    public var argsLines: String
    public var shell: String
    public var runAsync: Bool
    public var timeoutSec: Int
    public var statusMessage: String
    public var editable: Bool
    public var enabled: Bool

    public init(
        id: String,
        event: String,
        matcher: String,
        hookType: String = "command",
        scope: String = "user",
        command: String,
        argsLines: String = "",
        shell: String = "/bin/zsh",
        runAsync: Bool = false,
        timeoutSec: Int = 60,
        statusMessage: String = "",
        editable: Bool = true,
        enabled: Bool
    ) {
        self.id = id
        self.event = event
        self.matcher = matcher
        self.hookType = hookType
        self.scope = scope
        self.command = command
        self.argsLines = argsLines
        self.shell = shell
        self.runAsync = runAsync
        self.timeoutSec = timeoutSec
        self.statusMessage = statusMessage
        self.editable = editable
        self.enabled = enabled
    }
}

public struct ShortcutBindingItem: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var category: String // "Window", "Composer", "Workspace"
    public var defaultBinding: String
    public var customBinding: String?

    public var activeBinding: String {
        customBinding ?? defaultBinding
    }

    public static let officialDefaults: [ShortcutBindingItem] = [
        ShortcutBindingItem(id: "openCommandCenter", title: "Open Command Center", category: "Window", defaultBinding: "⌘ K"),
        ShortcutBindingItem(id: "openSettings", title: "Open Settings", category: "Window", defaultBinding: "⌘ ,"),
        ShortcutBindingItem(id: "newTask", title: "New Task", category: "Workspace", defaultBinding: "⌘ N"),
        ShortcutBindingItem(id: "openWorkspace", title: "Open Workspace", category: "Workspace", defaultBinding: "⌘ O"),
        ShortcutBindingItem(id: "findInTask", title: "Find in Conversation", category: "Window", defaultBinding: "⌘ F"),
        ShortcutBindingItem(id: "toggleSidebar", title: "Toggle Sidebar", category: "Window", defaultBinding: "⌘ B"),
        ShortcutBindingItem(id: "toggleSidePane", title: "Toggle Side Pane", category: "Window", defaultBinding: "⌘ ⌥ B"),
        ShortcutBindingItem(id: "toggleTerminal", title: "Toggle Integrated Terminal", category: "Window", defaultBinding: "⌘ J"),
        ShortcutBindingItem(id: "switchTheme", title: "Switch Theme", category: "Window", defaultBinding: "⌘ ⇧ L"),
        ShortcutBindingItem(id: "previousConversation", title: "Previous Conversation", category: "Workspace", defaultBinding: "⌘ ⇧ ["),
        ShortcutBindingItem(id: "nextConversation", title: "Next Conversation", category: "Workspace", defaultBinding: "⌘ ⇧ ]"),
        ShortcutBindingItem(id: "openModelMenu", title: "Open Model Selector", category: "Composer", defaultBinding: "⌃ M"),
        ShortcutBindingItem(id: "cycleSessionMode", title: "Cycle Execution Mode", category: "Composer", defaultBinding: "⌃ ⇧ M"),
        ShortcutBindingItem(id: "cycleThoughtLevel", title: "Cycle Reasoning Effort", category: "Composer", defaultBinding: "⌃ T"),
        ShortcutBindingItem(id: "composerSend", title: "Send Prompt", category: "Composer", defaultBinding: "↩"),
        ShortcutBindingItem(id: "composerInsertNewline", title: "Insert Newline in Composer", category: "Composer", defaultBinding: "⇧ ↩"),
        ShortcutBindingItem(id: "zoomIn", title: "Zoom In", category: "Window", defaultBinding: "⌘ ="),
        ShortcutBindingItem(id: "zoomOut", title: "Zoom Out", category: "Window", defaultBinding: "⌘ -"),
        ShortcutBindingItem(id: "resetZoom", title: "Reset Zoom", category: "Window", defaultBinding: "⌘ 0")
    ]
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
