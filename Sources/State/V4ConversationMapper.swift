import Foundation

/// Everything the UI needs from one V4 conversation snapshot, projected onto the app models.
struct V4SessionProjection {
    var messages: [ChatTurnMessage] = []
    var status: TaskSessionStatus = .idle
    var title: String?
    var mode: AgentExecutionMode?
    var model: LiveModelSelection?
    var contextUsage: ContextUsageSnapshot?
    var todos: [TodoChecklistItem] = []
    var queue: [QueuedPromptItem] = []
    var permission: PermissionPrompt?
    /// V4 permission options (`optionId`, `kind`) keyed by interaction id.
    var permissionOptions: [String: [[String: Any]]] = [:]
    var question: QuestionPrompt?
    var plan: PlanReviewPrompt?
    /// Legacy-shaped elicitation request (`requestId`, `questions`, `schema`, …) for the shared answer builder.
    var elicitation: [String: Any]?
    var statusNotice: String?
    /// Row targets (`rowId`, `entityId`) for row-scoped commands, keyed by message id.
    var rowTargets: [String: [String: Any]] = [:]
    /// Raw `userInput.attachments` refs keyed by message id; replayed verbatim by `editUserQuery`.
    var userAttachmentRefs: [String: [[String: Any]]] = [:]
    var foregroundExecutionId: String?
    /// Running subagents (`snapshot.subagents.running` merged with `backgroundWorks`).
    var subagentRuns: [SubagentSessionRun] = []
}

@MainActor
enum V4ConversationMapper {
    static let breakdownLabels: [String: String] = [
        "messages": "Messages",
        "system_prompt": "System prompt",
        "meta_user_context": "Meta context",
        "skills": "Skills",
        "tool_prompt": "Tool prompt",
        "system_tool_schemas": "System tools",
        "mcp_tool_schemas": "MCP tools"
    ]
    private static let breakdownOrder = ["messages", "system_prompt", "meta_user_context", "skills", "tool_prompt", "system_tool_schemas", "mcp_tool_schemas"]

