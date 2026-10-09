import SwiftUI
import UIKit

// MARK: - Shake detector

private class ShakeDetectorView: UIView {
    var onShake: (() -> Void)?
    override var canBecomeFirstResponder: Bool { true }
    override func didMoveToWindow() { super.didMoveToWindow(); becomeFirstResponder() }
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { onShake?() }
    }
}

private struct ShakeDetector: UIViewRepresentable {
    var onShake: () -> Void
    func makeUIView(context: Context) -> ShakeDetectorView {
        let v = ShakeDetectorView(); v.onShake = onShake; return v
    }
    func updateUIView(_ uiView: ShakeDetectorView, context: Context) { uiView.onShake = onShake }
}

// MARK: - Shake mission

struct ShakeMissionView: View {
    let config: MissionConfig
    var onSuccess: () -> Void

    private let required: Int
    @State private var count = 0
    @State private var iconBump = false

    init(config: MissionConfig, onSuccess: @escaping () -> Void) {
        self.config = config
        self.onSuccess = onSuccess
        if case .shake(let n) = config { required = n } else { required = 10 }
    }

    private var progress: Double { Double(count) / Double(required) }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            ShakeDetector(onShake: handleShake).frame(width: 1, height: 1).allowsHitTesting(false)

            VStack(spacing: 0) {
                missionHeader
                Spacer()
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(DesignTokens.Colors.emberText)
                    .scaleEffect(iconBump ? 1.28 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.38), value: iconBump)
                    .padding(.bottom, DesignTokens.Spacing.m)

                Text("\(count) / \(required)")
                    .font(.system(size: 52, weight: .bold).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .padding(.bottom, DesignTokens.Spacing.s)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DesignTokens.Colors.surfaceSecondary).frame(height: 6)
                        Capsule().fill(DesignTokens.Colors.ember)
                            .frame(width: geo.size.width * CGFloat(progress), height: 6)
                            .animation(.easeOut(duration: DesignTokens.Motion.controls), value: progress)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, DesignTokens.Spacing.l)
                .padding(.bottom, DesignTokens.Spacing.m)

                Text(String(localized: "Shake your phone to wake up!", comment: "Shake instruction"))
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Spacer()

                #if targetEnvironment(simulator)
                Button(String(localized: "Simulate Shake", comment: "Simulator fallback")) { handleShake() }
                    .font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.bottom, DesignTokens.Spacing.xl)
                #else
                Spacer().frame(height: DesignTokens.Spacing.xl)
                #endif
            }
        }
    }

    private var missionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: MissionKind.shake.systemImage).font(.system(size: 14)).foregroundStyle(DesignTokens.Colors.emberText)
            Text(String(localized: "Shake", comment: "Shake mission header")).font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.top, DesignTokens.Spacing.l)
    }

    private func handleShake() {
        guard count < required else { return }
        Haptics.impact(.medium)
        iconBump = true
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            iconBump = false
        }
        count += 1
        if count >= required {
            Haptics.notify(.success)
            Task { try? await Task.sleep(nanoseconds: 300_000_000); onSuccess() }
        }
    }
}

#Preview("Shake mission") {
    ShakeMissionView(config: .defaultShake, onSuccess: {})
        .environment(AppContainer.preview())
}
