import SwiftUI

/// Native 3x3 Pattern Lock + Face ID Unlock Gate (matching zcode-mobile-app SecurityVerifyActivity)
public struct SecurityUnlockGateView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @State private var statusMessage: String = "Draw your security pattern or use Face ID"

    public var body: some View {
        VStack(spacing: 26) {
            Spacer()

            Image("ZCodeLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderStrong, lineWidth: 1))

            VStack(spacing: 6) {
                Text("ZCode Enterprise Locked")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.foreground)

                Text(statusMessage)
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.foregroundSubtle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            PatternLockGridView { nodes in
                guard nodes.count >= 4 else {
                    statusMessage = "Connect at least 4 dots"
                    return
                }
                if store.verifyPattern(nodes) {
                    statusMessage = "Unlocked"
                } else {
                    statusMessage = "Incorrect pattern (\(store.failedUnlockAttempts)/5 attempts)"
                }
            }
            .frame(width: 250, height: 250)

            if store.biometricUnlockEnabled {
                Button {
                    Task {
                        await store.attemptBiometricUnlock()
                    }
                } label: {
                    Label("Unlock with Face ID", systemImage: "faceid")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.brandForeground)
                        .padding(.horizontal, 22)
                        .frame(height: 44)
                        .background(palette.brand, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background.ignoresSafeArea())
    }
}

public struct PatternSetupSheetView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var firstPattern: [Int]?
    @State private var prompt: String = "Draw a new unlock pattern (at least 4 dots)"

    public var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Text(prompt)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                PatternLockGridView { nodes in
                    guard nodes.count >= 4 else {
                        prompt = "Connect at least 4 dots"
                        return
                    }
                    if let first = firstPattern {
                        if first == nodes {
                            store.savePattern(nodes)
                            dismiss()
                        } else {
                            firstPattern = nil
                            prompt = "Patterns did not match. Draw a new pattern:"
                        }
                    } else {
                        firstPattern = nodes
                        prompt = "Draw the pattern again to confirm"
                    }
                }
                .frame(width: 250, height: 250)

                Spacer()
            }
            .navigationTitle("Set Security Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

public struct PatternLockGridView: View {
    let onCompleted: ([Int]) -> Void
    @Environment(\.zcodePalette) private var palette
    @State private var activeNodes: [Int] = []
    @State private var dragLocation: CGPoint?

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let step = size / 3.0
            let centers: [CGPoint] = (0..<9).map { idx in
                let row = idx / 3
                let col = idx % 3
                return CGPoint(x: CGFloat(col) * step + step / 2, y: CGFloat(row) * step + step / 2)
            }

            Canvas { context, _ in
                if activeNodes.count >= 1 {
                    var line = Path()
                    line.move(to: centers[activeNodes[0]])
                    for node in activeNodes.dropFirst() {
                        line.addLine(to: centers[node])
                    }
                    if let current = dragLocation {
                        line.addLine(to: current)
                    }
                    context.stroke(line, with: .color(palette.accentBlue), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                for (idx, pt) in centers.enumerated() {
                    let isSelected = activeNodes.contains(idx)
                    let outerRect = CGRect(x: pt.x - 18, y: pt.y - 18, width: 36, height: 36)
                    context.fill(Path(ellipseIn: outerRect), with: .color(isSelected ? palette.accentBlue.opacity(0.24) : palette.card))
                    context.stroke(Path(ellipseIn: outerRect), with: .color(isSelected ? palette.accentBlue : palette.borderStrong), lineWidth: 1.5)

                    let innerRect = CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: innerRect), with: .color(isSelected ? palette.accentBlue : palette.foregroundSubtle))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragLocation = value.location
                        for (idx, pt) in centers.enumerated() {
                            if hypot(value.location.x - pt.x, value.location.y - pt.y) < 28 {
                                if !activeNodes.contains(idx) {
                                    activeNodes.append(idx)
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        let captured = activeNodes
                        dragLocation = nil
                        activeNodes = []
                        onCompleted(captured)
                    }
            )
        }
    }
}
