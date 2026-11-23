import SwiftUI

// MARK: - 1:1 ZCode v3.16.3 Subagents Management Studio (`subagents`)

struct SubagentsSettingsView: View {
    @Bindable var store: AppStore
    var onJumpToModels: () -> Void

    @Environment(\.zcodePalette) private var palette

    enum ScopeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case enabled = "Enabled"
        case disabled = "Disabled"
        var id: String { rawValue }

        func matches(_ item: SubagentDefinitionItem) -> Bool {
            switch self {
            case .all: return true
            case .enabled: return item.enabled
            case .disabled: return !item.enabled
            }
        }
    }

    /// Real host model candidates (model-selection view first, provider settings as fallback).
    private var modelCandidates: [(id: String, label: String, levels: [String])] {
        if !store.liveModelOptions.isEmpty {
            return store.liveModelOptions.map { option in
                (option.id, "\(option.providerName) • \(option.modelId)", option.reasoningLevels)
            }
        }
        return store.allModels.map { model in
            (model.id, "\(model.providerName) • \(model.modelId)", model.reasoningLevels)
        }
    }

    func reasoningLevels(forOverride override: String) -> [String] {
        if override.isEmpty || override == "inherit" {
            guard let preferred = store.preferredModelSelection else { return [] }
            return store.liveModel(providerId: preferred.providerId, modelId: preferred.modelId)?.reasoningLevels ?? []
        }
        return modelCandidates.first(where: { $0.id == override })?.levels
            ?? store.allModels.first(where: { $0.id == override || $0.modelId == override })?.reasoningLevels
            ?? []
    }

    func defaultReasoningLevel(forOverride override: String) -> String {
        reasoningLevels(forOverride: override).last ?? "inherit"
    }

    func normalizedReasoning(_ level: String, forOverride override: String) -> String {
        let levels = reasoningLevels(forOverride: override)
        if level == "inherit" || levels.isEmpty { return "inherit" }
        return levels.contains(level) ? level : (levels.last ?? "inherit")
    }

    @State private var scopeFilter: ScopeFilter = .all
    @State private var searchText: String = ""
    @State private var editorTarget: EditorTarget? = nil
    @State private var inspectingAgent: SubagentDefinitionItem? = nil
    @State private var deletingAgent: SubagentDefinitionItem? = nil

    struct EditorTarget: Identifiable {
        let id = UUID()
        let isNew: Bool
        let draft: SubagentDefinitionItem
    }

    private func matchesSearch(_ item: SubagentDefinitionItem, _ q: String, extra: String = "") -> Bool {
        guard !q.isEmpty else { return true }
        return item.name.localizedCaseInsensitiveContains(q)
            || item.description.localizedCaseInsensitiveContains(q)
            || extra.localizedCaseInsensitiveContains(q)
    }

    private var customAgents: [SubagentDefinitionItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.subagents.filter { item in
            item.source == "user" && !item.readOnly
                && scopeFilter.matches(item)
                && matchesSearch(item, q)
        }
    }

    private var builtInAgents: [SubagentDefinitionItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.subagents.filter { item in
            item.source == "built-in" && scopeFilter.matches(item) && matchesSearch(item, q)
        }
    }

    private var pluginAgentGroups: [(pluginName: String, agents: [SubagentDefinitionItem])] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.subagents.filter { item in
            guard item.source == "plugin", scopeFilter.matches(item) else { return false }
            return matchesSearch(item, q, extra: item.pluginName ?? "")
        }
        let grouped = Dictionary(grouping: filtered, by: { $0.pluginName ?? "plugin" })
        return grouped.keys.sorted().map { key in
            (key, grouped[key] ?? [])
        }
    }

    private var enabledCount: Int {
        store.subagents.filter(\.enabled).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZCodeSettingsPageHeader(
                    groupTitle: "Agent capabilities",
                    title: "Subagents",
                    subtitle: "Manage user-level subagent Markdown files consumed by ZCode Agent."
                ) {
                    Button {
                        editorTarget = EditorTarget(
                            isNew: true,
                            draft: SubagentDefinitionItem(
                                id: "user:new:\(UUID().uuidString.prefix(6).lowercased())",
                                name: "",
                                description: "",
                                systemPrompt: "You are a specialized subagent. Focus strictly on the delegated task and return concise, verified findings.",
                                color: .blue,
                                scope: "user",
                                source: "user",
                                readOnly: false,
                                enabled: true,
                                modelOverride: "inherit",
                                reasoningOverride: "inherit",
                                allowedTools: ["*"],
                                permissionMode: .default,
                                injectAgentsMd: true,
                                runInBackground: false
                            )
                        )
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("New subagent")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(palette.brandForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.isRemoteRPCReady)
                    .accessibilityIdentifier("createSubagentButton")
                }

                Picker("Filter", selection: $scopeFilter) {
                    ForEach(ScopeFilter.allCases) { sc in
                        Text(sc.rawValue).tag(sc)
                    }
                }
                .pickerStyle(.segmented)

                ZCodeSettingsSearchBar(
                    text: $searchText,
                    placeholder: "Search subagents..."
                )

                // Installed (user) subagents
                ZCodeSettingsCard(
                    title: "Installed",
                    subtitle: "Saved as Markdown frontmatter files in ~/.zcode/agents (User) or .zcode/agents (Workspace)."
                ) {
                    if customAgents.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "person.2.badge.gearshape")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(palette.foregroundMuted)
                            Text("No subagents found")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(palette.foregroundSubtle)
                            Button {
                                editorTarget = EditorTarget(
                                    isNew: true,
                                    draft: SubagentDefinitionItem(
                                        id: "user:template:code-reviewer",
                                        name: "code-reviewer",
                                        description: "Adversarial code & security reviewer for diffs before merging.",
                                        systemPrompt: "Review code diffs rigorously for race conditions, auth bypasses, and regressions. Cite file:line.",
                                        color: .orange,
                                        scope: "user",
                                        source: "user",
                                        readOnly: false,
                                        enabled: true,
                                        modelOverride: "inherit",
                                        reasoningOverride: "inherit",
                                        allowedTools: ["Read", "Grep", "Glob"],
                                        permissionMode: .plan,
                                        injectAgentsMd: true,
                                        runInBackground: false
                                    )
                                )
                            } label: {
                                Text("+ Create from Code Reviewer Template")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.accentBlue)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(Array(customAgents.enumerated()), id: \.element.id) { idx, agent in
                            customAgentRow(agent)
                            if idx < customAgents.count - 1 {
                                Divider().overlay(palette.border).padding(.horizontal, 14)
                            }
                        }
                    }
                }

                if !builtInAgents.isEmpty {
                    ZCodeSettingsCard(
                        title: "Built-in subagents",
                        subtitle: "Runtime defaults. System prompts are locked, but you can override their model and reasoning level."
                    ) {
                        ForEach(Array(builtInAgents.enumerated()), id: \.element.id) { idx, agent in
                            readOnlyOverrideAgentRow(agent, badgeText: "Built-in")
                            if idx < builtInAgents.count - 1 {
                                Divider().overlay(palette.border).padding(.horizontal, 14)
                            }
                        }
                    }
                }

                ForEach(pluginAgentGroups, id: \.pluginName) { group in
                    ZCodeSettingsCard(
                        title: "Plugin subagents • \(group.pluginName)",
                        subtitle: "Provided by the \(group.pluginName) plugin. Only model and reasoning can be overridden."
                    ) {
                        ForEach(Array(group.agents.enumerated()), id: \.element.id) { idx, agent in
                            readOnlyOverrideAgentRow(agent, badgeText: group.pluginName)
                            if idx < group.agents.count - 1 {
                                Divider().overlay(palette.border).padding(.horizontal, 14)
                            }
                        }
                    }
                }

                Text("\(store.subagents.count) subagents · \(enabledCount) enabled")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.foregroundMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(palette.background)
        .sheet(item: $editorTarget) { target in
            SubagentEditorSheet(
                store: store,
                isNew: target.isNew,
                draft: target.draft
            )
        }
        .sheet(item: $inspectingAgent) { agent in
            SubagentPromptInspectorSheet(agent: agent)
        }
        .confirmationDialog(
            "Delete subagent '\(deletingAgent?.name ?? "")'?",
            isPresented: Binding(
                get: { deletingAgent != nil },
                set: { if !$0 { deletingAgent = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Subagent", role: .destructive) {
                if let target = deletingAgent {
                    Task { _ = await store.deleteSubagent(target.id) }
                }
                deletingAgent = nil
            }
            Button("Cancel", role: .cancel) { deletingAgent = nil }
        }
    }

    private func isInheritedModel(_ val: String) -> Bool {
        val.isEmpty || val == "inherit"
    }

    private func isInheritedEffort(_ val: String) -> Bool {
        val.isEmpty || val == "inherit"
    }

    private func customAgentRow(_ agent: SubagentDefinitionItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 9) {
                Circle()
                    .fill(Color(hex: agent.color.hex))
                    .frame(width: 10, height: 10)

                Text(agent.name)
                    .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.foreground)

                ZCodeSettingsPill(
                    text: agent.scope.lowercased() == "workspace" ? "Workspace" : "User",
                    tone: agent.scope.lowercased() == "workspace" ? .accent : .neutral
                )

                if agent.runInBackground {
                    ZCodeSettingsPill(text: "Background", tone: .warning)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { agent.enabled },
                    set: { newValue in Task { _ = await store.setSubagentEnabled(agent.id, enabled: newValue) } }
                ))
                .labelsHidden()
                .tint(palette.accentBlue)
                .disabled(!store.isRemoteRPCReady)
            }

            if !agent.description.isEmpty {
                Text(agent.description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                ZCodeSettingsPill(
                    text: isInheritedModel(agent.modelOverride) ? "Model: Inherit" : shortModelLabel(agent.modelOverride),
                    tone: isInheritedModel(agent.modelOverride) ? .neutral : .accent
                )
                if !isInheritedEffort(agent.reasoningOverride) {
                    ZCodeSettingsPill(text: "Effort: \(agent.reasoningOverride)", tone: .neutral)
                }
                ZCodeSettingsPill(text: agent.toolsSummary, tone: .neutral)
            }

            HStack(spacing: 8) {
                Button {
                    editorTarget = EditorTarget(isNew: false, draft: agent)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5.5)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    inspectingAgent = agent
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Prompt")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5.5)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(role: .destructive) {
                    deletingAgent = agent
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.destructive)
                        .frame(width: 28, height: 26)
                        .background(palette.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityIdentifier("subagentRow_\(agent.name)")
    }

    private func readOnlyOverrideAgentRow(_ agent: SubagentDefinitionItem, badgeText: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: agent.color.hex))
                    .frame(width: 9, height: 9)

                Text(agent.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.foreground)

                ZCodeSettingsPill(text: badgeText, tone: .neutral)

                Spacer()

                Button {
                    inspectingAgent = agent
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        Text("Inspect")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Text(agent.description)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.foregroundSubtle)
                .lineLimit(2)

            if agent.canOverrideModelInline {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Model")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.foregroundSubtle)
                        Spacer()
                        ZCodeSettingsSelect(
                            options: [ZCodeSettingsSelectOption(value: "inherit", label: "Inherit session model")]
                                + modelCandidates.map { ZCodeSettingsSelectOption(value: $0.id, label: $0.label) },
                            selection: Binding(
                                get: { agent.modelOverride },
                                set: { newModel in
                                    let newLevel = reasoningLevels(forOverride: newModel).last ?? "inherit"
                                    Task {
                                        _ = await store.setSubagentModelAndEffortOverride(
                                            id: agent.id,
                                            modelOverride: newModel,
                                            reasoningOverride: newLevel
                                        )
                                    }
                                }
                            ),
                            isEnabled: store.isRemoteRPCReady
                        )
                    }

                    let levels = reasoningLevels(forOverride: agent.modelOverride)
                    if levels.isEmpty {
                        Text("Reasoning effort unavailable")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.foregroundMuted)
                    } else {
                        HStack(spacing: 8) {
                            Text("Reasoning")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.foregroundSubtle)
                            Spacer()
                            ZCodeSettingsSelect(
                                options: [ZCodeSettingsSelectOption(value: "inherit", label: "Default")]
                                    + levels.map { ZCodeSettingsSelectOption(value: $0, label: $0.uppercased()) },
                                selection: Binding(
                                    get: { normalizedReasoning(agent.reasoningOverride, forOverride: agent.modelOverride) },
                                    set: { newLevel in
                                        Task {
                                            _ = await store.setSubagentModelAndEffortOverride(
                                                id: agent.id,
                                                modelOverride: agent.modelOverride,
                                                reasoningOverride: newLevel
                                            )
                                        }
                                    }
                                ),
                                isEnabled: store.isRemoteRPCReady
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityIdentifier("subagentRow_\(agent.name)")
    }

    private func shortModelLabel(_ raw: String) -> String {
        if let found = store.allModels.first(where: { $0.id == raw || $0.modelId == raw }) {
            return found.modelId
        }
        return raw.split(separator: "/").last.map(String.init) ?? raw
    }
}

