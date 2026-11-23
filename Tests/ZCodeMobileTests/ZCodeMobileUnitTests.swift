import XCTest
@testable import ZCode

final class ZCodeMobileUnitTests: XCTestCase {

    func testIEEE8023CRC32CheckVector() {
        let input = Data("123456789".utf8)
        XCTAssertEqual(ZCodeVQLCodec.crc32Hex(input), "cbf43926")
    }

    func testVQLBinaryRoundTripAndSocketFrameHeader() throws {
        let originalHeader: VQLValue = .array([
            .int32(100),
            .int32(42),
            .string("zcode-task"),
            .string("getTaskSnapshot")
        ])
        let originalArgs: VQLValue = .array([
            .fromJSONObject(["taskId": "task-123", "messageLimit": 50]),
            .buffer(Data([0xDE, 0xAD, 0xBE, 0xEF])),
            .int32(-7),
            .undefined
        ])

        var payload = Data()
        ZCodeVQLCodec.encode(originalHeader, into: &payload)
        ZCodeVQLCodec.encode(originalArgs, into: &payload)

        let socketFrame = ZCodeVQLCodec.wrapSocketFrame(payload: payload)
        XCTAssertEqual(socketFrame[0], 1)
        XCTAssertEqual(socketFrame.count, 13 + payload.count)

        let unwrapped = try ZCodeVQLCodec.unwrapSocketFrame(socketFrame)
        var offset = 0
        let decodedHeader = try ZCodeVQLCodec.decode(from: unwrapped.payload, offset: &offset)
        let decodedArgs = try ZCodeVQLCodec.decode(from: unwrapped.payload, offset: &offset)

        XCTAssertEqual(decodedHeader, originalHeader)
        XCTAssertEqual(decodedArgs, originalArgs)
    }

    func testConnectionURLParserSupportsRelayQRPassHashAndDirectWS() {
        let qrShare = "Connect my workstation: https://zcode.z.ai/remote/v4?sid=dev_sid_01&mid=mac_mid_99&name=EnterpriseMac#my_secret_hash"
        let parsedQR = ConnectionURLParser.parse(qrShare)
        XCTAssertNotNil(parsedQR)
        XCTAssertEqual(parsedQR?.transport, .cloudRelayV2)
        XCTAssertEqual(parsedQR?.sid, "dev_sid_01")
        XCTAssertEqual(parsedQR?.mid, "mac_mid_99")
        XCTAssertEqual(parsedQR?.passHash, "my_secret_hash")
        XCTAssertEqual(parsedQR?.name, "EnterpriseMac")

        // Bare domain without https:// scheme
        let bareZai = "zcode.z.ai/remote/v4?sid=sid_abc&mid=mid_1234567890"
        let parsedBare = ConnectionURLParser.parse(bareZai)
        XCTAssertNotNil(parsedBare)
        XCTAssertEqual(parsedBare?.transport, .cloudRelayV2)
        XCTAssertEqual(parsedBare?.sid, "sid_abc")
        XCTAssertEqual(parsedBare?.name, "Device mid_1234")

        // Incomplete /remote/v4 without sid or remoteControlToken must be rejected
        XCTAssertNil(ConnectionURLParser.parse("https://zcode.z.ai/remote/v4"))

        let directURL = "http://192.168.1.16:57743?token=sec_tok_1"
        let parsedDirect = ConnectionURLParser.parse(directURL)
        XCTAssertNotNil(parsedDirect)
        XCTAssertEqual(parsedDirect?.transport, .directServer)
        XCTAssertEqual(parsedDirect?.host, "192.168.1.16")
        XCTAssertEqual(parsedDirect?.port, 57743)
        XCTAssertEqual(parsedDirect?.token, "sec_tok_1")
    }

    func testRelayV4ChallengeProofBase64URL() {
        let proof = ZaiAuthAndRemoteService.calculateChallengeProof(
            passHash: "test_pass_hash",
            nonce: "nonce_12345",
            role: "terminal",
            deviceSid: "sid_98765"
        )
        XCTAssertFalse(proof.isEmpty)
        XCTAssertFalse(proof.contains("="))
        XCTAssertFalse(proof.contains("+"))
        XCTAssertFalse(proof.contains("/"))
    }

