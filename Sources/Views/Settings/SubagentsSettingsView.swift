import SwiftUI

// MARK: - 1:1 ZCode v3.16.3 Subagents Management Studio (`subagents`)

struct SubagentsSettingsView: View {
    @Bindable var store: AppStore
    var onJumpToModels: () -> Void

    @Environment(\.zcodePalette) private var palette

    enum ScopeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case user = "User"
        case workspace = "Workspace"
        var id: String { rawValue }
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

    private var customAgents: [SubagentDefinitionItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.subagents.filter { item in
            guard item.source == "user" && !item.readOnly else { return false }
            switch scopeFilter {
            case .all: break
            case .user:
                if item.scope.lowercased() != "user" { return false }
            case .workspace:
                if item.scope.lowercased() != "workspace" { return false }
            }
            guard !q.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(q)
                || item.description.localizedCaseInsensitiveContains(q)
        }
    }

    private var builtInAgents: [SubagentDefinitionItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.subagents.filter { item in
            guard item.source == "built-in" else { return false }
            guard !q.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(q)
                || item.description.localizedCaseInsensitiveContains(q)
        }
    }

    private var pluginAgentGroups: [(pluginName: String, agents: [SubagentDefinitionItem])] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.subagents.filter { item in
            guard item.source == "plugin" else { return false }
            let pName = item.pluginName ?? "plugin"
            guard !q.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(q)
                || item.description.localizedCaseInsensitiveContains(q)
                || pName.localizedCaseInsensitiveContains(q)
        }
        let grouped = Dictionary(grouping: filtered, by: { $0.pluginName ?? "plugin" })
        return grouped.keys.sorted().map { key in
            (key, grouped[key] ?? [])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZCodeSettingsPageHeader(
                    groupTitle: "Agent capabilities",
                    title: "Subagents",
                    subtitle: "Create specialized subagents with isolated context windows, custom system prompts, tool sandboxes, and dedicated model overrides."
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
                                scope: scopeFilter == .workspace ? "workspace" : "user",
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
                            Text("Create")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(palette.brandForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("createSubagentButton")
                }

                // Scope Filter + Manage Models Link Bar
                HStack(spacing: 10) {
                    Picker("Scope", selection: $scopeFilter) {
                        ForEach(ScopeFilter.allCases) { sc in
                            Text(sc.rawValue).tag(sc)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        onJumpToModels()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("Models")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(palette.accentBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(palette.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                ZCodeSettingsSearchBar(
                    text: $searchText,
                    placeholder: "Search subagents by name, role, or plugin…"
                )

                // Tier 1: Custom User & Workspace Subagents
                ZCodeSettingsCard(
                    title: "Custom Subagents (\(customAgents.count))",
                    subtitle: "Saved as Markdown frontmatter files in ~/.zcode/agents (User) or .zcode/agents (Workspace)."
                ) {
                    if customAgents.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "person.2.badge.gearshape")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(palette.foregroundMuted)
                            Text("No custom subagents in this scope yet.")
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
                                        scope: scopeFilter == .workspace ? "workspace" : "user",
                                        source: "user",
                                        readOnly: false,
                                        enabled: true,
                                        modelOverride: "inherit",
                                        reasoningOverride: "high",
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

                // Tier 2: Official Built-in Agents (`general-purpose`, `Explore`)
                if !builtInAgents.isEmpty && scopeFilter == .all {
                    ZCodeSettingsCard(
                        title: "Built-in Agents",
                        subtitle: "Core ZCode system subagents. System prompts are locked, but you can override their execution model and reasoning effort."
                    ) {
                        ForEach(Array(builtInAgents.enumerated()), id: \.element.id) { idx, agent in
                            readOnlyOverrideAgentRow(agent, badgeText: "Built-in")
                            if idx < builtInAgents.count - 1 {
                                Divider().overlay(palette.border).padding(.horizontal, 14)
                            }
                        }
                    }
                }

                // Tier 3: Plugin Agents grouped by Plugin
                if !pluginAgentGroups.isEmpty && scopeFilter == .all {
                    ForEach(pluginAgentGroups, id: \.pluginName) { group in
                        ZCodeSettingsCard(
                            title: "Plugin Agents • \(group.pluginName)",
                            subtitle: "Provided by the \(group.pluginName) plugin. Configure per-agent model and effort overrides."
                        ) {
                            ForEach(Array(group.agents.enumerated()), id: \.element.id) { idx, agent in
                                readOnlyOverrideAgentRow(agent, badgeText: group.pluginName)
                                if idx < group.agents.count - 1 {
                                    Divider().overlay(palette.border).padding(.horizontal, 14)
                                }
                            }
                        }
                    }
                }
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
                    store.deleteSubagent(target.id)
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
                    set: { store.setSubagentEnabled(agent.id, enabled: $0) }
                ))
                .labelsHidden()
                .tint(palette.accentBlue)
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
                HStack(spacing: 8) {
                    Menu {
                        Button {
                            store.setSubagentModelAndEffortOverride(
                                id: agent.id,
                                modelOverride: "inherit",
                                reasoningOverride: agent.reasoningOverride
                            )
                        } label: {
                            Label("Inherit Session Model", systemImage: isInheritedModel(agent.modelOverride) ? "checkmark" : "arrow.turn.down.right")
                        }
                        Divider()
                        ForEach(store.allModels) { m in
                            Button {
                                store.setSubagentModelAndEffortOverride(
                                    id: agent.id,
                                    modelOverride: m.id,
                                    reasoningOverride: agent.reasoningOverride
                                )
                            } label: {
                                if agent.modelOverride == m.id {
                                    Label("\(m.providerName) • \(m.modelId)", systemImage: "checkmark")
                                } else {
                                    Text("\(m.providerName) • \(m.modelId)")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "cpu")
                                .font(.system(size: 11))
                            Text(isInheritedModel(agent.modelOverride) ? "Inherit Model" : shortModelLabel(agent.modelOverride))
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(isInheritedModel(agent.modelOverride) ? palette.foregroundSubtle : palette.accentBlue)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5.5)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                    }

                    Menu {
                        ForEach(["inherit", "off", "low", "medium", "high", "max"], id: \.self) { lvl in
                            Button {
                                store.setSubagentModelAndEffortOverride(
                                    id: agent.id,
                                    modelOverride: agent.modelOverride,
                                    reasoningOverride: lvl
                                )
                            } label: {
                                let label = lvl == "inherit" ? "Default Effort" : lvl.uppercased()
                                if agent.reasoningOverride == lvl {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "brain")
                                .font(.system(size: 11))
                            Text(isInheritedEffort(agent.reasoningOverride) ? "Default Effort" : agent.reasoningOverride)
                                .font(.system(size: 11.5, weight: .semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(isInheritedEffort(agent.reasoningOverride) ? palette.foregroundSubtle : palette.foreground)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5.5)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                    }

                    Spacer()
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
                                    Picker("Scope", selection: $draft.scope) {
                                        Text("User (Global)").tag("user")
                                        Text("Workspace").tag("workspace")
                                    }
                                    .pickerStyle(.segmented)
                                    .disabled(!isNew)
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
                                    Text("Model Override")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                    Picker("Model", selection: $draft.modelOverride) {
                                        Text("Inherit Model").tag("inherit")
                                        ForEach(store.allModels) { m in
                                            Text("\(m.providerName) • \(m.modelId)").tag(m.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .lineLimit(1)
                                }

                                Divider().overlay(palette.border)

                                HStack {
                                    Text("Reasoning Effort")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                    Picker("Effort", selection: $draft.reasoningOverride) {
                                        Text("Default").tag("inherit")
                                        Text("off").tag("off")
                                        Text("low").tag("low")
                                        Text("medium").tag("medium")
                                        Text("high").tag("high")
                                        Text("max").tag("max")
                                    }
                                    .pickerStyle(.menu)
                                }

                                Divider().overlay(palette.border)

                                HStack {
                                    Text("Permission Mode")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                    Picker("Permission Mode", selection: $draft.permissionMode) {
                                        ForEach(SubagentPermissionMode.allCases) { pm in
                                            Text(pm.displayName).tag(pm)
                                        }
                                    }
                                    .pickerStyle(.menu)
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
                        store.saveSubagent(draft, isNew: isNew)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(nameError != nil || draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveSubagentButton")
                }
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
