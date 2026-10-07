import SwiftUI
import CoreMotion

// MARK: - Jump mission

/// Detects jump impacts using CMMotionManager's accelerometer.
/// A vertical acceleration spike above threshold (cleared device movement pattern)
/// counts as one jump.
struct JumpMissionView: View {
    let config: MissionConfig
    var onSuccess: () -> Void

    private let required: Int
    @State private var count = 0
    @State private var iconBump = false
    @State private var motionManager: CMMotionManager?
    @State private var lastJumpTime: Date = .distantPast
    @State private var notAvailable = false
    // 3.2g total (≈2.2g net above gravity) — filters out quick phone lifts, catches real jumps
    private let jumpThreshold: Double = 3.2
    private let jumpCooldown: TimeInterval = 0.8

    init(config: MissionConfig, onSuccess: @escaping () -> Void) {
        self.config = config
        self.onSuccess = onSuccess
        if case .jump(let n) = config { required = n } else { required = 5 }
    }

    private var progress: Double { min(1.0, Double(count) / Double(required)) }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                missionHeader
                Spacer()

                Image(systemName: "figure.jumprope")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(DesignTokens.Colors.emberText)
                    .scaleEffect(iconBump ? 1.3 : 1.0)
                    .animation(.spring(response: 0.20, dampingFraction: 0.35), value: iconBump)
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

                if notAvailable {
                    Text(String(localized: "Jump detection unavailable on this device.", comment: "Jump unavailable"))
                        .font(.mcCallout)
                        .foregroundStyle(DesignTokens.Colors.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.l)
                } else {
                    Text(String(localized: "Jump to wake up!", comment: "Jump mission instruction"))
                        .font(.mcCallout)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()

                #if targetEnvironment(simulator)
                Button(String(localized: "Simulate Jump", comment: "Simulator jump fallback")) { recordJump() }
                    .font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.bottom, DesignTokens.Spacing.xl)
                #else
                Spacer().frame(height: DesignTokens.Spacing.xl)
                #endif
            }
        }
        .onAppear { startMotion() }
        .onDisappear { motionManager?.stopAccelerometerUpdates(); motionManager = nil }
    }

    private var missionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: MissionKind.jump.systemImage).font(.system(size: 14)).foregroundStyle(DesignTokens.Colors.emberText)
            Text(String(localized: "Jump", comment: "Jump mission header")).font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.top, DesignTokens.Spacing.l)
    }

    private func startMotion() {
        let manager = CMMotionManager()
        guard manager.isAccelerometerAvailable else { notAvailable = true; return }
        manager.accelerometerUpdateInterval = 0.05
        manager.startAccelerometerUpdates(to: .main) { data, _ in
            guard let data else { return }
            // Total acceleration magnitude
            let a = data.acceleration
            let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            if mag > jumpThreshold {
                let now = Date()
                if now.timeIntervalSince(lastJumpTime) > jumpCooldown {
                    lastJumpTime = now
                    recordJump()
                }
            }
        }
        motionManager = manager
    }

    private func recordJump() {
        guard count < required else { return }
        Haptics.impact(.heavy)
        iconBump = true
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            iconBump = false
        }
        count += 1
        if count >= required {
            Haptics.notify(.success)
            motionManager?.stopAccelerometerUpdates()
            Task { try? await Task.sleep(nanoseconds: 300_000_000); onSuccess() }
        }
    }
}

#Preview("Jump mission") {
    JumpMissionView(config: .defaultJump, onSuccess: {})
        .environment(AppContainer.preview())
}
