import SwiftUI

public struct RootWorkspaceContainerView: View {
    @Bindable var store: AppStore
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: AppStore) {
        self.store = store
    }

    private var palette: ZCodePalette {
        ZCodePalette.resolve(mode: store.themeMode, systemScheme: systemColorScheme)
    }

    private var resolvedColorScheme: ColorScheme? {
        switch store.themeMode {
        case .dark, .graphite: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let isWideLayout = horizontalSizeClass == .regular && geo.size.width >= 820

            ZStack(alignment: .leading) {
                palette.background
                    .ignoresSafeArea()

                if store.showConnectionHub {
                    ZCodeOnboardingAndHubView(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if isWideLayout {
                    // Wide iPad / Landscape 3-Pane ZCode Layout
                    HStack(spacing: 0) {
                        WorkspaceSidebarView(store: store, isEmbeddedColumn: true)
                            .frame(width: 284)
                            .background(palette.sidebar)

                        Rectangle()
                            .fill(palette.border)
                            .frame(width: 1)

                        Group {
                            switch store.mobilePage {
                            case .automations:
                                AutomationsWorkspacePageView(store: store, isWideLayout: true)
                            case .pluginMarketplace:
                                PluginMarketplacePageView(store: store, isWideLayout: true)
                            case .home, .chat:
                                AgentChatCanvasView(store: store, isWideLayout: true)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if store.showInspectorSheet {
                            Rectangle()
                                .fill(palette.border)
                                .frame(width: 1)

                            CodingInspectorWindowView(store: store, isDockedPane: true)
                                .frame(width: min(460, geo.size.width * 0.42))
                                .transition(.move(edge: .trailing))
                        }
                    }
                } else {
                    // Official ZCode Remote Mobile Shell (`home` <-> `chat` / `automations` / `pluginMarketplace`)
                    Group {
                        switch store.mobilePage {
                        case .home:
                            WorkspaceSidebarView(store: store, isEmbeddedColumn: false)
                                .transition(reduceMotion ? .opacity : .move(edge: .leading))
                        case .chat:
                            AgentChatCanvasView(store: store, isWideLayout: false)
                                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                        case .automations:
                            AutomationsWorkspacePageView(store: store, isWideLayout: false)
                                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                        case .pluginMarketplace:
                            PluginMarketplacePageView(store: store, isWideLayout: false)
                                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 24, coordinateSpace: .local)
                            .onEnded { value in
                                guard store.mobilePage != .home,
                                      !store.showInspectorSheet,
                                      !store.showSubagentDrawer,
                                      value.startLocation.x < 28,
                                      value.translation.width > 72,
                                      abs(value.translation.height) < 60 else { return }
                                store.playImpactHaptic(.light)
                                store.mobilePage = .home
                            }
                    )
                }

                // Subtle ZCode Floating Toast Banner
                if let toast = store.toastMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(palette.success)
                                .font(.system(size: 13.5, weight: .semibold))
                            Text(toast)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.foreground)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(palette.card)
                                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(palette.borderStrong, lineWidth: 1)
                        )
                        .padding(.bottom, 88)
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(35)
                }

                // Enterprise Security Lock Gate
                if store.isLocked {
                    SecurityUnlockGateView(store: store)
                        .transition(.opacity)
                        .zIndex(50)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.mobilePage)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.toastMessage)
            .background {
                // Apple HIG iPadOS / Hardware Keyboard Shortcuts
                ZStack {
                    Button("") { store.createNewSession() }
                        .keyboardShortcut("n", modifiers: .command)
                    Button("") { store.showCommandCenter = true }
                        .keyboardShortcut("k", modifiers: .command)
                    Button("") { store.showSettingsSheet = true }
                        .keyboardShortcut(",", modifiers: .command)
                }
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .sheet(isPresented: $store.showSettingsSheet) {
                EnterpriseSettingsCenterView(store: store)
                    .environment(\.zcodePalette, palette)
                    .preferredColorScheme(resolvedColorScheme)
            }
            .sheet(isPresented: $store.showConnectionsSheet) {
                ConnectionsManagerSheetView(store: store)
                    .environment(\.zcodePalette, palette)
                    .preferredColorScheme(resolvedColorScheme)
            }
            .sheet(isPresented: $store.showCommandCenter) {
                CommandCenterSheetView(store: store)
                    .environment(\.zcodePalette, palette)
                    .preferredColorScheme(resolvedColorScheme)
            }
        }
        .environment(\.zcodePalette, palette)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .preferredColorScheme(resolvedColorScheme)
        .onOpenURL { url in
            Task {
                await store.handleIncomingURL(url)
            }
        }
    }
}
