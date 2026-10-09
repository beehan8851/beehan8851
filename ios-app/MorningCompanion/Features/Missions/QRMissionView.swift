import SwiftUI
import AVFoundation

// MARK: - Scanner coordinator

final class QRScannerCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput objects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let obj = objects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let value = obj.stringValue else { return }
        onFound?(value)
    }
}

// MARK: - Camera preview view

/// Auto-sizes the AVCaptureVideoPreviewLayer in layoutSubviews so the preview
/// fills the view correctly regardless of when bounds are first assigned.
final class QRPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var session: AVCaptureSession?

    func setup(session: AVCaptureSession) {
        guard self.session == nil else { return }
        self.session = session
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func stopSession() {
        guard let s = session else { return }
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - QRScannerView (UIViewRepresentable)

struct QRScannerView: UIViewRepresentable {
    var onFound: (String) -> Void

    func makeCoordinator() -> QRScannerCoordinator { QRScannerCoordinator() }

    func makeUIView(context: Context) -> QRPreviewView {
        let view = QRPreviewView()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return view }
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            output.metadataObjectTypes = [.qr, .ean13, .ean8, .code128, .code39, .upce]
        }
        session.commitConfiguration()
        view.setup(session: session)
        return view
    }

    func updateUIView(_ uiView: QRPreviewView, context: Context) {
        // Only update the callback — frame is handled by layoutSubviews
        context.coordinator.onFound = onFound
    }

    static func dismantleUIView(_ uiView: QRPreviewView, coordinator: QRScannerCoordinator) {
        uiView.stopSession()
    }
}

// MARK: - QR mission (alarm-time)

struct QRMissionView: View {
    let config: MissionConfig
    var onSuccess: () -> Void

    private let registeredCode: String?
    @State private var isWrong = false
    @State private var succeeded = false
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL

    init(config: MissionConfig, onSuccess: @escaping () -> Void) {
        self.config = config
        self.onSuccess = onSuccess
        if case .qrCode(let code) = config { registeredCode = code } else { registeredCode = nil }
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                missionHeader
                switch cameraPermission {
                case .denied, .restricted:
                    cameraPermissionDenied
                case .authorized:
                    if registeredCode == nil { notConfigured } else { scannerBody }
                default:
                    // .notDetermined — waiting for system dialog; don't create scanner yet
                    Spacer()
                    ProgressView().tint(DesignTokens.Colors.accent)
                    Spacer()
                }
            }
        }
        .onAppear { checkPermission() }
    }

    // MARK: - Sub-views

    private var missionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: MissionKind.qrCode.systemImage)
                .font(.system(size: 14)).foregroundStyle(DesignTokens.Colors.emberText)
            Text(String(localized: "QR Code", comment: "QR mission header"))
                .font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.top, DesignTokens.Spacing.l)
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    private var scannerBody: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            ZStack {
                QRScannerView { code in handleScan(code) }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))

                RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                    .stroke(isWrong ? DesignTokens.Colors.destructive : DesignTokens.Colors.ember, lineWidth: 2)
                    .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: isWrong)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .padding(.horizontal, DesignTokens.Spacing.l)

            Text(isWrong
                 ? String(localized: "Wrong code — scan your registered code", comment: "QR wrong code")
                 : String(localized: "Scan your registered QR or barcode",     comment: "QR instruction"))
                .font(.mcCallout)
                .foregroundStyle(isWrong ? DesignTokens.Colors.destructive : DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.l)
                .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: isWrong)

            Spacer()
        }
    }

    private var cameraPermissionDenied: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 48, weight: .thin)).foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(String(localized: "Camera access is required to scan QR codes.\nEnable it in Settings.",
                        comment: "Camera permission denied"))
                .font(.mcCallout).foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, DesignTokens.Spacing.l)
            Button(String(localized: "Open Settings", comment: "Open app settings")) {
                openURL(URL(string: UIApplication.openSettingsURLString)!)
            }
            .font(.mcSubhead.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.onEmber)
            .padding(.horizontal, DesignTokens.Spacing.l).padding(.vertical, 10)
            .background(DesignTokens.Colors.ember).clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous))
            Spacer()
        }
    }

    private var notConfigured: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Spacer()
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 48, weight: .thin)).foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(String(localized: "This alarm's QR code has not been set up.", comment: "QR not configured"))
                .font(.mcCallout).foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, DesignTokens.Spacing.l)
            Spacer()
        }
    }

    // MARK: - Logic

    private func handleScan(_ code: String) {
        guard !succeeded, let registered = registeredCode else { return }
        if code == registered {
            succeeded = true
            Haptics.notify(.success)
            onSuccess()
        } else {
            guard !isWrong else { return }
            Haptics.notify(.error)
            withAnimation { isWrong = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation { isWrong = false }
            }
        }
    }

    private func checkPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cameraPermission = granted ? .authorized : .denied }
            }
        } else {
            cameraPermission = status
        }
    }
}

