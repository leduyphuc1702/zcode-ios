import SwiftUI
import UIKit

public struct GitChangesAndDiffViewer: View {
    @Bindable var store: AppStore
    @Bindable var liveState: InspectorLiveState
    @Environment(\.zcodePalette) private var palette
    @State private var commitMessage: String = ""
    @State private var showCommitHistory: Bool = false
    @State private var expandedCommitHash: String? = nil

    @MainActor
    public init(store: AppStore, liveState: InspectorLiveState? = nil) {
        self.store = store
        self.liveState = liveState ?? InspectorLiveState()
    }

    private var activeDiffItem: GitChangedFile? {
        store.gitChanges.first(where: { $0.id == store.selectedDiffFileId }) ?? store.gitChanges.first
    }

    private var hasStagedChanges: Bool {
        store.gitChanges.contains(where: \.isStaged)
    }

    private var allChangesStaged: Bool {
        !store.gitChanges.isEmpty && store.gitChanges.allSatisfy(\.isStaged)
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    public var body: some View {
        VStack(spacing: 0) {
            // Git Top Control Strip (Branch Picker, Refresh, Split/Unified Toggle, History Toggle)
            HStack(spacing: 6) {
                Menu {
                    ForEach(store.gitBranches, id: \.self) { branch in
                        Button {
                            Task { @MainActor in
                                await store.switchInspectorGitBranch(branch, state: liveState)
                            }
                        } label: {
                            Label(branch, systemImage: branch == store.activeProject?.gitBranch ? "checkmark" : "arrow.triangle.branch")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.accentBlue)
                        Text(store.activeProject?.gitBranch ?? store.activeGitBranch)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.border, lineWidth: 1))
                }
                .disabled(liveState.isMutatingGit || (store.isLiveHostConnected && !liveState.isGitRepository))

                Spacer(minLength: 4)

                if store.isLiveHostConnected {
                    Button {
                        Task { @MainActor in
                            await store.refreshInspectorGitStatus(state: liveState)
                            if let active = activeDiffItem {
                                await store.loadInspectorGitDiff(for: active, state: liveState, force: true)
                            }
                            if showCommitHistory || liveState.commitsLoaded {
                                await store.loadInspectorCommitLog(state: liveState, loadMore: false)
                            }
                        }
                    } label: {
                        Group {
                            if liveState.isLoadingGitStatus || liveState.isLoadingCommits {
                                ProgressView()
                                    .scaleEffect(0.65)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.foregroundSubtle)
                            }
                        }
                        .frame(width: 28, height: 30)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh Git status and history")
                }

                if !showCommitHistory {
                    Button {
                        store.diffSplitMode.toggle()
                    } label: {
                        Text(store.diffSplitMode ? "Split" : "Unified")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.border, lineWidth: 1))
                            .animation(nil, value: store.diffSplitMode)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("toggleDiffModeButton")
                }

                Button {
                    showCommitHistory.toggle()
                    if showCommitHistory && store.isLiveHostConnected && !liveState.commitsLoaded {
                        Task { @MainActor in
                            await store.loadInspectorCommitLog(state: liveState, loadMore: false)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                        Text(showCommitHistory ? "Changes" : "History")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(showCommitHistory ? palette.accentBlue : palette.foregroundSubtle)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(showCommitHistory ? palette.accentBlue.opacity(0.45) : palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toggleCommitGraphButton")
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(palette.panel)

            Rectangle().fill(palette.border).frame(height: 1)

            if !store.isUITestSeededMode && !store.isLiveHostConnected {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 28))
                        .foregroundStyle(palette.foregroundMuted)
                    Text("Connect to a ZCode host to inspect Git changes and commit history.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showCommitHistory {
                commitGraphListView
            } else {
                changesBodyView
            }
        }
        .task(id: "\(store.isLiveHostConnected)-\(store.inspectorWorkspacePath)") {
            guard store.isLiveHostConnected else { return }
            await store.refreshInspectorGitStatus(state: liveState)
            if let active = activeDiffItem {
                await store.loadInspectorGitDiff(for: active, state: liveState)
            }
            if !liveState.commitsLoaded {
                await store.loadInspectorCommitLog(state: liveState, loadMore: false)
            }
        }
        .onChange(of: activeDiffItem?.id) { _, _ in
            guard store.isLiveHostConnected, let active = activeDiffItem else { return }
            Task { @MainActor in
                await store.loadInspectorGitDiff(for: active, state: liveState)
            }
        }
    }

    // MARK: - Changes & Diff View

    @ViewBuilder
    private var changesBodyView: some View {
        if liveState.isLoadingGitStatus && !liveState.gitStatusLoaded && store.gitChanges.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading Git status…")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = liveState.gitStatusError, store.gitChanges.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundStyle(palette.warning)
                Text(err)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.foregroundSubtle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Button("Retry") {
                    Task { @MainActor in
                        await store.refreshInspectorGitStatus(state: liveState)
                    }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.accentBlue)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.isLiveHostConnected && liveState.gitStatusLoaded && (!liveState.isGitAvailable || !liveState.isGitRepository) {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.minus")
                    .font(.system(size: 28))
                    .foregroundStyle(palette.foregroundMuted)
                Text(liveState.isGitAvailable ? "Not a Git repository" : "Git is not available on the host")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Text(store.inspectorWorkspacePath)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Changed Files List + Stage/Unstage All
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("CHANGES (\(store.gitChanges.count))")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.foregroundMuted)

                            if !store.gitChanges.isEmpty {
                                Text("+\(store.gitTotalAddedLines)")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.success)
                                Text("-\(store.gitTotalRemovedLines)")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.destructive)
                            }

                            Spacer()

                            if !store.gitChanges.isEmpty {
                                Button(allChangesStaged ? "Unstage All" : "Stage All") {
                                    Task { @MainActor in
                                        await store.stageAllInspectorFiles(!allChangesStaged, state: liveState)
                                    }
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.accentBlue)
                                .disabled(liveState.isMutatingGit)
                            }
                        }

                        if store.gitChanges.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 26))
                                    .foregroundStyle(palette.success)
                                Text("Working tree clean")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(palette.foreground)
                                Text("No uncommitted changes in this workspace.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.foregroundSubtle)
                                Button {
                                    showCommitHistory = true
                                    if store.isLiveHostConnected && !liveState.commitsLoaded {
                                        Task { @MainActor in
                                            await store.loadInspectorCommitLog(state: liveState, loadMore: false)
                                        }
                                    }
                                } label: {
                                    Label("View Commit History", systemImage: "clock.arrow.circlepath")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.accentBlue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(palette.accentBlue.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(palette.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))
                        } else {
                            ForEach(store.gitChanges) { item in
                                changedFileRow(item)
                            }
                        }
                    }

                    // Commit Box (only shown when changes exist)
                    if !store.gitChanges.isEmpty {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Commit message...", text: $commitMessage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(palette.foreground)
                                    .padding(.horizontal, 10)
                                    .frame(height: 36)
                                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))

                                Button {
                                    if store.isLiveHostConnected {
                                        Task { @MainActor in
                                            if let generated = await store.generateInspectorCommitMessage(state: liveState) {
                                                commitMessage = generated
                                            }
                                        }
                                    } else if store.isUITestSeededMode {
                                        commitMessage = "feat(rpc): update workspace changes"
                                    }
                                } label: {
                                    Group {
                                        if liveState.isGeneratingCommitMessage {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(palette.accentBlue)
                                        }
                                    }
                                    .frame(width: 36, height: 36)
                                    .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(liveState.isGeneratingCommitMessage || liveState.isMutatingGit)
                                .accessibilityIdentifier("aiGenerateCommitButton")
                            }

                            let canCommit = !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && hasStagedChanges
                                && !liveState.isMutatingGit

                            Button {
                                let msg = commitMessage
                                Task { @MainActor in
                                    let ok = await store.commitInspectorStagedChanges(message: msg, state: liveState)
                                    if ok { commitMessage = "" }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if liveState.isMutatingGit {
                                        ProgressView()
                                            .scaleEffect(0.75)
                                            .tint(palette.brandForeground)
                                    }
                                    Text("Commit Staged Changes")
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundStyle(palette.brandForeground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(palette.brand.opacity(canCommit ? 1.0 : 0.45), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canCommit)
                            .accessibilityIdentifier("commitStagedButton")
                        }
                    }

                    // Native Diff Renderer (Unified or Split)
                    if let diff = activeDiffItem {
                        diffCardView(for: diff)
                    }
                }
                .padding(12)
            }
        }
    }

    private func changedFileRow(_ item: GitChangedFile) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { @MainActor in
                    await store.toggleStageInspectorFile(item, state: liveState)
                }
            } label: {
                Image(systemName: item.isStaged ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isStaged ? palette.success : palette.foregroundSubtle)
            }
            .buttonStyle(.plain)
            .disabled(liveState.isMutatingGit)

            Button {
                store.selectedDiffFileId = item.id
                if store.isLiveHostConnected {
                    Task { @MainActor in
                        await store.loadInspectorGitDiff(for: item, state: liveState)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(item.status)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor(item.status))
                        .frame(width: 14)

                    Text(item.path)
                        .font(.system(size: 12.5, weight: item.id == activeDiffItem?.id ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    if item.added > 0 || item.removed > 0 {
                        Text("+\(item.added)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.success)
                        Text("-\(item.removed)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.destructive)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(item.id == activeDiffItem?.id ? palette.card : palette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(item.id == activeDiffItem?.id ? palette.borderStrong : palette.border, lineWidth: 1))
    }

    @ViewBuilder
    private func diffCardView(for diff: GitChangedFile) -> some View {
        let isLoadingDiff = liveState.loadingDiffIds.contains(diff.id)
        let diffError = liveState.diffErrors[diff.id]
        let diffDetail = liveState.diffDetails[diff.id]
        let effectivePatch = diffDetail?.patch ?? diff.patch

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(diff.path)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(diff.isStaged ? "STAGED" : "UNSTAGED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(diff.isStaged ? palette.success : palette.warning)
                if store.isLiveHostConnected {
                    Button {
                        Task { @MainActor in
                            await store.loadInspectorGitDiff(for: diff, state: liveState, force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(palette.header)

            Rectangle().fill(palette.border).frame(height: 1)

            if isLoadingDiff {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading diff…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(palette.backgroundElevated)
            } else if let diffError {
                VStack(spacing: 8) {
                    Text(diffError)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.destructive)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { @MainActor in
                            await store.loadInspectorGitDiff(for: diff, state: liveState, force: true)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accentBlue)
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(palette.backgroundElevated)
            } else if let detail = diffDetail, detail.availability != "patch" {
                VStack(spacing: 6) {
                    Image(systemName: detail.availability == "binary" ? "doc.zipper" : "doc.text")
                        .font(.system(size: 22))
                        .foregroundStyle(palette.foregroundMuted)
                    Text(detail.summary ?? (detail.availability == "binary" ? "Binary file changed — diff preview not available." : "No diff output available for this file."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(palette.backgroundElevated)
            } else if !effectivePatch.isEmpty {
                if store.diffSplitMode {
                    splitDiffView(effectivePatch)
                } else {
                    unifiedDiffView(effectivePatch)
                }
            } else if store.isLiveHostConnected {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading diff…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(palette.backgroundElevated)
                .task(id: diff.id) {
                    await store.loadInspectorGitDiff(for: diff, state: liveState)
                }
            } else {
                Text("No diff content available.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(palette.backgroundElevated)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))
    }

    private func unifiedDiffView(_ patch: String) -> some View {
        let lines = patch.components(separatedBy: "\n")
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(spacing: 8) {
                        Text("\(idx + 1)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.foregroundMuted)
                            .frame(width: 30, alignment: .trailing)
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(fgColor(for: line))
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bgColor(for: line))
                }
            }
        }
        .background(palette.backgroundElevated)
    }

    private func splitDiffView(_ patch: String) -> some View {
        let lines = patch.components(separatedBy: "\n")
        let removed = lines.filter { !$0.hasPrefix("+") || $0.hasPrefix("+++") }
        let added = lines.filter { !$0.hasPrefix("-") || $0.hasPrefix("---") }

        return HStack(alignment: .top, spacing: 0) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(removed.enumerated()), id: \.offset) { _, l in
                    Text(l)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(fgColor(for: l))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(bgColor(for: l))
                }
            }
            Rectangle().fill(palette.border).frame(width: 1)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(added.enumerated()), id: \.offset) { _, r in
                    Text(r)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(fgColor(for: r))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(bgColor(for: r))
                }
            }
        }
        .background(palette.backgroundElevated)
    }

    // MARK: - Commit History / Log View

    private var commitGraphListView: some View {
        Group {
            if liveState.isLoadingCommits && liveState.commitDetails.isEmpty && store.gitCommits.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading commit history…")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = liveState.commitsError, liveState.commitDetails.isEmpty && store.gitCommits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26))
                        .foregroundStyle(palette.warning)
                    Text(err)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Retry") {
                        Task { @MainActor in
                            await store.loadInspectorCommitLog(state: liveState, loadMore: false)
                        }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.accentBlue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.isLiveHostConnected && liveState.commitDetails.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(palette.foregroundMuted)
                    Text("No commits found")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text("This repository does not have any commits yet.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if store.isLiveHostConnected {
                            ForEach(liveState.commitDetails) { commit in
                                liveCommitRow(commit)
                            }
                            if liveState.hasMoreCommits {
                                Button {
                                    Task { @MainActor in
                                        await store.loadInspectorCommitLog(state: liveState, loadMore: true)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        if liveState.isLoadingMoreCommits {
                                            ProgressView().scaleEffect(0.75)
                                        }
                                        Text(liveState.isLoadingMoreCommits ? "Loading…" : "Load More Commits")
                                            .font(.system(size: 12.5, weight: .semibold))
                                    }
                                    .foregroundStyle(palette.accentBlue)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(liveState.isLoadingMoreCommits)
                            }
                        } else {
                            ForEach(store.gitCommits) { commit in
                                seededCommitRow(commit)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func liveCommitRow(_ commit: InspectorCommitDetail) -> some View {
        let isExpanded = expandedCommitHash == commit.hash
        let relativeTime = commit.timestamp.map { Self.relativeDateFormatter.localizedString(for: $0, relativeTo: Date()) } ?? ""

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    expandedCommitHash = isExpanded ? nil : commit.hash
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(palette.accentBlue)
                            .frame(width: 9, height: 9)
                            .padding(.top, 4)
                        Rectangle()
                            .fill(palette.borderStrong)
                            .frame(width: 2, height: 34)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(commit.shortHash)
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.accentBlue)

                            ForEach(commit.refs.prefix(3)) { ref in
                                Text(ref.name)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(refColor(for: ref.kind))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(refColor(for: ref.kind).opacity(0.14), in: Capsule())
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            if !relativeTime.isEmpty {
                                Text(relativeTime)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(palette.foregroundMuted)
                            }
                        }

                        Text(commit.subject.isEmpty ? "(no commit message)" : commit.subject)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.foreground)
                            .multilineTextAlignment(.leading)

                        Text(commit.author)
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle().fill(palette.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Commit")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.foregroundMuted)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = commit.hash
                            store.showToast("Copied \(commit.shortHash)")
                        } label: {
                            Label("Copy SHA", systemImage: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.accentBlue)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(commit.hash)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .textSelection(.enabled)

                    if !commit.parents.isEmpty {
                        Text("Parents: \(commit.parents.map { String($0.prefix(7)) }.joined(separator: ", "))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.foregroundSubtle)
                    }

                    if let ts = commit.timestamp {
                        Text("Authored: \(ts.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.foregroundSubtle)
                    }

                    Text("Per-commit file diffs are not exposed by the host Git RPC.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.top, 2)
                }
                .padding(10)
                .background(palette.panel)
            }
        }
        .background(palette.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isExpanded ? palette.borderStrong : palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func seededCommitRow(_ commit: GitCommitRecord) -> some View {
        let relativeTime = Self.relativeDateFormatter.localizedString(for: commit.timestamp, relativeTo: Date())
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(palette.accentBlue)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(palette.borderStrong)
                    .frame(width: 2, height: 36)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(commit.shortHash)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.accentBlue)
                    if let ref = commit.branchRef {
                        Text(ref)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.success.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    Text(relativeTime)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.foregroundMuted)
                }
                Text(commit.subject)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.foreground)
                Text(commit.author)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.foregroundSubtle)
            }
            Spacer()
        }
        .padding(10)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 9))
    }

    private func refColor(for kind: String) -> Color {
        switch kind {
        case "head", "branch": return palette.success
        case "tag": return palette.warning
        case "remote": return palette.info
        default: return palette.accentBlue
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "A", "U": return palette.success
        case "D", "!": return palette.destructive
        default: return palette.warning
        }
    }

    private func fgColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return palette.success }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return palette.destructive }
        if line.hasPrefix("@@") { return palette.info }
        return palette.foregroundSubtle
    }

    private func bgColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return palette.success.opacity(0.11) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return palette.destructive.opacity(0.11) }
        return Color.clear
    }
}
