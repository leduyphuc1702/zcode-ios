import XCTest
@testable import ZCode

@MainActor
final class LiveSyncTests: XCTestCase {

    private func makeStore(withTask taskId: String = "t1") -> AppStore {
        let store = AppStore(seedDemoWorkspace: false)
        store.sessions = [
            AgentTaskSession(
                id: taskId, traceId: "trace", projectId: "p1", workspacePath: "/w/a", title: "Old",
                status: .idle, mode: .build, modelId: "", effort: .high, pinned: false, archived: false,
                unread: false, offPeakEnabled: false, createdAt: Date(), updatedAt: Date(),
                contextUsedPercent: 0, totalTokensIn: 0, totalTokensOut: 0, cachedTokens: 0, costUSD: 0,
                messages: [], todos: [], pendingPermission: nil, pendingQuestion: nil, pendingPlan: nil,
                queuedPrompts: [], checkpoints: []
            )
        ]
        store.activeSessionId = taskId
        return store
    }

    func testModelPickerValueRoundTrip() {
        let sel = LiveModelSelection(pickerValue: "zai-coding-plan/glm-5.1$high")
        XCTAssertEqual(sel, LiveModelSelection(providerId: "zai-coding-plan", modelId: "glm-5.1", reasoningLevel: "high"))
        XCTAssertEqual(LiveModelSelection(pickerValue: "openrouter/anthropic/claude-x")?.modelId, "anthropic/claude-x")
        XCTAssertNil(LiveModelSelection(pickerValue: "noprovider"))
        let json = sel!.jsonObject
        XCTAssertEqual(json["providerId"] as? String, "zai-coding-plan")
        XCTAssertEqual((json["options"] as? [String: Any])?["reasoningLevel"] as? String, "high")
    }

    func testOfficialModeMapping() {
        XCTAssertEqual(AgentExecutionMode.officialCases.map(\.wireValue), ["build", "edit", "plan", "yolo"])
        XCTAssertEqual(AgentExecutionMode.officialCases.map(\.label), ["Ask before changes", "Edit automatically", "Plan mode", "Full access"])
        XCTAssertEqual(AgentExecutionMode(wire: "default"), .build)
        XCTAssertEqual(AgentExecutionMode(wire: "bypassPermissions"), .yolo)
        XCTAssertEqual(AgentExecutionMode(wire: "edit"), .autoEdit)
    }

    func testModelViewParsing() {
        let store = makeStore()
        store.applyModelView([
            "revision": 3,
            "providers": [
                [
                    "providerId": "zai", "providerName": "Z.ai",
                    "config": ["modelOrder": ["glm-5.1", "glm-4.7"]],
                    "models": [
                        ["modelId": "glm-4.7", "config": ["enabled": true, "properties": ["contextWindow": 200000]]],
                        ["modelId": "hidden", "config": ["enabled": false]],
                        ["modelId": "glm-5.1", "config": ["enabled": true, "optionSpecs": ["reasoningLevel": ["values": ["low", "high", "max"]]]]]
                    ]
                ]
            ],
            "preferredSelection": ["providerId": "zai", "modelId": "glm-5.1", "options": ["reasoningLevel": "max"]]
        ])
        XCTAssertEqual(store.liveModelGroups.first?.models.map(\.modelId), ["glm-5.1", "glm-4.7"])
        XCTAssertEqual(store.liveModel(providerId: "zai", modelId: "glm-5.1")?.defaultReasoningLevel, "max")
        XCTAssertEqual(store.preferredModelSelection?.reasoningLevel, "max")
        XCTAssertEqual(store.modelSelection(for: store.sessions[0])?.modelId, "glm-5.1")
        XCTAssertEqual(store.reasoningLevels(for: store.sessions[0]), ["low", "high", "max"])
    }

