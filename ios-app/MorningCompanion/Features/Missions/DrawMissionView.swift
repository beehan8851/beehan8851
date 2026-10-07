import SwiftUI
import UIKit

// MARK: - Drawing canvas

final class DrawingCanvasView: UIView {
    var strokes: [[(CGPoint)]] = []
    var onStrokeComplete: (([CGPoint]) -> Void)?

    private var currentStroke: [CGPoint] = []
    private let pathLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        pathLayer.strokeColor = Self.resolvedStrokeColor(for: .current)
        pathLayer.fillColor = UIColor.clear.cgColor
        pathLayer.lineWidth = 3
        pathLayer.lineCap = .round
        pathLayer.lineJoin = .round
        layer.addSublayer(pathLayer)
        backgroundColor = .clear

        // A CGColor does not resolve against the trait collection the way a UIColor
        // does, so the stroke has to be recoloured by hand when the appearance flips.
        // `traitCollectionDidChange` was deprecated in iOS 17; this is the registration
        // API that replaced it, and it fires only for the trait that matters.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: DrawingCanvasView, _) in
            view.pathLayer.strokeColor = Self.resolvedStrokeColor(for: view.traitCollection)
        }
    }

    private static func resolvedStrokeColor(for traits: UITraitCollection) -> CGColor {
        UIColor { t in
            t.userInterfaceStyle == .dark
                ? .white
                : UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        }.resolvedColor(with: traits).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        currentStroke = [pt]
        updatePath()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        currentStroke.append(pt)
        updatePath()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard currentStroke.count > 1 else { currentStroke = []; return }
        let stroke = currentStroke
        strokes.append(stroke)
        currentStroke = []
        onStrokeComplete?(stroke)
    }

    func clear() {
        strokes = []
        currentStroke = []
        pathLayer.path = nil
    }

    private func updatePath() {
        let path = UIBezierPath()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: first)
            stroke.dropFirst().forEach { path.addLine(to: $0) }
        }
        if let first = currentStroke.first {
            path.move(to: first)
            currentStroke.dropFirst().forEach { path.addLine(to: $0) }
        }
        pathLayer.path = path.cgPath
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pathLayer.frame = bounds
    }
}

struct DrawingCanvas: UIViewRepresentable {
    @Binding var strokes: [[(CGPoint)]]
    var onStrokeComplete: (([CGPoint]) -> Void)?

    func makeUIView(context: Context) -> DrawingCanvasView {
        let v = DrawingCanvasView()
        v.onStrokeComplete = onStrokeComplete
        return v
    }

    func updateUIView(_ uiView: DrawingCanvasView, context: Context) {
        uiView.onStrokeComplete = onStrokeComplete
        if strokes.isEmpty {
            uiView.clear()
        }
    }
}

// MARK: - Similarity algorithm

/// Rasterisation-based shape similarity (Intersection-over-Union on a 48×48 grid).
/// Invariant to drawing order, starting point, and stroke direction.
/// Both shapes are centred + scaled before rasterisation so position/size don't matter.
/// Consecutive points within each stroke are interpolated so lines have no gaps,
/// giving a more faithful filled representation without relying on coarse pixel dilation.
enum DrawSimilarity {
    private static let gridSize = 48

    static func score(reference: [[StrokePoint]], candidate: [[StrokePoint]]) -> Double {
        guard !reference.isEmpty, !candidate.isEmpty else { return 0 }
        let refNorm = normalizeStrokes(reference)
        let canNorm = normalizeStrokes(candidate)
        guard !refNorm.isEmpty, !canNorm.isEmpty else { return 0 }
        return iou(rasterize(refNorm), rasterize(canNorm))
    }

    // Normalise all strokes using a shared centroid + scale so shapes are comparable
    private static func normalizeStrokes(_ strokes: [[StrokePoint]]) -> [[StrokePoint]] {
        let all = strokes.flatMap { $0 }
        guard all.count > 1 else { return strokes }
        let cx = all.map(\.x).reduce(0, +) / Double(all.count)
        let cy = all.map(\.y).reduce(0, +) / Double(all.count)
        let distances = all.map { p -> Double in
            let dx = p.x - cx
            let dy = p.y - cy
            return sqrt(dx * dx + dy * dy)
        }
        let maxDist = distances.max() ?? 1
        guard maxDist > 0 else { return strokes }
        return strokes.map { stroke in
            stroke.map { StrokePoint(x: ($0.x - cx) / maxDist, y: ($0.y - cy) / maxDist) }
        }
    }

