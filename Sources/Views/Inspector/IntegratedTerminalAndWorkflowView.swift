import SwiftUI

public struct IntegratedTerminalView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @State private var commandInput: String = ""

    private var currentTab: TerminalTabModel? {
        store.terminalTabs.first(where: { $0.id == store.activeTerminalTabId }) ?? store.terminalTabs.first
    }

    private let quickKeys = ["git status", "swift test", "ls -la", "pwd", "clear", "|", "--", "/"]

    public var body: some View {
        VStack(spacing: 0) {
            // Multi-Tab Terminal Header
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(store.terminalTabs) { tab in
                            let selected = tab.id == store.activeTerminalTabId
                            Button {
                                store.activeTerminalTabId = tab.id
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(tab.isRunningJob ? palette.success : palette.foregroundMuted)
                                        .frame(width: 6, height: 6)
                                    Text(tab.title)
                                        .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .monospaced))
                                        .foregroundStyle(selected ? palette.foreground : palette.foregroundSubtle)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(selected ? palette.card : palette.surfaceHover, in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    store.addTerminalTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.foreground)
                        .frame(width: 30, height: 30)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newTerminalTabButton")
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(palette.panel)

            Rectangle().fill(palette.border).frame(height: 1)

            // Console Output ScrollView
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let tab = currentTab {
                        ForEach(tab.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                if let cmd = entry.command {
                                    HStack(spacing: 6) {
                                        Text("➜")
                                            .foregroundStyle(Color(hex: 0x46BF72))
                                        Text(cmd)
                                            .foregroundStyle(Color.white)
                                            .fontWeight(.semibold)
                                    }
                                    .font(.system(size: 12.5, design: .monospaced))
                                }
                                Text(entry.output)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(entry.isError ? Color(hex: 0xFF5C5C) : Color(hex: 0xC9D1D9))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(hex: 0x0D0F12))

            // Developer Quick Key Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickKeys, id: \.self) { key in
                        Button {
                            if ["|", "--", "/"].contains(key) {
                                commandInput += key
                            } else {
                                store.executeTerminalCommand(key)
                            }
                        } label: {
                            Text(key)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.foreground)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(palette.card, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(palette.header)

            // Terminal Prompt Input Row
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.success)
                TextField("Enter shell command...", text: $commandInput)
                    .font(.system(size: 13.5, design: .monospaced))
                    .foregroundStyle(palette.foreground)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        runCurrentCommand()
                    }
                    .accessibilityIdentifier("terminalInputField")

                Button {
                    runCurrentCommand()
                } label: {
                    Image(systemName: "return")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.brandForeground)
                        .frame(width: 34, height: 32)
                        .background(palette.brand, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("terminalRunButton")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.panel)
        }
    }

    private func runCurrentCommand() {
        guard !commandInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.executeTerminalCommand(commandInput)
        commandInput = ""
    }
}

public struct WorkflowGraphCanvasView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @State private var selectedNode: WorkflowGraphNode?

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Multi-Agent Execution Graph (Native Canvas)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Spacer()
                Text("5/5 Nodes Healthy")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.success)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(palette.panel)

            Rectangle().fill(palette.border).frame(height: 1)

            GeometryReader { geo in
                let isPortrait = geo.size.width < geo.size.height
                let coords: [CGPoint] = store.workflowNodes.enumerated().map { idx, node in
                    if isPortrait {
                        let portraitRatios: [(Double, Double)] = [
                            (0.50, 0.14),
                            (0.26, 0.39),
                            (0.74, 0.39),
                            (0.50, 0.64),
                            (0.50, 0.87)
                        ]
                        let r = idx < portraitRatios.count ? portraitRatios[idx] : (node.xRatio, node.yRatio)
                        return CGPoint(x: r.0 * geo.size.width, y: r.1 * geo.size.height)
                    } else {
                        return CGPoint(x: node.xRatio * geo.size.width, y: node.yRatio * geo.size.height)
                    }
                }

                ZStack {
                    Canvas { context, _ in
                        let edges: [(Int, Int)] = [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)]
                        for (fromIdx, toIdx) in edges where fromIdx < coords.count && toIdx < coords.count {
                            let p1 = coords[fromIdx]
                            let p2 = coords[toIdx]
                            var path = Path()
                            path.move(to: p1)
                            if isPortrait {
                                let midY = (p1.y + p2.y) / 2
                                path.addCurve(to: p2, control1: CGPoint(x: p1.x, y: midY), control2: CGPoint(x: p2.x, y: midY))
                            } else {
                                let midX = (p1.x + p2.x) / 2
                                path.addCurve(to: p2, control1: CGPoint(x: midX, y: p1.y), control2: CGPoint(x: midX, y: p2.y))
                            }
                            context.stroke(path, with: .color(palette.accentBlue.opacity(0.65)), lineWidth: 2)
                        }
                    }

                    ForEach(Array(store.workflowNodes.enumerated()), id: \.element.id) { idx, node in
                        Button {
                            selectedNode = node
                        } label: {
                            VStack(spacing: 3) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(palette.success)
                                        .frame(width: 6, height: 6)
                                    Text(node.title)
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundStyle(palette.foreground)
                                        .lineLimit(1)
                                }
                                Text("\(node.role) • \(node.durationText)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selectedNode?.id == node.id ? palette.accentBlue : palette.borderStrong, lineWidth: 1.2))
                        }
                        .buttonStyle(.plain)
                        .position(coords[idx])
                    }
                }
            }

            if let sel = selectedNode ?? store.workflowNodes.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(sel.title) — \(sel.role)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text("Status: \(sel.status.uppercased()) • Wall time: \(sel.durationText) • Verified deterministic output.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.panel)
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.border).frame(height: 1)
                }
            }
        }
    }
}
