import SwiftUI
import UIKit

// MARK: - 1:1 ZCode v3.16.3 Model & Provider Management (`modelProvider`)

struct ModelProviderSettingsView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette

    @State private var searchText: String = ""
    @State private var showAddProviderSheet: Bool = false
    @State private var createdProviderId: String? = nil

    private var accountProviders: [ModelProviderConfig] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.providers.filter { p in
            guard p.isAccountProvider else { return false }
            guard !q.isEmpty else { return true }
            return p.name.localizedCaseInsensitiveContains(q)
                || p.models.contains(where: { $0.modelId.localizedCaseInsensitiveContains(q) })
        }
    }

    private var personalProviders: [ModelProviderConfig] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = store.providers.filter { !$0.isAccountProvider }
        return ordered.filter { p in
            guard !q.isEmpty else { return true }
            return p.name.localizedCaseInsensitiveContains(q)
                || p.baseURL.localizedCaseInsensitiveContains(q)
                || p.models.contains(where: { $0.modelId.localizedCaseInsensitiveContains(q) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZCodeSettingsPageHeader(
                    groupTitle: "Basics",
                    title: "Model settings",
                    subtitle: "Manage custom model providers. Once configured, they can be selected during chat."
                ) {
                    HStack(spacing: 8) {
                        Button {
                            Task { await store.syncProvidersAndModelsRPC() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(palette.foregroundSubtle)
                                .frame(width: 30, height: 30)
                                .background(palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.isRemoteRPCReady)
                        .accessibilityLabel("Refresh providers")

                        Button {
                            showAddProviderSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11.5, weight: .bold))
                                Text("Add provider")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(palette.brandForeground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.isRemoteRPCReady)
                        .accessibilityIdentifier("addProviderButton")
                    }
                }

                if !store.isRemoteRPCReady {
                    ZCodeSettingsCard {
                        Text("Connect to your ZCode Desktop host to view and edit model providers.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.foregroundSubtle)
                            .padding(14)
                    }
                }

                ZCodeSettingsSearchBar(
                    text: $searchText,
                    placeholder: "Search providers or model IDs…"
                )

                // Group 1: host account/preset providers ("Providers").
                ZCodeSettingsCard(
                    title: "Providers",
                    subtitle: "Built-in plan providers supplied by ZCode Desktop."
                ) {
                    if accountProviders.isEmpty {
                        Text("No plan providers reported by the host.")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    } else {
                        ForEach(Array(accountProviders.enumerated()), id: \.element.id) { idx, provider in
                            NavigationLink {
                                ProviderDetailStudioView(store: store, providerId: provider.id)
                            } label: {
                                providerRowContent(provider: provider, indexInPersonal: 0, totalPersonal: 0)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("providerRow_\(provider.id)")

                            if idx < accountProviders.count - 1 {
                                Divider().overlay(palette.border).padding(.leading, 54)
                            }
                        }
                    }
                }

                // Group 2: host personal providers ("Custom providers") in providerOrder.
                ZCodeSettingsCard(
                    title: "Custom providers",
                    subtitle: "Providers you added, backed by API keys or custom endpoints."
                ) {
                    if personalProviders.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "cpu")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(palette.foregroundMuted)
                            Text("No custom model providers yet")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(palette.foregroundSubtle)
                            Button {
                                showAddProviderSheet = true
                            } label: {
                                Text("Add provider")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.accentBlue)
                            }
                            .disabled(!store.isRemoteRPCReady)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(Array(personalProviders.enumerated()), id: \.element.id) { idx, provider in
                            NavigationLink {
                                ProviderDetailStudioView(store: store, providerId: provider.id)
                            } label: {
                                providerRowContent(
                                    provider: provider,
                                    indexInPersonal: idx,
                                    totalPersonal: personalProviders.count
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("providerRow_\(provider.id)")

                            if idx < personalProviders.count - 1 {
                                Divider().overlay(palette.border).padding(.leading, 54)
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
        .navigationDestination(item: $createdProviderId) { pid in
            ProviderDetailStudioView(store: store, providerId: pid)
        }
        .sheet(isPresented: $showAddProviderSheet) {
            AddProviderTemplateSheet(store: store) { createdId in
                createdProviderId = createdId
            }
        }
    }

    private func providerRowContent(
        provider: ModelProviderConfig,
        indexInPersonal: Int,
        totalPersonal: Int
    ) -> some View {
        let enabledCount = provider.models.filter(\.enabled).count
        return HStack(spacing: 12) {
            providerAvatar(for: provider)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)

                    if provider.isAccountProvider {
                        ZCodeSettingsPill(
                            text: provider.entitled ? "Entitled" : (provider.accountAvailability == "available" ? "Not subscribed" : "Not signed in"),
                            tone: provider.entitled ? .success : .neutral
                        )
                    } else {
                        ZCodeSettingsPill(text: provider.apiFormat.shortBadge, tone: .neutral)
                    }
                }

                HStack(spacing: 6) {
                    Text("\(enabledCount)/\(provider.models.count) models")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)

                    Text("•").foregroundStyle(palette.foregroundMuted)

                    Circle()
                        .fill(statusColor(provider))
                        .frame(width: 6, height: 6)

                    Text(provider.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if totalPersonal > 1 && !provider.isAccountProvider {
                HStack(spacing: 2) {
                    Button {
                        Task { await store.movePersonalProvider(providerId: provider.id, direction: -1) }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(indexInPersonal == 0 ? palette.foregroundMuted.opacity(0.35) : palette.foregroundSubtle)
                            .frame(width: 24, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(indexInPersonal == 0 || !store.isRemoteRPCReady)

                    Button {
                        Task { await store.movePersonalProvider(providerId: provider.id, direction: 1) }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(indexInPersonal == totalPersonal - 1 ? palette.foregroundMuted.opacity(0.35) : palette.foregroundSubtle)
                            .frame(width: 24, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(indexInPersonal == totalPersonal - 1 || !store.isRemoteRPCReady)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.foregroundMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func statusColor(_ provider: ModelProviderConfig) -> Color {
        if !provider.enabled { return palette.foregroundMuted.opacity(0.4) }
        return provider.executable ? palette.success : palette.warning
    }

    private func providerAvatar(for provider: ModelProviderConfig) -> some View {
        let symbol: String = {
            switch provider.logoKey.lowercased() {
            case let key where key.contains("zai"), let key where key.contains("zhipu"): return "sparkles"
            case let key where key.contains("bigmodel"): return "cpu.fill"
            case let key where key.contains("anthropic"): return "a.circle.fill"
            case let key where key.contains("openai"): return "circle.hexagongrid.fill"
            case let key where key.contains("openrouter"): return "arrow.triangle.branch"
            case let key where key.contains("deepseek"): return "waveform.path.ecg"
            default: return provider.isAccountProvider ? "sparkles" : "server.rack"
            }
        }()
        let tint = provider.isAccountProvider ? palette.accentBlue : palette.foregroundSubtle
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.13))
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(tint.opacity(0.30), lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Provider Detail & Connection Studio

struct ProviderDetailStudioView: View {
    @Bindable var store: AppStore
    let providerId: String
    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var draftName: String = ""
    @State private var draftBaseURL: String = ""
    @State private var draftFormat: ProviderAPIFormat = .anthropicMessages
    @State private var draftAPIKey: String = ""
    @State private var revealAPIKey: Bool = false
    @State private var isRenaming: Bool = false
    @State private var isSavingConnection: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var modelFilter: String = ""
    @State private var editingModel: ModelEditorTarget? = nil
    @State private var didLoadInitial: Bool = false
    @State private var pendingDeleteModelId: String? = nil

    struct ModelEditorTarget: Identifiable {
        let id = UUID()
        let originalModelId: String?
        let draft: ModelDescriptor
    }

    private var provider: ModelProviderConfig? {
        store.providers.first(where: { $0.id == providerId })
    }

    private var filteredModels: [ModelDescriptor] {
        guard let provider else { return [] }
        let q = modelFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return provider.models }
        return provider.models.filter { $0.modelId.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            if let provider {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(provider)

                        if provider.isAccountProvider {
                            accountPlanStatusCard(provider)
                        } else {
                            personalConnectionCard(provider)
                        }

                        modelsSectionCard(provider)

                        if !provider.issues.isEmpty {
                            ZCodeSettingsCard(title: "Configuration issues") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(provider.issues) { issue in
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 11))
                                                .foregroundStyle(palette.warning)
                                            Text(issue.message)
                                                .font(.system(size: 12))
                                                .foregroundStyle(palette.foregroundSubtle)
                                        }
                                    }
                                }
                                .padding(14)
                            }
                        }

                        if !provider.isAccountProvider {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete provider")
                                        .fontWeight(.semibold)
                                }
                                .font(.system(size: 14))
                                .foregroundStyle(palette.destructive)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(palette.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(palette.destructive.opacity(0.28), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!store.isRemoteRPCReady)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            } else {
                Text("Provider no longer exists.")
                    .foregroundStyle(palette.foregroundSubtle)
            }
        }
        .navigationTitle(provider?.name ?? "Provider")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDraftIfNeeded() }
        .onChange(of: provider?.revision) { _, _ in
            guard !isRenaming else { return }
            loadDraftIfNeeded(force: true)
        }
        .sheet(item: $editingModel) { target in
            ModelConfigEditorSheet(
                store: store,
                providerId: providerId,
                originalModelId: target.originalModelId,
                initialModel: target.draft
            )
        }
        .confirmationDialog(
            "Delete provider \"\(provider?.name ?? "")\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if await store.deleteProvider(providerId) { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the provider and its custom model settings.")
        }
        .confirmationDialog(
            "Delete model \"\(pendingDeleteModelId ?? "")\"?",
            isPresented: Binding(get: { pendingDeleteModelId != nil }, set: { if !$0 { pendingDeleteModelId = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let mid = pendingDeleteModelId {
                    Task { _ = await store.deleteModel(providerId: providerId, modelId: mid) }
                }
                pendingDeleteModelId = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteModelId = nil }
        }
    }

    private func header(_ provider: ModelProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if isRenaming {
                    TextField("Provider name", text: $draftName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.foreground)
                        .textFieldStyle(.plain)
                        .onSubmit { commitRename(provider) }
                        .submitLabel(.done)
                        .accessibilityIdentifier("providerNameField")
                } else {
                    Text(provider.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.foreground)
                }

                Spacer()

                if !provider.isAccountProvider {
                    Toggle("", isOn: Binding(
                        get: { provider.enabled },
                        set: { newValue in
                            Task { _ = await store.saveProviderMeta(providerId: provider.id, enabled: newValue) }
                        }
                    ))
                    .labelsHidden()
                    .tint(palette.accentBlue)
                    .disabled(!store.isRemoteRPCReady)

                    Menu {
                        Button {
                            draftName = provider.name
                            isRenaming = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 30, height: 30)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .disabled(!store.isRemoteRPCReady)
                }
            }

            Text(provider.isAccountProvider
                 ? "Managed Z.ai / BigModel Coding Plan entitlement and built-in model availability."
                 : "Configure API format, endpoint URL, authentication key, and model capabilities.")
                .font(.system(size: 13))
                .foregroundStyle(palette.foregroundSubtle)
                .fixedSize(horizontal: false, vertical: true)

            if isRenaming {
                HStack(spacing: 8) {
                    Button("Save") { commitRename(provider) }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.brandForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Button("Cancel") {
                        isRenaming = false
                        draftName = provider.name
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.foregroundSubtle)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commitRename(_ provider: ModelProviderConfig) {
        let name = draftName
        isRenaming = false
        Task { _ = await store.saveProviderMeta(providerId: provider.id, name: name) }
    }

    private func loadDraftIfNeeded(force: Bool = false) {
        guard let p = provider else { return }
        if didLoadInitial && !force { return }
        didLoadInitial = true
        draftName = p.name
        draftBaseURL = p.baseURL
        draftFormat = p.apiFormat
        // The host returns the plaintext key; the renderer masks it with a reveal toggle.
        draftAPIKey = p.apiKey
        revealAPIKey = false
    }

    private func accountPlanStatusCard(_ provider: ModelProviderConfig) -> some View {
        ZCodeSettingsCard(
            title: "Plan & authentication status",
            subtitle: "Uses your Z.AI account session without a manual API key."
        ) {
            ZCodeSettingsRow(
                title: "Account session",
                subtitle: store.zaiAccount?.displayName ?? "Sign in with Z.AI in Remote devices to activate plan entitlements"
            ) {
                ZCodeSettingsPill(
                    text: provider.entitled ? "Entitled" : "Not subscribed",
                    tone: provider.entitled ? .success : .neutral
                )
            }

            Divider().overlay(palette.border)

            ZCodeSettingsRow(title: "Base URL", subtitle: provider.baseURL.isEmpty ? "Not reported" : provider.baseURL) {
                HStack(spacing: 4) {
                    Image(systemName: "lock")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Read-only")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(palette.foregroundMuted)
            }

            Divider().overlay(palette.border)

            ZCodeSettingsRow(title: "API format", subtitle: provider.apiFormat.displayName) {
                EmptyView()
            }

            if let urlStr = provider.apiKeyManagementURL, let url = URL(string: urlStr) {
                Divider().overlay(palette.border)
                Button {
                    openURL(url)
                } label: {
                    HStack {
                        Text("Manage Coding Plan subscription")
                            .font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(palette.accentBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func personalConnectionCard(_ provider: ModelProviderConfig) -> some View {
        ZCodeSettingsCard(
            title: "Connection & API credentials",
            subtitle: "Values are stored on your ZCode Desktop host; the API key is shown only here."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base URL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    TextField("https://api.example.com/v1", text: $draftBaseURL)
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("API format")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    ZCodeSettingsSelect(
                        options: ProviderAPIFormat.allCases.map {
                            ZCodeSettingsSelectOption(value: $0, label: $0.displayName)
                        },
                        selection: $draftFormat
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("API key")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.foregroundSubtle)
                        Spacer()
                        if let keyUrlStr = provider.apiKeyManagementURL, let keyUrl = URL(string: keyUrlStr) {
                            Button {
                                openURL(keyUrl)
                            } label: {
                                HStack(spacing: 3) {
                                    Text("Get API key")
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.accentBlue)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        Group {
                            if revealAPIKey {
                                TextField("Enter API key", text: $draftAPIKey)
                            } else {
                                SecureField("Enter API key", text: $draftAPIKey)
                            }
                        }
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            revealAPIKey.toggle()
                        } label: {
                            Image(systemName: revealAPIKey ? "eye.slash" : "eye")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.foregroundSubtle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(revealAPIKey ? "Hide API key" : "Reveal API key")

                        Button {
                            UIPasteboard.general.string = draftAPIKey
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(palette.foregroundSubtle)
                        }
                        .buttonStyle(.plain)
                        .disabled(draftAPIKey.isEmpty)
                        .accessibilityLabel("Copy API key")
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))

                    if draftAPIKey.isEmpty && provider.apiKey.isEmpty {
                        Text("No API key configured.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.warning)
                    }
                }

                Button {
                    saveConnection(provider)
                } label: {
                    HStack(spacing: 6) {
                        if isSavingConnection { ProgressView().controlSize(.mini) }
                        Text(isSavingConnection ? "Saving…" : "Save")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(palette.brandForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(palette.brand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSavingConnection || !store.isRemoteRPCReady)
                .accessibilityIdentifier("saveProviderConnectionButton")
            }
            .padding(14)
        }
    }

    private func saveConnection(_ provider: ModelProviderConfig) {
        let keyToSend: String? = draftAPIKey == provider.apiKey ? nil : draftAPIKey
        isSavingConnection = true
        Task {
            let ok = await store.saveProviderConnection(
                providerId: provider.id,
                name: draftName,
                baseURL: draftBaseURL,
                apiFormat: draftFormat,
                apiKey: keyToSend
            )
            await MainActor.run { isSavingConnection = false }
            if ok, let refreshed = store.providers.first(where: { $0.id == provider.id }) {
                draftAPIKey = refreshed.apiKey
                draftBaseURL = refreshed.baseURL
                draftFormat = refreshed.apiFormat
                draftName = refreshed.name
            }
        }
    }

    private func modelsSectionCard(_ provider: ModelProviderConfig) -> some View {
        ZCodeSettingsCard(
            title: "Model list",
            subtitle: "Models exposed to chat. Test connectivity, toggle availability, or edit capabilities."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZCodeSettingsSearchBar(text: $modelFilter, placeholder: "Filter models…")

                    if !provider.isAccountProvider {
                        Button {
                            editingModel = ModelEditorTarget(
                                originalModelId: nil,
                                draft: ModelDescriptor(
                                    id: "",
                                    modelId: "",
                                    name: "",
                                    providerId: provider.id,
                                    providerName: provider.name,
                                    enabled: true,
                                    builtin: false,
                                    useRecommendedConfig: true,
                                    contextWindowTokens: 0,
                                    maxOutputTokens: 0,
                                    supportsVision: false,
                                    supportsVideo: false,
                                    supportsAudio: false,
                                    supportsPdf: false,
                                    supportsToolCall: true,
                                    supportsReasoning: false,
                                    supportsJsonSchemaOutput: false,
                                    supportsNativeWebSearch: false,
                                    supportsMidConversationSystem: false,
                                    reasoningLevels: [],
                                    badge: nil
                                )
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11.5, weight: .bold))
                                Text("Add model")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(palette.brandForeground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(palette.brand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.isRemoteRPCReady)
                        .accessibilityIdentifier("addModelButton")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                if filteredModels.isEmpty {
                    Text(provider.models.isEmpty
                         ? "No models are configured. Add a model to use it in chat."
                         : "No matching models.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredModels.enumerated()), id: \.element.id) { idx, model in
                            modelRow(provider: provider, model: model, index: idx, count: filteredModels.count)
                            if idx < filteredModels.count - 1 {
                                Divider().overlay(palette.border).padding(.horizontal, 14)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func modelRow(provider: ModelProviderConfig, model: ModelDescriptor, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.modelId)
                            .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                        if model.supportsVision {
                            ZCodeSettingsPill(text: "Image", tone: .neutral)
                        }
                        if !model.reasoningLevels.isEmpty {
                            ZCodeSettingsPill(text: "Thinking", tone: .neutral)
                        }
                    }

                    HStack(spacing: 5) {
                        if model.contextWindowTokens > 0 {
                            ZCodeSettingsPill(text: "Context window: \(model.formattedContextWindow)", tone: .neutral)
                        }
                        if model.maxOutputTokens > 0 {
                            ZCodeSettingsPill(text: "Max output: \(model.maxOutputTokens)", tone: .neutral)
                        }
                        if !model.enabled {
                            ZCodeSettingsPill(text: "Disabled", tone: .neutral)
                        }
                        if !model.executable && model.enabled {
                            ZCodeSettingsPill(text: "Not ready", tone: .warning)
                        }
                    }
                }

                Spacer(minLength: 6)

                Toggle("", isOn: Binding(
                    get: { model.enabled },
                    set: { newValue in
                        Task { _ = await store.setModelEnabled(providerId: provider.id, modelId: model.modelId, enabled: newValue) }
                    }
                ))
                .labelsHidden()
                .tint(palette.accentBlue)
                .disabled(!store.isRemoteRPCReady)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await store.testModelConnectivity(providerId: provider.id, modelId: model.modelId) }
                } label: {
                    HStack(spacing: 5) {
                        if model.connectivityState == .testing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.horizontal.circle")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        Text(model.connectivityState == .testing ? "Testing…" : "Test")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(palette.foreground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!store.isRemoteRPCReady || !provider.enabled || model.connectivityState == .testing)
                .accessibilityLabel(provider.enabled ? "Test model" : "Enable provider first")

                if let connMsg = model.connectivityMessage, model.connectivityState != .testing {
                    ZCodeSettingsPill(
                        text: connMsg,
                        tone: model.connectivityState == .connected ? .success : (model.connectivityState == .failed ? .danger : .neutral)
                    )
                }

                Spacer()

                if !provider.isAccountProvider {
                    Button {
                        editingModel = ModelEditorTarget(originalModelId: model.modelId, draft: model)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 28, height: 26)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.isRemoteRPCReady)
                    .accessibilityLabel("Edit model")

                    if !model.builtin {
                        Button(role: .destructive) {
                            pendingDeleteModelId = model.modelId
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.destructive)
                                .frame(width: 28, height: 26)
                                .background(palette.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.isRemoteRPCReady)
                    }

                    HStack(spacing: 2) {
                        Button {
                            Task { await store.moveModel(providerId: provider.id, modelId: model.modelId, direction: -1) }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(palette.foregroundSubtle)
                                .frame(width: 22, height: 24)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0 || !store.isRemoteRPCReady)

                        Button {
                            Task { await store.moveModel(providerId: provider.id, modelId: model.modelId, direction: 1) }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(palette.foregroundSubtle)
                                .frame(width: 22, height: 24)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == count - 1 || !store.isRemoteRPCReady)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Add Provider Template Picker (host `providerTemplates` only)

struct AddProviderTemplateSheet: View {
    @Bindable var store: AppStore
    var onCreated: (String) -> Void

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var creatingTemplateId: String? = nil
    @State private var isCreatingCustom: Bool = false

    private func filtered(_ list: [ProviderTemplateDescriptor]) -> [ProviderTemplateDescriptor] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return list }
        return list.filter { $0.displayName().localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
    }

    private var zhipuTemplates: [ProviderTemplateDescriptor] {
        filtered(store.providerTemplates.filter(\.isZhipuFamily))
    }

    private var otherTemplates: [ProviderTemplateDescriptor] {
        filtered(store.providerTemplates.filter { !$0.isZhipuFamily })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ZCodeSettingsSearchBar(text: $query, placeholder: "Search provider templates…")

                        Button {
                            createCustom()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(palette.accentBlue.opacity(0.14))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "plus.square.dashed")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(palette.accentBlue)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Custom endpoint")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(palette.foreground)
                                    Text("Connect any Anthropic Messages or OpenAI-compatible endpoint")
                                        .font(.system(size: 12))
                                        .foregroundStyle(palette.foregroundSubtle)
                                }
                                Spacer()
                                if isCreatingCustom {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundMuted)
                                }
                            }
                            .padding(13)
                            .background(palette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.borderStrong, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(creatingTemplateId != nil || isCreatingCustom || !store.isRemoteRPCReady)
                        .accessibilityIdentifier("createCustomProviderButton")

                        if store.providerTemplates.isEmpty {
                            ZCodeSettingsCard {
                                Text("The host did not report any provider templates. Add a custom endpoint instead.")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .padding(14)
                            }
                        }

                        if !zhipuTemplates.isEmpty {
                            ZCodeSettingsCard(title: "Zhipu") {
                                ForEach(Array(zhipuTemplates.enumerated()), id: \.element.id) { idx, tpl in
                                    templateRow(tpl)
                                    if idx < zhipuTemplates.count - 1 {
                                        Divider().overlay(palette.border).padding(.leading, 52)
                                    }
                                }
                            }
                        }

                        if !otherTemplates.isEmpty {
                            ZCodeSettingsCard(title: "Other") {
                                ForEach(Array(otherTemplates.enumerated()), id: \.element.id) { idx, tpl in
                                    templateRow(tpl)
                                    if idx < otherTemplates.count - 1 {
                                        Divider().overlay(palette.border).padding(.leading, 52)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Add provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }

    private func templateRow(_ tpl: ProviderTemplateDescriptor) -> some View {
        Button {
            create(template: tpl)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.accentBlue.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: tpl.isZhipuFamily ? "sparkles" : "server.rack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accentBlue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tpl.displayName())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text(tpl.apiFormat.displayName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                }
                Spacer()
                if creatingTemplateId == tpl.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.foregroundMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(creatingTemplateId != nil || isCreatingCustom || !store.isRemoteRPCReady)
        .accessibilityIdentifier("providerTemplate_\(tpl.id)")
    }

    private func create(template: ProviderTemplateDescriptor) {
        creatingTemplateId = template.id
        Task {
            let id = await store.createProvider(template: template, customName: template.displayName())
            await MainActor.run {
                creatingTemplateId = nil
                if let id {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onCreated(id) }
                }
            }
        }
    }

    private func createCustom() {
        isCreatingCustom = true
        Task {
            let id = await store.createProvider(template: nil, customName: "New provider")
            await MainActor.run {
                isCreatingCustom = false
                if let id {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onCreated(id) }
                }
            }
        }
    }
}

// MARK: - Add / Edit Model Configuration (1:1 host `ModelConfig` shape)

struct ModelConfigEditorSheet: View {
    @Bindable var store: AppStore
    let providerId: String
    let originalModelId: String?
    @State var initialModel: ModelDescriptor

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var contextText: String = ""
    @State private var maxOutputText: String = ""
    @State private var newReasoningLevel: String = ""
    @State private var validationMessage: String? = nil
    @State private var isSaving: Bool = false
    @State private var smartStatus: String? = nil
    @State private var didCaptureOriginal: Bool = false
    @State private var originalSnapshot: ModelDescriptor? = nil
    @State private var resolveTask: Task<Void, Never>? = nil

    private var provider: ModelProviderConfig? {
        store.providers.first(where: { $0.id == providerId })
    }

    private var modelIdReadOnly: Bool {
        initialModel.builtin
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ZCodeSettingsCard(
                            title: originalModelId == nil ? "Add model" : "Model configuration",
                            subtitle: "Configure the model identifier, token limits, modalities and reasoning levels."
                        ) {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Model ID")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    TextField("Model ID", text: $initialModel.modelId)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundStyle(modelIdReadOnly ? palette.foregroundSubtle : palette.foreground)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .disabled(modelIdReadOnly)
                                        .padding(10)
                                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                                        .onSubmit { resolveRecommendedIfNeeded() }
                                }

                                Toggle(isOn: $initialModel.useRecommendedConfig) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Smart configuration")
                                            .font(.system(size: 13.5, weight: .medium))
                                            .foregroundStyle(palette.foreground)
                                        Text("Match ZCode's built-in capability and token defaults for this model ID.")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(palette.foregroundSubtle)
                                    }
                                }
                                .tint(palette.accentBlue)
                                .onChange(of: initialModel.useRecommendedConfig) { _, on in
                                    if on { resolveRecommendedIfNeeded() } else { smartStatus = nil }
                                }

                                if let smartStatus {
                                    Text(smartStatus)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(palette.success)
                                }

                                Divider().overlay(palette.border)

                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Context window")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.foregroundSubtle)
                                        TextField(inheritedContextPlaceholder, text: $contextText)
                                            .keyboardType(.numberPad)
                                            .font(.system(size: 14, design: .monospaced))
                                            .padding(10)
                                            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                                    }

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Max output tokens")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.foregroundSubtle)
                                        TextField(inheritedMaxOutputPlaceholder, text: $maxOutputText)
                                            .keyboardType(.numberPad)
                                            .font(.system(size: 14, design: .monospaced))
                                            .padding(10)
                                            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                                    }
                                }
                            }
                            .padding(14)
                        }

                        ZCodeSettingsCard(
                            title: "Advanced settings",
                            subtitle: "Input types, capabilities, and reasoning level mapping."
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Input types")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                                HStack(spacing: 8) {
                                    ZCodeSettingsPill(text: "Text (required)", tone: .success)
                                    modalityToggle("Image", isOn: $initialModel.supportsVision)
                                    modalityToggle("Video", isOn: $initialModel.supportsVideo)
                                    modalityToggle("PDF", isOn: $initialModel.supportsPdf)
                                }

                                Divider().overlay(palette.border)

                                Text("Model capabilities")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                                Toggle("Structured output", isOn: $initialModel.supportsJsonSchemaOutput)
                                    .font(.system(size: 13))
                                    .tint(palette.accentBlue)
                                Toggle("Native web search", isOn: $initialModel.supportsNativeWebSearch)
                                    .font(.system(size: 13))
                                    .tint(palette.accentBlue)
                                Toggle("Mid-conversation system messages", isOn: $initialModel.supportsMidConversationSystem)
                                    .font(.system(size: 13))
                                    .tint(palette.accentBlue)

                                Divider().overlay(palette.border)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Reasoning levels (low to high)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    Text("Order matters: the highest level is the default. Levels must be non-empty and unique.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.foregroundMuted)

                                    if initialModel.reasoningLevels.isEmpty {
                                        Text("This model exposes no reasoning levels.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(palette.foregroundMuted)
                                    } else {
                                        ForEach(Array(initialModel.reasoningLevels.enumerated()), id: \.offset) { idx, level in
                                            HStack(spacing: 8) {
                                                Text("\(idx + 1)")
                                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                                    .foregroundStyle(palette.foregroundMuted)
                                                    .frame(width: 18)
                                                Text(level)
                                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                                    .foregroundStyle(palette.foreground)
                                                Spacer()
                                                Button {
                                                    guard idx > 0 else { return }
                                                    initialModel.reasoningLevels.swapAt(idx, idx - 1)
                                                } label: {
                                                    Image(systemName: "chevron.up")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundStyle(idx == 0 ? palette.foregroundMuted.opacity(0.35) : palette.foregroundSubtle)
                                                        .frame(width: 26, height: 24)
                                                }
                                                .buttonStyle(.plain)
                                                .disabled(idx == 0)

                                                Button {
                                                    guard idx < initialModel.reasoningLevels.count - 1 else { return }
                                                    initialModel.reasoningLevels.swapAt(idx, idx + 1)
                                                } label: {
                                                    Image(systemName: "chevron.down")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundStyle(idx == initialModel.reasoningLevels.count - 1 ? palette.foregroundMuted.opacity(0.35) : palette.foregroundSubtle)
                                                        .frame(width: 26, height: 24)
                                                }
                                                .buttonStyle(.plain)
                                                .disabled(idx == initialModel.reasoningLevels.count - 1)

                                                Button(role: .destructive) {
                                                    initialModel.reasoningLevels.remove(at: idx)
                                                    initialModel.supportsReasoning = !initialModel.reasoningLevels.isEmpty
                                                } label: {
                                                    Image(systemName: "trash")
                                                        .font(.system(size: 11.5))
                                                        .foregroundStyle(palette.destructive)
                                                        .frame(width: 26, height: 24)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        TextField("Add level (e.g. medium)", text: $newReasoningLevel)
                                            .font(.system(size: 13, design: .monospaced))
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .padding(9)
                                            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                                        Button("Add") { addReasoningLevel() }
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(palette.brandForeground)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 9)
                                            .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .buttonStyle(.plain)
                                            .disabled(newReasoningLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }

                                    Text("Reasoning parameter mapping")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    TextEditor(text: $initialModel.reasoningMap)
                                        .font(.system(size: 12, design: .monospaced))
                                        .scrollContentBackground(.hidden)
                                        .frame(minHeight: 90)
                                        .padding(8)
                                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                                    Text("Opaque host expression used to map the selected level to provider parameters.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.foregroundMuted)
                                }
                            }
                            .padding(14)
                        }

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.destructive)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(originalModelId == nil ? "Add model" : initialModel.modelId)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView().controlSize(.small) }
                        else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("saveModelConfigButton")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset form") { resetForm() }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.accentBlue)
                        .disabled(isSaving)
                }
            }
            .onAppear {
                if !didCaptureOriginal {
                    didCaptureOriginal = true
                    originalSnapshot = initialModel
                    contextText = initialModel.contextWindowTokens > 0 ? String(initialModel.contextWindowTokens) : ""
                    maxOutputText = initialModel.maxOutputTokens > 0 ? String(initialModel.maxOutputTokens) : ""
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }

    private var inheritedContextPlaceholder: String {
        if let provider, let current = provider.models.first(where: { $0.modelId == originalModelId || $0.modelId == initialModel.modelId }), current.contextWindowTokens > 0 {
            return String(current.contextWindowTokens)
        }
        return "Inherited"
    }

    private var inheritedMaxOutputPlaceholder: String {
        if let provider, let current = provider.models.first(where: { $0.modelId == originalModelId || $0.modelId == initialModel.modelId }), current.maxOutputTokens > 0 {
            return String(current.maxOutputTokens)
        }
        return "Inherited"
    }

    private func modalityToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isOn.wrappedValue ? palette.accentBlue : palette.foregroundSubtle)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isOn.wrappedValue ? palette.accentBlue.opacity(0.13) : palette.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func addReasoningLevel() {
        let level = newReasoningLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !level.isEmpty else { return }
        guard !initialModel.reasoningLevels.contains(level) else {
            validationMessage = "Reasoning levels must be unique."
            return
        }
        initialModel.reasoningLevels.append(level)
        initialModel.supportsReasoning = true
        newReasoningLevel = ""
        validationMessage = nil
    }

    private func resetForm() {
        guard let originalSnapshot else { return }
        initialModel = originalSnapshot
        contextText = initialModel.contextWindowTokens > 0 ? String(initialModel.contextWindowTokens) : ""
        maxOutputText = initialModel.maxOutputTokens > 0 ? String(initialModel.maxOutputTokens) : ""
        validationMessage = nil
    }

    private func resolveRecommendedIfNeeded() {
        guard initialModel.useRecommendedConfig, store.isRemoteRPCReady else { return }
        let modelId = initialModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return }
        resolveTask?.cancel()
        resolveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            guard let resolved = await store.resolveModelConfig(
                providerId: providerId,
                modelId: modelId,
                originalModelId: originalModelId,
                personalConfig: nil
            ) else { return }
            guard let effective = resolved["effectiveConfig"] as? [String: Any] else { return }
            await MainActor.run {
                applyResolvedConfig(effective)
                smartStatus = "Smart configuration matched for this model"
            }
        }
    }

    private func applyResolvedConfig(_ config: [String: Any]) {
        let props = (config["properties"] as? [String: Any]) ?? [:]
        let inFmt = (props["inputFormat"] as? [String: Any]) ?? [:]
        let opt = (config["optionSpecs"] as? [String: Any]) ?? [:]
        let rSpec = (opt["reasoningLevel"] as? [String: Any]) ?? [:]
        let maxSpec = (opt["maxOutputTokens"] as? [String: Any]) ?? [:]
        if let ctx = props["contextWindow"] as? Int, ctx > 0 {
            initialModel.contextWindowTokens = ctx
            contextText = String(ctx)
        }
        if let maxOut = maxSpec["max"] as? Int, maxOut > 0 {
            initialModel.maxOutputTokens = maxOut
            maxOutputText = String(maxOut)
        }
        initialModel.maxOutputTokensMap = (maxSpec["map"] as? String) ?? initialModel.maxOutputTokensMap
        initialModel.supportsVision = (inFmt["supportsImage"] as? Bool) ?? initialModel.supportsVision
        initialModel.supportsVideo = (inFmt["supportsVideo"] as? Bool) ?? initialModel.supportsVideo
        initialModel.supportsPdf = (inFmt["supportsPdf"] as? Bool) ?? initialModel.supportsPdf
        initialModel.supportsAudio = (inFmt["supportsAudio"] as? Bool) ?? initialModel.supportsAudio
        initialModel.supportsToolCall = (props["supportsToolCall"] as? Bool) ?? initialModel.supportsToolCall
        initialModel.supportsJsonSchemaOutput = (props["supportsJsonSchemaOutput"] as? Bool) ?? initialModel.supportsJsonSchemaOutput
        initialModel.supportsNativeWebSearch = (props["supportsNativeWebSearch"] as? Bool) ?? initialModel.supportsNativeWebSearch
        initialModel.supportsMidConversationSystem = (props["supportsMidConversationSystem"] as? Bool) ?? initialModel.supportsMidConversationSystem
        initialModel.requiresMfjsToolSchema = (props["requiresMfjsToolSchema"] as? Bool) ?? initialModel.requiresMfjsToolSchema
        if let values = rSpec["values"] as? [String], !values.isEmpty {
            initialModel.reasoningLevels = values
            initialModel.supportsReasoning = true
        }
        if let map = rSpec["map"] as? String, !map.isEmpty {
            initialModel.reasoningMap = map
        }
    }

    private func save() {
        validationMessage = nil
        let cleanId = initialModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else {
            validationMessage = "Model ID is required."
            return
        }
        if let ctx = Int(contextText.trimmingCharacters(in: .whitespacesAndNewlines)), ctx > 0 {
            initialModel.contextWindowTokens = ctx
        } else {
            validationMessage = "Context window is required and must be a positive number."
            return
        }
        if let maxOut = Int(maxOutputText.trimmingCharacters(in: .whitespacesAndNewlines)), maxOut > 0 {
            initialModel.maxOutputTokens = maxOut
        } else if maxOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            initialModel.maxOutputTokens = 0
        } else {
            validationMessage = "Max output tokens must be a positive number."
            return
        }
        if !initialModel.reasoningLevels.isEmpty {
            guard initialModel.reasoningLevels.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                validationMessage = "Reasoning levels must be non-empty."
                return
            }
            guard Set(initialModel.reasoningLevels).count == initialModel.reasoningLevels.count else {
                validationMessage = "Reasoning levels must be unique."
                return
            }
            guard !initialModel.reasoningMap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                validationMessage = "Reasoning level mapping is required when levels are configured."
                return
            }
        }
        initialModel.modelId = cleanId
        isSaving = true
        Task {
            let ok = await store.upsertModel(providerId: providerId, originalModelId: originalModelId, draft: initialModel)
            await MainActor.run {
                isSaving = false
                if ok { dismiss() }
            }
        }
    }
}
