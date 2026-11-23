import SwiftUI
import AVFoundation
import PhotosUI
import CoreImage

public struct ConnectionsManagerSheetView: View {
    @Bindable var store: AppStore
    @Environment(\.zcodePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var showAddForm: Bool = false
    @State private var showQRScanner: Bool = false
    @State private var newURLInput: String = ""
    @State private var newNameInput: String = ""
    @State private var newTokenInput: String = ""
    @State private var detectedClipboardURL: String?

    public var body: some View {
        NavigationStack {
            List {
                if let clip = detectedClipboardURL {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.on.clipboard.fill")
                                .foregroundStyle(palette.accentBlue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ZCode Pairing URL in Clipboard")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(clip)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Connect") {
                                Task {
                                    _ = await store.addAndConnect(rawURLOrInput: clip)
                                    detectedClipboardURL = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                Section("Quick Pairing & Direct Server") {
                    Button {
                        showQRScanner = true
                    } label: {
                        Label("Scan ZCode Desktop QR Code", systemImage: "qrcode.viewfinder")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityIdentifier("scanQRButton")

                    Button {
                        showAddForm = true
                    } label: {
                        Label("Add Direct ZCode Server / Relay URL", systemImage: "server.rack")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .accessibilityIdentifier("addDirectServerButton")
                }

                Section("Configured Workstations") {
                    ForEach(store.connections) { conn in
                        Button {
                            Task {
                                await store.connectToWorkstation(conn.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: conn.transport.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(conn.id == store.activeConnectionId ? palette.accentBlue : palette.foregroundSubtle)
                                    .frame(width: 34, height: 34)
                                    .background(palette.surfaceHover, in: RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(conn.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(palette.foreground)
                                        if conn.id == store.activeConnectionId {
                                            Text("ACTIVE")
                                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                                .foregroundStyle(palette.success)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(palette.success.opacity(0.14), in: Capsule())
                                        }
                                    }
                                    Text(conn.url)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(palette.foregroundSubtle)
                                        .lineLimit(1)
                                    Text(connSubtitle(conn))
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.foregroundMuted)
                                }

                                Spacer()
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if conn.transport != .enterpriseSandbox {
                                Button(role: .destructive) {
                                    store.removeConnection(conn.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Workstations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("doneWorkstationsButton")
                }
            }
            .onAppear {
                if let str = UIPasteboard.general.string,
                   (str.contains("zcode") || str.contains("sid=") || str.hasPrefix("ws://") || str.hasPrefix("wss://")),
                   ConnectionURLParser.parse(str) != nil {
                    detectedClipboardURL = str
                }
            }
            .sheet(isPresented: $showAddForm) {
                addConnectionFormSheet
            }
            .sheet(isPresented: $showQRScanner) {
                NativeQRScannerSheetView { scanned in
                    showQRScanner = false
                    Task {
                        _ = await store.addAndConnect(rawURLOrInput: scanned)
                    }
                }
            }
        }
    }

    private func connSubtitle(_ conn: RemoteConnection) -> String {
        var parts: [String] = [conn.transport.title]
        if !conn.serverVersion.isEmpty { parts.append("v\(conn.serverVersion)") }
        if conn.latencyMs > 0 { parts.append("\(conn.latencyMs)ms") }
        return parts.joined(separator: " • ")
    }

    private var addConnectionFormSheet: some View {
        NavigationStack {
            Form {
                Section("Endpoint or Pairing URL") {
                    TextField("ws://192.168.1.16:57743/ws or https://zcode.z.ai/remote/v4?...", text: $newURLInput)
                        .font(.system(size: 13.5, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("newConnectionURLField")

                    TextField("Display Name (Optional)", text: $newNameInput)
                        .accessibilityIdentifier("newConnectionNameField")
                }

                Section("Authentication (Stored in iOS Keychain)") {
                    SecureField("Ingress Bearer Token or Relay Token (Optional)", text: $newTokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add Workstation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showAddForm = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save & Connect") {
                        let url = newURLInput
                        let name = newNameInput
                        let tok = newTokenInput
                        showAddForm = false
                        newURLInput = ""
                        newNameInput = ""
                        newTokenInput = ""
                        Task {
                            _ = await store.addAndConnect(rawURLOrInput: url, customName: name, token: tok)
                        }
                    }
                    .disabled(newURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveConnectionButton")
                }
            }
        }
    }
}

// MARK: - 100% Native AVFoundation QR Scanner + Photo Library QR Decoder

public struct NativeQRScannerSheetView: View {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var manualURL: String = ""
    @State private var torchOn: Bool = false

    private var hasCameraHardware: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if hasCameraHardware {
                    ZStack {
                        CameraQRPreviewRepresentable(torchOn: torchOn, onCodeScanned: onScanned)
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(hex: 0x3B82F6), style: StrokeStyle(lineWidth: 3, dash: [18, 10]))
                            .frame(width: 230, height: 230)
                    }
                    .frame(height: 320)
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 52))
                            .foregroundStyle(Color(hex: 0x3B82F6))
                        Text("Camera Viewfinder Ready on Physical iPhone")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Import a QR screenshot from Photos or paste your ZCode Desktop pairing URL below.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Scan from Photos", systemImage: "photo.on.rectangle")
                            .font(.system(size: 13.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.bordered)

                    if hasCameraHardware {
                        Button {
                            torchOn.toggle()
                        } label: {
                            Label(torchOn ? "Torch On" : "Torch", systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 13.5, weight: .semibold))
                                .frame(height: 42)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Or Paste Pairing URL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("https://zcode.z.ai/remote/v4?sid=...&mid=...", text: $manualURL)
                            .font(.system(size: 13, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button("Pair") {
                            onScanned(manualURL)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Scan ZCode QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("closeQRScannerButton")
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let ciImage = CIImage(data: data),
                       let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) {
                        let features = detector.features(in: ciImage)
                        if let qr = features.compactMap({ $0 as? CIQRCodeFeature }).first?.messageString {
                            onScanned(qr)
                        }
                    }
                }
            }
        }
    }
}

private struct CameraQRPreviewRepresentable: UIViewControllerRepresentable {
    let torchOn: Bool
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {
        uiViewController.setTorch(torchOn)
    }

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCodeScanned: ((String) -> Void)?
        private let captureSession = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didEmit = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let videoDevice = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: videoDevice),
                  captureSession.canAddInput(input) else { return }
            captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                if output.availableMetadataObjectTypes.contains(.qr) {
                    output.metadataObjectTypes = [.qr]
                }
            }

            let layer = AVCaptureVideoPreviewLayer(session: captureSession)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            self.previewLayer = layer

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        func setTorch(_ enabled: Bool) {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
            try? device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didEmit,
                  let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = readable.stringValue else { return }
            didEmit = true
            captureSession.stopRunning()
            onCodeScanned?(value)
        }
    }
}
