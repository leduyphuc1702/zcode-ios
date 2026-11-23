import XCTest
@testable import ZCode

final class V4WireFrameAssemblerTests: XCTestCase {
    private func envelope(ordinal: Int, kind: String = "complete", extra: [String: Any] = [:]) -> [String: Any] {
        var env: [String: Any] = [
            "wireVersion": 3, "topic": "conversation/s1", "subscriptionId": "sub1",
            "logicalFrameOrdinal": ordinal, "kind": kind
        ]
        for (k, v) in extra { env[k] = v }
        return env
    }

    func testCompleteFrameDeliveredOnceAndStaleOrdinalIgnored() {
        var assembler = V4WireFrameAssembler()
        let frame: [String: Any] = ["topic": "conversation/s1", "subscriptionId": "sub1", "fromSeq": 0, "toSeq": 1]
        guard case .frame(let out, let delivery) = assembler.ingest(envelope(ordinal: 1, extra: ["frame": frame, "deliveryKind": "initial"])) else {
            return XCTFail("expected frame")
        }
        XCTAssertEqual(ZCodeV4.int(out["toSeq"]), 1)
        XCTAssertEqual(delivery, "initial")
        guard case .ignored = assembler.ingest(envelope(ordinal: 1, extra: ["frame": frame])) else {
            return XCTFail("duplicate ordinal must be ignored")
        }
    }

    func testFragmentsReassembleWithChecksum() throws {
        var assembler = V4WireFrameAssembler()
        let data = try JSONSerialization.data(withJSONObject: ["topic": "conversation/s1", "toSeq": 7])
        let mid = data.count / 2
        let parts = [data.prefix(mid), data.suffix(from: mid)]
        let common: [String: Any] = [
            "fragmentCount": 2, "logicalFrameId": "f1", "logicalBytes": data.count,
            "checksum": ["algorithm": "crc32", "value": ZCodeVQLCodec.crc32Hex(data)]
        ]
        var first = common
        first["fragmentIndex"] = 1
        first["dataBase64"] = Data(parts[1]).base64EncodedString()
        guard case .ignored = assembler.ingest(envelope(ordinal: 1, kind: "fragment", extra: first)) else {
            return XCTFail("partial assembly must wait")
        }
        var second = common
        second["fragmentIndex"] = 0
        second["dataBase64"] = Data(parts[0]).base64EncodedString()
        guard case .frame(let out, _) = assembler.ingest(envelope(ordinal: 1, kind: "fragment", extra: second)) else {
            return XCTFail("expected assembled frame")
        }
        XCTAssertEqual(ZCodeV4.int(out["toSeq"]), 7)
    }

    func testChecksumMismatchFaults() throws {
        var assembler = V4WireFrameAssembler()
        let data = try JSONSerialization.data(withJSONObject: ["toSeq": 1])
        let extra: [String: Any] = [
            "fragmentIndex": 0, "fragmentCount": 1, "dataBase64": data.base64EncodedString(),
            "checksum": ["value": "deadbeef"]
        ]
        guard case .fault(let code) = assembler.ingest(envelope(ordinal: 1, kind: "fragment", extra: extra)) else {
            return XCTFail("expected fault")
        }
        XCTAssertEqual(code, "proto.frameAssemblyChecksumMismatch")
    }

    func testWrongWireVersionIgnored() {
        var assembler = V4WireFrameAssembler()
        guard case .ignored = assembler.ingest(["wireVersion": 2, "topic": "t", "subscriptionId": "s", "logicalFrameOrdinal": 1, "kind": "complete", "frame": [:]]) else {
            return XCTFail("old wire version must be ignored")
        }
    }
}

final class V4ConversationStateTests: XCTestCase {
    private func snapshotFrame(rows: [[String: Any]], seq: Int = 5) -> [String: Any] {
        [
            "toSeq": seq,
            "payload": [
                "kind": "snapshot",
                "snapshot": [
                    "revision": 3, "seq": seq, "logEpoch": "E1", "phase": "idle",
                    "rows": ["window": rows, "totalCount": rows.count, "firstRowId": 1]
                ]
            ]
        ]
    }

    private func deltas(from: Int, to: Int, _ ops: [[String: Any]]) -> [String: Any] {
        ["fromSeq": from, "toSeq": to, "payload": ["kind": "deltas", "deltas": ops]]
    }

    func testDeltasBeforeSnapshotAreGap() {
        var conv = V4ConversationState(sessionId: "s1")
        XCTAssertEqual(conv.apply(frame: deltas(from: 0, to: 1, [])), .gap)
    }

