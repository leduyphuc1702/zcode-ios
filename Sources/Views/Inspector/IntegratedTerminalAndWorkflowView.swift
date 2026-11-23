import SwiftUI

public struct IntegratedTerminalView: View {
    @Bindable var store: AppStore
    @Bindable var liveState: InspectorLiveState
    @Environment(\.zcodePalette) private var palette
    @State private var commandInput: String = ""

    @MainActor
    public init(store: AppStore, liveState: InspectorLiveState? = nil) {
        self.store = store
        self.liveState = liveState ?? InspectorLiveState()
    }

    private var currentTab: TerminalTabModel? {
        store.terminalTabs.first(where: { $0.id == store.activeTerminalTabId }) ?? store.terminalTabs.first
    }

    private let quickKeys = ["git status", "ls -la", "pwd", "clear", "|", "--", "/"]

    public var body: some View {
        if store.isUITestSeededMode {
            seededTerminalBody
        } else {
            liveTerminalBody
        }
    }

    // MARK: - Live Host PTY Terminal (`terminal` RPC channel)

    private var liveTerminalBody: some View {
        VStack(spacing: 0) {
            // Live PTY Header Bar
            HStack(spacing: 8) {
                Circle()
                    .fill(livePtyStatusColor)
                    .frame(width: 7, height: 7)

                Text(livePtyTitle)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)

                Spacer()

                if liveState.ptyId != nil && !liveState.ptyExited {
                    Button {
                        Task { @MainActor in
                            await store.sendInspectorTerminalInput("\u{03}", state: liveState)
                        }
                    } label: {
                        Text("^C")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.warning)
                            .padding(.horizontal, 7)
                            .frame(height: 26)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    liveState.ptyOutput = ""
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 26, height: 26)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear terminal output")

                Button {
                    liveState.ptyOutput = ""
                    Task { @MainActor in
                        await store.disposeInspectorLiveTerminal(state: liveState)
                        await store.startInspectorLiveTerminal(state: liveState)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .frame(width: 26, height: 26)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!store.isLiveHostConnected || liveState.isConnectingPty)
                .accessibilityLabel("Restart remote terminal")
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(palette.panel)

            Rectangle().fill(palette.border).frame(height: 1)

            if !store.isLiveHostConnected {
                VStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.system(size: 28))
                        .foregroundStyle(palette.foregroundMuted)
                    Text("Connect to a ZCode host to open a remote shell.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.foregroundSubtle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: 0x0D0F12))
            } else if liveState.isConnectingPty && liveState.ptyOutput.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Starting remote shell…")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xC9D1D9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: 0x0D0F12))
            } else if let err = liveState.ptyError, liveState.ptyId == nil {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26))
                        .foregroundStyle(palette.warning)
                    Text(err)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xFF7B72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Retry") {
                        Task { @MainActor in
                            await store.startInspectorLiveTerminal(state: liveState)
                        }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.accentBlue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: 0x0D0F12))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(liveState.ptyOutput.isEmpty ? "Remote shell ready." : liveState.ptyOutput)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color(hex: 0xC9D1D9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)

                            if liveState.ptyExited {
                                Text("[Process exited\(liveState.ptyExitCode.map { " with code \($0)" } ?? "")]")
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.warning)
                            }
                            if let err = liveState.ptyError {
                                Text(err)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Color(hex: 0xFF5C5C))
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("liveTerminalBottom")
                        }
                        .padding(12)
                    }
                    .background(Color(hex: 0x0D0F12))
                    .onChange(of: liveState.ptyOutput.count) { _, _ in
                        proxy.scrollTo("liveTerminalBottom", anchor: .bottom)
                    }
                }
            }

            // Quick Key Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickKeys, id: \.self) { key in
                        Button {
                            if ["|", "--", "/"].contains(key) {
                                commandInput += key
                            } else if key == "clear" {
                                liveState.ptyOutput = ""
                            } else {
                                sendLiveCommand(key)
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
                        .disabled(!isLivePtyWritable && key != "clear")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(palette.header)

            // Prompt Input Row
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(isLivePtyWritable ? palette.success : palette.foregroundMuted)
                TextField("Enter shell command...", text: $commandInput)
                    .font(.system(size: 13.5, design: .monospaced))
                    .foregroundStyle(palette.foreground)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!isLivePtyWritable)
                    .onSubmit {
                        runLiveCommandInput()
                    }
                    .accessibilityIdentifier("terminalInputField")

                Button {
                    runLiveCommandInput()
                } label: {
                    Image(systemName: "return")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.brandForeground)
                        .frame(width: 34, height: 32)
                        .background(palette.brand.opacity(isLivePtyWritable ? 1.0 : 0.4), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(!isLivePtyWritable)
                .accessibilityIdentifier("terminalRunButton")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.panel)
        }
        .task(id: "\(store.isLiveHostConnected)-\(store.inspectorWorkspacePath)") {
            guard store.isLiveHostConnected else { return }
            await store.startInspectorLiveTerminal(state: liveState)
        }
    }

    private var isLivePtyWritable: Bool {
        store.isLiveHostConnected && liveState.ptyId != nil && !liveState.ptyExited
    }

    private var livePtyStatusColor: Color {
        if !store.isLiveHostConnected { return palette.foregroundMuted }
        if liveState.isConnectingPty { return palette.warning }
        if liveState.ptyExited || liveState.ptyError != nil { return palette.destructive }
        if liveState.ptyId != nil { return palette.success }
        return palette.foregroundMuted
    }

    private var livePtyTitle: String {
        if let shell = liveState.ptyShell, !shell.isEmpty {
            let name = URL(fileURLWithPath: shell).lastPathComponent
            if liveState.ptyExited { return "\(name) (exited)" }
            return name
        }
        if liveState.isConnectingPty { return "Connecting PTY…" }
        return store.isLiveHostConnected ? "Remote Shell" : "Disconnected"
    }

    private func runLiveCommandInput() {
        let trimmed = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed == "clear" {
            liveState.ptyOutput = ""
            commandInput = ""
            return
        }
        sendLiveCommand(trimmed)
        commandInput = ""
    }

    private func sendLiveCommand(_ cmd: String) {
        guard isLivePtyWritable else { return }
        Task { @MainActor in
            await store.sendInspectorTerminalInput(cmd + "\n", state: liveState)
        }
    }

    // MARK: - Seeded UITest Terminal Body

    private var seededTerminalBody: some View {
        VStack(spacing: 0) {
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
                        runSeededCommand()
                    }
                    .accessibilityIdentifier("terminalInputField")

                Button {
                    runSeededCommand()
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

    private func runSeededCommand() {
        guard !commandInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.executeTerminalCommand(commandInput)
        commandInput = ""
    }
}

public struct WorkflowGraphCanvasView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette

    private var runs: [LiveWorkflowRunSummary] { store.activeWorkflowRunSummaries }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workflow runs")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Spacer()
                if !runs.isEmpty {
                    Text("\(runs.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.foregroundSubtle)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(palette.panel)

            Rectangle().fill(palette.border).frame(height: 1)

            if runs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 30))
                        .foregroundStyle(palette.foregroundMuted)
                    Text("No workflow runs in this session")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text("Workflow runs reported by the host appear here.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundSubtle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(runs) { run in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(statusColor(run.status))
                                        .frame(width: 7, height: 7)
                                    Text(run.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(palette.foreground)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                    Text(run.status.uppercased())
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(statusColor(run.status))
                                }
                                if !run.usageText.isEmpty {
                                    Text(run.usageText)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(palette.foregroundMuted)
                                }
                                if !run.detail.isEmpty {
                                    Text(run.detail)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(palette.foregroundSubtle)
                                        .lineLimit(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed": return palette.success
        case "running", "pending": return palette.accentBlue
        case "errored", "failed": return palette.destructive
        case "stopped": return palette.foregroundMuted
        default: return palette.foregroundMuted
        }
    }
}