    func testSnapshotParsingMapsMetaMessagesAndRuntime() {
        let store = makeStore()
        store.applyTaskSnapshot([
            "meta": [
                "taskId": "t1", "title": "Fix relay", "status": "running", "mode": "plan",
                "model": "zai/glm-5.1$high", "traceId": "abc"
            ],
            "messages": [
                ["id": "u1", "role": "user", "content": "hello", "timestamp": 1_790_000_000_000],
                [
                    "id": "a1", "role": "assistant", "content": "",
                    "parts": [["type": "thought", "content": "thinking"], ["type": "content", "content": "Done."], ["type": "tool-call", "toolIndex": 0]],
                    "tools": [["toolName": "Edit", "kind": "edit", "status": "completed", "title": "Edit a.swift",
                               "input": ["file_path": "a.swift", "old_string": "x", "new_string": "y\nz"]]],
                    "model": "zai/glm-5.1$high"
                ],
                ["id": "s1", "role": "assistant", "content": "synthetic", "syntheticTimeline": true]
            ],
            "runtime": [
                "pendingElicitations": [[
                    "type": "elicitation_request", "requestId": "r1", "message": "Approve?",
                    "options": [["value": "approve", "label": "Approve"]],
                    "schema": ["interaction": "plan_approval", "toolName": "ExitPlanMode", "plan": "Intro\n1. Step one\n2. Step two"]
                ]],
                "contextUsage": ["used": 50_000, "size": 200_000],
                "plan": [["id": "s1", "title": "Write code", "status": "in_progress"]]
            ]
        ], sessionIndex: 0)

        let s = store.sessions[0]
        XCTAssertEqual(s.title, "Fix relay")
        XCTAssertEqual(s.mode, .plan)
        XCTAssertEqual(s.modelProviderId, "zai")
        XCTAssertEqual(s.modelId, "glm-5.1")
        XCTAssertEqual(s.reasoningLevel, "high")
        XCTAssertEqual(s.messages.map(\.id), ["u1", "a1"])
        XCTAssertEqual(s.messages[1].content, "Done.")
        XCTAssertEqual(s.messages[1].thought, "thinking")
        XCTAssertEqual(s.messages[1].tools.first?.kind, .editFile)
        XCTAssertEqual(s.messages[1].tools.first?.addedLines, 2)
        XCTAssertEqual(s.messages[1].modelLabel, "glm-5.1")
        XCTAssertEqual(s.pendingPlan?.id, "r1")
        XCTAssertEqual(s.pendingPlan?.steps, ["Step one", "Step two"])
        XCTAssertEqual(s.status, .waitingPlan)
        XCTAssertEqual(s.contextUsedPercent, 25)
        XCTAssertEqual(s.todos.first?.status, "in_progress")
    }

