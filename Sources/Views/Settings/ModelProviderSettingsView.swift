import SwiftUI
import UIKit

// MARK: - 1:1 ZCode v3.16.3 Model & Provider Management (`modelProvider`)

struct ModelProviderSettingsView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @Environment(\.openURL) private var openURL

    @State private var searchText: String = ""
    @State private var showAddProviderSheet: Bool = false
    @State private var selectedProviderIdForPush: String? = nil

    private var accountProviders: [ModelProviderConfig] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.providers.filter { p in
            guard p.isAccountProvider else { return false }
            guard !q.isEmpty else { return true }
            return p.name.localizedCaseInsensitiveContains(q)
                || p.models.contains(where: { $0.modelId.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) })
        }
    }

    private var personalProviders: [ModelProviderConfig] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.providers.filter { p in
            guard !p.isAccountProvider else { return false }
            guard !q.isEmpty else { return true }
            return p.name.localizedCaseInsensitiveContains(q)
                || p.baseURL.localizedCaseInsensitiveContains(q)
                || p.models.contains(where: { $0.modelId.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZCodeSettingsPageHeader(
                    groupTitle: "Basics",
                    title: "Model settings",
                    subtitle: "Manage built-in Z.ai Coding Plans and custom model providers. Enabled models appear immediately in the chat model picker."
                ) {
                    Button {
                        showAddProviderSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("Add Provider")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(palette.brandForeground)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addProviderButton")
                }

                ZCodeSettingsSearchBar(
                    text: $searchText,
                    placeholder: "Search providers or model IDs (e.g. GLM-5.3, claude-opus, gpt-5.4)…"
                )

                // Group 1: Built-in Z.ai / BigModel Account Providers
                if !accountProviders.isEmpty {
                    ZCodeSettingsCard(
                        title: "Z.ai & Official Account Plans",
                        subtitle: "Authenticated via your signed-in Z.AI account session."
                    ) {
                        ForEach(Array(accountProviders.enumerated()), id: \.element.id) { idx, provider in
                            NavigationLink {
                                ProviderDetailStudioView(store: store, providerId: provider.id)
                            } label: {
                                providerRowContent(provider: provider, isPersonal: false, indexInPersonal: 0, totalPersonal: 0)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("providerRow_\(provider.id)")

                            if idx < accountProviders.count - 1 {
                                Divider().overlay(palette.border).padding(.leading, 54)
                            }
                        }
                    }
                }

                // Group 2: Custom & Template Personal Providers
                ZCodeSettingsCard(
                    title: "Custom & API-Key Providers",
                    subtitle: "Configure Anthropic, OpenAI, OpenRouter, DeepSeek, Kimi, MiniMax, xAI, or private enterprise endpoints."
                ) {
                    if personalProviders.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "cpu")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(palette.foregroundMuted)
                            Text("No custom model providers configured yet.")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(palette.foregroundSubtle)
                            Button {
                                showAddProviderSheet = true
                            } label: {
                                Text("Add Provider from 17+ Official Templates")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.accentBlue)
                            }
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
                                    isPersonal: true,
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
        .navigationDestination(isPresented: Binding(
            get: { selectedProviderIdForPush != nil },
            set: { if !$0 { selectedProviderIdForPush = nil } }
        )) {
            if let pid = selectedProviderIdForPush {
                ProviderDetailStudioView(store: store, providerId: pid)
            }
        }
        .sheet(isPresented: $showAddProviderSheet) {
            AddProviderTemplateSheet(store: store) { createdId in
                selectedProviderIdForPush = createdId
            }
        }
    }

    private func providerRowContent(
        provider: ModelProviderConfig,
        isPersonal: Bool,
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
                            text: provider.entitled ? "Entitled" : "Plan Inactive",
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

                    Text("•")
                        .foregroundStyle(palette.foregroundMuted)

                    if provider.isAccountProvider {
                        Text(provider.statusText)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.foregroundSubtle)
                            .lineLimit(1)
                    } else {
                        Text(provider.hasConfiguredAPIKey ? "API key set" : "API key needed")
                            .font(.system(size: 12))
                            .foregroundStyle(provider.hasConfiguredAPIKey ? palette.success : palette.warning)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 6)

            if isPersonal && totalPersonal > 1 {
                HStack(spacing: 2) {
                    Button {
                        store.movePersonalProvider(providerId: provider.id, direction: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(indexInPersonal == 0 ? palette.foregroundMuted.opacity(0.35) : palette.foregroundSubtle)
                            .frame(width: 24, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(indexInPersonal == 0)

                    Button {
                        store.movePersonalProvider(providerId: provider.id, direction: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(indexInPersonal == totalPersonal - 1 ? palette.foregroundMuted.opacity(0.35) : palette.foregroundSubtle)
                            .frame(width: 24, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(indexInPersonal == totalPersonal - 1)
                }
            }

            Circle()
                .fill(provider.enabled ? palette.success : palette.foregroundMuted.opacity(0.4))
                .frame(width: 7, height: 7)

            Image(systemName: "chevron.right")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.foregroundMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func providerAvatar(for provider: ModelProviderConfig) -> some View {
        let matchedTemplate = ProviderTemplateDescriptor.officialCatalog.first(where: { $0.id == provider.templateId || $0.id == provider.id })
        let hex = matchedTemplate?.accentHex ?? (provider.isAccountProvider ? 0x3B82F6 : 0x6366F1)
        let symbol = matchedTemplate?.logoSymbol ?? (provider.isAccountProvider ? "sparkles" : "server.rack")
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: hex).opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(hex: hex).opacity(0.35), lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Color(hex: hex))
        }
    }
}

// MARK: - Provider Detail & Connection Studio (`ProviderDetailStudioView`)

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
    @State private var draftEnabled: Bool = true
    @State private var revealAPIKey: Bool = false
    @State private var modelFilter: String = ""
    @State private var editingModel: ModelEditorTarget? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var didLoadInitial: Bool = false

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
        return provider.models.filter {
            $0.modelId.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            if let provider {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ZCodeSettingsPageHeader(
                            groupTitle: "Model settings",
                            title: provider.name,
                            subtitle: provider.isAccountProvider
                                ? "Managed Z.ai / BigModel Coding Plan entitlement and built-in model availability."
                                : "Configure API format, endpoint URL, authentication key, and model capabilities."
                        ) {
                            Toggle("", isOn: Binding(
                                get: { provider.enabled },
                                set: { newVal in
                                    draftEnabled = newVal
                                    store.updateProviderConnection(
                                        providerId: provider.id,
                                        name: draftName.isEmpty ? provider.name : draftName,
                                        baseURL: draftBaseURL.isEmpty ? provider.baseURL : draftBaseURL,
                                        apiFormat: draftFormat,
                                        apiKey: nil,
                                        enabled: newVal
                                    )
                                }
                            ))
                            .labelsHidden()
                            .tint(palette.accentBlue)
                        }

                        if provider.isAccountProvider {
                            accountPlanStatusCard(provider)
                        } else {
                            personalConnectionCard(provider)
                        }

                        modelsSectionCard(provider)

                        if !provider.isAccountProvider {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Provider")
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
        .onAppear {
            guard !didLoadInitial, let p = provider else { return }
            didLoadInitial = true
            draftName = p.name
            draftBaseURL = p.baseURL
            draftFormat = p.apiFormat
            draftEnabled = p.enabled
            draftAPIKey = KeychainStore.load("provider_key_\(p.id)") ?? ""
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
            "Delete this provider and all its custom model settings?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Provider", role: .destructive) {
                store.deleteProvider(providerId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func accountPlanStatusCard(_ provider: ModelProviderConfig) -> some View {
        ZCodeSettingsCard(
            title: "Plan & Authentication Status",
            subtitle: "Uses your Z.AI OAuth session automatically without manual API keys."
        ) {
            ZCodeSettingsRow(
                title: "Account Session",
                subtitle: store.zaiAccount?.displayName ?? "Sign in with Z.AI in Remote Devices to activate plan entitlements"
            ) {
                ZCodeSettingsPill(
                    text: provider.entitled ? "Active" : "Not Entitled",
                    tone: provider.entitled ? .success : .warning
                )
            }

            Divider().overlay(palette.border)

            ZCodeSettingsRow(
                title: "Endpoint Base URL",
                subtitle: provider.baseURL
            ) {
                ZCodeSettingsPill(text: provider.apiFormat.shortBadge, tone: .neutral)
            }

            if let urlStr = provider.apiKeyManagementURL, let url = URL(string: urlStr) {
                Divider().overlay(palette.border)
                Button {
                    openURL(url)
                } label: {
                    HStack {
                        Text("Manage Coding Plan Subscription")
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
            title: "Connection & API Credentials",
            subtitle: "Stored encrypted in iOS Keychain and synced to ZCode Desktop when paired."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider Name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    TextField("Provider display name", text: $draftName)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.foreground)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Protocol Format")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    Picker("API Format", selection: $draftFormat) {
                        ForEach(ProviderAPIFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Endpoint Base URL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    TextField("https://api.anthropic.com/v1", text: $draftBaseURL)
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
                    HStack {
                        Text("API Key")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.foregroundSubtle)
                        Spacer()
                        if let keyUrlStr = provider.apiKeyManagementURL, let keyUrl = URL(string: keyUrlStr) {
                            Button {
                                openURL(keyUrl)
                            } label: {
                                HStack(spacing: 3) {
                                    Text("Get API Key")
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
                                TextField("sk-…", text: $draftAPIKey)
                            } else {
                                SecureField(provider.hasConfiguredAPIKey ? "•••••••••••••••• (Configured)" : "Paste API key (sk-…)", text: $draftAPIKey)
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

                        Button {
                            if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                                draftAPIKey = clip
                            }
                        } label: {
                            Text("Paste")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.foreground)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(palette.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                }

                Button {
                    store.updateProviderConnection(
                        providerId: provider.id,
                        name: draftName,
                        baseURL: draftBaseURL,
                        apiFormat: draftFormat,
                        apiKey: draftAPIKey.isEmpty && provider.hasConfiguredAPIKey ? nil : draftAPIKey,
                        enabled: provider.enabled
                    )
                } label: {
                    Text("Save Connection Settings")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.brandForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("saveProviderConnectionButton")
            }
            .padding(14)
        }
    }

    private func modelsSectionCard(_ provider: ModelProviderConfig) -> some View {
        ZCodeSettingsCard(
            title: "Models (\(provider.models.filter(\.enabled).count) enabled of \(provider.models.count))",
            subtitle: "Test live model connectivity, toggle availability, or configure context window, modalities, and reasoning levels."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZCodeSettingsSearchBar(text: $modelFilter, placeholder: "Filter models in \(provider.name)…")

                    if !provider.isAccountProvider {
                        Button {
                            editingModel = ModelEditorTarget(
                                originalModelId: nil,
                                draft: ModelDescriptor(
                                    id: "\(provider.id)/custom-model",
                                    modelId: "",
                                    name: "",
                                    providerId: provider.id,
                                    providerName: provider.name,
                                    enabled: true,
                                    builtin: false,
                                    useRecommendedConfig: true,
                                    contextWindowK: 200,
                                    maxOutputTokens: 32_768
                                )
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11.5, weight: .bold))
                                Text("Add Model")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(palette.brandForeground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(palette.brand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("addModelButton")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                if filteredModels.isEmpty {
                    Text("No matching models.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredModels.enumerated()), id: \.element.id) { idx, model in
                            modelRow(provider: provider, model: model)
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

    private func modelRow(provider: ModelProviderConfig, model: ModelDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.modelId)
                            .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                        if let badge = model.badge, !badge.isEmpty {
                            ZCodeSettingsPill(text: badge, tone: .accent)
                        }
                        if !model.useRecommendedConfig {
                            ZCodeSettingsPill(text: "Custom Rules", tone: .warning)
                        }
                    }

                    // Capability Badges Row (Context Window + Modalities + Reasoning)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ZCodeSettingsPill(text: "\(model.formattedContextWindow) ctx", tone: .neutral)
                            ZCodeSettingsPill(text: "\(max(1, model.maxOutputTokens / 1000))K out", tone: .neutral)
                            if model.supportsVision {
                                Label("Image", systemImage: "photo")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(palette.card, in: Capsule())
                            }
                            if model.supportsPdf {
                                ZCodeSettingsPill(text: "PDF", tone: .neutral)
                            }
                            if model.supportsVideo {
                                ZCodeSettingsPill(text: "Video", tone: .neutral)
                            }
                            if !model.reasoningLevels.isEmpty {
                                Label("Thinking (\(model.reasoningLevels.count))", systemImage: "brain")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(palette.card, in: Capsule())
                            }
                        }
                    }
                }

                Spacer(minLength: 6)

                Toggle("", isOn: Binding(
                    get: { model.enabled },
                    set: { store.setModelEnabled(providerId: provider.id, modelId: model.modelId, enabled: $0) }
                ))
                .labelsHidden()
                .tint(palette.accentBlue)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await store.testModelConnectivity(providerId: provider.id, modelId: model.modelId)
                    }
                } label: {
                    HStack(spacing: 5) {
                        if model.connectivityState == .testing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.horizontal.circle")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        Text("Test Connectivity")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(palette.foreground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                if let connMsg = model.connectivityMessage {
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
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Configure")
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if !model.builtin {
                        Button(role: .destructive) {
                            store.deleteModel(providerId: provider.id, modelId: model.modelId)
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
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Add Provider Template Picker Sheet (1:1 ZCode `BGn` Dialog)

struct AddProviderTemplateSheet: View {
    @Bindable var store: AppStore
    var onCreated: (String) -> Void

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var query: String = ""
    @State private var selectedTemplate: ProviderTemplateDescriptor? = nil
    @State private var isCustomMode: Bool = false

    @State private var providerName: String = ""
    @State private var apiFormat: ProviderAPIFormat = .anthropicMessages
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""

    private var zhipuTemplates: [ProviderTemplateDescriptor] {
        filterTemplates(ProviderTemplateDescriptor.officialCatalog.filter { $0.category == "zhipu" })
    }

    private var otherTemplates: [ProviderTemplateDescriptor] {
        filterTemplates(ProviderTemplateDescriptor.officialCatalog.filter { $0.category == "other" })
    }

    private func filterTemplates(_ list: [ProviderTemplateDescriptor]) -> [ProviderTemplateDescriptor] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.id.localizedCaseInsensitiveContains(q)
                || $0.defaultModelIds.contains(where: { $0.localizedCaseInsensitiveContains(q) })
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                if selectedTemplate != nil || isCustomMode {
                    configureSelectedTemplateView
                } else {
                    templateCatalogView
                }
            }
            .navigationTitle(selectedTemplate != nil || isCustomMode ? "Configure Provider" : "Add Model Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedTemplate != nil || isCustomMode {
                        Button("Back") {
                            selectedTemplate = nil
                            isCustomMode = false
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }

    private var templateCatalogView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZCodeSettingsSearchBar(text: $query, placeholder: "Search 17 official provider templates…")

                Button {
                    selectedTemplate = nil
                    isCustomMode = true
                    providerName = ""
                    apiFormat = .openaiChatCompletions
                    baseURL = "https://"
                    apiKey = ""
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.accentBlue.opacity(0.16))
                                .frame(width: 36, height: 36)
                            Image(systemName: "plus.square.dashed")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.accentBlue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create Custom Provider")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(palette.foreground)
                            Text("Connect any OpenAI-compatible, Anthropic Messages, vLLM, or Ollama endpoint")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.foregroundSubtle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    .padding(13)
                    .background(palette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("createCustomProviderButton")

                if !zhipuTemplates.isEmpty {
                    ZCodeSettingsCard(title: "Z.ai & BigModel Templates") {
                        ForEach(Array(zhipuTemplates.enumerated()), id: \.element.id) { idx, tpl in
                            templateRow(tpl)
                            if idx < zhipuTemplates.count - 1 {
                                Divider().overlay(palette.border).padding(.leading, 52)
                            }
                        }
                    }
                }

                if !otherTemplates.isEmpty {
                    ZCodeSettingsCard(title: "Model Providers") {
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

    private func templateRow(_ tpl: ProviderTemplateDescriptor) -> some View {
        Button {
            selectedTemplate = tpl
            isCustomMode = false
            providerName = tpl.name
            apiFormat = tpl.apiFormat
            baseURL = tpl.defaultBaseURL
            apiKey = ""
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: tpl.accentHex).opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: tpl.logoSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: tpl.accentHex))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tpl.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                        ZCodeSettingsPill(text: tpl.apiFormat.shortBadge, tone: .neutral)
                    }
                    Text("\(tpl.defaultModelIds.prefix(3).joined(separator: ", "))\(tpl.defaultModelIds.count > 3 ? " +\(tpl.defaultModelIds.count - 3)" : "")")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.foregroundMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("providerTemplate_\(tpl.id)")
    }

    private var configureSelectedTemplateView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZCodeSettingsCard(
                    title: selectedTemplate?.name ?? "Custom Provider",
                    subtitle: "Review endpoint defaults and enter your API key."
                ) {
                    VStack(alignment: .leading, spacing: 13) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Provider Name")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.foregroundSubtle)
                            TextField("e.g. Anthropic Production", text: $providerName)
                                .font(.system(size: 14))
                                .foregroundStyle(palette.foreground)
                                .padding(10)
                                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("API Format")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.foregroundSubtle)
                            Picker("API Format", selection: $apiFormat) {
                                ForEach(ProviderAPIFormat.allCases) { fmt in
                                    Text(fmt.displayName).tag(fmt)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Base URL")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.foregroundSubtle)
                            TextField("https://api.example.com/v1", text: $baseURL)
                                .font(.system(size: 13.5, design: .monospaced))
                                .foregroundStyle(palette.foreground)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("API Key")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                                Spacer()
                                if let uStr = selectedTemplate?.apiKeyURL, let u = URL(string: uStr) {
                                    Button("Get API Key ↗") { openURL(u) }
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(palette.accentBlue)
                                }
                            }
                            SecureField("sk-… (saved to Keychain)", text: $apiKey)
                                .font(.system(size: 13.5, design: .monospaced))
                                .foregroundStyle(palette.foreground)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                        }

                        if let tpl = selectedTemplate, !tpl.defaultModelIds.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Pre-configured Models (\(tpl.defaultModelIds.count))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foregroundSubtle)
                                Text(tpl.defaultModelIds.joined(separator: "  •  "))
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(palette.foregroundMuted)
                            }
                        }

                        Button {
                            let createdId = store.createProvider(
                                template: selectedTemplate,
                                customName: providerName,
                                baseURL: baseURL,
                                apiFormat: apiFormat,
                                apiKey: apiKey
                            )
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onCreated(createdId)
                            }
                        } label: {
                            Text("Create Provider")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(palette.brandForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(palette.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                        .accessibilityIdentifier("confirmCreateProviderButton")
                    }
                    .padding(14)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Add / Edit Model Configuration Sheet (1:1 ZCode `JHn` Dialog)

struct ModelConfigEditorSheet: View {
    @Bindable var store: AppStore
    let providerId: String
    let originalModelId: String?
    @State var initialModel: ModelDescriptor

    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var showAdvanced: Bool = true
    private let contextPresets: [Int] = [32_000, 64_000, 128_000, 200_000, 256_000, 1_000_000]
    private let outputPresets: [Int] = [8_192, 16_384, 32_768, 65_536]
    private let candidateReasoningLevels: [String] = ["off", "minimal", "low", "medium", "high", "max"]

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ZCodeSettingsCard(
                            title: originalModelId == nil ? "Add Model" : "Edit Model Configuration",
                            subtitle: "Configure model identifier, token limits, input modalities, and reasoning levels."
                        ) {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Model ID")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    TextField("e.g. claude-opus-5 or gpt-5.4", text: $initialModel.modelId)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundStyle(palette.foreground)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(10)
                                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Display Label (Optional)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)
                                    TextField("Defaults to Model ID", text: $initialModel.name)
                                        .font(.system(size: 14))
                                        .foregroundStyle(palette.foreground)
                                        .padding(10)
                                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.inputBorder, lineWidth: 1))
                                }

                                Toggle(isOn: $initialModel.useRecommendedConfig) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Follow Recommended Configuration")
                                            .font(.system(size: 13.5, weight: .medium))
                                            .foregroundStyle(palette.foreground)
                                        Text("Automatically inherit ZCode's built-in capability & token rules for known model IDs")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(palette.foregroundSubtle)
                                    }
                                }
                                .tint(palette.accentBlue)

                                Divider().overlay(palette.border)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Context Window")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.foregroundSubtle)
                                        Spacer()
                                        Text("\(initialModel.contextWindowTokens) tokens")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(palette.accentBlue)
                                    }
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(contextPresets, id: \.self) { val in
                                                let label = val >= 1_000_000 ? "1M" : "\(val / 1000)K"
                                                Button {
                                                    initialModel.contextWindowTokens = val
                                                } label: {
                                                    Text(label)
                                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                        .foregroundStyle(initialModel.contextWindowTokens == val ? palette.brandForeground : palette.foreground)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 6)
                                                        .background(
                                                            initialModel.contextWindowTokens == val ? palette.brand : palette.card,
                                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                        )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Max Output Tokens")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.foregroundSubtle)
                                        Spacer()
                                        Text("\(initialModel.maxOutputTokens) tokens")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(palette.accentBlue)
                                    }
                                    HStack(spacing: 6) {
                                        ForEach(outputPresets, id: \.self) { val in
                                            Button {
                                                initialModel.maxOutputTokens = val
                                            } label: {
                                                Text("\(val / 1024)K")
                                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                    .foregroundStyle(initialModel.maxOutputTokens == val ? palette.brandForeground : palette.foreground)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        initialModel.maxOutputTokens == val ? palette.brand : palette.card,
                                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(14)
                        }

                        // Collapsible Advanced Configuration (`inputFormat`, `capabilities`, `optionSpecs.reasoningLevel`)
                        ZCodeSettingsCard(
                            title: "Advanced Capabilities & Modalities",
                            subtitle: "Fine-tune multimodal inputs, tool calling, structured output, and reasoning levels."
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    ZCodeSettingsPill(text: "Text Input (Locked ON)", tone: .success)
                                    Spacer()
                                }

                                Toggle("Image / Vision Input", isOn: $initialModel.supportsVision)
                                    .font(.system(size: 13.5))
                                    .tint(palette.accentBlue)
                                Toggle("PDF Document Input", isOn: $initialModel.supportsPdf)
                                    .font(.system(size: 13.5))
                                    .tint(palette.accentBlue)
                                Toggle("Video Input", isOn: $initialModel.supportsVideo)
                                    .font(.system(size: 13.5))
                                    .tint(palette.accentBlue)
                                Toggle("Audio Input", isOn: $initialModel.supportsAudio)
                                    .font(.system(size: 13.5))
                                    .tint(palette.accentBlue)

                                Divider().overlay(palette.border)

                                Toggle("Tool / Function Calling", isOn: $initialModel.supportsToolCall)
                                    .font(.system(size: 13.5))
                                    .tint(palette.accentBlue)
                                Toggle("JSON Schema Structured Output", isOn: $initialModel.supportsJsonSchemaOutput)
                                    .font(.system(size: 13.5))
                                    .tint(palette.accentBlue)
                                Toggle("Native Web Search", isOn: $initialModel.supportsNativeWebSearch)
                                    .font(.system(size: 13.5))
                                    .tint(palette.accentBlue)
                                Toggle("Mid-Conversation System Instructions", isOn: $initialModel.supportsMidConversationSystem)
                                    .font(.system(size: 13.5))
                                    .tint(palette.accentBlue)

                                Divider().overlay(palette.border)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Supported Reasoning Effort Levels")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.foregroundSubtle)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(candidateReasoningLevels, id: \.self) { level in
                                                let active = initialModel.reasoningLevels.contains(level)
                                                Button {
                                                    if active {
                                                        initialModel.reasoningLevels.removeAll { $0 == level }
                                                    } else {
                                                        initialModel.reasoningLevels.append(level)
                                                    }
                                                    initialModel.supportsReasoning = !initialModel.reasoningLevels.isEmpty
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                                            .font(.system(size: 11))
                                                        Text(level)
                                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                    }
                                                    .foregroundStyle(active ? palette.accentBlue : palette.foregroundSubtle)
                                                    .padding(.horizontal, 9)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        active ? palette.accentBlue.opacity(0.15) : palette.card,
                                                        in: Capsule()
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(14)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(originalModelId == nil ? "Add Model" : initialModel.modelId)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let cleanId = initialModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanId.isEmpty else { return }
                        initialModel.modelId = cleanId
                        if initialModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            initialModel.name = cleanId
                        }
                        store.upsertModel(providerId: providerId, originalModelId: originalModelId, draft: initialModel)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(initialModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveModelConfigButton")
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}
