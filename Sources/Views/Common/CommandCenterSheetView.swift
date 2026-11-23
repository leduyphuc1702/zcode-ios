import SwiftUI

public struct CommandCenterSheetView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var matchingFiles: [WorkspaceFileNode] {
        let q = query.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let files = store.flattenedFiles
        guard !q.isEmpty else { return files }
        return files.filter { $0.path.localizedCaseInsensitiveContains(q) }
    }

    private var matchingCommands: [SlashCommandItem] {
        let q = query.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.slashCommands }
        return store.slashCommands.filter {
            $0.trigger.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.foregroundSubtle)
                    TextField("Search > commands, @ files, or # sessions...", text: $query)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.foreground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.borderStrong, lineWidth: 1))
                .padding(14)

                List {
                    Section("Quick Actions & Slash Commands") {
                        ForEach(matchingCommands) { cmd in
                            Button {
                                store.composerText = cmd.trigger
                                dismiss()
                                store.sendPrompt()
                            } label: {
                                HStack {
                                    Text(cmd.trigger)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(palette.accentBlue)
                                    Text(cmd.summary)
                                        .font(.system(size: 13))
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                }
                            }
                        }
                    }

                    Section("Workspace Files (Open in Inspector)") {
                        ForEach(matchingFiles) { file in
                            Button {
                                dismiss()
                                store.openFileInInspector(pathOrId: file.id, preferPreview: file.kind == .image || file.kind == .pdf)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: iconName(for: file.kind))
                                        .foregroundStyle(palette.info)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name)
                                            .font(.system(size: 13.5, weight: .medium))
                                            .foregroundStyle(palette.foreground)
                                        Text(file.path)
                                            .font(.system(size: 11.5, design: .monospaced))
                                            .foregroundStyle(palette.foregroundSubtle)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(palette.background)
            .navigationTitle("Command Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func iconName(for kind: WorkspaceFileKind) -> String {
        switch kind {
        case .directory: return "folder.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .markdown: return "doc.richtext"
        case .image: return "photo"
        case .pdf: return "doc.viewfinder"
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        }
    }
}