// MARK: - 1:1 ZCode Create / Edit Subagent Studio Sheet (`Nqn`)

struct SubagentEditorSheet: View {
    @Bindable var store: AppStore
    let isNew: Bool
    @State var draft: SubagentDefinitionItem

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let toolColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var nameError: String? {
        let existing = store.subagents
            .filter { isNew || $0.id != draft.id }
            .map(\.name)
        return AppStore.validateSubagentName(draft.name, existingNames: existing, isNew: isNew)
    }

    private func levels(for override: String) -> [String] {
        if override.isEmpty || override == "inherit" {
            guard let preferred = store.preferredModelSelection else { return [] }
            return store.liveModel(providerId: preferred.providerId, modelId: preferred.modelId)?.reasoningLevels ?? []
        }
        if let live = store.liveModelOptions.first(where: { $0.id == override }) {
            return live.reasoningLevels
        }
        return store.allModels.first(where: { $0.id == override || $0.modelId == override })?.reasoningLevels ?? []
    }

    private var editorReasoningLevels: [String] {
        levels(for: draft.modelOverride)
    }

    private func normalizeReasoningForEditor() {
        let available = editorReasoningLevels
        if available.isEmpty {
            draft.reasoningOverride = "inherit"
        } else if draft.reasoningOverride != "inherit", !available.contains(draft.reasoningOverride) {
            draft.reasoningOverride = available.last ?? "inherit"
        }
    }

