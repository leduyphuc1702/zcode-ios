import Foundation

public enum SeedWorkspaceFactory {

    public static func defaultConnections() -> [RemoteConnection] {
        [
            RemoteConnection(
                id: "conn-workstation-primary",
                name: "Macs-Mac-mini.local",
                transport: .enterpriseSandbox,
                url: "ws://127.0.0.1:57743/ws",
                host: "127.0.0.1",
                port: 57743,
                serverVersion: "3.16.3",
                lastConnectedAt: Date(),
                lastTaskId: "task-rpc-refactor",
                state: .connected,
                latencyMs: 4
            ),
            RemoteConnection(
                id: "conn-relay-cloud",
                name: "Z.ai Cloud Relay • Studio Cluster",
                transport: .cloudRelayV2,
                url: "https://zcode.z.ai/remote/v4?sid=zc_prod_98a4f2&mid=mac_arm64_0af9fa&name=StudioCluster",
                host: "zcode.z.ai",
                port: 443,
                mid: "mac_arm64_0af9fa",
                sid: "zc_prod_98a4f2",
                serverVersion: "3.16.3",
                lastConnectedAt: Date().addingTimeInterval(-3600),
                lastTaskId: "task-security-audit",
                state: .disconnected,
                latencyMs: 28
            )
        ]
    }

    public static func defaultProjects() -> [WorkspaceProject] {
        [
            WorkspaceProject(
                id: "proj-zcode-core",
                name: "zcode-enterprise-core",
                rootPath: "/Users/macos/workspace/zcode-enterprise-core",
                gitBranch: "feat/native-rpc-v4",
                ahead: 2,
                behind: 0,
                isDirty: true,
                isRemote: false,
                pinned: true
            ),
            WorkspaceProject(
                id: "proj-gateway-rs",
                name: "edge-gateway-rust",
                rootPath: "/srv/cloud/edge-gateway-rust",
                gitBranch: "main",
                ahead: 0,
                behind: 0,
                isDirty: false,
                isRemote: true,
                pinned: false
            )
        ]
    }

