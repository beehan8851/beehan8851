import SwiftUI
import CoreMotion

// MARK: - Steps mission

struct StepsMissionView: View {
    let config: MissionConfig
    var onSuccess: () -> Void

    private let required: Int
    @Environment(\.openURL) private var openURL

    @State private var count: Int = 0
    @State private var pedometer = CMPedometer()
    @State private var notAvailable = false
    /// Motion access refused. Distinct from `notAvailable`: the hardware is there, the
    /// permission is not, and unlike a missing pedometer that is something the user
    /// can change.
    @State private var motionDenied = false
    @State private var baselineSteps: Int? = nil
    @State private var didSucceed = false

    init(config: MissionConfig, onSuccess: @escaping () -> Void) {
        self.config = config
        self.onSuccess = onSuccess
        if case .steps(let n) = config { required = n } else { required = 20 }
    }

    private var progress: Double { min(1.0, Double(count) / Double(required)) }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                missionHeader
                Spacer()

                Image(systemName: "figure.walk")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(DesignTokens.Colors.emberText)
                    .padding(.bottom, DesignTokens.Spacing.m)
                    .symbolEffect(.bounce, value: count)

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

                if motionDenied {
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        Text(String(localized: "Motion access is off, so steps can't be counted.", comment: "Motion permission denied during the steps mission"))
                            .font(.mcCallout)
                            .foregroundStyle(DesignTokens.Colors.destructive)
                            .multilineTextAlignment(.center)
                        Button(String(localized: "Open Settings", comment: "Opens the Settings app")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.mcSubhead)
                        .foregroundStyle(DesignTokens.Colors.emberText)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.l)
                } else if notAvailable {
                    Text(String(localized: "Step counting unavailable on this device.", comment: "Pedometer unavailable"))
                        .font(.mcCallout)
                        .foregroundStyle(DesignTokens.Colors.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.l)
                } else {
                    Text(String(localized: "Walk to wake up!", comment: "Steps mission instruction"))
                        .font(.mcCallout)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()

                #if targetEnvironment(simulator)
                Button(String(localized: "Simulate Steps", comment: "Simulator fallback")) { simulateSteps() }
                    .font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.bottom, DesignTokens.Spacing.xl)
                #else
                Spacer().frame(height: DesignTokens.Spacing.xl)
                #endif
            }
        }
        .onAppear { startTracking() }
        .onDisappear { pedometer.stopUpdates() }
    }

    private var missionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: MissionKind.steps.systemImage).font(.system(size: 14)).foregroundStyle(DesignTokens.Colors.emberText)
            Text(String(localized: "Steps", comment: "Steps mission header")).font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.top, DesignTokens.Spacing.l)
    }

    private func startTracking() {
        guard CMPedometer.isStepCountingAvailable() else {
            notAvailable = true
            return
        }
        // Asked before the first query so a refusal is stated rather than looking like
        // a mission that simply never counts anything — at the one moment the user is
        // least able to work out why.
        if CMPedometer.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .restricted {
            motionDenied = true
            return
        }

        let start = Date()
        pedometer.startUpdates(from: start) { data, error in
            guard let data, error == nil else {
                // A refusal can also arrive here, on the first update after the prompt.
                if let error = error as? NSError, error.domain == CMErrorDomain {
                    DispatchQueue.main.async { motionDenied = true }
                }
                return
            }
            DispatchQueue.main.async {
                let rawCount = data.numberOfSteps.intValue
                // Capture first reading as baseline to ignore any stale data iOS delivers
                if baselineSteps == nil {
                    baselineSteps = rawCount
                    return
                }
                let newCount = max(0, rawCount - (baselineSteps ?? 0))
                if newCount != count {
                    Haptics.impact(.light)
                    count = newCount
                    if count >= required, !didSucceed {
                        didSucceed = true
                        Haptics.notify(.success)
                        pedometer.stopUpdates()
                        Task { try? await Task.sleep(nanoseconds: 300_000_000); onSuccess() }
                    }
                }
            }
        }
    }

    private func simulateSteps() {
        count = min(count + 5, required)
        Haptics.impact(.medium)
        if count >= required, !didSucceed {
            didSucceed = true
            Haptics.notify(.success)
            Task { try? await Task.sleep(nanoseconds: 300_000_000); onSuccess() }
        }
    }
}

#Preview("Steps mission") {
    StepsMissionView(config: .defaultSteps, onSuccess: {})
        .environment(AppContainer.preview())
}