    private var allowAllToolsBinding: Binding<Bool> {
        Binding(
            get: { draft.isAllTools },
            set: { newVal in
                if newVal {
                    draft.allowedTools = ["*"]
                } else {
                    draft.allowedTools = SubagentBuiltInToolSpec.officialTools.map(\.id)
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Card 1: Identity, Scope & Color Dot
                        ZCodeSettingsCard(
                            title: "Identity & Delegation Trigger",
                            subtitle: "Define the unique slug and explain when ZCode should spawn this subagent."
                        ) {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("Subagent Name")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.foregroundSubtle)
                                        Spacer()
                                        Text("\(draft.name.count)/50")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(palette.foregroundMuted)
                                    }
                                    TextField("e.g. security-auditor or api-architect", text: $draft.name)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundStyle(palette.foreground)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(10)
                                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .strokeBorder(!draft.name.isEmpty && nameError != nil ? palette.destructive : palette.inputBorder, lineWidth: 1)
                                        )
                                        .accessibilityIdentifier("subagentNameField")

                                    if !draft.name.isEmpty, let err = nameError {
                                        Text(err)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundStyle(palette.destructive)
                                    } else {
                                        Text("Letters, numbers, and hyphens only (3–50 chars).")
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.foregroundMuted)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Storage Scope")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.foregroundSubtle)
                                        Spacer()
                                        Text(draft.scope == "workspace" ? ".zcode/agents/" : "~/.zcode/agents/")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(palette.foregroundMuted)
                                    }
                                    ZCodeSettingsSelect(
                                        options: [
                                            ZCodeSettingsSelectOption(value: "user", label: "User (Global)"),
                                            ZCodeSettingsSelectOption(value: "workspace", label: "Workspace")
                                        ],
                                        selection: $draft.scope,
                                        isEnabled: isNew
                                    )
                                }