    @MainActor
    func testProductionStoreStartsZeroDemoAndShowsOnboarding() {
        UserDefaults.standard.removeObject(forKey: "zcode_mobile_enterprise_prefs_v2")
        UserDefaults.standard.removeObject(forKey: "zcode_saved_connections_v2")
        UserDefaults.standard.removeObject(forKey: "zcode_zai_account_v1")
        KeychainStore.delete("zcode_zai_jwt_token_v1")

        let prodStore = AppStore(seedDemoWorkspace: false)
        XCTAssertFalse(prodStore.isUITestSeededMode)
        XCTAssertEqual(prodStore.language, .english)
        XCTAssertTrue(prodStore.connections.isEmpty, "Production launch must contain zero demo connections")
        XCTAssertTrue(prodStore.projects.isEmpty, "Production launch must contain zero demo projects")
        XCTAssertTrue(prodStore.sessions.isEmpty, "Production launch must contain zero demo sessions")
        XCTAssertTrue(prodStore.fileTree.isEmpty, "Production launch must contain zero demo files")
        XCTAssertTrue(prodStore.gitChanges.isEmpty, "Production launch must contain zero demo git diffs")
        XCTAssertTrue(prodStore.terminalTabs.isEmpty, "Production launch must contain zero demo terminal tabs")
        XCTAssertTrue(prodStore.showConnectionHub, "Production launch must open Onboarding & Connection Hub")
        XCTAssertTrue(prodStore.shouldShowSignInStepFirst, "Fresh Production launch must show Step 1 Z.AI Sign-In first")
    }

    @MainActor
    func testDefaultEnglishLanguageAndCoreWorkflows() {
        UserDefaults.standard.removeObject(forKey: "zcode_mobile_enterprise_prefs_v2")
        let store = AppStore(seedDemoWorkspace: true)

        // Requirement 5: Default app language must be English
        XCTAssertEqual(store.language, .english)
        XCTAssertEqual(store.themeMode, .dark)
        XCTAssertEqual(SettingsGroupKind.allCases.count, 3)
        XCTAssertEqual(SettingsSectionKind.allCases.count, 18)

        // Inline code comment workflow
        store.addInlineCodeComment(filePath: "src/rpc/SocketProtocol.swift", startLine: 18, endLine: 22, comment: "Verify endianness", snippet: "buffer.appendBigEndian")
        XCTAssertEqual(store.inlineComments.count, 1)
        XCTAssertEqual(store.composerAttachments.last?.name, "src/rpc/SocketProtocol.swift:18-22")

        // Git commit workflow
        let initialCommits = store.gitCommits.count
        store.commitStagedChanges(message: "test: commit staged VQL header")
        XCTAssertEqual(store.gitCommits.count, initialCommits + 1)

        // Terminal execution
        let initialEntries = store.terminalTabs[0].entries.count
        store.executeTerminalCommand("pwd")
        XCTAssertEqual(store.terminalTabs[0].entries.count, initialEntries + 1)

        // Official ZCode Slash Commands & Plugins 1:1 Parity
        XCTAssertEqual(store.slashCommands.first?.trigger, "/goal")
        XCTAssertEqual(store.plugins.first?.name, "Visualize")

        // Prompt Queue (Enqueue while running, Edit, Delete)
        store.selectSession(store.sessions.first(where: { $0.id == "task-pinned-relay" })!)
        let initialQueueCount = store.activeSession?.queuedPrompts.count ?? 0
        store.composerText = "Follow-up queued check"
        store.sendPrompt()
        XCTAssertEqual(store.activeSession?.queuedPrompts.count, initialQueueCount + 1)
        if let lastId = store.activeSession?.queuedPrompts.last?.id {
            store.editQueuedPrompt(lastId)
            XCTAssertEqual(store.composerText, "Follow-up queued check")
        }
    }

