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
    var foregroundExecutionId: String?
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
        return out
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
                result.append(msg)

            case "reasoning", "assistantText", "toolCall", "subagent":
                let rank: SegmentRank = kind == "reasoning" ? .reasoning : (kind == "assistantText" ? .text : .tool)
                if current == nil || rank.rawValue < currentRank {
                    flush()
                    current = blank(id: "r\(rowId)", role: "assistant", timestamp: timestamp)
                }
                currentRank = max(currentRank, rank.rawValue)
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
                case "toolCall":
                    current!.tools.append(tool(row))
                default:
                    current!.tools.append(subagent(row))
                }

            default:
                continue
            }
        }
        flush()

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

    static func tool(_ row: [String: Any]) -> ToolCallItem {
        let toolName = (row["toolName"] as? String) ?? "Tool"
        var input = row["input"] as? [String: Any]
        if input == nil, let text = row["inputText"] as? String, let data = text.data(using: .utf8) {
            input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        let output = row["output"] as? [String: Any]
        let error = row["error"] as? [String: Any]
        var legacy: [String: Any] = [
            "toolId": (row["toolCallId"] as? String) ?? "r\(ZCodeV4.int(row["rowId"]) ?? 0)",
            "toolName": toolName,
            "input": input ?? [:],
            "status": "completed"
        ]
        if let text = output?["text"] as? String { legacy["output"] = text }
        else if let preview = (row["outputPreview"] as? [String: Any])?["text"] as? String { legacy["output"] = preview }
        if let message = error?["message"] as? String { legacy["error"] = message }
        if let started = ZCodeV4.double(row["startedAt"]), let ended = ZCodeV4.double(row["endedAt"]) {
            legacy["durationMs"] = max(0, ended - started)
        }
        var item = AppStore.parseTool(legacy, fallbackId: legacy["toolId"] as! String)
        item.toolName = toolName
        item.status = {
            switch row["status"] as? String {
            case "pendingApproval": return .pendingApproval
            case "inputStreaming", "running": return .running
            case "error", "cancelled": return .failed
            default: return .completed
            }
        }()
        if let display = output?["display"] as? [String: Any], (display["kind"] as? String) == "file_diff" {
            item.addedLines = ZCodeV4.int(display["additions"]) ?? item.addedLines
            item.removedLines = ZCodeV4.int(display["deletions"]) ?? item.removedLines
            if let path = display["filePath"] as? String, !path.isEmpty { item.filePath = path }
            let hunks = ((display["structuredPatch"] as? [[String: Any]]) ?? []).map { hunk -> String in
                let header = "@@ -\(ZCodeV4.int(hunk["oldStart"]) ?? 0),\(ZCodeV4.int(hunk["oldLines"]) ?? 0) +\(ZCodeV4.int(hunk["newStart"]) ?? 0),\(ZCodeV4.int(hunk["newLines"]) ?? 0) @@"
                return ([header] + ((hunk["lines"] as? [String]) ?? [])).joined(separator: "\n")
            }
            if !hunks.isEmpty { item.diffPatch = hunks.joined(separator: "\n") }
        }
        return item
    }

    private static func subagent(_ row: [String: Any]) -> ToolCallItem {
        let type = (row["subagentType"] as? String) ?? "Agent"
        let summary = (row["summaryText"] as? String) ?? ""
        let status: ToolCallStatus = {
            switch row["status"] as? String {
            case "running": return .running
            case "failed", "cancelled": return .failed
            default: return .completed
            }
        }()
        var item = ToolCallItem(
            id: (row["parentToolCallId"] as? String) ?? "sub-r\(ZCodeV4.int(row["rowId"]) ?? 0)",
            kind: .subagent,
            title: type,
            subtitle: String(summary.split(separator: "\n").first ?? "").prefix(120).description,
            status: status,
            filePath: nil,
            lineRange: nil,
            diffPatch: nil,
            command: nil,
            output: summary.isEmpty ? nil : summary,
            durationMs: 0,
            addedLines: 0,
            removedLines: 0,
            subagentSteps: [],
            subagentRunId: row["childSessionId"] as? String,
            toolName: "Task"
        )
        if let started = ZCodeV4.double(row["startedAt"]), let ended = ZCodeV4.double(row["endedAt"]) {
            item.durationMs = Int(max(0, ended - started))
        }
        return item
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