    func testSnapshotThenDeltasStreamText() {
        var conv = V4ConversationState(sessionId: "s1")
        XCTAssertEqual(conv.apply(frame: snapshotFrame(rows: [["rowId": 1, "kind": "userInput", "text": "hi"]])), .applied)
        XCTAssertEqual(conv.revision, 3)
        XCTAssertEqual(conv.base?["seq"] as? Int, 5)

        XCTAssertEqual(conv.apply(frame: deltas(from: 5, to: 6, [
            ["op": "row.appended", "row": ["rowId": 2, "kind": "assistantText", "text": "Hel"]],
            ["op": "state.updated", "patch": ["phase": "running", "revision": 4]]
        ])), .applied)
        XCTAssertEqual(conv.apply(frame: deltas(from: 6, to: 7, [
            ["op": "row.delta", "rowId": 2, "path": "text", "append": "lo"]
        ])), .applied)
        XCTAssertEqual(conv.rows.last?["text"] as? String, "Hello")
        XCTAssertEqual(conv.state["phase"] as? String, "running")
        XCTAssertEqual(conv.revision, 4)
        XCTAssertEqual(conv.totalCount, 2)

        // Replayed frame is ignored, skipped seq is a gap.
        XCTAssertEqual(conv.apply(frame: deltas(from: 6, to: 7, [])), .ignored)
        XCTAssertEqual(conv.apply(frame: deltas(from: 9, to: 10, [])), .gap)
    }

    func testRowRemovedTruncatesTail() {
        var conv = V4ConversationState(sessionId: "s1")
        _ = conv.apply(frame: snapshotFrame(rows: (1...4).map { ["rowId": $0, "kind": "assistantText", "text": "\($0)"] }))
        XCTAssertEqual(conv.apply(frame: deltas(from: 5, to: 6, [["op": "row.removed", "fromRowId": 3]])), .applied)
        XCTAssertEqual(conv.rows.compactMap { ZCodeV4.int($0["rowId"]) }, [1, 2])
        XCTAssertEqual(conv.totalCount, 2)
    }

    func testPrependOlderRowsOnlyForSameEpoch() {
        var conv = V4ConversationState(sessionId: "s1")
        _ = conv.apply(frame: snapshotFrame(rows: [["rowId": 5, "kind": "userInput", "text": "x"]]))
        XCTAssertTrue(conv.hasOlderRows)
        XCTAssertFalse(conv.prepend(olderRows: [["rowId": 4]], atLogEpoch: "OTHER"))
        XCTAssertTrue(conv.prepend(olderRows: [["rowId": 3], ["rowId": 4], ["rowId": 5]], atLogEpoch: "E1"))
        XCTAssertEqual(conv.rows.compactMap { ZCodeV4.int($0["rowId"]) }, [3, 4, 5])
    }
}

final class V4SessionsIndexStateTests: XCTestCase {
    func testSnapshotAndUpserts() {
        var index = V4SessionsIndexState(workspaceKey: "local:/w")
        XCTAssertEqual(index.apply(frame: [
            "toSeq": 2,
            "payload": ["kind": "snapshot", "snapshot": ["logEpoch": "E", "sessions": [["sessionId": "a", "phase": "idle"]]]]
        ]), .applied)
        XCTAssertEqual(index.apply(frame: [
            "fromSeq": 2, "toSeq": 3,
            "payload": ["kind": "deltas", "deltas": [
                ["op": "session.upserted", "session": ["sessionId": "b", "phase": "running"]],
                ["op": "session.removed", "sessionId": "a"]
            ]]
        ]), .applied)
        XCTAssertEqual(Set(index.sessions.keys), ["b"])
        XCTAssertEqual(index.apply(frame: ["fromSeq": 5, "toSeq": 6, "payload": ["kind": "deltas", "deltas": []]]), .gap)
    }
}