    static func project(_ conv: V4ConversationState, elicitationIndex: (String) -> Int) -> V4SessionProjection {
        var out = V4SessionProjection()
        let state = conv.state

        if let meta = state["meta"] as? [String: Any],
           let title = (meta["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            out.title = title
        }
        if let config = state["config"] as? [String: Any] {
            if let mode = config["mode"] as? String { out.mode = AgentExecutionMode(wire: mode) }
            out.model = LiveModelSelection(json: config["modelSelection"] as? [String: Any])
            if out.model == nil, let provider = config["provider"] as? String, let model = config["model"] as? String,
               !provider.isEmpty, !model.isEmpty {
                out.model = LiveModelSelection(providerId: provider, modelId: model, reasoningLevel: config["thought"] as? String)
            } else if out.model?.reasoningLevel == nil, let thought = config["thought"] as? String {
                out.model?.reasoningLevel = thought
            }
        }
        out.contextUsage = contextUsage(state["usage"] as? [String: Any])
        out.todos = todos(state["plan"] as? [String: Any])
        out.queue = queue(state["queue"] as? [String: Any])

        let control = (state["control"] as? [String: Any]) ?? [:]
        let phase = (control["phase"] as? String) ?? "draft"
        out.foregroundExecutionId = ((control["activeWorks"] as? [[String: Any]]) ?? [])
            .compactMap { $0["foregroundExecutionId"] as? String }.first
        out.status = {
            switch phase {
            case "running", "prewarming": return .running
            case "error": return .error
            case "completedSuccess": return .completed
            default: return .idle
            }
        }()
        if let retry = control["apiRetry"] as? [String: Any],
           let attempt = ZCodeV4.int(retry["attempt"]), let maxAttempts = ZCodeV4.int(retry["maxAttempts"]) {
            out.statusNotice = "Retrying request (\(attempt)/\(maxAttempts))…"
        } else if phase == "error", let error = control["lastError"] as? [String: Any] {
            out.statusNotice = (error["message"] as? String) ?? (error["code"] as? String)
        }

        applyInteractions((state["pendingInteractions"] as? [[String: Any]]) ?? [], into: &out, elicitationIndex: elicitationIndex)
        out.messages = messages(conv.rows, rowTargets: &out.rowTargets)
        for row in conv.rows where (row["kind"] as? String) == "userInput" {
            guard let rowId = ZCodeV4.int(row["rowId"]) else { continue }
            out.userAttachmentRefs["r\(rowId)"] = (row["attachments"] as? [[String: Any]]) ?? []
        }
        out.subagentRuns = runningSubagents(state)
        return out
    }

    /// Status-panel merge (`O2t`): running subagents keyed by `childSessionId`, stop control from background works.
    static func runningSubagents(_ state: [String: Any]) -> [SubagentSessionRun] {
        let works = ((state["backgroundWorks"] as? [[String: Any]]) ?? [])
        var workByChild: [String: [String: Any]] = [:]
        for work in works {
            if let child = work["childSessionId"] as? String { workByChild[child] = work }
        }
        var seen = Set<String>()
        var runs: [SubagentSessionRun] = []
        let running = ((state["subagents"] as? [String: Any])?["running"] as? [[String: Any]]) ?? []
        for item in running {
            guard let child = item["childSessionId"] as? String, seen.insert(child).inserted else { continue }
            let work = workByChild[child]
            runs.append(subagentRun(
                childSessionId: child,
                title: (item["title"] as? String) ?? (work?["title"] as? String) ?? "",
                type: (item["subagentType"] as? String) ?? "subagent",
                status: (item["status"] as? String) ?? "running",
                startedAt: ZCodeV4.double(item["startedAt"]) ?? ZCodeV4.double(work?["startedAt"]),
                work: work
            ))
        }
        for work in works where (work["kind"] as? String) == "subagent" && (work["status"] as? String) == "running" {
            guard let child = work["childSessionId"] as? String, seen.insert(child).inserted else { continue }
            runs.append(subagentRun(
                childSessionId: child,
                title: (work["title"] as? String) ?? "",
                type: "subagent",
                status: "running",
                startedAt: ZCodeV4.double(work["startedAt"]),
                work: work
            ))
        }
        return runs
    }

    private static func subagentRun(childSessionId: String, title: String, type: String, status: String,
                                    startedAt: Double?, work: [String: Any]?) -> SubagentSessionRun {
        let started = startedAt.map { Date(timeIntervalSince1970: $0 > 9_999_999_999 ? $0 / 1000 : $0) }
        var run = SubagentSessionRun(
            id: childSessionId,
            title: title.isEmpty ? type : title,
            agentType: type,
            isRunning: true,
            elapsedText: "",
            transcriptMarkdown: "",
            timestamp: started ?? Date()
        )
        run.startedAt = started
        run.status = status
        if let work, (work["cancellable"] as? Bool) != false { run.controlWorkId = work["workId"] as? String }
        return run
    }

    // MARK: Usage / plan / queue

    static func contextUsage(_ usage: [String: Any]?) -> ContextUsageSnapshot? {
        guard let usage else { return nil }
        let window = usage["contextWindow"] as? [String: Any]
        let cumulative = (usage["cumulative"] as? [String: Any]) ?? [:]
        guard let window, let maxTokens = ZCodeV4.int(window["maxTokens"]), maxTokens > 0 else { return nil }
        var chars: [String: Int] = [:]
        for item in (window["breakdown"] as? [[String: Any]]) ?? [] {
            guard let source = item["source"] as? String, let count = ZCodeV4.int(item["chars"]), count > 0 else { continue }
            chars[source, default: 0] += count
        }
        let total = chars.values.reduce(0, +)
        let slices: [ContextUsageSnapshot.Slice] = total <= 0 ? [] : chars
            .sorted { lhs, rhs in
                lhs.value != rhs.value
                    ? lhs.value > rhs.value
                    : (breakdownOrder.firstIndex(of: lhs.key) ?? 99) < (breakdownOrder.firstIndex(of: rhs.key) ?? 99)
            }
            .map { .init(source: $0.key, label: breakdownLabels[$0.key] ?? $0.key, fraction: Double($0.value) / Double(total)) }
        return ContextUsageSnapshot(
            usedTokens: ZCodeV4.int(window["usedTokens"]) ?? 0,
            maxTokens: maxTokens,
            autoCompactThresholdTokens: ZCodeV4.int(window["autoCompactThresholdTokens"]),
            breakdown: slices,
            cacheHitRate: ZCodeV4.double((window["cache"] as? [String: Any])?["hitRate"]),
            cumulativeInputTokens: ZCodeV4.int(cumulative["inputTokens"]) ?? 0,
            cumulativeOutputTokens: ZCodeV4.int(cumulative["outputTokens"]) ?? 0,
            cumulativeCacheReadTokens: ZCodeV4.int(cumulative["cacheReadTokens"]) ?? 0,
            cumulativeCacheWriteTokens: ZCodeV4.int(cumulative["cacheWriteTokens"]) ?? 0
        )
    }

    static func todos(_ plan: [String: Any]?) -> [TodoChecklistItem] {
        ((plan?["items"] as? [[String: Any]]) ?? []).enumerated().map { i, item in
            let status: String = {
                switch item["status"] as? String {
                case "completed": return "completed"
                case "inProgress", "in_progress": return "in_progress"
                default: return "pending"
                }
            }()
            return TodoChecklistItem(
                id: (item["id"] as? String) ?? "plan-\(i)",
                content: (item["content"] as? String) ?? "",
                status: status,
                priority: "medium"
            )
        }
    }

    static func queue(_ queue: [String: Any]?) -> [QueuedPromptItem] {
        ((queue?["items"] as? [[String: Any]]) ?? []).compactMap { item in
            guard let id = item["queueItemId"] as? String else { return nil }
            let kind = (item["kind"] as? String) ?? "sendText"
            let text = (item["text"] as? String) ?? (kind == "compact" ? "/compact" : "")
            let created = ZCodeV4.double(item["createdAt"]) ?? ZCodeV4.double(item["enqueuedAt"])
            return QueuedPromptItem(
                id: id,
                content: text,
                attachments: attachments(item["attachments"]),
                createdAt: created.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            )
        }
    }

    // MARK: Pending interactions

    private static func applyInteractions(_ list: [[String: Any]], into out: inout V4SessionProjection, elicitationIndex: (String) -> Int) {
        for interaction in list {
            guard let id = interaction["interactionId"] as? String,
                  let payload = interaction["payload"] as? [String: Any] else { continue }
            let kind = (payload["kind"] as? String) ?? (interaction["kind"] as? String) ?? ""
            if kind == "permission", out.permission == nil {
                var options = (payload["options"] as? [[String: Any]]) ?? []
                if let full = payload["fullAccessOption"] as? [String: Any] { options.append(full) }
                out.permissionOptions[id] = options
                out.permission = permissionPrompt(id: id, payload: payload)
                out.status = .waitingApproval
            } else if kind == "userInput", out.question == nil, out.plan == nil {
                let request = legacyElicitation(id: id, payload: payload)
                out.elicitation = request
                if isPlanApproval(payload) {
                    let planText = planText(payload)
                    let parsed = AppStore.splitPlan(planText)
                    out.plan = PlanReviewPrompt(id: id, title: "Implementation plan", summary: parsed.summary, steps: parsed.steps, verification: "")
                    out.status = .waitingPlan
                } else {
                    out.question = AppStore.questionPrompt(from: request, index: elicitationIndex(id))
                    out.status = .waitingQuestion
                }
            }
        }
        if out.permission != nil { out.status = .waitingApproval }
    }

    static func isPlanApproval(_ payload: [String: Any]) -> Bool {
        let schema = payload["schema"] as? [String: Any]
        if (schema?["interaction"] as? String) == "plan_approval" { return true }
        return ((payload["toolName"] as? String) ?? "").lowercased() == "exitplanmode"
    }

    private static func planText(_ payload: [String: Any]) -> String {
        let schema = payload["schema"] as? [String: Any]
        let input = payload["input"] as? [String: Any]
        let text = (input?["plan"] as? String) ?? (schema?["plan"] as? String) ?? (payload["prompt"] as? String) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func legacyElicitation(id: String, payload: [String: Any]) -> [String: Any] {
        var request: [String: Any] = [
            "requestId": id,
            "message": (payload["prompt"] as? String) ?? "Input required",
            "header": ""
        ]
        if let schema = payload["schema"] { request["schema"] = schema }
        if let questions = payload["questions"] as? [[String: Any]], !questions.isEmpty {
            request["questions"] = questions
        } else {
            request["v4Generic"] = true
            request["options"] = ((payload["options"] as? [[String: Any]]) ?? []).map { opt in
                ["value": (opt["optionId"] as? String) ?? "", "label": (opt["label"] as? String) ?? ""]
            }
        }
        return request
    }

    private static func permissionPrompt(id: String, payload: [String: Any]) -> PermissionPrompt {
        let toolName = (payload["toolName"] as? String) ?? "Tool"
        let summary = (payload["summary"] as? String) ?? toolName
        let detail = payload["detail"] as? [String: Any]
        let input = (detail?["input"] as? [String: Any]) ?? detail ?? [:]
        let target = (input["command"] as? String)
            ?? (input["file_path"] as? String)
            ?? (input["path"] as? String)
            ?? (input["url"] as? String)
            ?? (input["pattern"] as? String)
            ?? ""
        let preview: String = {
            if let command = input["command"] as? String { return "$ \(command)" }
            if let oldText = input["old_string"] as? String, let newText = input["new_string"] as? String {
                return AppStore.miniDiff(old: oldText, new: newText)
            }
            if let content = input["content"] as? String { return String(content.prefix(1200)) }
            if let text = payload["detail"] as? String { return String(text.prefix(1200)) }
            return target.isEmpty ? summary : target
        }()
        let lower = toolName.lowercased()
        return PermissionPrompt(
            id: id,
            toolName: toolName,
            summary: summary,
            commandOrPath: target.isEmpty ? summary : target,
            previewDiffOrCommand: preview,
            riskLevel: lower.contains("bash") || lower.contains("exec") ? "MEDIUM" : "LOW"
        )
    }

    // MARK: Rows → transcript

    private enum SegmentRank: Int { case reasoning = 0, tool = 1, text = 2 }

    static func messages(_ rows: [[String: Any]], rowTargets: inout [String: [String: Any]]) -> [ChatTurnMessage] {
        var result: [ChatTurnMessage] = []
        var current: ChatTurnMessage?
        var currentRank = -1
        var currentTurn: String?
        var turnHeaders: [String: [String: Any]] = [:]
        for row in rows where (row["kind"] as? String) == "turnHeader" {
            if let turn = row["turnId"] as? String { turnHeaders[turn] = row }
        }
        let pairing = pairSubagents(rows)
        var lastSegmentByTurn: [String: String] = [:]
        var latestTextByTurn: [String: (messageId: String, row: [String: Any])] = [:]
        var turnTexts: [String: [String]] = [:]
        var turnOrder: [String] = []

        func flush() {
            if let msg = current { result.append(msg) }
            current = nil
            currentRank = -1
        }

        for row in rows {
            guard let kind = row["kind"] as? String, let rowId = ZCodeV4.int(row["rowId"]) else { continue }
            let turnId = row["turnId"] as? String
            if turnId != currentTurn {
                flush()
                currentTurn = turnId
            }
            let timestamp = date(row["createdAt"])
            let target: [String: Any] = {
                var t: [String: Any] = ["rowId": rowId]
                if let entity = row["entityId"] as? String { t["entityId"] = entity }
                return t
            }()

            switch kind {
            case "userInput":
                let origin = (row["origin"] as? String) ?? "realUser"
                guard ["realUser", "mailbox", "workflowLaunch"].contains(origin) else { continue }
                flush()
                let id = "r\(rowId)"
                rowTargets[id] = target
                var msg = blank(id: id, role: "user", timestamp: timestamp)
                msg.content = (row["text"] as? String) ?? ""
                msg.attachments = attachments(row["attachments"])
                let quotes = ((row["conversationQuotes"] as? [[String: Any]]) ?? []).enumerated().compactMap { i, q -> ConversationQuote? in
                    guard let text = q["text"] as? String, !text.isEmpty else { return nil }
                    return ConversationQuote(id: "\(id)-q\(i)", text: text, path: q["path"] as? String,
                                             senderName: q["senderName"] as? String, messageId: q["messageId"] as? String)
                }
                msg.quotes = quotes.isEmpty ? nil : quotes
                // Desktop gates the pencil on `row.actions.canEdit` plus an `entityId` row target (`Afn` in renderer).
                let actions = row["actions"] as? [String: Any]
                msg.canEdit = ((actions?["canEdit"] as? Bool) == true) && target["entityId"] != nil
                msg.editRewindAvailability = turnId.map { rewindAvailability(turnHeaders[$0]) }
                result.append(msg)

            case "reasoning", "assistantText", "toolCall", "subagent":
                if kind == "subagent", pairing.suppressed.contains(rowId) { continue }
                let rank: SegmentRank = kind == "reasoning" ? .reasoning : (kind == "assistantText" ? .text : .tool)
                if current == nil || rank.rawValue < currentRank {
                    flush()
                    current = blank(id: "r\(rowId)", role: "assistant", timestamp: timestamp)
                }
                currentRank = max(currentRank, rank.rawValue)
                let turnKey = turnId ?? ""
                if lastSegmentByTurn[turnKey] == nil { turnOrder.append(turnKey) }
                lastSegmentByTurn[turnKey] = current!.id
                switch kind {
                case "reasoning":
                    let text = (row["text"] as? String) ?? ""
                    current!.thought = [current!.thought, text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                    current!.thoughtDurationMs += ZCodeV4.int(row["durationMs"]) ?? 0
                case "assistantText":
                    let text = (row["text"] as? String) ?? ""
                    current!.content = current!.content.isEmpty ? text : current!.content + "\n\n" + text
                    if let model = row["model"] as? String, !model.isEmpty {
                        current!.modelLabel = LiveModelSelection(pickerValue: model)?.modelId ?? model
                    }
                    switch row["feedback"] as? String {
                    case "like": current!.feedback = 1
                    case "dislike": current!.feedback = -1
                    default: break
                    }
                    if (row["state"] as? String) == "interrupted", current!.content.isEmpty {
                        current!.content = "_Interrupted_"
                    }
                    rowTargets[current!.id] = target
                    latestTextByTurn[turnKey] = (current!.id, row)
                    if !text.isEmpty { turnTexts[turnKey, default: []].append(text) }
                case "toolCall":
                    let key = "\(turnId ?? "")|\((row["toolCallId"] as? String) ?? "")"
                    current!.tools.append(tool(row, subagent: pairing.byToolCall[key]))
                default:
                    current!.tools.append(subagent(row))
                }

            default:
                continue
            }
        }
        flush()

        for turn in turnOrder {
            guard let latest = latestTextByTurn[turn], (latest.row["state"] as? String) == "complete",
                  let copyText = turnTexts[turn]?.joined(separator: "\n\n"), !copyText.isEmpty,
                  let lastId = lastSegmentByTurn[turn],
                  let idx = result.firstIndex(where: { $0.id == lastId }) else { continue }
            let feedback = result.first(where: { $0.id == latest.messageId })?.feedback ?? 0
            let canFork = ((latest.row["actions"] as? [String: Any])?["canFork"] as? Bool) == true
            result[idx].turnActions = TurnActionBar(copyText: copyText, targetMessageId: latest.messageId, canFork: canFork, feedback: feedback)
        }

        // Turn timing / token totals belong on the last assistant segment of each turn.
        var seenTurns = Set<String>()
        for idx in result.indices.reversed() where result[idx].role == "assistant" {
            guard let turnRow = rows.first(where: { "r\(ZCodeV4.int($0["rowId"]) ?? -1)" == result[idx].id }),
                  let turn = turnRow["turnId"] as? String, !seenTurns.contains(turn) else { continue }
            seenTurns.insert(turn)
            if let header = turnHeaders[turn] {
                result[idx].durationMs = ZCodeV4.int(header["activeMs"]) ?? 0
                result[idx].tokensOut = ZCodeV4.int(header["outputTokens"]) ?? 0
            }
        }
        return result
    }

    static let agentToolNames: Set<String> = ["Agent", "Task", "subagent"]

    /// Desktop renderer `re` (`editWorkspaceRewindAvailability`): turn file-change summary + header actions decide
    /// whether "Reset chat + files" is offered inside the inline editor.
    static func rewindAvailability(_ turnHeader: [String: Any]?) -> String {
        let fileChanges = turnHeader?["fileChanges"] as? [String: Any]
        let files = ZCodeV4.int(fileChanges?["files"]) ?? 0
        if files <= 0 { return "noFiles" }
        if (fileChanges?["state"] as? String) == "reverted" { return "reverted" }
        if (turnHeader?["state"] as? String) == "running" { return "running" }
        if ((turnHeader?["actions"] as? [String: Any])?["canRewindFiles"] as? Bool) == true { return "available" }
        return "unavailable"
    }

    /// `$sn`: subagent rows attach to the Agent tool call with the same `(turnId, toolCallId)`;
    /// a parentless row pairs only when its turn has exactly one unpaired Agent call and one unpaired subagent row.
    static func pairSubagents(_ rows: [[String: Any]]) -> (byToolCall: [String: [String: Any]], suppressed: Set<Int>) {
        var agentCalls: [String: [String]] = [:]
        for row in rows where (row["kind"] as? String) == "toolCall" {
            guard agentToolNames.contains((row["toolName"] as? String) ?? ""), let id = row["toolCallId"] as? String else { continue }
            agentCalls[(row["turnId"] as? String) ?? "", default: []].append(id)
        }
        var byToolCall: [String: [String: Any]] = [:]
        var suppressed = Set<Int>()
        var parentless: [String: [[String: Any]]] = [:]
        for row in rows where (row["kind"] as? String) == "subagent" {
            let turn = (row["turnId"] as? String) ?? ""
            if let parent = row["parentToolCallId"] as? String, !parent.isEmpty {
                guard agentCalls[turn]?.contains(parent) == true, let rowId = ZCodeV4.int(row["rowId"]) else { continue }
                byToolCall["\(turn)|\(parent)"] = row
                suppressed.insert(rowId)
            } else {
                parentless[turn, default: []].append(row)
            }
        }
        for (turn, list) in parentless where list.count == 1 {
            let unpaired = (agentCalls[turn] ?? []).filter { byToolCall["\(turn)|\($0)"] == nil }
            guard unpaired.count == 1, let rowId = ZCodeV4.int(list[0]["rowId"]) else { continue }
            byToolCall["\(turn)|\(unpaired[0])"] = list[0]
            suppressed.insert(rowId)
        }
        return (byToolCall, suppressed)
    }

    static func tool(_ row: [String: Any], subagent: [String: Any]? = nil) -> ToolCallItem {
        let toolName = (row["toolName"] as? String) ?? "Tool"
        let lower = toolName.lowercased()
        let rawStatus = (row["status"] as? String) ?? "success"
        var input = row["input"] as? [String: Any]
        if input == nil, let text = row["inputText"] as? String, let data = text.data(using: .utf8) {
            input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        let inputDict = input ?? [:]
        let output = row["output"] as? [String: Any]
        let display = (output?["display"] as? [String: Any]) ?? (row["display"] as? [String: Any])
        let displayKind = display?["kind"] as? String
        let id = (row["toolCallId"] as? String) ?? "r\(ZCodeV4.int(row["rowId"]) ?? 0)"
        let status: ToolCallStatus = {
            switch rawStatus {
            case "pendingApproval": return .pendingApproval
            case "inputStreaming", "running": return .running
            case "error": return .failed
            default: return .completed
            }
        }()

        let outputText: String? = {
            if status == .running, let preview = row["outputPreview"] as? [String: Any] {
                return (preview["fullText"] as? String) ?? (preview["text"] as? String)
            }
            if displayKind == "bash_output", let text = display?["output"] as? String { return text }
            if let text = output?["text"] as? String { return text }
            return (row["outputPreview"] as? [String: Any])?["text"] as? String
        }()
        let errorText: String? = {
            guard rawStatus == "error" else { return nil }
            if let message = (row["error"] as? [String: Any])?["message"] as? String, !message.isEmpty { return message }
            if let text = outputText, !text.isEmpty { return text }
            return "Failed"
        }()

        let filePath = (display?["filePath"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? firstString(inputDict, ["file_path", "filePath", "path", "filename", "notebook_path"])

        var item = ToolCallItem(
            id: id,
            kind: legacyKind(lower),
            title: toolName,
            subtitle: "",
            status: status,
            filePath: filePath,
            lineRange: nil,
            diffPatch: nil,
            command: shellCommand(inputDict),
            output: outputText,
            durationMs: 0,
            addedLines: 0,
            removedLines: 0,
            subagentSteps: [],
            subagentRunId: nil,
            toolName: toolName
        )
        item.rawStatus = rawStatus
        item.errorText = errorText
        item.workId = row["workId"] as? String
        if let input { item.inputJSON = prettyJSON(input) }
        item.rawJSON = prettyJSON(row, limit: 24_000)

        // File changes
        if displayKind == "file_diff" {
            item.addedLines = ZCodeV4.int(display?["additions"]) ?? 0
            item.removedLines = ZCodeV4.int(display?["deletions"]) ?? 0
            let hunks = ((display?["structuredPatch"] as? [[String: Any]]) ?? []).map { hunk -> String in
                let header = "@@ -\(ZCodeV4.int(hunk["oldStart"]) ?? 0),\(ZCodeV4.int(hunk["oldLines"]) ?? 0) +\(ZCodeV4.int(hunk["newStart"]) ?? 0),\(ZCodeV4.int(hunk["newLines"]) ?? 0) @@"
                return ([header] + ((hunk["lines"] as? [String]) ?? [])).joined(separator: "\n")
            }
            if !hunks.isEmpty { item.diffPatch = hunks.joined(separator: "\n") }
        } else if let oldText = inputDict["old_string"] as? String, let newText = inputDict["new_string"] as? String {
            item.diffPatch = AppStore.miniDiff(old: oldText, new: newText)
            item.removedLines = oldText.isEmpty ? 0 : oldText.components(separatedBy: "\n").count
            item.addedLines = newText.isEmpty ? 0 : newText.components(separatedBy: "\n").count
        } else if let content = inputDict["content"] as? String, ["write", "write_file", "create_file"].contains(lower) {
            item.contentPreview = content
            item.addedLines = content.isEmpty ? 0 : content.components(separatedBy: "\n").count
        }

        // Search / fetch
        item.webURL = inputDict["url"] as? String
        item.searchLabel = searchLabel(lower: lower, input: inputDict, rawInput: row["input"])

        // MCP
        if displayKind == "mcp_tool" {
            item.mcpServer = display?["serverName"] as? String
            item.mcpTool = display?["toolName"] as? String
            item.mcpDescription = display?["description"] as? String
        }
        if item.mcpServer == nil, let parsed = parseMCPName(toolName) {
            item.mcpServer = parsed.server
            item.mcpTool = parsed.tool
        }

        // Todo / questions / skill / plan
        if lower == "todowrite" || lower == "todoread" || lower == "update_plan" {
            item.todoItems = todoItems(inputDict) ?? outputText.flatMap { text in
                (try? JSONSerialization.jsonObject(with: Data(text.utf8))).flatMap { $0 as? [String: Any] }.flatMap(todoItems)
            }
        }
        if lower == "askuserquestion" {
            item.questionAnswers = questionAnswers(input: inputDict, output: outputText)
        }
        if lower == "skill" {
            item.skillName = firstString(inputDict, ["skill", "name", "command"])
            item.skillArgs = firstString(inputDict, ["args", "arguments"])
        }
        if lower == "exitplanmode" || lower == "enterplanmode" {
            item.planMarkdown = (inputDict["plan"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }

        // Agent / Task (inline subagent card)
        if agentToolNames.contains(toolName) || ["agent", "task", "spawn_agent"].contains(lower) {
            item.kind = .subagent
            item.agentName = (subagent?["subagentType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? firstString(inputDict, ["nickname", "agentType", "agent_type", "subagent_type", "subagentType"])
            item.agentDescription = firstString(inputDict, ["description", "subagent_type", "agent_type"])
            item.subagentRunId = subagent?["childSessionId"] as? String
            if item.workId == nil { item.workId = subagent?["workId"] as? String }
        }

        item.subtitle = item.command ?? item.filePath ?? item.searchLabel ?? item.webURL ?? ""
        return item
    }

    private static func subagent(_ row: [String: Any]) -> ToolCallItem {
        let type = (row["subagentType"] as? String) ?? "subagent"
        let summary = (row["summaryText"] as? String) ?? ""
        let rawStatus = (row["status"] as? String) ?? "running"
        let status: ToolCallStatus = {
            switch rawStatus {
            case "running": return .running
            case "failed": return .failed
            default: return .completed
            }
        }()
        var item = ToolCallItem(
            id: "sub-r\(ZCodeV4.int(row["rowId"]) ?? 0)",
            kind: .subagent,
            title: type,
            subtitle: summary,
            status: status,
            filePath: nil,
            lineRange: nil,
            diffPatch: nil,
            command: nil,
            output: nil,
            durationMs: 0,
            addedLines: 0,
            removedLines: 0,
            subagentSteps: [],
            subagentRunId: row["childSessionId"] as? String,
            toolName: "subagent"
        )
        item.rawStatus = rawStatus
        item.standaloneSubagentLine = "\(type) · \(rawStatus)" + (summary.isEmpty ? "" : " — \(summary)")
        return item
    }

    private static func legacyKind(_ lower: String) -> ToolCallKind {
        switch lower {
        case "read", "notebookread": return .readFile
        case "write", "write_file", "create_file": return .writeFile
        case "edit", "multiedit", "apply_patch", "applypatch", "notebookedit": return .editFile
        case "bash", "shell", "execute": return .bash
        case "grep", "glob", "ls", "websearch", "web_search", "webfetch", "fetch", "web_fetch": return .search
        default: return lower.hasPrefix("mcp__") ? .mcp : .readFile
        }
    }

    /// `JZ`/`YZ`: string, argv (element after `-lc`, else the tail), or `command|cmd|script`; strips `/bin/zsh -lc`.
    static func shellCommand(_ input: [String: Any]) -> String? {
        var command: String?
        for key in ["command", "cmd", "script"] {
            if let text = input[key] as? String, !text.isEmpty { command = text; break }
            if let argv = input[key] as? [String], !argv.isEmpty {
                if let idx = argv.firstIndex(of: "-lc"), idx + 1 < argv.count { command = argv[idx + 1] }
                else { command = argv.count > 1 ? argv.dropFirst().joined(separator: " ") : argv[0] }
                break
            }
        }
        if command == nil, let parsed = input["parsed_cmd"] as? [[String: Any]] {
            command = parsed.compactMap { $0["cmd"] as? String }.first
        }
        guard var text = command else { return nil }
        for prefix in ["/bin/zsh -lc ", "/bin/bash -lc ", "zsh -lc ", "bash -lc "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            if text.count >= 2, let first = text.first, first == text.last, first == "'" || first == "\"" {
                text = String(text.dropFirst().dropLast())
            }
            break
        }
        return text
    }

    /// `d7t`: "Find {query}" / "List in {cwd}".
    private static func searchLabel(lower: String, input: [String: Any], rawInput: Any?) -> String? {
        guard ["grep", "glob", "ls", "websearch", "web_search", "toolsearch", "localtoolsearch"].contains(lower) else { return nil }
        if lower == "toolsearch" || lower == "localtoolsearch" {
            let query = firstString(input, ["query"]) ?? ""
            return query.isEmpty ? "Search tools" : "Search tools: \(query)"
        }
        if let text = rawInput as? String { return text.isEmpty ? "Find" : "Find \(text)" }
        if let parsed = input["parsed_cmd"] as? [[String: Any]], let first = parsed.first {
            if (first["type"] as? String) == "list_files" {
                let cwd = (first["path"] as? String) ?? (first["cwd"] as? String) ?? ""
                return cwd.isEmpty ? "List" : "List in \(cwd)"
            }
            if let value = firstString(first, ["pattern", "query", "path"]) { return "Find \(value)" }
        }
        if lower == "ls" {
            let path = firstString(input, ["path"]) ?? ""
            return path.isEmpty ? "List" : "List in \(path)"
        }
        let value = firstString(input, ["search_query", "searchQuery", "query", "pattern", "path", "url", "prompt", "target", "name"])
        return value.map { "Find \($0)" } ?? "Find"
    }

    /// `FYe`: `mcp__<server>__<tool>`, deduping a suffix shared by server and tool segments.
    static func parseMCPName(_ name: String) -> (server: String, tool: String)? {
        guard name.lowercased().hasPrefix("mcp__") else { return nil }
        let parts = String(name.dropFirst(5)).components(separatedBy: "__").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        var server = parts[0]
        if server.hasPrefix("plugin_") { server = String(server.dropFirst(7)) }
        return (server, parts.dropFirst().joined(separator: "__"))
    }

    private static func todoItems(_ dict: [String: Any]) -> [TodoChecklistItem]? {
        guard let list = ["todos", "plan", "steps", "items"].lazy.compactMap({ dict[$0] as? [Any] }).first else { return nil }
        var out: [TodoChecklistItem] = []
        for (i, element) in list.enumerated() {
            if let text = element as? String {
                out.append(TodoChecklistItem(id: text, content: text, status: i == 0 ? "in_progress" : "pending", priority: "medium"))
            } else if let obj = element as? [String: Any],
                      let title = firstString(obj, ["content", "step", "title", "text", "activeForm"]) {
                let raw = ((obj["status"] as? String) ?? "pending").replacingOccurrences(of: "-", with: "_")
                guard ["pending", "in_progress", "completed"].contains(raw) else { return nil }
                out.append(TodoChecklistItem(id: (obj["id"] as? String) ?? title, content: title, status: raw, priority: "medium"))
            } else {
                return nil
            }
        }
        return out
    }

    private static func questionAnswers(input: [String: Any], output: String?) -> [ToolQuestionAnswer] {
        let questions = (input["questions"] as? [[String: Any]]) ?? []
        var answers: [String: Any] = [:]
        if let output, let obj = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: Any] {
            answers = (obj["answers"] as? [String: Any]) ?? [:]
        }
        return questions.compactMap { q in
            guard let text = (q["question"] as? String) ?? (q["header"] as? String) else { return nil }
            let raw = answers[text] ?? (q["id"] as? String).flatMap { answers[$0] }
            let answer: String? = {
                if let s = raw as? String { return s }
                if let list = raw as? [String] { return list.joined(separator: "，") }
                return nil
            }()
            return ToolQuestionAnswer(question: text, answer: answer)
        }
    }

    private static func firstString(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    static func prettyJSON(_ object: Any, limit: Int = 60_000) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.count > limit ? String(text.prefix(limit)) + "\n…" : text
    }

    static func attachments(_ raw: Any?) -> [ComposerAttachment] {
        ((raw as? [[String: Any]]) ?? []).map { att in
            let mime = ((att["mime"] as? String) ?? "").lowercased()
            let kind = mime.hasPrefix("image/") ? "image" : (mime == "application/pdf" ? "pdf" : "file")
            return ComposerAttachment(
                id: (att["ref"] as? String) ?? UUID().uuidString,
                name: (att["fileName"] as? String) ?? "Attachment",
                kind: kind,
                sizeBytes: ZCodeV4.int(att["bytes"]) ?? 0,
                filePath: nil,
                lineNote: nil,
                previewPNGData: nil
            )
        }
    }

    private static func blank(id: String, role: String, timestamp: Date) -> ChatTurnMessage {
        ChatTurnMessage(
            id: id, role: role, content: "", thought: nil, thoughtDurationMs: 0, tools: [], attachments: [],
            timestamp: timestamp, modelLabel: nil, tokensIn: 0, tokensOut: 0, durationMs: 0, feedback: 0
        )
    }

    private static func date(_ raw: Any?) -> Date {
        guard let ms = ZCodeV4.double(raw) else { return Date() }
        return Date(timeIntervalSince1970: ms > 9_999_999_999 ? ms / 1000 : ms)
    }
}

extension AppStore {
    /// Turn footers keyed by message id. V4 transcripts carry them from the mapper; legacy transcripts (no row
    /// states) get one on the last assistant segment of each finished turn that has text.
    static func turnActionBars(_ messages: [ChatTurnMessage], fromHost: Bool, running: Bool) -> [String: TurnActionBar] {
        var bars: [String: TurnActionBar] = [:]
        if fromHost {
            for message in messages { if let bar = message.turnActions { bars[message.id] = bar } }
            return bars
        }
        var group: [ChatTurnMessage] = []
        func close(isLast: Bool) {
            defer { group.removeAll() }
            guard let last = group.last, !(isLast && running) else { return }
            let texts = group.map(\.content).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !texts.isEmpty, let target = group.last(where: { !$0.content.isEmpty }) else { return }
            bars[last.id] = TurnActionBar(copyText: texts.joined(separator: "\n\n"), targetMessageId: target.id, canFork: false, feedback: target.feedback)
        }
        for message in messages {
            if message.role == "user" { close(isLast: false) } else { group.append(message) }
        }
        close(isLast: true)
        return bars
    }
}
