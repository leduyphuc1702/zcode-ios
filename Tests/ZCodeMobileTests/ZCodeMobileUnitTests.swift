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
        XCTAssertEqual(SettingsSectionKind.allCases.count, 19)

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
}
