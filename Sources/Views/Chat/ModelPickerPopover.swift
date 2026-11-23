import SwiftUI

struct ModelPickerItem: Identifiable, Equatable {
    let id: String
    let providerId: String
    let providerName: String
    let modelId: String
    let displayName: String
    let supportsVision: Bool
    let reasoningLevels: [String]
}

struct ModelPickerProviderGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let badgeText: String
    let models: [ModelPickerItem]
}

struct ModelPickerPopover: View {
    let groups: [ModelPickerProviderGroup]
    let activeProviderId: String?
    let activeModelId: String
    let activeReasoningLevels: [String]
    let activeReasoningLevel: String
    let isLoading: Bool
    let onSelectModel: (ModelPickerItem) -> Void
    let onSelectReasoningLevel: (String) -> Void
    let onManageModels: () -> Void

    @Environment(\.zcodePalette) private var palette
    @State private var showingProviderList: Bool = false
    @State private var browsingProviderId: String? = nil

    private var cardFill: Color {
        palette.isDark ? Color(red: 0.129, green: 0.129, blue: 0.129) : palette.menuBackground
    }

    private var rowHighlight: Color {
        palette.isDark ? Color(red: 0.185, green: 0.185, blue: 0.185) : palette.surfaceHover
    }

    private var resolvedActiveProviderId: String? {
        if let activeProviderId, !activeProviderId.isEmpty,
           groups.contains(where: { $0.id == activeProviderId }) {
            return activeProviderId
        }
        return groups.first(where: { group in
            group.models.contains(where: { $0.modelId == activeModelId })
        })?.id
    }

