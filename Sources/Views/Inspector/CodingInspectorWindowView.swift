import SwiftUI

public struct CodingInspectorWindowView: View {
    @Bindable var store: AppStore
    let isDockedPane: Bool
    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: 0) {
            // Official ZCode Side-Pane Header Bar
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(InspectorTab.allCases) { tab in
                            let isSelected = store.activeInspectorTab == tab
                            Button {
                                store.playSelectionHaptic()
                                store.activeInspectorTab = tab
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(tab.title)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .foregroundStyle(isSelected ? palette.foreground : palette.foregroundSubtle)
                                .padding(.horizontal, 8)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelected ? palette.card : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(isSelected ? palette.borderStrong : Color.clear, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("inspectorTab_\(tab.rawValue)")
                        }
                    }
                }

                Button {
                    store.playImpactHaptic(.light)
                    store.isInspectorExpandedFull.toggle()
                } label: {
                    Image(systemName: store.isInspectorExpandedFull ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isInspectorExpandedFull ? "Restore inspector width" : "Expand inspector full width")
                .accessibilityIdentifier("expandInspectorButton")

                Button {
                    store.playImpactHaptic(.light)
                    if isDockedPane {
                        store.showInspectorSheet = false
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 32, height: 32)
                        .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 8))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close inspector")
                .accessibilityIdentifier("closeInspectorButton")
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(palette.header)

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            Group {
                switch store.activeInspectorTab {
                case .files:
                    FileExplorerAndCodeViewer(store: store)
                case .preview:
                    NativeMediaDocumentViewer(store: store)
                case .gitDiff:
                    GitChangesAndDiffViewer(store: store)
                case .terminal:
                    IntegratedTerminalView(store: store)
                case .workflows:
                    WorkflowGraphCanvasView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
        }
        .background(palette.background)
    }
}