@MainActor
final class V4ConversationMapperTests: XCTestCase {
    func testContextBreakdownSortedAndNormalized() throws {
        let usage = V4ConversationMapper.contextUsage([
            "contextWindow": [
                "usedTokens": 50_000, "maxTokens": 200_000,
                "breakdown": [
                    ["source": "systemPrompt", "chars": 100],
                    ["source": "messages", "chars": 300],
                    ["source": "messages", "chars": 100],
                    ["source": "skills", "chars": 0]
                ]
            ]
        ])
        let snapshot = try XCTUnwrap(usage)
        XCTAssertEqual(snapshot.fraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(snapshot.breakdown.map(\.source), ["messages", "systemPrompt"])
        XCTAssertEqual(snapshot.breakdown.first?.fraction ?? 0, 0.8, accuracy: 0.0001)
    }

    func testRowsGroupIntoUserAndAssistantTurns() {
        var targets: [String: [String: Any]] = [:]
        let rows: [[String: Any]] = [
            ["rowId": 1, "turnId": "t1", "kind": "userInput", "origin": "realUser", "text": "Fix it",
             "conversationQuotes": [["text": "quoted line", "path": "a.swift"]]],
            ["rowId": 2, "turnId": "t1", "kind": "turnHeader", "activeMs": 4200, "outputTokens": 99],
            ["rowId": 3, "turnId": "t1", "kind": "reasoning", "text": "thinking"],
            ["rowId": 4, "turnId": "t1", "kind": "assistantText", "text": "Done", "feedback": "like"]
        ]
        let messages = V4ConversationMapper.messages(rows, rowTargets: &targets)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(messages[0].quotes?.first?.text, "quoted line")
        XCTAssertEqual(messages[1].thought, "thinking")
        XCTAssertEqual(messages[1].content, "Done")
        XCTAssertEqual(messages[1].feedback, 1)
        XCTAssertEqual(messages[1].durationMs, 4200)
        XCTAssertEqual(messages[1].tokensOut, 99)
        XCTAssertEqual(ZCodeV4.int(targets[messages[1].id]?["rowId"]), 4)
    }

    // MARK: Edit a sent prompt (`editUserQuery`)

    private func makeConversation(rows: [[String: Any]]) -> V4ConversationState {
        var conv = V4ConversationState(sessionId: "s1")
        _ = conv.apply(frame: [
            "payload": [
                "kind": "snapshot",
                "snapshot": [
                    "seq": 1,
                    "logEpoch": "E",
                    "revision": 3,
                    "rows": ["window": rows, "totalCount": rows.count, "firstRowId": 1]
                ]
            ]
        ])
        return conv
    }

    func testUserRowEditabilityComesOnlyFromHostActions() {
        let conv = makeConversation(rows: [
            ["rowId": 1, "turnId": "t1", "kind": "userInput", "origin": "realUser", "text": "First",
             "entityId": "e1", "actions": ["canEdit": true, "canRewindFiles": true]],
            ["rowId": 2, "turnId": "t1", "kind": "userInput", "origin": "realUser", "text": "Second",
             "entityId": "e2"],
            ["rowId": 3, "turnId": "t1", "kind": "turnHeader", "state": "completedSuccess",
             "fileChanges": ["files": 2, "additions": 10, "deletions": 1, "state": "active"],
             "actions": ["canRewindFiles": true]]
        ])
        let projection = V4ConversationMapper.project(conv) { _ in 0 }
        let userMessages = projection.messages.filter { $0.role == "user" }
        XCTAssertEqual(userMessages.map(\.content), ["First", "Second"])
        XCTAssertEqual(userMessages[0].canEdit, true)
        XCTAssertEqual(userMessages[0].editRewindAvailability, "available")
        // The host did not advertise `canEdit` for the second row: the client must not invent it.
        XCTAssertEqual(userMessages[1].canEdit, false)
        XCTAssertEqual(projection.rowTargets["r1"]?["entityId"] as? String, "e1")
    }

    func testEditRewindAvailabilityMirrorsDesktopReasons() {
        XCTAssertEqual(V4ConversationMapper.rewindAvailability(nil), "noFiles")
        XCTAssertEqual(
            V4ConversationMapper.rewindAvailability(["state": "completedSuccess", "fileChanges": ["files": 0]]),
            "noFiles"
        )
        XCTAssertEqual(
            V4ConversationMapper.rewindAvailability([
                "state": "completedSuccess", "fileChanges": ["files": 1, "state": "reverted"]
            ]),
            "reverted"
        )
        XCTAssertEqual(
            V4ConversationMapper.rewindAvailability([
                "state": "running", "fileChanges": ["files": 1, "state": "active"],
                "actions": ["canRewindFiles": true]
            ]),
            "running"
        )
        XCTAssertEqual(
            V4ConversationMapper.rewindAvailability([
                "state": "completedSuccess", "fileChanges": ["files": 1, "state": "active"]
            ]),
            "unavailable"
        )
        XCTAssertEqual(
            V4ConversationMapper.rewindAvailability([
                "state": "completedSuccess", "fileChanges": ["files": 1, "state": "active"],
                "actions": ["canRewindFiles": true]
            ]),
            "available"
        )
    }

    func testUserAttachmentRefsArePreservedForEditReplay() {
        let rowAttachments: [[String: Any]] = [
            ["ref": "upl-1", "fileName": "shot.png", "mime": "image/png", "bytes": 42]
        ]
        let conv = makeConversation(rows: [
            ["rowId": 7, "turnId": "t1", "kind": "userInput", "origin": "realUser", "text": "Look",
             "entityId": "e7", "actions": ["canEdit": true], "attachments": rowAttachments]
        ])
        let projection = V4ConversationMapper.project(conv) { _ in 0 }
        XCTAssertEqual(projection.userAttachmentRefs["r7"]?.count, 1)
        XCTAssertEqual(projection.userAttachmentRefs["r7"]?.first?["ref"] as? String, "upl-1")
        XCTAssertEqual(projection.userAttachmentRefs["r7"]?.first?["mime"] as? String, "image/png")
    }

    func testEditUserQueryPayloadMatchesDesktopHelper() throws {
        let payload = AppStore.editUserQueryPayload(
            target: ["rowId": 7, "entityId": "e7"],
            newText: "Edited prompt",
            workspaceMode: "rewind",
            quotes: [ConversationQuote(text: "quoted", path: "a.swift", senderName: "user", messageId: "r3")],
            attachmentRefs: [["ref": "upl-1", "fileName": "shot.png", "mime": "image/png", "bytes": 42]],
            selection: LiveModelSelection(providerId: "zai", modelId: "glm-5.1", reasoningLevel: "high")
        )
        XCTAssertEqual(payload["workspaceMode"] as? String, "rewind")
        XCTAssertEqual(payload["newText"] as? String, "Edited prompt")
        let target = try XCTUnwrap(payload["target"] as? [String: Any])
        XCTAssertEqual(target["rowId"] as? Int, 7)
        XCTAssertEqual(target["entityId"] as? String, "e7")
        let attachments = try XCTUnwrap(payload["attachments"] as? [[String: Any]])
        XCTAssertEqual(attachments.first?["ref"] as? String, "upl-1")
        let quotes = try XCTUnwrap(payload["conversationQuotes"] as? [[String: Any]])
        XCTAssertEqual(quotes.first?["text"] as? String, "quoted")
        XCTAssertEqual(quotes.first?["path"] as? String, "a.swift")
        let selection = try XCTUnwrap(payload["modelSelection"] as? [String: Any])
        XCTAssertEqual(selection["providerId"] as? String, "zai")
        XCTAssertEqual((selection["options"] as? [String: Any])?["reasoningLevel"] as? String, "high")
    }

    func testEditUserQueryResultClassifiesBlockedDisposition() {
        var outcome = AppStore.V4EditUserQueryResult()
        outcome.disposition = .blocked
        outcome.reasonCode = "workspace.rewindConflict"
        XCTAssertTrue(outcome.isBlocked)
        outcome.disposition = .rewind
        XCTAssertFalse(outcome.isBlocked)
        outcome.disposition = nil
        XCTAssertFalse(outcome.isBlocked)
    }
}

@MainActor
final class V4HandshakeRecoveryTests: XCTestCase {
    func testHandshakeRequiredIsDetectedFromAckAndTransportErrors() {
        XCTAssertTrue(AppStore.isHandshakeRequired(V4CommandError(status: "rejected", reasonCode: "fault.connection.handshakeRequired", message: nil)))
        XCTAssertTrue(AppStore.isHandshakeRequired(NSError(domain: "ZCodeRPC", code: 1, userInfo: [NSLocalizedDescriptionKey: "fault.connection.handshakeRequired"])))
        XCTAssertFalse(AppStore.isHandshakeRequired(V4CommandError(status: "stale", reasonCode: "revision.stale", message: nil)))
    }
}

final class SelectableMessageTextTests: XCTestCase {
    func testInlineMarkdownKeepsPlainTextForPartialSelection() {
        let rendered = SelectableMessageText.render(
            markdown: "Run **swift build** then `make test` and [docs](https://example.com)",
            font: .systemFont(ofSize: 15), color: .white, lineSpacing: 4, codeBackground: .darkGray
        )
        XCTAssertEqual(rendered.string, "Run swift build then make test and docs")
        let codeRange = (rendered.string as NSString).range(of: "make test")
        let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? UIFont
        XCTAssertTrue(codeFont?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
        let boldFont = rendered.attribute(.font, at: (rendered.string as NSString).range(of: "swift").location, effectiveRange: nil) as? UIFont
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertNotNil(rendered.attribute(.link, at: (rendered.string as NSString).range(of: "docs").location, effectiveRange: nil))
    }
}

@MainActor
final class TurnFooterTests: XCTestCase {
    func testOneFooterPerTurnOnLastSegmentWhenLatestTextComplete() {
        var targets: [String: [String: Any]] = [:]
        let rows: [[String: Any]] = [
            ["rowId": 1, "turnId": "t1", "kind": "userInput", "origin": "realUser", "text": "Go"],
            ["rowId": 2, "turnId": "t1", "kind": "assistantText", "text": "Looking", "state": "complete", "entityId": "e2"],
            ["rowId": 3, "turnId": "t1", "kind": "toolCall", "toolName": "Read", "toolCallId": "c1", "status": "success"],
            ["rowId": 4, "turnId": "t1", "kind": "assistantText", "text": "Done", "state": "complete", "entityId": "e4",
             "feedback": "like", "actions": ["canFork": true]],
            ["rowId": 5, "turnId": "t1", "kind": "toolCall", "toolName": "Bash", "toolCallId": "c2", "status": "success"],
            ["rowId": 6, "turnId": "t2", "kind": "userInput", "origin": "realUser", "text": "More"],
            ["rowId": 7, "turnId": "t2", "kind": "assistantText", "text": "Work", "state": "streaming", "entityId": "e7"]
        ]
        let messages = V4ConversationMapper.messages(rows, rowTargets: &targets)
        let footers = messages.compactMap(\.turnActions)
        XCTAssertEqual(footers.count, 1, "streaming turn has no footer; finished turn has exactly one")
        XCTAssertEqual(messages.last(where: { $0.role == "assistant" && $0.id != "r7" })?.turnActions, footers.first)
        XCTAssertEqual(footers[0].copyText, "Looking\n\nDone")
        XCTAssertEqual(footers[0].targetMessageId, "r3")
        XCTAssertEqual(ZCodeV4.int(targets["r3"]?["rowId"]), 4)
        XCTAssertTrue(footers[0].canFork)
        XCTAssertEqual(footers[0].feedback, 1)
        let bars = AppStore.turnActionBars(messages, fromHost: true, running: true)
        XCTAssertEqual(bars.count, 1)
    }