    private var displayedProvider: ModelPickerProviderGroup? {
        if let browsingProviderId,
           let match = groups.first(where: { $0.id == browsingProviderId }) {
            return match
        }
        if let resolved = resolvedActiveProviderId,
           let match = groups.first(where: { $0.id == resolved }) {
            return match
        }
        return groups.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if groups.isEmpty {
                emptyOrLoadingContent
            } else if showingProviderList {
                providerListPage
            } else if let provider = displayedProvider {
                modelsMainPage(provider: provider)
            }
        }
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 16, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modelPickerPopover")
    }

    // MARK: - Empty / Loading State

    private var emptyOrLoadingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isLoading ? "Loading models from host…" : "No models available")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(palette.foregroundSubtle)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            manageModelsFooterButton
        }
    }

    // MARK: - Main Models Page

    private func modelsMainPage(provider: ModelPickerProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    showingProviderList = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cube")
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(palette.foregroundSubtle)

                    Text(provider.name)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)

                    apiBadge(provider.badgeText)

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("modelPickerProviderHeaderButton")

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            Text("Models")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(palette.foregroundSubtle)
                .padding(.horizontal, 14)
                .padding(.top, 11)
                .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(provider.models) { model in
                        modelRow(model)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            .frame(height: min(228, CGFloat(max(1, provider.models.count)) * 40 + 10))

            if !activeReasoningLevels.isEmpty {
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Effort")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.foregroundSubtle)

                        Text(ZCodeComposerView.reasoningTitle(activeReasoningLevel))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(palette.foreground)

                        Spacer()
                    }

                    EffortSegmentedSlider(
                        levels: activeReasoningLevels,
                        selectedLevel: activeReasoningLevel,
                        onSelect: onSelectReasoningLevel
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private func modelRow(_ model: ModelPickerItem) -> some View {
        let isSelected = model.modelId == activeModelId
            && (resolvedActiveProviderId == nil || model.providerId == resolvedActiveProviderId)

        return Button {
            onSelectModel(model)
        } label: {
            HStack(spacing: 8) {
                Text(model.displayName)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                if model.supportsVision {
                    visionBadge
                }

                Spacer(minLength: 6)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? rowHighlight.opacity(0.65) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("modelPickerOption_\(model.id)")
    }

    // MARK: - Provider List Page

    private var providerListPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    showingProviderList = false
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)

                    Text("Back")
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(palette.foreground)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(rowHighlight)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .accessibilityIdentifier("modelPickerBackButton")

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { group in
                        providerRow(group)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(height: min(300, CGFloat(max(1, groups.count)) * 40 + 14))

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            manageModelsFooterButton
        }
    }

    private func providerRow(_ group: ModelPickerProviderGroup) -> some View {
        let isCurrent = group.id == resolvedActiveProviderId

        return Button {
            browsingProviderId = group.id
            withAnimation(.easeOut(duration: 0.16)) {
                showingProviderList = false
            }
        } label: {
            HStack(spacing: 8) {
                Text(group.name)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                apiBadge(group.badgeText)

                Spacer(minLength: 6)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("modelPickerProvider_\(group.id)")
    }

    private var manageModelsFooterButton: some View {
        Button {
            onManageModels()
        } label: {
            HStack {
                Text("Manage models")
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(palette.foreground)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("modelPickerManageModelsButton")
    }

    // MARK: - Badges

    private func apiBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.foregroundSubtle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(palette.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            )
    }

    private var visionBadge: some View {
        Text("Vision")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(palette.foregroundSubtle)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(palette.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
            .overlay(
                Capsule()
                    .strokeBorder(palette.borderStrong, lineWidth: 1)
            )
    }
}

// MARK: - Segmented Effort Slider

private struct EffortSegmentedSlider: View {
    let levels: [String]
    let selectedLevel: String
    let onSelect: (String) -> Void

    @Environment(\.zcodePalette) private var palette

    private var selectedIndex: Int {
        if let idx = levels.firstIndex(of: selectedLevel) {
            return idx
        }
        return max(0, levels.count - 1)
    }

    var body: some View {
        let count = max(1, levels.count)
        let trackHeight: CGFloat = 28
        let thumbSize: CGFloat = 24
        let inset: CGFloat = thumbSize / 2 + 2

        GeometryReader { geo in
            let width = max(inset * 2, geo.size.width)
            let usable = max(1, width - inset * 2)
            let xPosition: (Int) -> CGFloat = { idx in
                if count <= 1 { return width - inset }
                return inset + usable * CGFloat(idx) / CGFloat(count - 1)
            }
            let activeX = xPosition(selectedIndex)
            let fillWidth = max(thumbSize, activeX + thumbSize / 2 - 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(palette.borderStrong, lineWidth: 1)
                    )

                Capsule()
                    .fill(palette.success)
                    .frame(width: min(width - 4, fillWidth), height: trackHeight - 4)
                    .padding(.leading, 2)

                ForEach(0..<count, id: \.self) { idx in
                    if idx != selectedIndex {
                        Circle()
                            .fill(idx < selectedIndex ? Color.white.opacity(0.45) : palette.foregroundMuted.opacity(0.75))
                            .frame(width: 4, height: 4)
                            .position(x: xPosition(idx), y: trackHeight / 2)
                    }
                }

                Circle()
                    .fill(Color.white)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(palette.isDark ? 0.08 : 0.14), lineWidth: 0.5)
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.32), radius: 3, y: 1)
                    .position(x: activeX, y: trackHeight / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let idx = nearestIndex(for: value.location.x, inset: inset, usable: usable, count: count)
                        if idx < levels.count, levels[idx] != selectedLevel {
                            onSelect(levels[idx])
                        }
                    }
                    .onEnded { value in
                        let idx = nearestIndex(for: value.location.x, inset: inset, usable: usable, count: count)
                        if idx < levels.count, levels[idx] != selectedLevel {
                            onSelect(levels[idx])
                        }
                    }
            )
        }
        .frame(height: trackHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reasoning effort")
        .accessibilityValue(ZCodeComposerView.reasoningTitle(selectedLevel))
        .accessibilityIdentifier("modelPickerEffortSlider")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if selectedIndex + 1 < levels.count {
                    onSelect(levels[selectedIndex + 1])
                }
            case .decrement:
                if selectedIndex > 0 {
                    onSelect(levels[selectedIndex - 1])
                }
            @unknown default:
                break
            }
        }
    }

    private func nearestIndex(for x: CGFloat, inset: CGFloat, usable: CGFloat, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let ratio = (x - inset) / usable
        return max(0, min(count - 1, Int((ratio * CGFloat(count - 1)).rounded())))
    }
}