    // Rasterise each stroke as a solid line (interpolated between touch points)
    private static func rasterize(_ strokes: [[StrokePoint]]) -> [Bool] {
        let g = gridSize
        var grid = [Bool](repeating: false, count: g * g)

        func paint(_ pt: StrokePoint) {
            let px = max(0, min(g - 1, Int(((pt.x + 1.0) / 2.0) * Double(g - 1))))
            let py = max(0, min(g - 1, Int(((pt.y + 1.0) / 2.0) * Double(g - 1))))
            grid[py * g + px] = true
        }

        for stroke in strokes {
            for (i, pt) in stroke.enumerated() {
                paint(pt)
                guard i + 1 < stroke.count else { continue }
                let next = stroke[i + 1]
                let dx = next.x - pt.x
                let dy = next.y - pt.y
                let dist = sqrt(dx * dx + dy * dy)
                guard dist > 0 else { continue }
                // Step size = one grid cell in normalised space; fills any gap between samples
                let step = 2.0 / Double(g)
                let steps = max(1, Int(dist / step))
                for s in 1..<steps {
                    let t = Double(s) / Double(steps)
                    paint(StrokePoint(x: pt.x + dx * t, y: pt.y + dy * t))
                }
            }
        }
        return grid
    }

    // Intersection-over-Union: 1.0 = identical, 0.0 = no overlap
    private static func iou(_ a: [Bool], _ b: [Bool]) -> Double {
        var inter = 0; var union = 0
        for i in 0..<a.count {
            if a[i] && b[i] { inter += 1 }
            if a[i] || b[i] { union += 1 }
        }
        return union > 0 ? Double(inter) / Double(union) : 0
    }
}

// MARK: - Draw mission (alarm-time)

struct DrawMissionView: View {
    let config: MissionConfig
    var onSuccess: () -> Void

    private let referenceStrokes: [[StrokePoint]]?
    private let similarityThreshold = 0.33
    @State private var canvasStrokes: [[(CGPoint)]] = []
    @State private var feedbackState: FeedbackState = .idle
    @State private var showHint = false
    @State private var didSucceed = false

    enum FeedbackState { case idle, wrong, checking, notConfigured }

    init(config: MissionConfig, onSuccess: @escaping () -> Void) {
        self.config = config
        self.onSuccess = onSuccess
        if case .draw(let ref) = config { referenceStrokes = ref } else { referenceStrokes = nil }
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                missionHeader
                Spacer()

                Text(String(localized: "Draw your shape", comment: "Draw mission instruction"))
                    .font(.mcCallout).foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.bottom, DesignTokens.Spacing.s)

                // A shape can take several strokes. Nothing is judged until Done —
                // judging after each stroke failed every two-stroke shape on the first.
                DrawingCanvas(strokes: $canvasStrokes, onStrokeComplete: { stroke in
                    canvasStrokes.append(stroke)
                    if feedbackState == .wrong { feedbackState = .idle }
                })
                    .overlay(alignment: .center) {
                        if showHint, let ref = referenceStrokes {
                            Canvas { ctx, _ in
                                var path = Path()
                                for stroke in ref {
                                    guard let first = stroke.first else { continue }
                                    path.move(to: CGPoint(x: first.x, y: first.y))
                                    stroke.dropFirst().forEach { path.addLine(to: CGPoint(x: $0.x, y: $0.y)) }
                                }
                                ctx.stroke(path, with: .color(Color.primary.opacity(0.30)),
                                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            }
                            .allowsHitTesting(false)
                            .transition(.opacity)
                        }
                    }
                    .background(DesignTokens.Colors.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                            .stroke(borderColor, lineWidth: 2)
                            .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: feedbackState == .wrong)
                    )
                    .frame(maxWidth: .infinity).frame(height: 280)
                    .padding(.horizontal, DesignTokens.Spacing.l)

                feedbackRow.padding(.top, DesignTokens.Spacing.s)

                Spacer()