                                // 8 Official Color Dots (`yellow`, `red`, `orange`, `green`, `cyan`, `blue`, `purple`, `pink`)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("Badge Color")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    HStack(spacing: 12) {
                                        ForEach(SubagentColor.allCases) { colorOpt in
                                            let selected = draft.color == colorOpt
                                            Button {
                                                draft.color = colorOpt
                                            } label: {
                                                ZStack {
                                                    Circle()
                                                        .fill(Color(hex: colorOpt.hex))
                                                        .frame(width: 24, height: 24)
                                                    if selected {
                                                        Circle()
                                                            .strokeBorder(palette.foreground, lineWidth: 2)
                                                            .frame(width: 30, height: 30)
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("When to Use (Description)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    TextField("Describe what tasks the main agent should delegate to this subagent…", text: $draft.description, axis: .vertical)
                                        .lineLimit(2...4)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(palette.foreground)
                                        .padding(10)
                                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                                }
                            }
                            .padding(14)
                        }

                        // Card 2: Model, Reasoning Effort, Permissions & Context Behavior
                        ZCodeSettingsCard(
                            title: "Model, Permissions & Execution",
                            subtitle: "Control model routing, permission policy, and workspace instruction injection."
                        ) {
                            VStack(alignment: .leading, spacing: 13) {
                                HStack {
                                    Text("Model")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                    ZCodeSettingsSelect(
                                        options: [ZCodeSettingsSelectOption(value: "inherit", label: "Inherit")]
                                            + store.liveModelOptions.map {
                                                ZCodeSettingsSelectOption(
                                                    value: $0.id,
                                                    label: "\($0.providerName) • \($0.modelId)"
                                                )
                                            }
                                            + (store.liveModelOptions.isEmpty
                                                ? store.allModels.map {
                                                    ZCodeSettingsSelectOption(value: $0.id, label: "\($0.providerName) • \($0.modelId)")
                                                }
                                                : []),
                                        selection: $draft.modelOverride
                                    )
                                }

                                Divider().overlay(palette.border)

                                if editorReasoningLevels.isEmpty {
                                    Text("Reasoning effort unavailable")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(palette.foregroundMuted)
                                } else {
                                    HStack {
                                        Text("Reasoning level")
                                            .font(.system(size: 13.5, weight: .medium))
                                            .foregroundStyle(palette.foreground)
                                        Spacer()
                                        ZCodeSettingsSelect(
                                            options: [ZCodeSettingsSelectOption(value: "inherit", label: "Default")]
                                                + editorReasoningLevels.map {
                                                    ZCodeSettingsSelectOption(value: $0, label: $0.uppercased())
                                                },
                                            selection: $draft.reasoningOverride
                                        )
                                    }
                                }

                                Divider().overlay(palette.border)

                                HStack {
                                    Text("Permission mode")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                    ZCodeSettingsSelect(
                                        options: SubagentPermissionMode.allCases.map {
                                            ZCodeSettingsSelectOption(value: $0, label: $0.displayName)
                                        },
                                        selection: $draft.permissionMode
                                    )
                                }

                                Divider().overlay(palette.border)

                                Toggle(isOn: $draft.injectAgentsMd) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Inject AGENTS.md / CLAUDE.md")
                                            .font(.system(size: 13.5, weight: .medium))
                                            .foregroundStyle(palette.foreground)
                                        Text("Include repository rules and memory in subagent context")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(palette.foregroundSubtle)
                                    }
                                }
                                .tint(palette.accentBlue)

                                Toggle(isOn: $draft.runInBackground) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Run in Background by Default")
                                            .font(.system(size: 13.5, weight: .medium))
                                            .foregroundStyle(palette.foreground)
                                        Text("Execute asynchronously and notify main conversation on completion")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(palette.foregroundSubtle)
                                    }
                                }
                                .tint(palette.accentBlue)
                            }
                            .padding(14)
                        }

                        // Card 3: Tool Sandbox (`All tools (*)` vs 2-column Official Tool Grid + Red Destructive Indicators)
                        ZCodeSettingsCard(
                            title: "Allowed Tools",
                            subtitle: "Grant all tools (*) or restrict this subagent to a read-only or scoped toolset."
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: allowAllToolsBinding) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Allow All Tools (*)")
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundStyle(palette.foreground)
                                        Text("Uncheck to pick specific built-in and MCP tools")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(palette.foregroundSubtle)
                                    }
                                }
                                .tint(palette.accentBlue)

                                if !draft.isAllTools {
                                    Divider().overlay(palette.border)

                                    HStack {
                                        Text("Built-in Tools")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.foregroundSubtle)
                                        Spacer()
                                        Button("Read-Only Preset") {
                                            draft.allowedTools = ["Read", "Grep", "Glob"]
                                        }
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(palette.accentBlue)
                                    }

                                    LazyVGrid(columns: toolColumns, spacing: 8) {
                                        ForEach(SubagentBuiltInToolSpec.officialTools) { spec in
                                            let checked = draft.allowedTools.contains(spec.id)
                                            Button {
                                                draft.allowedTools.removeAll { $0 == "*" }
                                                if checked {
                                                    draft.allowedTools.removeAll { $0 == spec.id }
                                                } else {
                                                    draft.allowedTools.append(spec.id)
                                                }
                                            } label: {
                                                HStack(spacing: 7) {
                                                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(checked ? palette.accentBlue : palette.foregroundMuted)
                                                    Text(spec.id)
                                                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                                        .foregroundStyle(palette.foreground)
                                                        .lineLimit(1)
                                                    Spacer(minLength: 2)
                                                    if spec.isDestructiveOrMutating {
                                                        Circle()
                                                            .fill(palette.destructive)
                                                            .frame(width: 6, height: 6)
                                                    }
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 8)
                                                .background(
                                                    checked ? palette.accentBlue.opacity(0.10) : palette.card,
                                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .strokeBorder(checked ? palette.accentBlue.opacity(0.45) : palette.border, lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    HStack(spacing: 5) {
                                        Circle().fill(palette.destructive).frame(width: 6, height: 6)
                                        Text("Red dot marks state-mutating / command-execution tools (Bash, Edit, Write).")
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.foregroundMuted)
                                    }

                                    if !store.mcpServers.isEmpty {
                                        Divider().overlay(palette.border)
                                        Text("MCP Server Tool Wildcards")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.foregroundSubtle)

                                        ForEach(store.mcpServers) { srv in
                                            let wildcard = "mcp__\(srv.name)__*"
                                            let checked = draft.allowedTools.contains(wildcard)
                                            Button {
                                                draft.allowedTools.removeAll { $0 == "*" }
                                                if checked {
                                                    draft.allowedTools.removeAll { $0 == wildcard }
                                                } else {
                                                    draft.allowedTools.append(wildcard)
                                                }
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                                                        .foregroundStyle(checked ? palette.accentBlue : palette.foregroundMuted)
                                                    Text(wildcard)
                                                        .font(.system(size: 12.5, design: .monospaced))
                                                        .foregroundStyle(palette.foreground)
                                                    Spacer()
                                                    ZCodeSettingsPill(text: "\(srv.tools.count) tools", tone: .neutral)
                                                }
                                                .padding(.vertical, 4)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(14)
                        }

                        // Card 4: System Prompt Markdown Editor
                        ZCodeSettingsCard(
                            title: "System Prompt (Markdown)",
                            subtitle: "Instructions written to the Markdown body of the subagent definition file."
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(draft.systemPrompt.count) chars")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(palette.foregroundMuted)
                                    Spacer()
                                    Button("Insert Structured Template") {
                                        draft.systemPrompt = """
                                        # Role
                                        You are a focused specialist subagent.

                                        ## Workflow
                                        1. Gather exact file and symbol evidence first.
                                        2. Verify assumptions against live code.
                                        3. Return a concise conclusion with `file:line` references.
                                        """
                                    }
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(palette.accentBlue)
                                }

                                TextEditor(text: $draft.systemPrompt)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(palette.foreground)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 170)
                                    .padding(8)
                                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                            }
                            .padding(14)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isNew ? "Create Subagent" : "Edit \(draft.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isNew ? "Create" : "Save") {
                        guard nameError == nil else { return }
                        if !draft.isAllTools && draft.allowedTools.isEmpty {
                            draft.allowedTools = ["Read"]
                        }
                        normalizeReasoningForEditor()
                        let snapshot = draft
                        Task {
                            let ok = await store.saveSubagent(snapshot, isNew: isNew)
                            if ok { await MainActor.run { dismiss() } }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(nameError != nil || draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.isRemoteRPCReady)
                    .accessibilityIdentifier("saveSubagentButton")
                }
            }
            .onChange(of: draft.modelOverride) { _, _ in
                normalizeReasoningForEditor()
            }
            .onAppear {
                normalizeReasoningForEditor()
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}

// MARK: - Read-Only System Prompt Inspector Sheet

struct SubagentPromptInspectorSheet: View {
    let agent: SubagentDefinitionItem
    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ZCodeSettingsCard(
                            title: agent.name,
                            subtitle: agent.description
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    ZCodeSettingsPill(text: agent.source == "built-in" ? "Built-in" : (agent.pluginName ?? agent.scope), tone: .accent)
                                    ZCodeSettingsPill(text: agent.toolsSummary, tone: .neutral)
                                }
                                Divider().overlay(palette.border)
                                Text(agent.systemPrompt.isEmpty ? "(Managed by ZCode runtime)" : agent.systemPrompt)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(palette.foreground)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Subagent Definition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}