    func testRelayV4StrictRPCFrameAndAckSchemasMatchDesktopV3163() throws {
        let bridge = RelayBridgeIdentity(
            bridgeSessionId: "bridge-sess-01",
            bridgeGeneration: 3,
            recoveryId: "rec-99",
            workspaceKey: "ws-ident-alpha",
            workspacePath: "/Users/macos/project",
            workspaceIdentity: "ws-ident-alpha"
        )

        // Raw VQL payload (Relay V4 uses ChannelClient directly without 13-byte SocketProtocol header)
        let longPrompt = String(repeating: "Verify strict Relay V4 rpc-frame schema. ", count: 65)
        let rawVQL = ZCodeVQLCodec.buildRawRPCRequestPayload(
            id: 1,
            channel: "zcode-task",
            method: "sendPrompt",
            args: [.fromJSONObject([
                "workspacePath": "/Users/macos/project",
                "workspaceIdentity": "ws-ident-alpha",
                "content": longPrompt
            ])]
        )
        XCTAssertNotEqual(rawVQL[0], 1, "Raw Relay V4 VQL payload must start with VQL array tag (0x04), not SocketProtocol Regular=1")
        XCTAssertEqual(rawVQL[0], 4)

        let built = ZCodeRPCClient.buildRPCFramePayloads(
            vqlPayload: rawVQL,
            identity: bridge,
            firstPhysicalSeq: 1,
            messageSeq: 1,
            maxFragmentBytes: 1024
        )
        let frames = built.payloads
        XCTAssertGreaterThan(frames.count, 1, "Multi-KB payload with 1024-byte chunk limit must fragment cleanly")
        XCTAssertEqual(built.nextPhysicalSeq, frames.count + 1)

        let expectedCRC = ZCodeVQLCodec.crc32Hex(rawVQL)
        var reassembled = Data()
        let allowedFrameKeys: Set<String> = [
            "zcode_type", "bridgeSessionId", "bridgeGeneration", "recoveryId",
            "seq", "messageSeq", "fragmentIndex", "fragmentCount", "messageBytes",
            "checksum", "dataBase64"
        ]

        for (index, frame) in frames.enumerated() {
            XCTAssertTrue(Set(frame.keys).isSubset(of: allowedFrameKeys), "Strict Zod schema rejects unknown keys")
            XCTAssertEqual(frame["zcode_type"] as? String, "rpc-frame")
            XCTAssertEqual(frame["bridgeSessionId"] as? String, "bridge-sess-01")
            XCTAssertEqual(frame["bridgeGeneration"] as? Int, 3)
            XCTAssertEqual(frame["recoveryId"] as? String, "rec-99")
            XCTAssertEqual(frame["seq"] as? Int, index + 1)
            XCTAssertEqual(frame["messageSeq"] as? Int, 1)
            XCTAssertEqual(frame["fragmentIndex"] as? Int, index)
            XCTAssertEqual(frame["fragmentCount"] as? Int, frames.count)
            XCTAssertEqual(frame["messageBytes"] as? Int, rawVQL.count)
            let checksum = try XCTUnwrap(frame["checksum"] as? [String: Any])
            XCTAssertEqual(checksum["algorithm"] as? String, "crc32")
            XCTAssertEqual(checksum["value"] as? String, expectedCRC)
            XCTAssertTrue(bridge.matchesTransportPayload(frame))

            let b64 = try XCTUnwrap(frame["dataBase64"] as? String)
            XCTAssertGreaterThanOrEqual(b64.count, 4)
            XCTAssertEqual(b64.count % 4, 0)
            let chunk = try XCTUnwrap(Data(base64Encoded: b64))
            reassembled.append(chunk)
        }

        XCTAssertEqual(reassembled, rawVQL)
        XCTAssertEqual(ZCodeVQLCodec.crc32Hex(reassembled), expectedCRC)

        // Strict rpc-frame-ack check
        let ack = ZCodeRPCClient.buildRPCFrameAckPayload(identity: bridge, ackMessageSeq: 7)
        let allowedAckKeys: Set<String> = [
            "zcode_type", "bridgeSessionId", "bridgeGeneration", "recoveryId", "ackMessageSeq"
        ]
        XCTAssertEqual(Set(ack.keys), allowedAckKeys)
        XCTAssertEqual(ack["zcode_type"] as? String, "rpc-frame-ack")
        XCTAssertEqual(ack["ackMessageSeq"] as? Int, 7)
        XCTAssertTrue(bridge.matchesTransportPayload(ack))

        var mismatched = ack
        mismatched["bridgeGeneration"] = 4
        XCTAssertFalse(bridge.matchesTransportPayload(mismatched))
    }