    public static func defaultProviders() -> [ModelProviderConfig] {
        [
            ModelProviderConfig(
                id: "account:zai-individual-coding-plan",
                name: "Z.ai Coding Plan",
                baseURL: "https://api.z.ai/api/anthropic",
                protocolKind: "anthropic-messages",
                group: "zai-family",
                templateId: "zai-api",
                apiKeyManagementURL: "https://z.ai/manage-apikey/subscription",
                hasConfiguredAPIKey: true,
                enabled: true,
                isBuiltin: true,
                entitled: true,
                accountAvailability: "available",
                statusText: "Z.ai Account • Coding Plan",
                logoKey: "zai",
                models: [
                    ModelDescriptor(id: "zai/GLM-5.3", modelId: "GLM-5.3", name: "GLM-5.3", providerId: "account:zai-individual-coding-plan", providerName: "Z.ai Coding Plan", contextWindowK: 200, maxOutputTokens: 32_768, supportsVision: true, supportsReasoning: true, badge: "Default"),
                    ModelDescriptor(id: "zai/GLM-5.3-Flash", modelId: "GLM-5.3-Flash", name: "GLM-5.3 Flash", providerId: "account:zai-individual-coding-plan", providerName: "Z.ai Coding Plan", contextWindowK: 200, maxOutputTokens: 16_384, supportsVision: true, supportsReasoning: true, badge: "Fast"),
                    ModelDescriptor(id: "zai/GLM-5.1", modelId: "GLM-5.1", name: "GLM-5.1 Coding", providerId: "account:zai-individual-coding-plan", providerName: "Z.ai Coding Plan", contextWindowK: 200, maxOutputTokens: 32_768, supportsVision: true, supportsReasoning: true, badge: nil),
                    ModelDescriptor(id: "zai/GLM-5V-Turbo", modelId: "GLM-5V-Turbo", name: "GLM-5V Turbo", providerId: "account:zai-individual-coding-plan", providerName: "Z.ai Coding Plan", contextWindowK: 128, maxOutputTokens: 16_384, supportsVision: true, supportsVideo: true, supportsReasoning: true, badge: "Vision")
                ]
            ),
            ModelProviderConfig(
                id: "account:zai-team-coding-plan",
                name: "Z.ai Team Coding Plan",
                baseURL: "https://api.z.ai/api/anthropic",
                protocolKind: "anthropic-messages",
                group: "zai-family",
                apiKeyManagementURL: "https://z.ai/manage-apikey/subscription",
                hasConfiguredAPIKey: false,
                enabled: true,
                isBuiltin: true,
                entitled: false,
                accountAvailability: "unavailable",
                statusText: "Team Organization Plan",
                logoKey: "zai",
                models: [
                    ModelDescriptor(id: "zai-team/GLM-5.3", modelId: "GLM-5.3", name: "GLM-5.3 (Team)", providerId: "account:zai-team-coding-plan", providerName: "Z.ai Team", contextWindowK: 200, supportsVision: true, supportsReasoning: true)
                ]
            ),
            ModelProviderConfig(
                id: "account:zai-start-plan",
                name: "Z.ai Start Plan",
                baseURL: "https://api.z.ai/api/anthropic",
                protocolKind: "anthropic-messages",
                group: "zai-family",
                apiKeyManagementURL: "https://z.ai/manage-apikey/subscription",
                hasConfiguredAPIKey: true,
                enabled: true,
                isBuiltin: true,
                entitled: true,
                accountAvailability: "available",
                statusText: "Starter Entitlement",
                logoKey: "zai",
                models: [
                    ModelDescriptor(id: "zai-start/GLM-5.3-Flash", modelId: "GLM-5.3-Flash", name: "GLM-5.3 Flash", providerId: "account:zai-start-plan", providerName: "Z.ai Start", contextWindowK: 128, supportsVision: true, supportsReasoning: true)
                ]
            ),
            ModelProviderConfig(
                id: "anthropic",
                name: "Anthropic",
                baseURL: "https://api.anthropic.com/v1",
                protocolKind: "anthropic-messages",
                group: "standard-personal",
                templateId: "anthropic",
                apiKeyManagementURL: "https://console.anthropic.com/settings/keys",
                hasConfiguredAPIKey: false,
                enabled: true,
                isBuiltin: false,
                statusText: "Anthropic Messages API",
                logoKey: "anthropic",
                models: [
                    ModelDescriptor(id: "anthropic/claude-opus-4-7", modelId: "claude-opus-4-7", name: "Claude Opus 4.7", providerId: "anthropic", providerName: "Anthropic", builtin: false, contextWindowK: 200, maxOutputTokens: 32_768, supportsVision: true, supportsPdf: true, supportsReasoning: true, badge: "Max"),
                    ModelDescriptor(id: "anthropic/claude-sonnet-4-6", modelId: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", providerId: "anthropic", providerName: "Anthropic", builtin: false, contextWindowK: 200, maxOutputTokens: 16_384, supportsVision: true, supportsPdf: true, supportsReasoning: true, badge: nil)
                ]
            ),
            ModelProviderConfig(
                id: "openai",
                name: "OpenAI",
                baseURL: "https://api.openai.com/v1",
                protocolKind: "openai-responses",
                group: "standard-personal",
                templateId: "openai",
                apiKeyManagementURL: "https://platform.openai.com/api-keys",
                hasConfiguredAPIKey: false,
                enabled: true,
                isBuiltin: false,
                statusText: "OpenAI Responses API",
                logoKey: "openai",
                models: [
                    ModelDescriptor(id: "openai/gpt-5.4", modelId: "gpt-5.4", name: "GPT-5.4", providerId: "openai", providerName: "OpenAI", builtin: false, contextWindowK: 256, maxOutputTokens: 32_768, supportsVision: true, supportsReasoning: true, badge: nil),
                    ModelDescriptor(id: "openai/gpt-5.3-codex", modelId: "gpt-5.3-codex", name: "GPT-5.3 Codex", providerId: "openai", providerName: "OpenAI", builtin: false, contextWindowK: 256, maxOutputTokens: 32_768, supportsVision: true, supportsReasoning: true, badge: "Codex")
                ]
            )
        ]
    }

    public static func defaultFileTree() -> [WorkspaceFileNode] {
        let archPNG = SampleAssetGenerator.makeArchitectureDiagramPNG()
        let uiMockPNG = SampleAssetGenerator.makeUIPreviewMockupPNG()
        let specPDF = SampleAssetGenerator.makeEnterpriseSpecPDF()

        return [
            WorkspaceFileNode(
                id: "dir-src",
                name: "src",
                path: "src",
                kind: .directory,
                gitStatus: "M",
                sizeBytes: 0,
                updatedAt: Date(),
                children: [
                    WorkspaceFileNode(
                        id: "dir-src-rpc",
                        name: "rpc",
                        path: "src/rpc",
                        kind: .directory,
                        gitStatus: "M",
                        sizeBytes: 0,
                        updatedAt: Date(),
                        children: [
                            WorkspaceFileNode(
                                id: "file-socket-protocol",
                                name: "SocketProtocol.swift",
                                path: "src/rpc/SocketProtocol.swift",
                                kind: .code,
                                gitStatus: "M",
                                sizeBytes: 2480,
                                updatedAt: Date(),
                                textContent: """
                                import Foundation

                                /// ZCode v3.16.3 Binary Frame Transport (13-byte Big-Endian Header)
                                public struct SocketFrameHeader: Equatable, Sendable {
                                    public let messageType: UInt8
                                    public let sequenceId: UInt32
                                    public let acknowledgeId: UInt32
                                    public let payloadBytes: UInt32

                                    public static let headerSize = 13

                                    public init(messageType: UInt8 = 1, sequenceId: UInt32 = 0, acknowledgeId: UInt32 = 0, payloadBytes: UInt32) {
                                        self.messageType = messageType
                                        self.sequenceId = sequenceId
                                        self.acknowledgeId = acknowledgeId
                                        self.payloadBytes = payloadBytes
                                    }

                                    public func encode(with payload: Data) -> Data {
                                        var buffer = Data(capacity: Self.headerSize + payload.count)
                                        buffer.append(messageType)
                                        buffer.appendBigEndian(sequenceId)
                                        buffer.appendBigEndian(acknowledgeId)
                                        buffer.appendBigEndian(UInt32(payload.count))
                                        buffer.append(payload)
                                        return buffer
                                    }
                                }
                                """
                            ),
                            WorkspaceFileNode(
                                id: "file-relay-multiplexer",
                                name: "RelayMultiplexer.ts",
                                path: "src/rpc/RelayMultiplexer.ts",
                                kind: .code,
                                gitStatus: "A",
                                sizeBytes: 1940,
                                updatedAt: Date(),
                                textContent: """
                                export interface RelayRpcFrame {
                                  zcode_type: "rpc-frame";
                                  bridgeSessionId: string;
                                  bridgeGeneration: number;
                                  messageSeq: number;
                                  fragmentIndex: number;
                                  fragmentCount: number;
                                  checksum: { algorithm: "crc32"; value: string };
                                  dataBase64: string;
                                }

                                export async function dispatchTunneledFrame(socket: WebSocket, frame: RelayRpcFrame): Promise<void> {
                                  const envelope = JSON.stringify({
                                    type: "data",
                                    payload: frame,
                                    client_ts: Math.floor(Date.now() / 1000),
                                  });
                                  socket.send(envelope);
                                }
                                """
                            )
                        ]
                    ),
                    WorkspaceFileNode(
                        id: "dir-src-agent",
                        name: "agent",
                        path: "src/agent",
                        kind: .directory,
                        gitStatus: nil,
                        sizeBytes: 0,
                        updatedAt: Date(),
                        children: [
                            WorkspaceFileNode(
                                id: "file-session-orchestrator",
                                name: "SessionOrchestrator.swift",
                                path: "src/agent/SessionOrchestrator.swift",
                                kind: .code,
                                gitStatus: nil,
                                sizeBytes: 1820,
                                updatedAt: Date(),
                                textContent: """
                                import Foundation

                                @MainActor
                                public final class SessionOrchestrator {
                                    private let maxConcurrentSubagents = 6
                                    public private(set) var activeSessionId: String?

                                    public func resume(sessionId: String, mode: String = "build") async throws {
                                        self.activeSessionId = sessionId
                                        // Synchronize snapshot + dynamic event stream
                                    }
                                }
                                """
                            )
                        ]
                    )
                ]
            ),
            WorkspaceFileNode(
                id: "dir-assets",
                name: "assets",
                path: "assets",
                kind: .directory,
                gitStatus: "A",
                sizeBytes: 0,
                updatedAt: Date(),
                children: [
                    WorkspaceFileNode(
                        id: "file-arch-png",
                        name: "architecture-overview.png",
                        path: "assets/architecture-overview.png",
                        kind: .image,
                        gitStatus: "A",
                        sizeBytes: archPNG.count,
                        updatedAt: Date(),
                        binaryData: archPNG
                    ),
                    WorkspaceFileNode(
                        id: "file-telemetry-png",
                        name: "telemetry-latency-chart.png",
                        path: "assets/telemetry-latency-chart.png",
                        kind: .image,
                        gitStatus: nil,
                        sizeBytes: uiMockPNG.count,
                        updatedAt: Date(),
                        binaryData: uiMockPNG
                    ),
                    WorkspaceFileNode(
                        id: "file-spec-pdf",
                        name: "ZCode-Enterprise-Spec.pdf",
                        path: "assets/ZCode-Enterprise-Spec.pdf",
                        kind: .pdf,
                        gitStatus: nil,
                        sizeBytes: specPDF.count,
                        updatedAt: Date(),
                        binaryData: specPDF
                    ),
                    WorkspaceFileNode(
                        id: "file-benchmarks-csv",
                        name: "rpc-benchmarks.csv",
                        path: "assets/rpc-benchmarks.csv",
                        kind: .csv,
                        gitStatus: nil,
                        sizeBytes: 512,
                        updatedAt: Date(),
                        textContent: """
                        Transport,P50 Latency (ms),P99 Latency (ms),Throughput (MB/s),Zero-Copy
                        Local Unix Socket,0.4,1.2,640,Yes
                        Direct LAN WebSocket,2.1,6.8,215,Yes
                        Cloud Relay V2 (CRC32),18.4,42.0,68,Chunked
                        SSH Duplex Proxy,7.5,19.3,142,Yes
                        """
                    )
                ]
            ),
            WorkspaceFileNode(
                id: "file-readme",
                name: "README.md",
                path: "README.md",
                kind: .markdown,
                gitStatus: "M",
                sizeBytes: 1420,
                updatedAt: Date(),
                textContent: """
                # ZCode Enterprise Core (v3.16.3)

                Unified high-throughput coding agent runtime with **SocketProtocol VQL IPC**, **Cloud Relay V2**, and **Multi-Agent Subagent Orchestration**.

                ## Key Capabilities
                - **Binary VQL Transport**: Deterministic 13-byte framing with zero JSON overhead on raw buffers.
                - **Interactive Inspector**: Real-time file tree, Shiki syntax highlighting, visual image/PDF preview, and unified/split Git diffs.
                - **Enterprise Security**: Hardware Keychain isolation, Face ID gate, and granular tool execution governance.
                """
            ),
            WorkspaceFileNode(
                id: "file-package-json",
                name: "zcode.config.json",
                path: "zcode.config.json",
                kind: .json,
                gitStatus: nil,
                sizeBytes: 640,
                updatedAt: Date(),
                textContent: """
                {
                  "version": "3.16.3",
                  "protocolVersion": 1,
                  "defaultModel": "zai/glm-5.1-coding",
                  "reasoningEffort": "high",
                  "mcpServers": ["gitnexus", "codegraph", "aiblueprint"],
                  "security": {
                    "requireApprovalForDestructiveBash": true,
                    "keychainIsolation": true
                  }
                }
                """
            )
        ]
    }

    public static func defaultSessions() -> [AgentTaskSession] {
        let mainSession = AgentTaskSession(
            id: "task-rpc-refactor",
            traceId: "trc_98f1204e",
            projectId: "proj-zcode-core",
            workspacePath: "/Users/macos/workspace/zcode-enterprise-core",
            title: "Implement Native Binary VQL & Image/Code Inspector",
            status: .completed,
            mode: .yolo,
            modelId: "anthropic/claude-opus-4-7",
            effort: .high,
            pinned: true,
            archived: false,
            unread: false,
            offPeakEnabled: false,
            createdAt: Date().addingTimeInterval(-5400),
            updatedAt: Date().addingTimeInterval(-3600),
            contextUsedPercent: 34,
            totalTokensIn: 42850,
            totalTokensOut: 6940,
            cachedTokens: 31200,
            costUSD: 0.18,
            messages: [
                ChatTurnMessage(
                    id: "msg-1",
                    role: "user",
                    content: "Upgrade @src/rpc/SocketProtocol.swift to verify CRC32 frame integrity on Cloud Relay V2 chunks and generate an updated architecture diagram in @assets/architecture-overview.png.",
                    thought: nil,
                    thoughtDurationMs: 0,
                    tools: [],
                    attachments: [],
                    timestamp: Date().addingTimeInterval(-5200),
                    modelLabel: nil,
                    tokensIn: 142,
                    tokensOut: 0,
                    durationMs: 0,
                    feedback: 0
                ),
                ChatTurnMessage(
                    id: "msg-2",
                    role: "assistant",
                    content: "> 13-byte Big-Endian SocketFrameHeader + IEEE 802.3 CRC32 verification enabled across Direct WS and Cloud Relay V2.\n\nKey changes completed:\n\n- Implemented deterministic `SocketFrameHeader` encoding in `src/rpc/SocketProtocol.swift` with zero-copy payload framing.\n- Added multi-fragment `rpc-frame` assembly in `src/rpc/RelayMultiplexer.ts` and rendered the diagram at `assets/architecture-overview.png`.\n\nTap `Changes` above or the right side-pane toggle to inspect files, images, PDFs, or Git diffs.",
                    thought: "Inspecting server-core.js SocketProtocol framing: 1-byte messageType (0x01 Regular), 4-byte sequenceId BE, 4-byte acknowledgeId BE, and 4-byte payload byteLength BE. Relay V2 wraps chunks in base64 with lowercase 8-char IEEE 802.3 CRC32 verification.",
                    thoughtDurationMs: 1840,
                    tools: [
                        ToolCallItem(
                            id: "tool-0-subagent",
                            kind: .subagent,
                            title: "Read server resources and framing",
                            subtitle: "SubAgent • Verified 13-byte VQL & CRC32 envelopes",
                            status: .completed,
                            filePath: "src/rpc/SocketProtocol.swift",
                            lineRange: "1-32",
                            diffPatch: nil,
                            command: nil,
                            output: "Audited binary frame transport and Relay V2 fragmentation rules.",
                            durationMs: 920,
                            addedLines: 0,
                            removedLines: 0,
                            subagentSteps: [
                                "Inspected SocketFrameHeader 13-byte big-endian layout",
                                "Verified lowercase 8-char IEEE 802.3 CRC32 checksum field",
                                "Captured architecture preview artifact"
                            ],
                            subagentRunId: "sub-rpc-framing"
                        ),
                        ToolCallItem(
                            id: "tool-1",
                            kind: .readFile,
                            title: "Read src/rpc/SocketProtocol.swift",
                            subtitle: "Lines 1–32 • 2.4 KB",
                            status: .completed,
                            filePath: "src/rpc/SocketProtocol.swift",
                            lineRange: "1-32",
                            diffPatch: nil,
                            command: nil,
                            output: nil,
                            durationMs: 42,
                            addedLines: 0,
                            removedLines: 0,
                            subagentSteps: []
                        ),
                        ToolCallItem(
                            id: "tool-2",
                            kind: .editFile,
                            title: "Edit src/rpc/SocketProtocol.swift",
                            subtitle: "+14 -3 • Added big-endian payload framing",
                            status: .completed,
                            filePath: "src/rpc/SocketProtocol.swift",
                            lineRange: "12-28",
                            diffPatch: """
                            @@ -12,5 +12,16 @@
                            -    public func encode() -> Data {
                            -        return Data()
                            +    public func encode(with payload: Data) -> Data {
                            +        var buffer = Data(capacity: Self.headerSize + payload.count)
                            +        buffer.append(messageType)
                            +        buffer.appendBigEndian(sequenceId)
                            +        buffer.appendBigEndian(acknowledgeId)
                            +        buffer.appendBigEndian(UInt32(payload.count))
                            +        buffer.append(payload)
                            +        return buffer
                                 }
                            """,
                            command: nil,
                            output: nil,
                            durationMs: 118,
                            addedLines: 14,
                            removedLines: 3,
                            subagentSteps: []
                        ),
                        ToolCallItem(
                            id: "tool-3",
                            kind: .writeFile,
                            title: "Write assets/architecture-overview.png",
                            subtitle: "1200×760 PNG • Architecture Diagram",
                            status: .completed,
                            filePath: "assets/architecture-overview.png",
                            lineRange: nil,
                            diffPatch: nil,
                            command: nil,
                            output: "Generated 1200x760 high-DPI architecture diagram.",
                            durationMs: 210,
                            addedLines: 1,
                            removedLines: 0,
                            subagentSteps: []
                        ),
                        ToolCallItem(
                            id: "tool-4",
                            kind: .bash,
                            title: "swift test --filter SocketProtocolTests",
                            subtitle: "Exit 0 • 14 tests passed",
                            status: .completed,
                            filePath: nil,
                            lineRange: nil,
                            diffPatch: nil,
                            command: "swift test --filter SocketProtocolTests",
                            output: "Test Suite 'SocketProtocolTests' passed.\nExecuted 14 tests, with 0 failures (0 unexpected) in 0.194 seconds.",
                            durationMs: 690,
                            addedLines: 0,
                            removedLines: 0,
                            subagentSteps: []
                        )
                    ],
                    attachments: [],
                    timestamp: Date().addingTimeInterval(-5100),
                    modelLabel: "GLM-5.1 Coding • High",
                    tokensIn: 18420,
                    tokensOut: 1640,
                    durationMs: 2890,
                    feedback: 0
                )
            ],
            todos: [
                TodoChecklistItem(id: "td-1", content: "Implement 13-byte BE SocketFrameHeader serializer", status: "completed", priority: "high"),
                TodoChecklistItem(id: "td-2", content: "Add IEEE 802.3 CRC32 verification on Relay V2 chunks", status: "completed", priority: "high"),
                TodoChecklistItem(id: "td-3", content: "Render architecture diagram & verify unit suite", status: "completed", priority: "medium"),
                TodoChecklistItem(id: "td-4", content: "Audit multi-fragment out-of-order replay window", status: "in_progress", priority: "high"),
                TodoChecklistItem(id: "td-5", content: "Publish throughput benchmark CSV snapshot", status: "pending", priority: "low")
            ],
            pendingPermission: nil,
            pendingQuestion: nil,
            pendingPlan: nil,
            queuedPrompts: [],
            checkpoints: [
                GitCheckpointSnapshot(id: "cp-1", label: "Before SocketProtocol framing update", commitShortHash: "a41c90b", createdAt: Date().addingTimeInterval(-5190), messageIndex: 0, filesChanged: 0),
                GitCheckpointSnapshot(id: "cp-2", label: "Completed VQL + Architecture PNG", commitShortHash: "e83f21d", createdAt: Date().addingTimeInterval(-5100), messageIndex: 1, filesChanged: 3)
            ],
            goals: [
                GoalObjectiveItem(id: "goal-main-1", title: "Deliver zero-copy 13-byte binary VQL framing + native Inspector parity with 0 test failures", completed: false)
            ],
            goalElapsedText: "14m 54s",
            goalPaused: false,
            subagentRuns: [
                SubagentSessionRun(
                    id: "sub-rpc-framing",
                    title: "Read server resources and framing",
                    agentType: "Explore",
                    isRunning: true,
                    elapsedText: "Running for 14m 54s",
                    transcriptMarkdown: """
                    Verified binary framing and Relay V2 envelope rules across server and mobile client:

                    - `SocketFrameHeader` uses a deterministic `13-byte` big-endian layout (`messageType`, `sequenceId`, `acknowledgeId`, `payloadBytes`) in `src/rpc/SocketProtocol.swift`.
                    - Multi-chunk `rpc-frame` envelopes validate `checksum.algorithm = "crc32"` against the raw base64 slice before reassembly in `src/rpc/RelayMultiplexer.ts`.
                    - Captured high-DPI architecture snapshot at `assets/architecture-overview.png` for visual inspection:
                    """,
                    artifactImagePath: "assets/architecture-overview.png",
                    timestamp: Date().addingTimeInterval(-320)
                ),
                SubagentSessionRun(
                    id: "sub-crc32-bench",
                    title: "Benchmark CRC32 & Relay chunk throughput",
                    agentType: "general-purpose",
                    isRunning: true,
                    elapsedText: "Running for 9m 18s",
                    transcriptMarkdown: """
                    Running sustained 64KB chunked frame benchmarks across LAN Direct WebSocket and Cloud Relay V2:

                    - Direct WebSocket (`ws://Macs-Mac-mini.local:57743/ws`) averages `0.42ms` p50 frame round-trip with `0` dropped acknowledgements.
                    - Cloud Relay V2 (`wss://zcode.z.ai/api/v1/remote/ws2`) completes 8-fragment `512KB` PDF payload transfer in `18.4ms` with full IEEE 802.3 CRC32 verification.
                    """,
                    artifactImagePath: "assets/telemetry-latency-chart.png",
                    timestamp: Date().addingTimeInterval(-190)
                ),
                SubagentSessionRun(
                    id: "sub-inspector-verify",
                    title: "Adversarial audit of Inspector & Diff views",
                    agentType: "Explore",
                    isRunning: true,
                    elapsedText: "Running for 4m 07s",
                    transcriptMarkdown: """
                    Auditing native SwiftUI Inspector tabs (`Files`, `Viewer`, `Changes`, `Terminal`, `Graph`):

                    - Confirmed `0` references to `WKWebView` or `WebKit` across all compiled Swift targets.
                    - Verified Unified and Split Git diff hunks match `src/rpc/SocketProtocol.swift` (`+38 -4`) and `src/rpc/RelayMultiplexer.ts` (`+18 -4`).
                    """,
                    artifactImagePath: nil,
                    timestamp: Date().addingTimeInterval(-85)
                )
            ]
        )

        let approvalSession = AgentTaskSession(
            id: "task-security-audit",
            traceId: "trc_77c04b12",
            projectId: "proj-zcode-core",
            workspacePath: "/Users/macos/workspace/zcode-enterprise-core",
            title: "Production TLS Rotation & Firewall Hardening",
            status: .waitingApproval,
            mode: .ask,
            modelId: "anthropic/claude-opus-4-7",
            effort: .max,
            pinned: false,
            archived: false,
            unread: true,
            offPeakEnabled: true,
            createdAt: Date().addingTimeInterval(-1800),
            updatedAt: Date().addingTimeInterval(-45),
            contextUsedPercent: 22,
            totalTokensIn: 16400,
            totalTokensOut: 2310,
            cachedTokens: 12000,
            costUSD: 0.14,
            messages: [
                ChatTurnMessage(
                    id: "msg-sec-1",
                    role: "user",
                    content: "Audit mTLS cipher suites and rotate the staging ingress certificate.",
                    thought: nil,
                    thoughtDurationMs: 0,
                    tools: [],
                    attachments: [],
                    timestamp: Date().addingTimeInterval(-1750),
                    modelLabel: nil,
                    tokensIn: 88,
                    tokensOut: 0,
                    durationMs: 0,
                    feedback: 0
                ),
                ChatTurnMessage(
                    id: "msg-sec-2",
                    role: "assistant",
                    content: "I verified the TLS 1.3 cipher configuration and prepared the certificate rotation command. Please review and approve execution below:",
                    thought: "Staging rotation touches /etc/zcode/tls/ingress.pem; requesting explicit operator approval under Ask mode.",
                    thoughtDurationMs: 1120,
                    tools: [
                        ToolCallItem(
                            id: "tool-sec-1",
                            kind: .subagent,
                            title: "Explore Subagent • TLS & Ingress Audit",
                            subtitle: "Scanned 18 config files • 0 weak ciphers",
                            status: .completed,
                            filePath: "zcode.config.json",
                            lineRange: "1-14",
                            diffPatch: nil,
                            command: nil,
                            output: "Verified TLS_AES_256_GCM_SHA384 and TLS_CHACHA20_POLY1305_SHA256.",
                            durationMs: 940,
                            addedLines: 0,
                            removedLines: 0,
                            subagentSteps: [
                                "Inspected zcode.config.json security policy",
                                "Checked certificate expiration window (348 days remaining)",
                                "Prepared zero-downtime reload command"
                            ]
                        )
                    ],
                    attachments: [],
                    timestamp: Date().addingTimeInterval(-60),
                    modelLabel: "Claude Opus 4.7 • Max",
                    tokensIn: 16300,
                    tokensOut: 2310,
                    durationMs: 2100,
                    feedback: 0
                )
            ],
            todos: [
                TodoChecklistItem(id: "tds-1", content: "Audit TLS 1.3 cipher suites across ingress", status: "completed", priority: "high"),
                TodoChecklistItem(id: "tds-2", content: "Rotate staging ingress certificate & reload daemon", status: "in_progress", priority: "high")
            ],
            pendingPermission: PermissionPrompt(
                id: "perm-tls-rotate",
                toolName: "Bash",
                summary: "Reload ZCode Server TLS certificate without dropping active RPC streams",
                commandOrPath: "zcode-server reload-tls --cert ./certs/staging-2026.pem",
                previewDiffOrCommand: "$ zcode-server reload-tls --cert ./certs/staging-2026.pem --verify-chain",
                riskLevel: "MEDIUM"
            ),
            pendingQuestion: nil,
            pendingPlan: nil,
            queuedPrompts: [],
            checkpoints: []
        )

        let archivedSession = AgentTaskSession(
            id: "task-archived-migration",
            traceId: "trc_11a09d44",
            projectId: "proj-gateway-rs",
            workspacePath: "/srv/cloud/edge-gateway-rust",
            title: "Migrate Tokio WebSocket Codec to Zero-Copy Bytes",
            status: .completed,
            mode: .autoEdit,
            modelId: "openai/gpt-5.4",
            effort: .medium,
            pinned: false,
            archived: true,
            unread: false,
            offPeakEnabled: false,
            createdAt: Date().addingTimeInterval(-86400 * 3),
            updatedAt: Date().addingTimeInterval(-86400 * 3),
            contextUsedPercent: 61,
            totalTokensIn: 84200,
            totalTokensOut: 12900,
            cachedTokens: 60100,
            costUSD: 0.42,
            messages: [
                ChatTurnMessage(
                    id: "msg-arch-1",
                    role: "user",
                    content: "Refactor WebSocket frame decoder in Rust to avoid heap copies.",
                    thought: nil,
                    thoughtDurationMs: 0,
                    tools: [],
                    attachments: [],
                    timestamp: Date().addingTimeInterval(-86400 * 3),
                    modelLabel: nil,
                    tokensIn: 60,
                    tokensOut: 0,
                    durationMs: 0,
                    feedback: 0
                ),
                ChatTurnMessage(
                    id: "msg-arch-2",
                    role: "assistant",
                    content: "Completed zero-copy `BytesMut::split_to` refactoring across 4 crates. Throughput increased by 38%.",
                    thought: nil,
                    thoughtDurationMs: 920,
                    tools: [],
                    attachments: [],
                    timestamp: Date().addingTimeInterval(-86400 * 3 + 30),
                    modelLabel: "GPT-5.4 Codex",
                    tokensIn: 84140,
                    tokensOut: 12900,
                    durationMs: 3200,
                    feedback: 1
                )
            ],
            todos: [],
            pendingPermission: nil,
            pendingQuestion: nil,
            pendingPlan: nil,
            queuedPrompts: [],
            checkpoints: []
        )

        let pinnedRelayTask = AgentTaskSession(
            id: "task-pinned-relay",
            traceId: "trc_62b10a91",
            projectId: "proj-zcode-core",
            workspacePath: "/Users/macos/workspace/zcode-enterprise-core",
            title: "Prevent reconnect jitter on Cloud Relay V2 multiplexer",
            status: .running,
            mode: .yolo,
            modelId: "anthropic/claude-opus-4-7",
            effort: .high,
            pinned: true,
            archived: false,
            unread: false,
            offPeakEnabled: false,
            createdAt: Date().addingTimeInterval(-3600),
            updatedAt: Date().addingTimeInterval(-3600),
            contextUsedPercent: 18,
            totalTokensIn: 14200,
            totalTokensOut: 1980,
            cachedTokens: 9800,
            costUSD: 0.09,
            messages: [
                ChatTurnMessage(
                    id: "msg-pr-1",
                    role: "user",
                    content: "Add exponential backoff with jitter when wss://zcode.z.ai/api/v1/remote/ws2 drops transiently.",
                    thought: nil,
                    thoughtDurationMs: 0,
                    tools: [],
                    attachments: [],
                    timestamp: Date().addingTimeInterval(-3600),
                    modelLabel: nil,
                    tokensIn: 76,
                    tokensOut: 0,
                    durationMs: 0,
                    feedback: 0
                ),
                ChatTurnMessage(
                    id: "msg-pr-2",
                    role: "assistant",
                    content: "Implemented bounded `250ms–8s` jittered backoff and preserved active `bridgeSessionId` frame buffers across `RelayMultiplexer.ts`.",
                    thought: "Checking transient WebSocket close codes (1006/1012) on Relay V2 and ensuring unacknowledged SocketFrameHeader sequence IDs replay cleanly.",
                    thoughtDurationMs: 840,
                    tools: [
                        ToolCallItem(
                            id: "tool-pr-1",
                            kind: .readFile,
                            title: "Read src/rpc/SocketProtocol.swift",
                            subtitle: "Lines 1–32",
                            status: .completed,
                            filePath: "src/rpc/SocketProtocol.swift",
                            lineRange: "1-32",
                            diffPatch: nil,
                            command: nil,
                            output: nil,
                            durationMs: 31,
                            addedLines: 0,
                            removedLines: 0,
                            subagentSteps: []
                        ),
                        ToolCallItem(
                            id: "tool-pr-2",
                            kind: .editFile,
                            title: "Edit src/rpc/RelayMultiplexer.ts",
                            subtitle: "+18 -4 • Bounded jitter backoff",
                            status: .completed,
                            filePath: "src/rpc/RelayMultiplexer.ts",
                            lineRange: "14-42",
                            diffPatch: """
                            @@ -14,4 +14,18 @@
                            -  const delayMs = 1000;
                            +  const baseMs = Math.min(8000, 250 * Math.pow(2, attempt));
                            +  const delayMs = Math.round(baseMs * (0.8 + Math.random() * 0.4));
                            """,
                            command: nil,
                            output: nil,
                            durationMs: 94,
                            addedLines: 18,
                            removedLines: 4,
                            subagentSteps: []
                        )
                    ],
                    attachments: [],
                    timestamp: Date().addingTimeInterval(-3540),
                    modelLabel: "claude-opus-4-7",
                    tokensIn: 14124,
                    tokensOut: 1980,
                    durationMs: 1420,
                    feedback: 0
                )
            ],
            todos: [
                TodoChecklistItem(id: "td-r1", content: "Wire bounded 250ms–8s reconnect backoff", status: "completed", priority: "high"),
                TodoChecklistItem(id: "td-r2", content: "Verify multi-chunk rpc-frame CRC32 replay", status: "in_progress", priority: "high")
            ],
            pendingPermission: nil,
            pendingQuestion: nil,
            pendingPlan: nil,
            queuedPrompts: [
                QueuedPromptItem(
                    id: "qp-seed-1",
                    content: "Also benchmark reconnect latency against assets/rpc-benchmarks.csv",
                    attachments: [
                        ComposerAttachment(
                            id: "att-qp-seed-1",
                            name: "architecture-overview.png",
                            kind: "image",
                            sizeBytes: 24576,
                            filePath: "assets/architecture-overview.png",
                            lineNote: nil,
                            previewPNGData: nil
                        )
                    ],
                    createdAt: Date().addingTimeInterval(-25)
                )
            ],
            checkpoints: [],
            goals: [
                GoalObjectiveItem(id: "goal-relay-1", title: "Eliminate reconnect thundering herd across Cloud Relay V2 while preserving queued rpc-frame sequence order", completed: false)
            ],
            goalElapsedText: "8m 26s",
            goalPaused: false,
            subagentRuns: [
                SubagentSessionRun(
                    id: "sub-relay-1",
                    title: "Trace Relay V2 close code 1006/1012 recovery",
                    agentType: "Explore",
                    isRunning: true,
                    elapsedText: "Running for 8m 24s",
                    transcriptMarkdown: """
                    Inspected `RelayMultiplexer.ts` reconnect state machine:

                    - Unacknowledged frames stay buffered per `bridgeSessionId` across `bridgeGeneration + 1`.
                    - Jittered backoff bounds delay to `[200ms, 8000ms]` using `0.8 + Math.random() * 0.4`.
                    """,
                    artifactImagePath: "assets/telemetry-latency-chart.png",
                    timestamp: Date().addingTimeInterval(-240)
                ),
                SubagentSessionRun(
                    id: "sub-relay-2",
                    title: "Simulate 20% packet drop over wss://zcode.z.ai",
                    agentType: "general-purpose",
                    isRunning: true,
                    elapsedText: "Running for 5m 11s",
                    transcriptMarkdown: """
                    Running fault-injection test suite across 120 simulated reconnect cycles:

                    - `120/120` cycles re-established `client-ready` handshake without duplicate RPC dispatch.
                    """,
                    artifactImagePath: nil,
                    timestamp: Date().addingTimeInterval(-140)
                )
            ]
        )

        let pinnedPluginTask = AgentTaskSession(
            id: "task-pinned-mcp",
            traceId: "trc_41f08c22",
            projectId: "proj-zcode-core",
            workspacePath: "/Users/macos/workspace/zcode-enterprise-core",
            title: "Prioritize CodeGraph & GitNexus MCP over fallback grep",
            status: .completed,
            mode: .yolo,
            modelId: "zai/glm-5.1-coding",
            effort: .high,
            pinned: true,
            archived: false,
            unread: false,
            offPeakEnabled: false,
            createdAt: Date().addingTimeInterval(-86400 * 2),
            updatedAt: Date().addingTimeInterval(-86400 * 2),
            contextUsedPercent: 29,
            totalTokensIn: 24800,
            totalTokensOut: 3410,
            cachedTokens: 19200,
            costUSD: 0.11,
            messages: [],
            todos: [],
            pendingPermission: nil,
            pendingQuestion: nil,
            pendingPlan: nil,
            queuedPrompts: [],
            checkpoints: []
        )

        let gatewayActiveTask = AgentTaskSession(
            id: "task-gateway-epoll",
            traceId: "trc_39d82e10",
            projectId: "proj-gateway-rs",
            workspacePath: "/srv/cloud/edge-gateway-rust",
            title: "Benchmark arm64 SIMD CRC32 frame validator in Rust",
            status: .completed,
            mode: .yolo,
            modelId: "anthropic/claude-opus-4-7",
            effort: .high,
            pinned: false,
            archived: false,
            unread: true,
            offPeakEnabled: false,
            createdAt: Date().addingTimeInterval(-3600 * 22),
            updatedAt: Date().addingTimeInterval(-3600 * 22),
            contextUsedPercent: 41,
            totalTokensIn: 31200,
            totalTokensOut: 4120,
            cachedTokens: 21000,
            costUSD: 0.15,
            messages: [],
            todos: [],
            pendingPermission: nil,
            pendingQuestion: nil,
            pendingPlan: nil,
            queuedPrompts: [],
            checkpoints: []
        )

        return [pinnedRelayTask, mainSession, pinnedPluginTask, approvalSession, gatewayActiveTask, archivedSession]
    }

    public static func defaultGitChanges() -> [GitChangedFile] {
        [
            GitChangedFile(
                id: "git-1",
                path: "src/rpc/SocketProtocol.swift",
                status: "M",
                isStaged: true,
                added: 14,
                removed: 3,
                patch: """
                @@ -12,7 +12,18 @@ public struct SocketFrameHeader: Equatable, Sendable {
                     public init(messageType: UInt8 = 1, sequenceId: UInt32 = 0, acknowledgeId: UInt32 = 0, payloadBytes: UInt32) {
                         self.messageType = messageType
                         self.sequenceId = sequenceId
                -        self.acknowledgeId = 0
                +        self.acknowledgeId = acknowledgeId
                         self.payloadBytes = payloadBytes
                     }
                +
                +    public func encode(with payload: Data) -> Data {
                +        var buffer = Data(capacity: Self.headerSize + payload.count)
                +        buffer.append(messageType)
                +        buffer.appendBigEndian(sequenceId)
                +        buffer.appendBigEndian(acknowledgeId)
                +        buffer.appendBigEndian(UInt32(payload.count))
                +        buffer.append(payload)
                +        return buffer
                +    }
                 }
                """,
                beforeContent: "self.acknowledgeId = 0",
                afterContent: "self.acknowledgeId = acknowledgeId"
            ),
            GitChangedFile(
                id: "git-2",
                path: "src/rpc/RelayMultiplexer.ts",
                status: "A",
                isStaged: false,
                added: 22,
                removed: 0,
                patch: """
                @@ -0,0 +1,18 @@
                +export interface RelayRpcFrame {
                +  zcode_type: "rpc-frame";
                +  bridgeSessionId: string;
                +  bridgeGeneration: number;
                +  messageSeq: number;
                +  fragmentIndex: number;
                +  fragmentCount: number;
                +  checksum: { algorithm: "crc32"; value: string };
                +  dataBase64: string;
                +}
                +
                +export async function dispatchTunneledFrame(socket: WebSocket, frame: RelayRpcFrame): Promise<void> {
                +  socket.send(JSON.stringify({ type: "data", payload: frame }));
                +}
                """,
                beforeContent: "",
                afterContent: "export interface RelayRpcFrame { ... }"
            ),
            GitChangedFile(
                id: "git-3",
                path: "README.md",
                status: "M",
                isStaged: false,
                added: 6,
                removed: 1,
                patch: """
                @@ -3,4 +3,9 @@
                -Legacy JSON bridge runtime.
                +Unified high-throughput coding agent runtime with SocketProtocol VQL IPC and Cloud Relay V2.
                +
                +## Key Capabilities
                +- Binary VQL Transport
                +- Interactive Native Inspector
                +- Hardware Keychain Security
                """,
                beforeContent: "Legacy JSON bridge runtime.",
                afterContent: "Unified high-throughput coding agent runtime..."
            )
        ]
    }

    public static func defaultGitCommits() -> [GitCommitRecord] {
        [
            GitCommitRecord(id: "c1", shortHash: "e83f21d", subject: "feat(rpc): add CRC32 verified chunk assembly for Relay V2", author: "ZCode Agent", branchRef: "HEAD -> feat/native-rpc-v4", timestamp: Date().addingTimeInterval(-900)),
            GitCommitRecord(id: "c2", shortHash: "a41c90b", subject: "refactor(inspector): add 6 Shiki syntax palettes & PDF viewer", author: "Platform Team", branchRef: nil, timestamp: Date().addingTimeInterval(-7200)),
            GitCommitRecord(id: "c3", shortHash: "79b03e4", subject: "chore(security): enforce Keychain credential isolation per workstation", author: "Security Eng", branchRef: "origin/main", timestamp: Date().addingTimeInterval(-28800))
        ]
    }

    public static func defaultTerminalTabs() -> [TerminalTabModel] {
        [
            TerminalTabModel(
                id: "term-1",
                title: "zsh • zcode-core",
                cwd: "~/workspace/zcode-enterprise-core",
                shell: "/bin/zsh",
                isRunningJob: false,
                entries: [
                    TerminalEntry(
                        id: "te-1",
                        command: "zcode-server status --json",
                        output: """
                        {
                          "state": "ready",
                          "version": "3.16.3",
                          "protocolVersion": 1,
                          "host": "127.0.0.1",
                          "port": 57743,
                          "channels": 57
                        }
                        """,
                        isError: false,
                        timestamp: Date().addingTimeInterval(-600)
                    ),
                    TerminalEntry(
                        id: "te-2",
                        command: "git status -sb",
                        output: "## feat/native-rpc-v4...origin/feat/native-rpc-v4 [ahead 2]\nM  src/rpc/SocketProtocol.swift\n?? src/rpc/RelayMultiplexer.ts\n M README.md",
                        isError: false,
                        timestamp: Date().addingTimeInterval(-240)
                    )
                ]
            ),
            TerminalTabModel(
                id: "term-2",
                title: "watch • test-runner",
                cwd: "~/workspace/zcode-enterprise-core",
                shell: "/bin/zsh",
                isRunningJob: true,
                entries: [
                    TerminalEntry(
                        id: "te-3",
                        command: "swift test --parallel",
                        output: "[14/14] Compiling ZCodeRPCTests • Watching for file changes (0 failures)...",
                        isError: false,
                        timestamp: Date().addingTimeInterval(-90)
                    )
                ]
            )
        ]
    }

    public static func defaultMCPServers() -> [MCPServerItem] {
        [
            MCPServerItem(id: "mcp-gitnexus", name: "gitnexus", transport: "stdio", endpointOrCommand: "npx -y gitnexus-mcp serve", enabled: true, connected: true, tools: ["query", "context", "impact", "detect_changes", "rename", "cypher"], resourcesCount: 8),
            MCPServerItem(id: "mcp-codegraph", name: "codegraph", transport: "stdio", endpointOrCommand: "codegraph-mcp --watch", enabled: true, connected: true, tools: ["codegraph_explore"], resourcesCount: 3),
            MCPServerItem(id: "mcp-aiblueprint", name: "aiblueprint", transport: "http", endpointOrCommand: "http://127.0.0.1:8790/mcp", enabled: true, connected: true, tools: ["drawing", "entity", "layer", "compliance", "view"], resourcesCount: 4),
            MCPServerItem(id: "mcp-postgres", name: "enterprise-postgres", transport: "sse", endpointOrCommand: "https://mcp.internal.corp/pg/sse", enabled: false, connected: false, tools: ["query_readonly", "describe_schema"], resourcesCount: 12)
        ]
    }

    public static func defaultSkills() -> [SkillCatalogItem] {
        [
            SkillCatalogItem(id: "sk-adv-verify", name: "adversarial-verify", summary: "Fresh decisive verification check before presenting substantive work.", scope: "Built-in", enabled: true, markdownBody: "# Adversarial Verify\nVerify explicit success criteria with fresh runtime evidence before completion."),
            SkillCatalogItem(id: "sk-sys-debug", name: "systematic-debugging", summary: "Root-cause investigation workflow before proposing fixes.", scope: "Built-in", enabled: true, markdownBody: "# Systematic Debugging\n1. Reproduce deterministically.\n2. Trace data flow from source to sink.\n3. Verify hypothesis with minimal test."),
            SkillCatalogItem(id: "sk-tdd", name: "test-driven-development", summary: "Write failing test first, verify red-green-refactor cycle.", scope: "Built-in", enabled: true, markdownBody: "# Test-Driven Development\nAlways write a minimal failing test before implementation code."),
            SkillCatalogItem(id: "sk-ui", name: "frontend-ui-engineering", summary: "Production-grade native & design-system UI craftsmanship.", scope: "Workspace", enabled: true, markdownBody: "# UI Engineering\nMaintain strict visual hierarchy, crisp hairline borders, and accessible contrast."),
            SkillCatalogItem(id: "sk-sec", name: "security-and-hardening", summary: "OWASP & enterprise auth/input/storage hardening audit.", scope: "Built-in", enabled: true, markdownBody: "# Security & Hardening\nValidate untrusted boundaries, isolate secrets in Keychain, enforce least privilege.")
        ]
    }

    public static func defaultPlugins() -> [PluginCatalogItem] {
        [
            PluginCatalogItem(id: "pl-visualize", name: "Visualize", version: "0.1.0", marketplace: "zcode-plugins-official", summary: "Interactive diagrams, architecture graphs, and visual explorers.", installed: true, enabled: true),
            PluginCatalogItem(id: "pl-node-repl", name: "Node Repl Host", version: "0.2.0", marketplace: "zcode-plugins-official", summary: "Stateful JavaScript & TypeScript evaluation host.", installed: true, enabled: true),
            PluginCatalogItem(id: "pl-browser-use", name: "Browser Use", version: "0.5.1", marketplace: "zcode-plugins-official", summary: "Interactive browser automation and GUI verification.", installed: true, enabled: true),
            PluginCatalogItem(id: "pl-documents", name: "Documents", version: "0.2.1", marketplace: "zcode-plugins-official", summary: "DOCX document creation, editing, and inspection.", installed: true, enabled: true),
            PluginCatalogItem(id: "pl-pdf", name: "PDF", version: "0.2.2", marketplace: "zcode-plugins-official", summary: "Native PDF toolkit for reports, specs, and visual inspection.", installed: true, enabled: true),
            PluginCatalogItem(id: "pl-presentations", name: "Presentations", version: "0.2.1", marketplace: "zcode-plugins-official", summary: "Slide deck authoring, restyling, and review.", installed: true, enabled: true),
            PluginCatalogItem(id: "pl-spreadsheets", name: "Spreadsheets", version: "0.2.1", marketplace: "zcode-plugins-official", summary: "Workbook modeling, formula auditing, and CSV/XLSX views.", installed: true, enabled: true),
            PluginCatalogItem(id: "pl-zguide", name: "zcode-diagnostics", version: "0.3.0", marketplace: "zcode-plugins-official", summary: "Diagnose MCP servers, hooks, commands, and skills.", installed: true, enabled: true),
            PluginCatalogItem(id: "pl-sentry", name: "sentry-incident-triage", version: "1.4.2", marketplace: "enterprise-registry", summary: "Correlate production stack traces with repository commits.", installed: false, enabled: false)
        ]
    }

    public static func defaultSubagents() -> [SubagentDefinitionItem] {
        [
            SubagentDefinitionItem(
                id: "built-in:built-in:general-purpose",
                name: "general-purpose",
                description: "General-purpose agent for researching complex questions, searching for code, and executing multi-step tasks autonomously.",
                systemPrompt: "You are ZCode's general-purpose subagent. Research thoroughly, verify facts in code, and return concise actionable findings.",
                color: .blue,
                scope: "built-in",
                source: "built-in",
                readOnly: true,
                enabled: true,
                modelOverride: "inherit",
                reasoningOverride: "inherit",
                allowedTools: ["*"],
                filePath: "built-in:general-purpose"
            ),
            SubagentDefinitionItem(
                id: "built-in:built-in:Explore",
                name: "Explore",
                description: "Read-only search agent for broad fan-out codebase searches across files, directories, and naming conventions.",
                systemPrompt: "You are ZCode's fast read-only Explore subagent. Locate relevant files, symbols, and call chains quickly without modifying files.",
                color: .cyan,
                scope: "built-in",
                source: "built-in",
                readOnly: true,
                enabled: true,
                modelOverride: "inherit",
                reasoningOverride: "low",
                allowedTools: ["Read", "Grep", "Glob", "Bash", "WebFetch", "WebSearch", "TodoWrite"],
                filePath: "built-in:Explore"
            ),
            SubagentDefinitionItem(
                id: "user:user:plan-architect",
                name: "plan-architect",
                description: "Analyzes requirements and designs system architecture, API contracts, and database schemas without writing implementation code.",
                systemPrompt: "Analyze system requirements, trade-offs, API boundaries, and data schemas. Return a structured architecture blueprint with file-level impact.",
                color: .purple,
                scope: "user",
                source: "user",
                readOnly: false,
                enabled: true,
                modelOverride: "inherit",
                reasoningOverride: "high",
                allowedTools: ["Read", "Grep", "Glob", "WebFetch", "TodoWrite"],
                injectAgentsMd: true,
                filePath: "~/.zcode/agents/plan-architect.md"
            ),
            SubagentDefinitionItem(
                id: "plugin:documents:visual-judge",
                name: "documents:visual-judge",
                description: "Single visual acceptance gate for rendered DOCX, PDF, PPTX, and XLSX page images.",
                systemPrompt: "Inspect rendered page PNGs for visual layout, typography, alignment, and asset quality. Return structured JSON pass/fail verdicts per page.",
                color: .orange,
                scope: "user",
                source: "plugin",
                readOnly: true,
                enabled: true,
                modelOverride: "inherit",
                reasoningOverride: "medium",
                allowedTools: ["Read", "Bash"],
                filePath: "plugin:documents/visual-judge.md",
                pluginId: "documents@zcode-plugins-official",
                pluginName: "Documents"
            ),
            SubagentDefinitionItem(
                id: "plugin:pdf:visual-judge",
                name: "pdf:visual-judge",
                description: "Visual quality gate for generated PDF reports, academic papers, and posters.",
                systemPrompt: "Evaluate rendered PDF page images for clipping, overlap, contrast, and layout polish.",
                color: .pink,
                scope: "user",
                source: "plugin",
                readOnly: true,
                enabled: true,
                modelOverride: "inherit",
                reasoningOverride: "medium",
                allowedTools: ["Read", "Bash"],
                filePath: "plugin:pdf/visual-judge.md",
                pluginId: "pdf@zcode-plugins-official",
                pluginName: "PDF"
            )
        ]
    }

    public static func defaultSlashCommands() -> [SlashCommandItem] {
        [
            SlashCommandItem(id: "cmd-goal", trigger: "/goal", summary: "Turn on auto-mode", scope: "System", promptTemplate: "Enable autonomous goal execution mode."),
            SlashCommandItem(id: "cmd-workflow", trigger: "/workflow", summary: "Orchestrate multi-step subagent workflow", scope: "System", promptTemplate: "Create and run a structured multi-agent workflow."),
            SlashCommandItem(id: "cmd-compact", trigger: "/compact", summary: "Summarize conversation context to free token budget", scope: "System", promptTemplate: "Compact context window while preserving architectural decisions."),
            SlashCommandItem(id: "cmd-init", trigger: "/init", summary: "Initialize AGENTS.md project guidelines", scope: "System", promptTemplate: "Scan repository conventions and generate AGENTS.md."),
            SlashCommandItem(id: "cmd-plan", trigger: "Plan mode", summary: "Switch session into structured Plan mode", scope: "System", promptTemplate: "/plan "),
            SlashCommandItem(id: "cmd-review", trigger: "/review", summary: "Run adversarial code & security review on current Git diff", scope: "Project", promptTemplate: "Inspect all staged and unstaged changes for bugs, race conditions, and UX regressions."),
            SlashCommandItem(id: "cmd-rewind", trigger: "/rewind", summary: "Restore conversation and files to an earlier Git checkpoint", scope: "System", promptTemplate: "Open checkpoint rewind selector."),
            SlashCommandItem(id: "cmd-demo-approval", trigger: "/ask-permission", summary: "Simulate a live tool permission approval card", scope: "System", promptTemplate: "Trigger interactive tool approval card."),
            SlashCommandItem(id: "cmd-demo-question", trigger: "/ask-question", summary: "Simulate an interactive AskUserQuestion card", scope: "System", promptTemplate: "Trigger interactive structured user question.")
        ]
    }

    public static func defaultHooks() -> [HookRuleItem] {
        [
            HookRuleItem(id: "hk-1", event: "PreToolUse", matcher: "Bash(rm -rf*)", command: "zcode-policy block-destructive", enabled: true),
            HookRuleItem(id: "hk-2", event: "PostToolUse", matcher: "Edit(*.swift)", command: "swiftformat --lint", enabled: true),
            HookRuleItem(id: "hk-3", event: "Stop", matcher: "*", command: "zcode-notify session-complete", enabled: true)
        ]
    }

    public static func defaultMemories() -> [MemoryNoteItem] {
        [
            MemoryNoteItem(id: "mem-1", slug: "ios-native-policy", type: "feedback", description: "Strictly native SwiftUI/UIKit/PDFKit — never use WebView", body: "All mobile interfaces must use 100% native iOS components (SwiftUI, PDFKit, CoreGraphics, URLSessionWebSocketTask). Why: Enterprise performance, security, and offline resilience.", updatedAt: Date().addingTimeInterval(-3600)),
            MemoryNoteItem(id: "mem-2", slug: "rpc-wire-framing", type: "project", description: "ZCode Server v3.16.3 uses 13-byte BE SocketProtocol + 7-bit VQL", body: "ChannelServer wraps arguments in an array via ProxyChannel.fromService; Initialize frame [200] precedes unary [100] calls.", updatedAt: Date().addingTimeInterval(-7200))
        ]
    }

    public static func defaultAutomations() -> [AutomationScheduleItem] {
        [
            AutomationScheduleItem(id: "auto-1", name: "Nightly Dependency & CVE Audit", cronExpression: "0 2 * * *", workspacePath: "/Users/macos/workspace/zcode-enterprise-core", prompt: "Scan Package.resolved and Cargo.lock for security advisories and open a summary report.", enabled: true, lastRunStatus: "Succeeded (0 CVEs)", lastRunAt: Date().addingTimeInterval(-21600)),
            AutomationScheduleItem(id: "auto-2", name: "Weekly Dead-Code & Coverage Sweep", cronExpression: "0 6 * * 1", workspacePath: "/srv/cloud/edge-gateway-rust", prompt: "Identify unused public symbols via GitNexus and propose cleanup.", enabled: false, lastRunStatus: "Idle", lastRunAt: nil)
        ]
    }

    public static func defaultTokenUsage() -> [DailyTokenUsageItem] {
        [
            DailyTokenUsageItem(id: "d1", dayLabel: "Mon", inputTokensK: 320, outputTokensK: 58, cachedTokensK: 240, costUSD: 1.42),
            DailyTokenUsageItem(id: "d2", dayLabel: "Tue", inputTokensK: 485, outputTokensK: 91, cachedTokensK: 390, costUSD: 2.15),
            DailyTokenUsageItem(id: "d3", dayLabel: "Wed", inputTokensK: 410, outputTokensK: 74, cachedTokensK: 310, costUSD: 1.84),
            DailyTokenUsageItem(id: "d4", dayLabel: "Thu", inputTokensK: 620, outputTokensK: 118, cachedTokensK: 505, costUSD: 2.76),
            DailyTokenUsageItem(id: "d5", dayLabel: "Fri", inputTokensK: 540, outputTokensK: 102, cachedTokensK: 430, costUSD: 2.38),
            DailyTokenUsageItem(id: "d6", dayLabel: "Sat", inputTokensK: 290, outputTokensK: 49, cachedTokensK: 215, costUSD: 1.19),
            DailyTokenUsageItem(id: "d7", dayLabel: "Sun", inputTokensK: 465, outputTokensK: 86, cachedTokensK: 372, costUSD: 2.04)
        ]
    }

    public static func defaultWorkflowNodes() -> [WorkflowGraphNode] {
        [
            WorkflowGraphNode(id: "wf-1", title: "Intake & Spec", role: "Lead Agent", status: "completed", durationText: "0.8s", xRatio: 0.16, yRatio: 0.50),
            WorkflowGraphNode(id: "wf-2", title: "Explore Repo", role: "Explore Subagent", status: "completed", durationText: "1.4s", xRatio: 0.44, yRatio: 0.25),
            WorkflowGraphNode(id: "wf-3", title: "Impact Check", role: "GitNexus MCP", status: "completed", durationText: "0.9s", xRatio: 0.44, yRatio: 0.75),
            WorkflowGraphNode(id: "wf-4", title: "Patch & Test", role: "Builder Agent", status: "completed", durationText: "2.6s", xRatio: 0.74, yRatio: 0.50),
            WorkflowGraphNode(id: "wf-5", title: "Verify Gate", role: "Visual Judge", status: "completed", durationText: "1.1s", xRatio: 0.92, yRatio: 0.50)
        ]
    }
}
