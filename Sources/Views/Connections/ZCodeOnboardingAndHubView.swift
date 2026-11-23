import SwiftUI

public struct ZCodeOnboardingAndHubView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette

    @State private var urlInput: String = ""
    @State private var aliasInput: String = ""
    @State private var customBearerToken: String = ""
    @State private var showAdvancedTokenField: Bool = false

    @State private var showAccessTokenLogin: Bool = false
    @State private var manualZaiToken: String = ""
    @State private var manualZaiAlias: String = ""

    @State private var showQRScanner: Bool = false
    @State private var detectedClipboardURL: String? = nil

    @State private var editingConnection: RemoteConnection? = nil
    @State private var editName: String = ""
    @State private var editURL: String = ""
    @State private var editToken: String = ""

    public init(store: AppStore) {
        self.store = store
    }

    private var parsedPreview: ParsedConnectionDescriptor? {
        ConnectionURLParser.parse(urlInput)
    }

    private var canDismissToWorkspace: Bool {
        store.activeConnection?.state == .connected && !store.connections.isEmpty
    }

    private var isShowingPairingOverlay: Bool {
        switch store.pairingPhase {
        case .idle, .connected:
            return false
        case .connecting, .authenticating, .waitingPairing, .pairedSyncing, .failed:
            return true
        }
    }

    public var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)

                ScrollView {
                    VStack(spacing: 18) {
                        if store.shouldShowSignInStepFirst {
                            stepOneZaiSignInCard
                        } else {
                            stepTwoRemoteConnectContent
                        }
                    }
                    .frame(maxWidth: 540)
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if isShowingPairingOverlay {
                relayPairingOverlay
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .onAppear {
            inspectClipboardForRemoteLink()
        }
        .sheet(isPresented: $showQRScanner) {
            NativeQRScannerSheetView { scanned in
                showQRScanner = false
                urlInput = scanned
                Task {
                    _ = await store.addAndConnect(rawURLOrInput: scanned, customName: aliasInput)
                }
            }
        }
        .sheet(item: $editingConnection) { conn in
            editConnectionSheet(conn)
        }
    }

    // MARK: - Top Header Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if store.shouldShowSignInStepFirst {
                HStack(spacing: 7) {
                    Text("STEP 1 OF 2")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.accentBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.accentBlue.opacity(0.14), in: Capsule())

                    Text("Z.AI Account")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                }
            } else if let acct = store.zaiAccount {
                Menu {
                    let headerTitle = (acct.email ?? "").isEmpty ? acct.displayName : (acct.email ?? acct.displayName)
                    Section(headerTitle) {
                        Button {
                            Task { await store.refreshZaiRegisteredDevices() }
                        } label: {
                            Label("Refresh Z.AI Computers", systemImage: "arrow.clockwise")
                        }

                        Button(role: .destructive) {
                            store.signOutZaiAccount()
                        } label: {
                            Label("Sign Out of Z.AI", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(palette.success)
                            .frame(width: 7, height: 7)
                        Text(acct.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(palette.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("signedInZaiAccountMenu")
            } else {
                Button {
                    store.didSkipAccountStep = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Sign in with Z.AI")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(palette.accentBlue)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(palette.accentBlue.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("returnToZaiSignInButton")
            }

            Spacer()

            Menu {
                Picker("Language", selection: $store.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 13))
                    Text(store.language.rawValue.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(palette.foregroundSubtle)
                .padding(.horizontal, 9)
                .frame(height: 34)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))
            }
            .accessibilityLabel("Language")

            Button {
                store.showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                    .frame(width: 36, height: 34)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("onboardingSettingsButton")

            if canDismissToWorkspace {
                Button {
                    store.showConnectionHub = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                        .frame(width: 36, height: 34)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to workspace")
                .accessibilityIdentifier("closeConnectionHubButton")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(palette.sidebar)
    }

    // MARK: - Step 1: Sign In with Z.AI Account

    private var stepOneZaiSignInCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(palette.card)
                        .frame(width: 72, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(palette.borderStrong, lineWidth: 1)
                        )

                    Image("ZCodeLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(spacing: 6) {
                    Text(L10n.text("Sign in to ZCode Remote", vi: "Đăng nhập ZCode Remote", zh: "登录 ZCode 远程控制", lang: store.language))
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(palette.foreground)
                        .multilineTextAlignment(.center)

                    Text(L10n.text(
                        "Authenticate with your Z.AI account to unlock ZCode Remote Control and pair with your desktop workspaces.",
                        vi: "Xác thực bằng tài khoản Z.AI để kết nối ZCode Remote Control và đồng bộ máy tính của bạn.",
                        zh: "使用您的 Z.AI 账号认证，连接 ZCode 远程控制并同步桌面工作区。",
                        lang: store.language
                    ))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.foregroundSubtle)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 8)
                }
            }
            .padding(.top, 6)

            // Region Selector (Z.AI Global vs BigModel CN)
            VStack(alignment: .leading, spacing: 8) {
                Text("Z.AI Service Region")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.foregroundMuted)

                HStack(spacing: 8) {
                    ForEach(ZaiAuthRegion.allCases) { region in
                        let selected = store.zaiRegion == region
                        Button {
                            store.playSelectionHaptic()
                            store.zaiRegion = region
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: region == .global ? "globe" : "building.2")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(region == .global ? "Z.AI Global" : "BigModel CN")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(selected ? palette.foreground : palette.foregroundSubtle)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? palette.surfaceHover : palette.inputBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selected ? palette.accentBlue : palette.border, lineWidth: selected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("zaiRegion_\(region.rawValue)")
                    }
                }
            }

            if let err = store.zaiAuthErrorMessage, !err.isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.warning)
                        .font(.system(size: 14))
                    Text(err)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(palette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.warning.opacity(0.35), lineWidth: 1))
            }

            // Primary Native OAuth Button
            VStack(spacing: 10) {
                Button {
                    Task { await store.signInWithZaiOAuth() }
                } label: {
                    HStack(spacing: 10) {
                        if store.isSigningInZai {
                            ProgressView()
                                .tint(.white)
                            Text("Waiting for Z.AI Sign-In…")
                                .font(.system(size: 15.5, weight: .semibold))
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 16, weight: .semibold))
                            Text(L10n.text("Sign in with Z.AI", vi: "Đăng nhập bằng Z.AI", zh: "使用 Z.AI 登录", lang: store.language))
                                .font(.system(size: 15.5, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x2563EB), Color(hex: 0x3B82F6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(store.isSigningInZai)
                .accessibilityIdentifier("signInWithZaiButton")

                if store.isSigningInZai {
                    Button("Cancel Sign-In") {
                        ZaiAuthAndRemoteService.shared.cancelPendingSignIn()
                        store.isSigningInZai = false
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.foregroundSubtle)
                }
            }

            // Expandable Token Sign-In Option
            VStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showAccessTokenLogin.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12))
                        Text("Use Z.AI / ZCode Access Token")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: showAccessTokenLogin ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(palette.foregroundSubtle)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toggleZaiTokenLoginButton")

                if showAccessTokenLogin {
                    VStack(spacing: 10) {
                        SecureField("Paste Z.AI or ZCode JWT / Access Token", text: $manualZaiToken)
                            .font(.system(size: 13, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))
                            .accessibilityIdentifier("zaiAccessTokenField")

                        TextField("Account Display Name (Optional)", text: $manualZaiAlias)
                            .font(.system(size: 13.5))
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))

                        Button {
                            let tok = manualZaiToken
                            let alias = manualZaiAlias
                            Task {
                                if await store.signInWithZaiToken(tok, aliasHint: alias) {
                                    manualZaiToken = ""
                                    showAccessTokenLogin = false
                                }
                            }
                        } label: {
                            Text("Verify Token & Continue")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.foreground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.borderStrong, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(manualZaiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSigningInZai)
                        .accessibilityIdentifier("verifyZaiTokenButton")
                    }
                }
            }

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            // Direct Link / QR Step Bypass
            Button {
                store.playSelectionHaptic()
                store.didSkipAccountStep = true
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.text(
                        "Continue with Z.AI Remote Link or QR Code",
                        vi: "Tiếp tục bằng link Z.AI Remote hoặc mã QR",
                        zh: "直接输入 Z.AI 远程链接或扫码连接",
                        lang: store.language
                    ))
                    .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(palette.accentBlue)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("skipToRemoteLinkStepButton")
        }
        .padding(22)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }

    // MARK: - Step 2: Enter Z.AI Remote Link / Scan QR / Select Computer

    private var stepTwoRemoteConnectContent: some View {
        VStack(spacing: 16) {
            if let clip = detectedClipboardURL {
                clipboardBanner(clip)
            }

            remoteLinkEntryCard

            if store.isZaiAuthenticated {
                registeredZaiComputersCard
            }

            if !store.connections.isEmpty {
                savedConnectionsCard
            }
        }
    }

    private func clipboardBanner(_ clip: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 18))
                .foregroundStyle(palette.accentBlue)
                .frame(width: 36, height: 36)
                .background(palette.accentBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("Z.AI Remote Link in Clipboard")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Text(clip)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button("Use Link") {
                urlInput = clip
                detectedClipboardURL = nil
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(palette.accentBlue, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityIdentifier("useClipboardLinkButton")
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.accentBlue.opacity(0.45), lineWidth: 1))
    }

    private var remoteLinkEntryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.accentBlue.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "link.icloud.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(palette.accentBlue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("STEP 2 OF 2")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accentBlue)
                        Text("• REMOTE PAIRING")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.foregroundMuted)
                    }

                    Text(L10n.text(
                        "Connect Z.AI Remote Control",
                        vi: "Kết nối Z.AI Remote Control",
                        zh: "连接 Z.AI 远程控制",
                        lang: store.language
                    ))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(palette.foreground)

                    Text(L10n.text(
                        "In ZCode Desktop, open Remote Control and paste the zcode.z.ai/remote/v4 link below or scan the QR code.",
                        vi: "Trên ZCode Desktop, mở Remote Control rồi dán link zcode.z.ai/remote/v4 vào bên dưới hoặc quét mã QR.",
                        zh: "在 ZCode 桌面端打开远程控制，粘贴下方 zcode.z.ai/remote/v4 链接或扫描二维码。",
                        lang: store.language
                    ))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.foregroundSubtle)
                    .lineSpacing(1.5)
                }
            }

            // Z.AI Remote URL Field + Paste Action
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Z.AI Remote Link or ZCode Server URL")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.foregroundSubtle)
                    Spacer()
                    Button {
                        if let str = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !str.isEmpty {
                            urlInput = str
                            store.playSelectionHaptic()
                        } else {
                            store.showToast("Clipboard is empty")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("Paste")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(palette.accentBlue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pasteRemoteURLButton")
                }

                HStack(spacing: 8) {
                    TextField(
                        "https://zcode.z.ai/remote/v4?sid=...&mid=...",
                        text: $urlInput
                    )
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(palette.foreground)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit {
                        submitConnect()
                    }
                    .accessibilityIdentifier("remoteURLTextField")

                    if !urlInput.isEmpty {
                        Button {
                            urlInput = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(palette.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear link")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            parsedPreview != nil ? palette.success.opacity(0.75) : palette.border,
                            lineWidth: 1
                        )
                )

                // Live Link Validation Feedback
                if !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let parsed = parsedPreview {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.success)
                            Text("\(parsed.transport.title) • \(parsed.name)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.success)
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.warning)
                            Text("Enter a complete https://zcode.z.ai/remote/v4?sid=...&mid=... link or ws://host:port/ws")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.warning)
                                .lineLimit(2)
                        }
                    }
                }
            }

            // Optional Device Alias
            VStack(alignment: .leading, spacing: 6) {
                Text("Computer Alias (Optional)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.foregroundMuted)

                TextField(
                    parsedPreview?.name ?? "e.g. MacBook Pro Office",
                    text: $aliasInput
                )
                .font(.system(size: 13.5))
                .foregroundStyle(palette.foreground)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                .accessibilityIdentifier("remoteAliasTextField")
            }

            // Optional Direct Server Ingress Token
            DisclosureGroup(
                isExpanded: $showAdvancedTokenField,
                content: {
                    SecureField("Ingress Bearer Token (for direct ws:// zcode-server)", text: $customBearerToken)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.border, lineWidth: 1))
                        .padding(.top, 6)
                },
                label: {
                    Text("Advanced: Custom Server Bearer Token")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.foregroundSubtle)
                }
            )
            .tint(palette.foregroundMuted)

            // Primary Connect + Scan QR Buttons
            VStack(spacing: 10) {
                Button {
                    submitConnect()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(L10n.text("Connect to ZCode Remote", vi: "Kết nối ZCode Remote", zh: "连接 ZCode 远程工作区", lang: store.language))
                            .font(.system(size: 15.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(parsedPreview != nil ? Color(hex: 0x2563EB) : Color(hex: 0x2563EB).opacity(0.45))
                    )
                }
                .buttonStyle(.plain)
                .disabled(parsedPreview == nil)
                .accessibilityIdentifier("connectRemoteLinkButton")

                Button {
                    showQRScanner = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 16, weight: .semibold))
                        Text(L10n.text("Scan ZCode Desktop QR Code", vi: "Quét mã QR ZCode Desktop", zh: "扫描 ZCode 桌面端二维码", lang: store.language))
                            .font(.system(size: 14.5, weight: .semibold))
                    }
                    .foregroundStyle(palette.foreground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboardingScanQRButton")
            }
        }
        .padding(20)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }

    // MARK: - Registered Z.AI Computers List

    private var registeredZaiComputersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Your Z.AI Computers", systemImage: "desktopcomputer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.foreground)

                Spacer()

                Button {
                    Task { await store.refreshZaiRegisteredDevices() }
                } label: {
                    if store.isLoadingZaiDevices {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.foregroundSubtle)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
            }

            if store.zaiRegisteredDevices.isEmpty {
                Text("No online computers announced under this Z.AI account yet. Open ZCode Desktop → Remote Control to copy a pairing link or scan QR.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.foregroundMuted)
                    .lineSpacing(1.5)
            } else {
                ForEach(store.zaiRegisteredDevices) { dev in
                    HStack(spacing: 12) {
                        Image(systemName: dev.platform.lowercased().contains("win") ? "pc" : "laptopcomputer")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(dev.online ? palette.accentBlue : palette.foregroundMuted)
                            .frame(width: 36, height: 36)
                            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(dev.deviceName.isEmpty ? "Unknown device" : dev.deviceName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(palette.foreground)
                                Circle()
                                    .fill(dev.online ? palette.success : palette.foregroundMuted)
                                    .frame(width: 7, height: 7)
                            }
                            Text(dev.version.isEmpty
                                 ? (dev.online ? "Online" : "Offline")
                                 : "\(dev.online ? "Online" : "Offline") • v\(dev.version)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.foregroundSubtle)
                        }

                        Spacer()

                        Button("Connect") {
                            Task { await store.connectToRegisteredZaiDevice(dev) }
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(dev.online ? palette.accentBlue : palette.foregroundMuted.opacity(0.5), in: Capsule())
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .padding(18)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }

    // MARK: - Saved Connections List (Connect / Edit / Delete)

    private var savedConnectionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Saved Connections", systemImage: "externaldrive.connected.to.line.below")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Spacer()
                Text("\(store.connections.count)")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.foregroundMuted)
            }

            ForEach(store.connections) { conn in
                HStack(spacing: 12) {
                    Button {
                        Task { await store.connectToWorkstation(conn.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: conn.transport.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(conn.state == .connected ? palette.success : palette.accentBlue)
                                .frame(width: 36, height: 36)
                                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 9))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(conn.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(palette.foreground)
                                        .lineLimit(1)
                                    if conn.state == .connected {
                                        Text("CONNECTED")
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(palette.success)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(palette.success.opacity(0.14), in: Capsule())
                                    }
                                }
                                Text(conn.url)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(palette.foregroundSubtle)
                                    .lineLimit(1)
                                Text(conn.transport.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.foregroundMuted)
                            }

                            Spacer(minLength: 4)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("savedConnectionRow_\(conn.id)")

                    Menu {
                        Button {
                            Task { await store.connectToWorkstation(conn.id) }
                        } label: {
                            Label("Connect Now", systemImage: "bolt.horizontal.circle")
                        }
                        Button {
                            editName = conn.name
                            editURL = conn.url
                            editToken = ""
                            editingConnection = conn
                        } label: {
                            Label("Edit Connection", systemImage: "pencil")
                        }
                        Button {
                            UIPasteboard.general.string = conn.url
                            store.showToast("Copied link")
                        } label: {
                            Label("Copy Link", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(role: .destructive) {
                            store.removeConnection(conn.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(palette.foregroundSubtle)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(10)
                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border, lineWidth: 1))
            }
        }
        .padding(18)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }

    // MARK: - 1:1 Official ZCode 4-Step Relay Pairing Overlay

    private var relayPairingOverlay: some View {
        let activeIdx = store.pairingPhase.activeStepIndex
        let failureText: String? = {
            if case .failed(let msg) = store.pairingPhase { return msg }
            return nil
        }()

        let steps: [(Int, String, String)] = [
            (1, "Connect to relay service", "Opening TLS WebSocket to Z.AI Remote Control"),
            (2, "Authenticate terminal", "Verifying Z.AI session & HMAC-SHA256 device challenge"),
            (3, "Pair with ZCode Desktop", "Matching target computer session (sid / mid)"),
            (4, "Sync workspaces & tasks", "Hydrating open folders, Git branches, and active tasks")
        ]

        return ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image("ZCodeLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(failureText == nil ? "Connecting to \(store.pairingTargetName)" : "Connection Failed")
                            .font(.system(size: 16.5, weight: .bold))
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                        Text(failureText == nil ? "ZCode Remote V4 Handshake" : "Check link or ZCode Desktop status")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.foregroundSubtle)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(steps, id: \.0) { idx, title, detail in
                        HStack(alignment: .top, spacing: 11) {
                            pairingStepIndicator(step: idx, activeStep: activeIdx, failed: failureText != nil)
                                .frame(width: 22, height: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.system(size: 13.5, weight: idx == activeIdx ? .semibold : .medium))
                                    .foregroundStyle(idx <= max(activeIdx, 1) ? palette.foreground : palette.foregroundMuted)
                                Text(detail)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.foregroundMuted)
                            }
                        }
                    }
                }

                if let err = failureText {
                    Text(err)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(hex: 0xFF6B6B))
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xFF6B6B).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0xFF6B6B).opacity(0.35), lineWidth: 1))
                        .accessibilityIdentifier("pairingErrorText")
                }

                HStack(spacing: 10) {
                    Button {
                        store.cancelPairingAttempt()
                    } label: {
                        Text(failureText == nil ? "Cancel" : "Edit Remote Link")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cancelOrDismissPairingButton")

                    if failureText != nil, !store.isZaiAuthenticated {
                        Button {
                            let savedTarget = store.pairingTargetId
                            store.pairingPhase = .idle
                            store.pairingTargetId = savedTarget
                            store.didSkipAccountStep = false
                        } label: {
                            Text("Sign in with Z.AI")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(palette.accentBlue, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pairingSignInWithZaiButton")
                    } else if failureText != nil, !store.pairingTargetId.isEmpty {
                        Button {
                            let targetId = store.pairingTargetId
                            Task { await store.connectToWorkstation(targetId) }
                        } label: {
                            Text("Retry")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(palette.accentBlue, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("retryPairingButton")
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.borderStrong, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func pairingStepIndicator(step: Int, activeStep: Int, failed: Bool) -> some View {
        if failed {
            if step == 1 {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0xFF6B6B))
            } else {
                Circle()
                    .strokeBorder(palette.borderStrong, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
            }
        } else if step < activeStep {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(palette.success)
        } else if step == activeStep {
            ProgressView()
                .controlSize(.small)
        } else {
            Circle()
                .strokeBorder(palette.borderStrong, lineWidth: 1.5)
                .frame(width: 16, height: 16)
        }
    }

    // MARK: - Edit Connection Sheet & Helpers

    private func editConnectionSheet(_ conn: RemoteConnection) -> some View {
        NavigationStack {
            Form {
                Section("Connection Alias & Z.AI Remote Link") {
                    TextField("Alias", text: $editName)
                    TextField("https://zcode.z.ai/remote/v4?sid=...&mid=...", text: $editURL)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Update Token (Optional)") {
                    SecureField("Bearer / Relay Token", text: $editToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { editingConnection = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.updateConnection(id: conn.id, name: editName, rawURL: editURL, token: editToken)
                        editingConnection = nil
                    }
                    .disabled(ConnectionURLParser.parse(editURL) == nil)
                }
            }
        }
    }

    private func submitConnect() {
        let raw = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let customAlias = aliasInput
        let customTok = customBearerToken
        Task {
            _ = await store.addAndConnect(rawURLOrInput: raw, customName: customAlias, token: customTok)
        }
    }

    private func inspectClipboardForRemoteLink() {
        guard UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings else { return }
        if let str = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           (str.contains("zcode") || str.contains("sid=") || str.hasPrefix("ws://") || str.hasPrefix("wss://")),
           ConnectionURLParser.parse(str) != nil,
           urlInput.isEmpty {
            detectedClipboardURL = str
        }
    }
}