    func testParseWorkspaceSummariesMatchesDesktopBootstrapShape() {
        let rawList: [[String: Any]] = [
            [
                "workspacePath": "/Users/macos/.zcode/workspace/zcode-ios",
                "workspaceIdentity": "ws-id-zcode-ios",
                "label": "zcode-ios",
                "kind": "local",
                "connectionState": "ready"
            ],
            [
                "workspacePath": "/remote/offline-box",
                "workspaceIdentity": "ws-remote-1",
                "remoteSessionId": "ssh-sess-1",
                "label": "offline-ssh",
                "kind": "remote",
                "connectionState": "disconnected"
            ]
        ]

        let summaries = ZCodeRPCClient.parseWorkspaceSummaries(from: rawList)
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].name, "zcode-ios")
        XCTAssertEqual(summaries[0].workspaceKey, "ws-id-zcode-ios")
        XCTAssertTrue(summaries[0].canBridge)

        XCTAssertEqual(summaries[1].name, "offline-ssh")
        XCTAssertEqual(summaries[1].workspaceKey, "ws-remote-1")
        XCTAssertFalse(summaries[1].canBridge)
    }

    @MainActor
    func testZCodeSettingsModelProviderAndSubagentStudioParity() async {
        let store = AppStore(seedDemoWorkspace: true)

        // 1. Provider catalog is host-owned: nothing is fabricated before the view arrives.
        XCTAssertTrue(store.providerTemplates.isEmpty)

        let hostView: [String: Any] = [
            "revision": "[\"builtin-r1\",\"personal-r2\"]",
            "providerTemplates": [[
                "templateId": "openrouter",
                "templateNameMap": ["en-US": "OpenRouter"],
                "config": [
                    "group": "standard-personal",
                    "api": ["type": "anthropic-messages", "baseUrl": "https://openrouter.ai/api"],
                    "access": ["type": "api-key"],
                    "logo": ["key": "openrouter"]
                ]
            ]],
            "providerOrder": ["provider-openrouter"],
            "providers": [
                [
                    "providerId": "provider-zai",
                    "providerName": "Z.AI",
                    "templateId": "zai",
                    "enabled": true,
                    "executable": true,
                    "accountState": ["availability": "available", "entitled": true],
                    "effectiveConfig": [
                        "group": "zai-family",
                        "access": [
                            "type": "zhipu-account",
                            "accountType": "zai",
                            "mode": "individual-coding-plan",
                            "entitled": true
                        ],
                        "api": ["type": "anthropic-messages", "baseUrl": "https://api.z.ai"],
                        "logo": ["key": "zai"]
                    ],
                    "models": []
                ],
                [
                    "providerId": "provider-openrouter",
                    "providerName": "OpenRouter",
                    "templateId": "openrouter",
                    "enabled": true,
                    "executable": true,
                    "personalConfig": ["access": ["type": "api-key", "apiKey": "sk-or-real"]],
                    "effectiveConfig": [
                        "group": "standard-personal",
                        "access": ["type": "api-key", "apiKey": "sk-or-real"],
                        "api": ["type": "anthropic-messages", "baseUrl": "https://openrouter.ai/api"],
                        "logo": ["key": "openrouter"]
                    ],
                    "models": [[
                        "modelId": "anthropic/claude-opus-5",
                        "enabled": true,
                        "kind": "builtin",
                        "selectable": true,
                        "executable": true,
                        "effectiveConfig": [
                            "properties": [
                                "contextWindow": 1_000_000,
                                "requiresMfjsToolSchema": true,
                                "inputFormat": ["supportsImage": true, "supportsPdf": true],
                                "outputFormat": ["supportsText": true],
                                "supportsToolCall": true
                            ],
                            "optionSpecs": [
                                "reasoningLevel": ["values": ["low", "medium", "high", "max"], "map": "reasoning.level"],
                                "maxOutputTokens": ["max": 65_536, "map": "max_output"]
                            ]
                        ]
                    ]]
                ]
            ]
        ]

        store.applyProviderSettingsViewDictionary(hostView)

        XCTAssertEqual(store.providerSettingsRevision, "[\"builtin-r1\",\"personal-r2\"]")
        XCTAssertEqual(store.providerTemplates.map(\.id), ["openrouter"])
        XCTAssertEqual(store.providerTemplates.first?.displayName(), "OpenRouter")
        XCTAssertEqual(store.providerTemplates.first?.apiFormat, .anthropicMessages)
        XCTAssertEqual(store.providerOrder, ["provider-openrouter"])
        XCTAssertEqual(store.providers.map(\.id), ["provider-zai", "provider-openrouter"])

        let account = store.providers.first(where: { $0.id == "provider-zai" })
        XCTAssertEqual(account?.isAccountProvider, true)
        XCTAssertEqual(account?.accountAvailability, "available")
        XCTAssertEqual(account?.entitled, true)

        let personal = store.providers.first(where: { $0.id == "provider-openrouter" })
        XCTAssertEqual(personal?.apiKey, "sk-or-real")
        XCTAssertTrue(personal?.hasConfiguredAPIKey == true)
        XCTAssertEqual(personal?.revision, "[\"builtin-r1\",\"personal-r2\"]")
        XCTAssertEqual(personal?.apiKey, "sk-or-real")

        let model = personal?.models.first
        XCTAssertEqual(model?.modelId, "anthropic/claude-opus-5")
        XCTAssertEqual(model?.reasoningLevels, ["low", "medium", "high", "max"])
        XCTAssertEqual(model?.reasoningMap, "reasoning.level")
        XCTAssertEqual(model?.maxOutputTokens, 65_536)
        XCTAssertEqual(model?.contextWindowTokens, 1_000_000)
        XCTAssertTrue(model?.supportsVision == true)
        XCTAssertTrue(model?.supportsPdf == true)
        XCTAssertTrue(model?.executable == true)

        // An empty host view must clear local state (no `!rawProviders.isEmpty` guard).
        store.applyProviderSettingsViewDictionary([
            "revision": "[]",
            "providerTemplates": [],
            "providerOrder": [],
            "providers": []
        ])
        XCTAssertTrue(store.providers.isEmpty)
        XCTAssertTrue(store.providerTemplates.isEmpty)
        XCTAssertEqual(store.providerSettingsRevision, "[]")

        // Connectivity is never faked offline: honest failure message with no host.
        store.applyProviderSettingsViewDictionary(hostView)
        await store.testModelConnectivity(providerId: "provider-openrouter", modelId: "anthropic/claude-opus-5")
        let tested = store.providers
            .first(where: { $0.id == "provider-openrouter" })?
            .models.first(where: { $0.modelId == "anthropic/claude-opus-5" })
        XCTAssertEqual(tested?.connectivityState, .failed)
        XCTAssertEqual(tested?.connectivityMessage, "Connect to your computer to test")

        // Provider/model mutations require the host; no local fake provider is inserted.
        let createdId = await store.createProvider(
            template: store.providerTemplates.first,
            customName: "OpenRouter Enterprise",
            apiKey: "sk-or-test-unit-key"
        )
        XCTAssertNil(createdId)
        XCTAssertFalse(store.providers.contains(where: { $0.name == "OpenRouter Enterprise" }))

        let customModel = ModelDescriptor(
            id: "provider-openrouter/anthropic/claude-opus-5-custom",
            modelId: "anthropic/claude-opus-5-custom",
            name: "Claude Opus 5 Custom",
            providerId: "provider-openrouter",
            providerName: "OpenRouter",
            enabled: true,
            builtin: false,
            useRecommendedConfig: false,
            contextWindowTokens: 1_000_000,
            maxOutputTokens: 65_536,
            supportsVision: true,
            supportsPdf: true,
            reasoningLevels: ["low", "medium", "high", "max"],
            reasoningMap: "reasoning.level"
        )
        let upserted = await store.upsertModel(
            providerId: "provider-openrouter",
            originalModelId: nil,
            draft: customModel
        )
        XCTAssertFalse(upserted)
        XCTAssertFalse(store.providers
            .first(where: { $0.id == "provider-openrouter" })?
            .models.contains(where: { $0.modelId == "anthropic/claude-opus-5-custom" }) == true)

        // 2. Subagent Name Validation & Studio CRUD / Overrides (seed-mode local CRUD).
        XCTAssertNotNil(AppStore.validateSubagentName("ab"))
        XCTAssertNotNil(AppStore.validateSubagentName("bad_underscore"))
        XCTAssertNotNil(AppStore.validateSubagentName("Explore"))
        XCTAssertNotNil(AppStore.validateSubagentName("general-purpose"))
        XCTAssertNil(AppStore.validateSubagentName("security-reviewer-v2"))

        let newSubagent = SubagentDefinitionItem(
            id: "user:user:security-reviewer-v2",
            name: "security-reviewer-v2",
            description: "Audits authentication and IPC boundaries.",
            systemPrompt: "Audit every untrusted input boundary.",
            color: .red,
            scope: "user",
            source: "user",
            readOnly: false,
            enabled: true,
            modelOverride: "anthropic/claude-opus-4-7",
            reasoningOverride: "max",
            allowedTools: ["Read", "Grep", "Glob"],
            permissionMode: .plan,
            injectAgentsMd: true,
            runInBackground: true
        )
        let saved = await store.saveSubagent(newSubagent, isNew: true)
        XCTAssertTrue(saved)
        XCTAssertTrue(store.subagents.contains(where: { $0.name == "security-reviewer-v2" }))

        if let explore = store.subagents.first(where: { $0.name == "Explore" && $0.source == "built-in" }) {
            let overridden = await store.setSubagentModelAndEffortOverride(
                id: explore.id,
                modelOverride: "openai/gpt-5.4",
                reasoningOverride: "high"
            )
            XCTAssertTrue(overridden)
            let updatedExplore = store.subagents.first(where: { $0.id == explore.id })
            XCTAssertEqual(updatedExplore?.modelOverride, "openai/gpt-5.4")
            XCTAssertEqual(updatedExplore?.reasoningOverride, "high")
        } else {
            XCTFail("Seed fixtures must include the built-in Explore subagent")
        }
    }
}
