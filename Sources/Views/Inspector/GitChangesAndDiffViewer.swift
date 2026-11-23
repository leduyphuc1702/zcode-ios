import SwiftUI

public struct GitChangesAndDiffViewer: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @State private var commitMessage: String = ""
    @State private var showCommitHistory: Bool = false

    private var activeDiffItem: GitChangedFile? {
        store.gitChanges.first(where: { $0.id == store.selectedDiffFileId }) ?? store.gitChanges.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Git Top Control Strip (Branch Picker, Split/Unified Toggle, History Toggle)
            HStack(spacing: 8) {
                Menu {
                    ForEach(store.gitBranches, id: \.self) { branch in
                        Button {
                            store.switchGitBranch(branch)
                        } label: {
                            Label(branch, systemImage: branch == store.activeProject?.gitBranch ? "checkmark" : "arrow.triangle.branch")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.accentBlue)
                        Text(store.activeProject?.gitBranch ?? "main")
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

                Spacer()

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

                Button {
                    showCommitHistory.toggle()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                        .foregroundStyle(showCommitHistory ? palette.accentBlue : palette.foregroundSubtle)
                        .frame(width: 30, height: 30)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toggleCommitGraphButton")
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(palette.panel)

            Rectangle().fill(palette.border).frame(height: 1)

            if showCommitHistory {
                commitGraphListView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Changed Files List + Stage All
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("CHANGES (\(store.gitChanges.count))")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.foregroundMuted)
                                Spacer()
                                if !store.gitChanges.isEmpty {
                                    Button("Stage All") {
                                        store.stageAllGitChanges(true)
                                    }
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(palette.accentBlue)
                                }
                            }

                            ForEach(store.gitChanges) { item in
                                HStack(spacing: 8) {
                                    Button {
                                        store.toggleStageGitFile(item.id)
                                    } label: {
                                        Image(systemName: item.isStaged ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 15))
                                            .foregroundStyle(item.isStaged ? palette.success : palette.foregroundSubtle)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        store.selectedDiffFileId = item.id
                                    } label: {
                                        HStack {
                                            Text(item.path)
                                                .font(.system(size: 12.5, weight: item.id == activeDiffItem?.id ? .semibold : .regular, design: .monospaced))
                                                .foregroundStyle(palette.foreground)
                                                .lineLimit(1)
                                            Spacer()
                                            Text("+\(item.added)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(palette.success)
                                            Text("-\(item.removed)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(palette.destructive)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(item.id == activeDiffItem?.id ? palette.card : palette.panel, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))
                            }
                        }

                        // Commit Box
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
                                    commitMessage = "feat(rpc): verify binary VQL frame & update docs"
                                } label: {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(palette.accentBlue)
                                        .frame(width: 36, height: 36)
                                        .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("aiGenerateCommitButton")
                            }

                            Button {
                                store.commitStagedChanges(message: commitMessage)
                                commitMessage = ""
                            } label: {
                                Text("Commit Staged Changes")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(palette.brandForeground)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(palette.brand, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("commitStagedButton")
                        }

                        // Native Diff Renderer (Unified or Split)
                        if let diff = activeDiffItem {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text(diff.path)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                    Text(diff.isStaged ? "STAGED" : "UNSTAGED")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(diff.isStaged ? palette.success : palette.warning)
                                }
                                .padding(10)
                                .background(palette.header)

                                Rectangle().fill(palette.border).frame(height: 1)

                                if store.diffSplitMode {
                                    splitDiffView(diff.patch)
                                } else {
                                    unifiedDiffView(diff.patch)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func unifiedDiffView(_ patch: String) -> some View {
        let lines = patch.components(separatedBy: "\n")
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(spacing: 8) {
                        Text("\(idx + 1)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.foregroundMuted)
                            .frame(width: 26, alignment: .trailing)
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(fgColor(for: line))
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
        let removed = lines.filter { !$0.hasPrefix("+") }
        let added = lines.filter { !$0.hasPrefix("-") }

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
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
            VStack(alignment: .leading, spacing: 0) {
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

    private var commitGraphListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(store.gitCommits) { commit in
                    HStack(alignment: .top, spacing: 10) {
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
            }
            .padding(12)
        }
    }

    private func fgColor(for line: String) -> Color {
        if line.hasPrefix("+") { return palette.success }
        if line.hasPrefix("-") { return palette.destructive }
        if line.hasPrefix("@@") { return palette.info }
        return palette.foregroundSubtle
    }

    private func bgColor(for line: String) -> Color {
        if line.hasPrefix("+") { return palette.success.opacity(0.11) }
        if line.hasPrefix("-") { return palette.destructive.opacity(0.11) }
        return Color.clear
    }
}