    func testLegacyTranscriptGetsFooterOnlyOnFinishedTurnsWithText() {
        func msg(_ id: String, _ role: String, _ content: String) -> ChatTurnMessage {
            ChatTurnMessage(id: id, role: role, content: content, thought: nil, thoughtDurationMs: 0, tools: [], attachments: [],
                            timestamp: Date(), modelLabel: nil, tokensIn: 0, tokensOut: 0, durationMs: 0, feedback: 0)
        }
        let messages = [msg("u1", "user", "a"), msg("a1", "assistant", "x"), msg("a2", "assistant", ""),
                        msg("u2", "user", "b"), msg("a3", "assistant", "y")]
        let running = AppStore.turnActionBars(messages, fromHost: false, running: true)
        XCTAssertEqual(Array(running.keys), ["a2"])
        XCTAssertEqual(running["a2"]?.targetMessageId, "a1")
        XCTAssertEqual(Set(AppStore.turnActionBars(messages, fromHost: false, running: false).keys), ["a2", "a3"])
    }
}

@MainActor
final class EditAttachmentRefsTests: XCTestCase {
    private let refs: [[String: Any]] = [
        ["ref": "a", "fileName": "one.png", "mime": "image/png"],
        ["ref": "b", "fileName": "two.png", "mime": "image/png"],
        ["ref": "c", "fileName": "notes.txt", "mime": "text/plain"]
    ]

    func testNilIndicesKeepEveryAttachment() {
        XCTAssertEqual(AppStore.keptAttachmentRefs(refs, indices: nil).compactMap { $0["ref"] as? String }, ["a", "b", "c"])
    }

    func testRemovedAttachmentsAreDroppedAndOrderKept() {
        XCTAssertEqual(AppStore.keptAttachmentRefs(refs, indices: [0, 2, 7]).compactMap { $0["ref"] as? String }, ["a", "c"])
        XCTAssertTrue(AppStore.keptAttachmentRefs(refs, indices: []).isEmpty)
    }

    func testEditPayloadCarriesKeptAttachments() {
        let payload = AppStore.editUserQueryPayload(
            target: ["rowId": 4, "entityId": "e4"],
            newText: "fixed",
            workspaceMode: "preserve",
            quotes: [],
            attachmentRefs: AppStore.keptAttachmentRefs(refs, indices: [1]),
            selection: nil
        )
        XCTAssertEqual((payload["attachments"] as? [[String: Any]])?.compactMap { $0["ref"] as? String }, ["b"])
    }
}