// MARK: - QR setup (alarm editor)

struct QRSetupView: View {
    @Binding var config: MissionConfig
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var scannedCode: String?
    @State private var scanning = true
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.Colors.background.ignoresSafeArea()
                VStack(spacing: DesignTokens.Spacing.m) {
                    switch cameraStatus {
                    case .authorized:
                        authorizedBody
                    case .denied, .restricted:
                        permissionDeniedBody
                    default:
                        Spacer()
                        ProgressView().tint(DesignTokens.Colors.accent)
                        Spacer()
                    }
                }
                .padding(.top, DesignTokens.Spacing.m)
            }
            .navigationTitle(String(localized: "Register QR Code", comment: "QR setup nav title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel")) { dismiss() }
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .task { await requestCameraPermission() }
        }
    }

    @ViewBuilder
    private var authorizedBody: some View {
        Text(String(localized: "Scan the QR or barcode you will use at alarm time.",
                    comment: "QR setup instruction"))
            .font(.mcCallout).foregroundStyle(DesignTokens.Colors.textSecondary)
            .multilineTextAlignment(.center).padding(.horizontal, DesignTokens.Spacing.l)

        if scanning {
            QRScannerView { code in
                scannedCode = code
                scanning = false
                Haptics.notify(.success)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            .frame(maxWidth: .infinity).frame(height: 300)
            .padding(.horizontal, DesignTokens.Spacing.l)
        } else if let code = scannedCode {
            VStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48)).foregroundStyle(DesignTokens.Colors.success)
                Text(String(localized: "Code registered!", comment: "QR code registered"))
                    .font(.mcTitle3).foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(code.prefix(40) + (code.count > 40 ? "…" : ""))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, DesignTokens.Spacing.l)

                HStack(spacing: DesignTokens.Spacing.s) {
                    Button(String(localized: "Rescan", comment: "Rescan QR button")) {
                        scannedCode = nil; scanning = true
                    }
                    .font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.m).padding(.vertical, 10)
                    .background(DesignTokens.Colors.surfacePrimary).clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous))

                    Button(String(localized: "Save", comment: "Save QR registration")) {
                        config = .qrCode(registeredCode: code)
                        dismiss()
                    }
                    .font(.mcSubhead).fontWeight(.semibold)
                    .foregroundStyle(DesignTokens.Colors.onEmber)
                    .padding(.horizontal, DesignTokens.Spacing.m).padding(.vertical, 10)
                    .background(DesignTokens.Colors.ember).clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous))
                }
            }
            .padding(.top, DesignTokens.Spacing.l)
        }
        Spacer()
    }

    private var permissionDeniedBody: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 52, weight: .thin)).foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(String(localized: "Camera access is required to scan QR codes.\nEnable it in Settings.",
                        comment: "QR camera denied"))
                .font(.mcCallout).foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, DesignTokens.Spacing.l)
            Button(String(localized: "Open Settings", comment: "Open app settings")) {
                openURL(URL(string: UIApplication.openSettingsURLString)!)
            }
            .font(.mcSubhead.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.onEmber)
            .padding(.horizontal, DesignTokens.Spacing.l).padding(.vertical, 10)
            .background(DesignTokens.Colors.ember).clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous))
            Spacer()
        }
    }

    private func requestCameraPermission() async {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        if current == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraStatus = granted ? .authorized : .denied
        } else {
            cameraStatus = current
        }
    }
}
