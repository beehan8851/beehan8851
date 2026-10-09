import SwiftUI
import UIKit

// MARK: - Math problem

private struct MathProblem {
    enum Op { case add, sub, mul
        var symbol: String { switch self { case .add: return "+"; case .sub: return "−"; case .mul: return "×" } }
    }
    let a: Int
    let b: Int
    let op: Op
    var answer: Int { switch op { case .add: return a + b; case .sub: return a - b; case .mul: return a * b } }
    var display: String { "\(a)  \(op.symbol)  \(b)" }
    var spoken: String {
        switch op {
        case .add: return String(localized: "\(a) plus \(b)", comment: "Math problem, VoiceOver")
        case .sub: return String(localized: "\(a) minus \(b)", comment: "Math problem, VoiceOver")
        case .mul: return String(localized: "\(a) times \(b)", comment: "Math problem, VoiceOver")
        }
    }

    static func generate(difficulty: MathDifficulty, index: Int) -> MathProblem {
        switch difficulty {
        case .easy:
            return MathProblem(a: Int.random(in: 2...9), b: Int.random(in: 2...9), op: .add)
        case .medium:
            let ops: [Op] = [.add, .sub, .mul]
            let op = ops[index % ops.count]
            switch op {
            case .add: return MathProblem(a: Int.random(in: 10...40), b: Int.random(in: 5...20), op: .add)
            case .sub:
                let a = Int.random(in: 15...50)
                return MathProblem(a: a, b: Int.random(in: 3...min(a - 1, 15)), op: .sub)
            case .mul: return MathProblem(a: Int.random(in: 3...9), b: Int.random(in: 3...9), op: .mul)
            }
        case .hard:
            let ops: [Op] = [.mul, .sub, .mul]
            let op = ops[index % ops.count]
            switch op {
            case .mul: return MathProblem(a: Int.random(in: 12...19), b: Int.random(in: 3...9), op: .mul)
            case .sub:
                let a = Int.random(in: 30...99)
                return MathProblem(a: a, b: Int.random(in: 10...min(a - 5, 30)), op: .sub)
            case .add: return MathProblem(a: Int.random(in: 40...90), b: Int.random(in: 20...50), op: .add)
            }
        }
    }
}

// MARK: - Math mission

struct MathMissionView: View {
    let config: MissionConfig
    var onSuccess: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var problems: [MathProblem]
    @State private var index = 0
    @State private var input = ""
    @State private var isWrong = false
    @State private var errorOffset: CGFloat = 0

    private let difficulty: MathDifficulty
    private let rounds: Int

    init(config: MissionConfig, onSuccess: @escaping () -> Void) {
        self.config = config
        self.onSuccess = onSuccess
        guard case .math(let d, let r) = config else {
            difficulty = .medium; rounds = 3
            _problems = State(wrappedValue: (0..<3).map { MathProblem.generate(difficulty: .medium, index: $0) })
            return
        }
        difficulty = d; rounds = r
        _problems = State(wrappedValue: (0..<r).map { MathProblem.generate(difficulty: d, index: $0) })
    }