    func testStreamReducerAppliesChunksToolsAndPermission() {
        let store = makeStore()
        store.applyTaskStreamEvent(["type": "task_run_started", "taskId": "t1"], taskId: "t1")
        store.applyTaskStreamEvent(["type": "agent_thought_chunk", "content": "Plan "], taskId: "t1")
        store.applyTaskStreamEvent(["type": "agent_message_chunk", "content": ["type": "text", "text": "Hel"], "messageId": "m1"], taskId: "t1")
        store.applyTaskStreamEvent([
            "type": "task_stream_mirror_batch",
            "ops": [["kind": "stream_event", "event": ["type": "agent_message_chunk", "content": "lo"]]],
            "terminal": false
        ], taskId: "t1")
        store.applyTaskStreamEvent(["type": "agent_message_chunk", "content": "ignored", "parentToolUseId": "sub"], taskId: "t1")
        store.applyTaskStreamEvent(["type": "tool_call", "toolId": "tc1", "toolName": "Bash", "kind": "execute", "input": ["command": "ls"]], taskId: "t1")
        store.applyTaskStreamEvent(["type": "tool_call_update", "toolId": "tc1", "status": "completed", "content": "a\nb"], taskId: "t1")
        store.applyTaskStreamEvent(["type": "usage_update", "used": 10, "size": 100], taskId: "t1")
        store.applyTaskStreamEvent([
            "type": "permission_request", "requestId": "p1", "description": "Run rm", "kind": "Bash", "title": "Bash",
            "options": [["optionId": "o1", "kind": "allow_once", "name": "Allow"], ["optionId": "o2", "kind": "reject_once", "name": "Deny"]],
            "raw": ["input": ["command": "rm -rf build"]]
        ], taskId: "t1")

        let s = store.sessions[0]
        XCTAssertEqual(s.messages.count, 1)
        XCTAssertEqual(s.messages[0].thought, "Plan ")
        XCTAssertEqual(s.messages[0].content, "Hello")
        XCTAssertEqual(s.messages[0].tools.first?.kind, .bash)
        XCTAssertEqual(s.messages[0].tools.first?.status, .completed)
        XCTAssertEqual(s.messages[0].tools.first?.output, "a\nb")
        XCTAssertEqual(s.contextUsedPercent, 10)
        XCTAssertEqual(s.pendingPermission?.commandOrPath, "rm -rf build")
        XCTAssertEqual(s.status, .waitingApproval)

        store.applyTaskStreamEvent(["type": "permission_response", "requestId": "p1"], taskId: "t1")
        XCTAssertNil(store.sessions[0].pendingPermission)
        XCTAssertEqual(store.sessions[0].status, .running)
        store.applyTaskStreamEvent(["type": "agent_message_chunk", "content": "x", "taskId": "other"], taskId: "t1")
        XCTAssertEqual(store.sessions[0].messages[0].content, "Hello")
    }

    func testWorkspaceEventUpsertsAndDeletes() {
        let store = makeStore()
        store.handleWorkspaceEvent([
            "type": "workspace_task_list_changed", "workspacePath": "/w/a", "taskId": "t2", "reason": "task_created",
            "taskMeta": ["taskId": "t2", "title": "New one", "workspacePath": "/w/a", "status": "running",
                         "mode": "yolo", "model": "zai/glm-5.1", "createdAt": 1, "updatedAt": 2]
        ], projectId: "p1", workspacePath: "/w/a", workspaceIdentity: nil)
        XCTAssertEqual(store.sessions.first?.id, "t2")
        XCTAssertEqual(store.sessions.first?.mode, .yolo)
        XCTAssertEqual(store.sessions.first?.status, .running)

        store.handleWorkspaceEvent([
            "type": "workspace_task_list_changed", "taskId": "t1", "reason": "task_status_changed",
            "taskMeta": ["taskId": "t1", "title": "Renamed", "workspacePath": "/w/a", "status": "completed", "updatedAt": 3]
        ], projectId: "p1", workspacePath: "/w/a", workspaceIdentity: nil)
        XCTAssertEqual(store.sessions.first(where: { $0.id == "t1" })?.title, "Renamed")

        store.handleWorkspaceEvent(["taskId": "t2", "reason": "task_deleted"], projectId: "p1", workspacePath: "/w/a", workspaceIdentity: nil)
        XCTAssertFalse(store.sessions.contains(where: { $0.id == "t2" }))
    }

    func testTaskSummaryParsesModeModelAndPendingInteraction() {
        let summary = ZCodeRPCClient.parseTaskSummary([
            "taskId": "t9", "title": "x", "workspacePath": "/w", "status": "running", "mode": "edit",
            "model": "zai/glm-5.1$max", "thoughtLevel": "max", "updatedAt": 1_790_000_000_000,
            "pendingInteraction": ["interactionId": "i", "kind": "userInput"]
        ], fallbackWorkspacePath: "/w")
        XCTAssertEqual(summary?.mode, "edit")
        XCTAssertEqual(summary?.thoughtLevel, "max")
        let session = AppStore.makeAgentSession(from: summary!, projectId: "p")
        XCTAssertEqual(session.status, .waitingQuestion)
        XCTAssertEqual(session.mode, .autoEdit)
        XCTAssertEqual(session.modelProviderId, "zai")
        XCTAssertEqual(session.reasoningLevel, "max")
    }
}