                VStack(spacing: DesignTokens.Spacing.xs) {
                    Button {
                        Haptics.impact(.medium)
                        checkAfterDelay()
                    } label: {
                        Text(String(localized: "Done", comment: "Draw mission: judge the drawing"))
                            .mcPrimaryButton()
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(canvasStrokes.isEmpty || feedbackState == .checking)
                    .opacity(canvasStrokes.isEmpty ? 0.5 : 1)

                    Button(String(localized: "Clear", comment: "Clear drawing")) {
                        canvasStrokes = []
                        feedbackState = .idle
                    }
                    .font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(minHeight: DesignTokens.Size.row)
                }
                .padding(.horizontal, DesignTokens.Spacing.l)
                .padding(.bottom, DesignTokens.Spacing.m)
            }
        }
    }

    private var borderColor: Color {
        switch feedbackState {
        case .wrong:         return DesignTokens.Colors.destructive
        case .checking:      return DesignTokens.Colors.ember.opacity(0.5)
        case .notConfigured: return DesignTokens.Colors.warning.opacity(0.6)
        case .idle:          return DesignTokens.Colors.surfaceSecondary
        }
    }

    private var missionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: MissionKind.draw.systemImage).font(.system(size: 14)).foregroundStyle(DesignTokens.Colors.emberText)
            Text(String(localized: "Draw", comment: "Draw mission header")).font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.top, DesignTokens.Spacing.l)
    }

    private var feedbackRow: some View {
        Group {
            switch feedbackState {
            case .idle:
                Text(verbatim: " ")
            case .checking:
                Text(String(localized: "Checking…", comment: "Draw checking feedback"))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            case .wrong:
                Text(String(localized: "Try again — match your saved shape", comment: "Draw wrong feedback"))
                    .foregroundStyle(DesignTokens.Colors.destructive)
            case .notConfigured:
                Text(String(localized: "Not calibrated — edit this alarm to set up Draw.", comment: "Draw not calibrated error"))
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.mcCaption)
        .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: feedbackState == .wrong)
    }

    private func checkAfterDelay() {
        feedbackState = .checking
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await evaluate()
        }
    }

    @MainActor
    private func evaluate() {
        guard !didSucceed else { return }
        guard let ref = referenceStrokes else {
            // No reference calibrated — block success, surface error.
            // MissionHostView's unconfiguredMissionView guard should prevent reaching here,
            // but defend in depth.
            feedbackState = .notConfigured
            return
        }
        guard !canvasStrokes.isEmpty else { feedbackState = .idle; return }
        let candidate = canvasStrokes.map { stroke in
            stroke.map { pt in StrokePoint(x: pt.x, y: pt.y) }
        }
        let score = DrawSimilarity.score(reference: ref, candidate: candidate)
        if score >= similarityThreshold {
            didSucceed = true
            Haptics.notify(.success)
            onSuccess()
        } else {
            Haptics.notify(.error)
            feedbackState = .wrong
            withAnimation { showHint = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation { showHint = false }
                try? await Task.sleep(nanoseconds: 300_000_000)
                canvasStrokes = []
                feedbackState = .idle
            }
        }
    }
}

// MARK: - Draw setup (alarm editor)

struct DrawSetupView: View {
    @Binding var config: MissionConfig
    @Environment(\.dismiss) private var dismiss

    enum SetupPhase { case first, second, done }
    @State private var phase: SetupPhase = .first
    @State private var firstStrokes: [[(CGPoint)]] = []
    @State private var secondStrokes: [[(CGPoint)]] = []
    @State private var canvasStrokes: [[(CGPoint)]] = []

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.Colors.background.ignoresSafeArea()
                VStack(spacing: DesignTokens.Spacing.m) {
                    instruction
                    DrawingCanvas(strokes: $canvasStrokes, onStrokeComplete: { stroke in
                        canvasStrokes.append(stroke)
                    })
                        .background(DesignTokens.Colors.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
                        .frame(maxWidth: .infinity).frame(height: 280)
                        .padding(.horizontal, DesignTokens.Spacing.l)
                    actionButtons
                    Spacer()
                }
                .padding(.top, DesignTokens.Spacing.m)
            }
            .navigationTitle(String(localized: "Draw Setup", comment: "Draw setup nav title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel")) { dismiss() }
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
        }
    }

    private var instruction: some View {
        Group {
            switch phase {
            case .first:
                Text(String(localized: "Draw your shape (1 of 2)", comment: "Draw setup step 1"))
            case .second:
                Text(String(localized: "Draw it again to calibrate (2 of 2)", comment: "Draw setup step 2"))
            case .done:
                Text(String(localized: "Shape saved!", comment: "Draw setup done"))
                    .foregroundStyle(DesignTokens.Colors.success)
            }
        }
        .font(.mcCallout).foregroundStyle(DesignTokens.Colors.textSecondary)
        .multilineTextAlignment(.center).padding(.horizontal, DesignTokens.Spacing.l)
    }

    private var actionButtons: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Button(String(localized: "Clear", comment: "Clear drawing")) {
                canvasStrokes = []
            }
            .font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.m).padding(.vertical, 10)
            .background(DesignTokens.Colors.surfacePrimary).clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous))

            Button(phase == .done
                   ? String(localized: "Save", comment: "Save drawing")
                   : String(localized: "Next", comment: "Next drawing step")) {
                handleNext()
            }
            .font(.mcSubhead).fontWeight(.semibold)
            .foregroundStyle(DesignTokens.Colors.onEmber)
            .padding(.horizontal, DesignTokens.Spacing.m).padding(.vertical, 10)
            .background(canvasStrokes.isEmpty ? DesignTokens.Colors.surfaceSecondary : DesignTokens.Colors.ember)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous))
            .disabled(canvasStrokes.isEmpty && phase != .done)
        }
    }

    private func handleNext() {
        switch phase {
        case .first:
            firstStrokes = canvasStrokes
            canvasStrokes = []
            phase = .second
        case .second:
            secondStrokes = canvasStrokes
            phase = .done
            Haptics.notify(.success)
        case .done:
            // Use second drawing as canonical reference — combining both creates a
            // double-traversal that mismatches a single alarm-time drawing.
            let reference = secondStrokes.map { stroke in stroke.map { StrokePoint(x: $0.x, y: $0.y) } }
            config = .draw(referenceStrokes: reference)
            dismiss()
        }
    }
}