    private var current: MathProblem { problems[index] }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer()
                problemArea
                Spacer()
                keypad
            }
        }
        .accessibilityAction(.escape) {}
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: MissionKind.math.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.Colors.emberText)
                Text(String(localized: "Math", comment: "Math mission header"))
                    .font(.mcSubhead)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(0..<rounds, id: \.self) { i in
                    Circle()
                        .fill(i <= index ? DesignTokens.Colors.ember : DesignTokens.Colors.surfaceSecondary)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: DesignTokens.Motion.controls), value: index)
                }
            }
        }
        .padding(.top, DesignTokens.Spacing.l)
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    // MARK: Problem

    private var problemArea: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            Text(current.display)
                .font(.mcDisplay(52))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .id(index)
                .accessibilityLabel(current.spoken)

            Text(verbatim: "=")
                .font(.mcDisplay(36, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .accessibilityHidden(true)

            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                    .fill(isWrong ? DesignTokens.Colors.destructive.opacity(0.12) : DesignTokens.Colors.surfacePrimary)
                    .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: isWrong)
                RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                    .stroke(isWrong ? DesignTokens.Colors.destructive : DesignTokens.Colors.surfaceSecondary, lineWidth: 1.5)
                    .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: isWrong)
                Text(input.isEmpty ? "?" : input)
                    .font(.mcCountdown(.largeTitle, weight: .regular))
                    .foregroundStyle(input.isEmpty ? DesignTokens.Colors.textTertiary
                                     : (isWrong ? DesignTokens.Colors.destructive : DesignTokens.Colors.textPrimary))
                    .accessibilityLabel(input.isEmpty
                                        ? String(localized: "Your answer", comment: "Math answer field, empty")
                                        : String(localized: "Your answer, \(input)", comment: "Math answer field"))
            }
            .frame(height: 80)
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .offset(x: errorOffset)

            // The wrong answer stays on screen for a beat, in red, before it clears —
            // a half-asleep person needs to see *what* they typed, not just that it was wrong.
            Text(isWrong
                 ? String(localized: "Not quite. Try again.", comment: "Wrong answer hint")
                 : String(localized: "Round \(index + 1) of \(rounds)", comment: "Math round counter"))
                .font(.mcFootnote)
                .foregroundStyle(isWrong ? DesignTokens.Colors.destructive : DesignTokens.Colors.textSecondary)
                .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: isWrong)
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
    }

    // MARK: Keypad

    private var keypad: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            numericRow([1, 2, 3])
            numericRow([4, 5, 6])
            numericRow([7, 8, 9])
            HStack(spacing: DesignTokens.Spacing.xs) {
                deleteButton; digitButton(0); submitButton
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.bottom, DesignTokens.Spacing.xl)
    }

    private func numericRow(_ digits: [Int]) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) { ForEach(digits, id: \.self) { digitButton($0) } }
    }

    private func digitButton(_ digit: Int) -> some View {
        Button { guard input.count < 4 else { return }; input += "\(digit)" } label: {
            Text("\(digit)")
                .font(.mcCountdown(.title, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 64)
                .background(DesignTokens.Colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s))
        }.buttonStyle(KeypadButtonStyle())
    }

    private var deleteButton: some View {
        Button { if !input.isEmpty { input.removeLast() } } label: {
            Image(systemName: "delete.backward")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity).frame(height: 64)
                .background(DesignTokens.Colors.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s))
        }
        .buttonStyle(KeypadButtonStyle())
        .accessibilityLabel(String(localized: "Delete", comment: "Keypad delete button"))
    }

    private var submitButton: some View {
        Button { checkAnswer() } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(input.isEmpty ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.onEmber)
                .frame(maxWidth: .infinity).frame(height: 64)
                .background(input.isEmpty ? DesignTokens.Colors.surfaceSecondary : DesignTokens.Colors.ember)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s))
                .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: input.isEmpty)
        }
        .buttonStyle(KeypadButtonStyle())
        .disabled(input.isEmpty)
        .accessibilityLabel(String(localized: "Submit answer", comment: "Keypad submit button"))
    }

    private func checkAnswer() {
        guard let entered = Int(input) else { return }
        if entered == current.answer {
            Haptics.notify(.success)
            input = ""
            if index + 1 < rounds {
                withAnimation(.easeInOut(duration: DesignTokens.Motion.controls)) { index += 1 }
            } else {
                onSuccess()
            }
        } else {
            Haptics.notify(.error)
            // A side-to-side shake is a textbook vestibular trigger. With Reduce Motion
            // on, the colour change and the haptic carry the same message.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.2)) {
                isWrong = true
                errorOffset = reduceMotion ? 0 : 14
            }
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { errorOffset = 0 }
                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation { isWrong = false }
                input = ""
            }
        }
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

#Preview("Math — medium") {
    MathMissionView(config: .defaultMath, onSuccess: {})
        .environment(AppContainer.preview())
}
