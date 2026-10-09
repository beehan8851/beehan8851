import SwiftUI
import UIKit

// MARK: - Memory mission

struct MemoryMissionView: View {
    let config: MissionConfig
    var onSuccess: () -> Void

    private let difficulty: MemoryDifficulty
    private let rounds: Int
    @State private var phase: Phase = .memorize
    @State private var round = 0
    @State private var highlighted: Set<Int> = []
    @State private var selected: Set<Int> = []
    @State private var isWrong = false
    @State private var showingPattern = false

    private enum Phase { case memorize, recall, feedback }

    init(config: MissionConfig, onSuccess: @escaping () -> Void) {
        self.config = config
        self.onSuccess = onSuccess
        if case .memory(let d, let r) = config { difficulty = d; rounds = r }
        else { difficulty = .easy; rounds = 1 }
    }

    private var columns: Int { difficulty.columns }
    private var cellCount: Int { columns * columns }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                missionHeader
                Spacer()
                instructionText
                    .padding(.bottom, DesignTokens.Spacing.m)
                grid
                    .padding(.horizontal, DesignTokens.Spacing.l)
                Spacer()
            }
        }
        .onAppear { startRound() }
    }

    private var missionHeader: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: MissionKind.memory.systemImage).font(.system(size: 14)).foregroundStyle(DesignTokens.Colors.emberText)
                Text(String(localized: "Memory", comment: "Memory mission header")).font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            if rounds > 1 {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(0..<rounds, id: \.self) { i in
                        Circle().fill(i < round ? DesignTokens.Colors.ember : DesignTokens.Colors.surfaceSecondary)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .padding(.top, DesignTokens.Spacing.l)
    }

    /// How long the pattern stays up.
    private static let memorizeSeconds: Double = 2.5

    private var instructionText: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            instructionLabel
            // A bar that drains while the pattern is up, so the moment it vanishes is
            // never a surprise.
            GeometryReader { proxy in
                Capsule()
                    .fill(DesignTokens.Colors.ember)
                    .frame(width: proxy.size.width * (showingPattern ? 0 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(showingPattern ? .linear(duration: Self.memorizeSeconds) : nil, value: showingPattern)
            }
            .frame(height: 3)
            .background(Capsule().fill(DesignTokens.Colors.surfaceSecondary))
            .frame(width: 120)
            .opacity(phase == .memorize ? 1 : 0)
            .accessibilityHidden(true)
        }
    }

    private var instructionLabel: some View {
        Group {
            switch phase {
            case .memorize:
                Text(String(localized: "Memorize the pattern", comment: "Memory memorize phase"))
            case .recall:
                Text(String(localized: "Tap the highlighted cells", comment: "Memory recall phase"))
            case .feedback:
                Text(isWrong
                     ? String(localized: "Wrong — try again", comment: "Memory wrong")
                     : String(localized: "Correct!", comment: "Memory correct"))
                    .foregroundStyle(isWrong ? DesignTokens.Colors.destructive : DesignTokens.Colors.success)
            }
        }
        .font(.mcCallout)
        .foregroundStyle(DesignTokens.Colors.textSecondary)
        // No crossfade: two instructions layered on top of each other read as neither.
        .transaction { $0.animation = nil }
    }

    private var grid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(0..<cellCount, id: \.self) { idx in
                cellView(for: idx)
            }
        }
    }

    private func cellView(for idx: Int) -> some View {
        let isHighlighted = highlighted.contains(idx)
        let isSelected = selected.contains(idx)
        let canTap = phase == .recall

        return RoundedRectangle(cornerRadius: 10)
            .fill(cellColor(idx: idx, highlighted: isHighlighted, selected: isSelected))
            .frame(height: CGFloat(64 / max(1, columns - 2)))
            .animation(.easeInOut(duration: 0.15), value: showingPattern)
            .onTapGesture {
                guard canTap else { return }
                Haptics.impact(.light)
                if selected.contains(idx) { selected.remove(idx) } else { selected.insert(idx) }
                if selected.count == highlighted.count { checkSelection() }
            }
            // A filled shape with a tap gesture is not a control as far as VoiceOver
            // is concerned — it is not focusable and has nothing to say. The grid is
            // read by position because the cells are otherwise indistinguishable.
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(String(
                localized: "Row \(idx / columns + 1), column \(idx % columns + 1)",
                comment: "Memory grid cell position"
            ))
            .accessibilityValue(isSelected
                ? String(localized: "Selected", comment: "Memory cell state")
                : String(localized: "Not selected", comment: "Memory cell state"))
    }

    private func cellColor(idx: Int, highlighted: Bool, selected: Bool) -> Color {
        if phase == .memorize && showingPattern && highlighted {
            return DesignTokens.Colors.ember
        }
        if phase == .recall || phase == .feedback {
            if selected { return DesignTokens.Colors.ember.opacity(0.85) }
        }
        return DesignTokens.Colors.surfacePrimary
    }

    private func startRound() {
        selected = []
        isWrong = false
        phase = .memorize
        let indices = Array(0..<cellCount).shuffled().prefix(difficulty.highlightCount)
        highlighted = Set(indices)
        showingPattern = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.memorizeSeconds * 1_000_000_000))
            withAnimation { showingPattern = false }
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation { phase = .recall }
        }
    }

    private func checkSelection() {
        if selected == highlighted {
            Haptics.notify(.success)
            phase = .feedback
            isWrong = false
            let nextRound = round + 1
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if nextRound >= rounds {
                    onSuccess()
                } else {
                    round = nextRound
                    startRound()
                }
            }
        } else if selected.count == highlighted.count {
            Haptics.notify(.error)
            phase = .feedback
            isWrong = true
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                startRound()
            }
        }
    }
}

#Preview("Memory — easy") {
    MemoryMissionView(config: .defaultMemory, onSuccess: {})
        .environment(AppContainer.preview())
}
