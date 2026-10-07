import SwiftUI

// MARK: - Mission art

/// A small moving picture of each mission, so the picker shows what you will do rather
/// than naming it: keys pressing, a phone shaking, steps walking up the tile, a scan
/// line over a code, a memory grid lighting in order, a line typing itself, a stroke
/// drawing itself, a ball jumping. Drawn in code, looping, and still under Reduce
/// Motion. Hidden from VoiceOver: the tile says the mission's name.
struct MissionArt: View {
    enum Tone {
        /// On an ink tile: paper lines, yolk accents.
        case onInk
        /// On a yolk tile (the mission is chosen): ink lines, white accents.
        case onYolk
    }

    let kind: MissionKind
    var tone: Tone = .onInk
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(time: MissionArtDrawing.restingTime(for: kind))
            }
        }
        .aspectRatio(MissionArtDrawing.size.width / MissionArtDrawing.size.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func canvas(time: Double) -> some View {
        Canvas { context, size in
            MissionArtDrawing.draw(kind, tone: tone, in: &context, size: size, time: time)
        }
    }
}

// MARK: - Drawing

enum MissionArtDrawing {
    static let size = CGSize(width: 72, height: 48)

    private struct Ink {
        let line: Color
        let accent: Color
        let muted: Color
        /// Type on an `accent` key and on a `line` key.
        let onAccent: Color
        let onLine: Color

        init(_ tone: MissionArt.Tone) {
            let paper = Color(artHex: 0xF4F2ED)
            let yolk = Color(artHex: 0xFFC629)
            let ink = Color(artHex: 0x1B1A17)
            switch tone {
            case .onInk:
                line = paper; accent = yolk; muted = paper.opacity(0.2)
                onAccent = ink; onLine = ink
            case .onYolk:
                line = ink; accent = .white; muted = ink.opacity(0.16)
                onAccent = ink; onLine = yolk
            }
        }
    }

    /// The frame shown when nothing moves: the most telling moment of each loop.
    static func restingTime(for kind: MissionKind) -> Double {
        switch kind {
        case .steps:  return 1.7
        case .typing: return 1.2
        case .draw:   return 1.6
        case .memory: return 0.5
        case .jump:   return 0.6
        case .catchCat: return 0.7
        default:      return 0.35
        }
    }

    static func draw(_ kind: MissionKind, tone: MissionArt.Tone, in context: inout GraphicsContext, size box: CGSize, time t: Double) {
        let k = min(box.width / size.width, box.height / size.height)
        var g = context
        g.translateBy(x: (box.width - size.width * k) / 2, y: (box.height - size.height * k) / 2)
        g.scaleBy(x: k, y: k)
        let ink = Ink(tone)
        switch kind {
        case .math:   math(&g, ink, t)
        case .shake:  shake(&g, ink, t)
        case .steps:  steps(&g, ink, t)
        case .qrCode: qr(&g, ink, t)
        case .memory: memory(&g, ink, t)
        case .typing: typing(&g, ink, t)
        case .draw:   drawing(&g, ink, t)
        case .jump:   jump(&g, ink, t)
        case .catchCat: catchCat(&g, ink, t)
        }
    }

    // MARK: Helpers

    private static func phase(_ t: Double, _ cycle: Double) -> Double {
        t.truncatingRemainder(dividingBy: cycle)
    }

    /// 0 → 1 → 0 across `start ..< start + length`, eased.
    private static func bump(_ p: Double, _ start: Double, _ length: Double) -> Double {
        guard p >= start, p < start + length else { return 0 }
        return sin((p - start) / length * .pi)
    }

    private static func key(_ g: inout GraphicsContext, center: CGPoint, side: CGFloat, angle: Double,
                            press: Double, fill: Color, glyph: String, glyphColor: Color) {
        var c = g
        c.translateBy(x: center.x, y: center.y + CGFloat(press) * 2)
        c.rotate(by: .degrees(angle))
        c.scaleBy(x: 1 - CGFloat(press) * 0.1, y: 1 - CGFloat(press) * 0.1)
        let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
        c.fill(Path(roundedRect: rect, cornerRadius: side * 0.26, style: .continuous), with: .color(fill))
        c.draw(Text(verbatim: glyph).font(.system(size: side * 0.62, weight: .heavy)).foregroundStyle(glyphColor),
               at: .zero)
    }

    // MARK: Missions

    private static func math(_ g: inout GraphicsContext, _ ink: Ink, _ t: Double) {
        let p = phase(t, 1.6)
        key(&g, center: CGPoint(x: 24, y: 24), side: 32, angle: -9, press: bump(p, 0.05, 0.3),
            fill: ink.accent, glyph: "÷", glyphColor: ink.onAccent)
        key(&g, center: CGPoint(x: 51, y: 27), side: 27, angle: 9, press: bump(p, 0.85, 0.3),
            fill: ink.line, glyph: "+", glyphColor: ink.onLine)
    }

    private static func shake(_ g: inout GraphicsContext, _ ink: Ink, _ t: Double) {
        let p = phase(t, 1.8)
        let burst = p < 0.75 ? 1 - p / 0.75 : 0
        let angle = sin(p * 2 * .pi * 5.5) * 15 * burst
        for side in [-1.0, 1.0] as [CGFloat] {
            for (i, r) in [CGFloat(19), 26].enumerated() {
                var arc = Path()
                arc.addArc(center: CGPoint(x: 36, y: 24), radius: r,
                           startAngle: .degrees(side > 0 ? -28 : 152), endAngle: .degrees(side > 0 ? 28 : 208),
                           clockwise: false)
                g.stroke(arc, with: .color(ink.accent.opacity(burst * (i == 0 ? 1 : 0.55))),
                         style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }
        }
        var phone = g
        phone.translateBy(x: 36, y: 24)
        phone.rotate(by: .degrees(angle))
        let body = Path(roundedRect: CGRect(x: -10, y: -17, width: 20, height: 34), cornerRadius: 5.5, style: .continuous)
        phone.stroke(body, with: .color(ink.line), lineWidth: 3)
        phone.fill(Path(roundedRect: CGRect(x: -3.5, y: -13, width: 7, height: 2.4), cornerRadius: 1.2), with: .color(ink.line))
    }

    private static func steps(_ g: inout GraphicsContext, _ ink: Ink, _ t: Double) {
        let p = phase(t, 2.6)
        let prints: [(CGPoint, Bool)] = [
            (CGPoint(x: 14, y: 36), true), (CGPoint(x: 28, y: 30), false),
            (CGPoint(x: 40, y: 20), true), (CGPoint(x: 54, y: 14), false),
        ]
        let shown = min(prints.count, Int(p / 0.45) + 1)
        let fade = p > 2.2 ? 1 - (p - 2.2) / 0.4 : 1
        for (i, print) in prints.prefix(shown).enumerated() {
            var c = g
            c.translateBy(x: print.0.x, y: print.0.y)
            c.rotate(by: .degrees(28))
            let newest = i == shown - 1
            let color = newest ? ink.accent : ink.line.opacity(0.35 + 0.15 * Double(i))
            c.opacity = fade
            let dx: CGFloat = print.1 ? -2 : 2
            c.fill(Path(ellipseIn: CGRect(x: -4.2 + dx, y: -9, width: 8.4, height: 11)), with: .color(color))
            c.fill(Path(ellipseIn: CGRect(x: -3.2 + dx, y: 3, width: 6.4, height: 6)), with: .color(color))
        }
    }

    private static func qr(_ g: inout GraphicsContext, _ ink: Ink, _ t: Double) {
        let p = phase(t, 2.0)
        let origin = CGPoint(x: 21, y: 7)
        let side: CGFloat = 34
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: side - 11, y: 0), CGPoint(x: 0, y: side - 11)] {
            let r = CGRect(x: origin.x + corner.x, y: origin.y + corner.y, width: 11, height: 11)
            g.stroke(Path(roundedRect: r.insetBy(dx: 1.25, dy: 1.25), cornerRadius: 2), with: .color(ink.line), lineWidth: 2.5)
            g.fill(Path(roundedRect: r.insetBy(dx: 3.6, dy: 3.6), cornerRadius: 1), with: .color(ink.line))
        }
        let modules: [(CGFloat, CGFloat)] = [(15, 2), (19, 6), (15, 10), (2, 15), (8, 15), (15, 15), (23, 15), (28, 19),
                                             (19, 23), (15, 28), (23, 28), (28, 28), (30, 24)]
        for (x, y) in modules {
            g.fill(Path(roundedRect: CGRect(x: origin.x + x, y: origin.y + y, width: 3.6, height: 3.6), cornerRadius: 0.8),
                   with: .color(ink.line.opacity(0.75)))
        }
        let y = origin.y + 2 + (side - 4) * CGFloat(0.5 - 0.5 * cos(p / 2.0 * 2 * .pi))
        g.fill(Path(roundedRect: CGRect(x: origin.x - 4, y: y - 1.4, width: side + 8, height: 2.8), cornerRadius: 1.4),
               with: .color(ink.accent))
    }

    private static func memory(_ g: inout GraphicsContext, _ ink: Ink, _ t: Double) {
        let order = [0, 4, 2, 5, 1, 3]
        let step = Int(phase(t, 2.7) / 0.45) % order.count
        let lit = order[step]
        let tile: CGFloat = 14, gap: CGFloat = 5
        let origin = CGPoint(x: (size.width - (tile * 3 + gap * 2)) / 2, y: 7)
        for i in 0..<6 {
            let col = CGFloat(i % 3), row = CGFloat(i / 3)
            var rect = CGRect(x: origin.x + col * (tile + gap), y: origin.y + row * (tile + gap), width: tile, height: tile)
            if i == lit { rect = rect.insetBy(dx: -1, dy: -1) }
            g.fill(Path(roundedRect: rect, cornerRadius: 4, style: .continuous),
                   with: .color(i == lit ? ink.accent : ink.muted))
        }
    }

    private static func typing(_ g: inout GraphicsContext, _ ink: Ink, _ t: Double) {
        let p = phase(t, 2.6)
        let typed = min(p / 1.8, 1)
        let barX: CGFloat = 10, barWidth: CGFloat = 52
        g.fill(Path(roundedRect: CGRect(x: barX, y: 6, width: barWidth, height: 8), cornerRadius: 2.5), with: .color(ink.muted))
        let filled = barWidth * CGFloat(typed)
        if filled > 1 {
            g.fill(Path(roundedRect: CGRect(x: barX, y: 6, width: filled, height: 8), cornerRadius: 2.5),
                   with: .color(ink.line.opacity(0.9)))
        }
        let cursorOn = p < 1.8 || sin(p * 2 * .pi * 2) > 0
        if cursorOn {
            g.fill(Path(CGRect(x: min(barX + filled + 1.5, barX + barWidth + 1.5), y: 3.5, width: 2.4, height: 13)),
                   with: .color(ink.accent))
        }
        var keys: [CGRect] = []
        for i in 0..<5 { keys.append(CGRect(x: 10 + CGFloat(i) * 10.75, y: 22, width: 8.5, height: 8.5)) }
        keys.append(CGRect(x: 10, y: 33.5, width: 8.5, height: 8.5))
        keys.append(CGRect(x: 21.5, y: 33.5, width: 29, height: 8.5))
        keys.append(CGRect(x: 53.5, y: 33.5, width: 8.5, height: 8.5))
        let pressed = p < 1.8 ? [2, 5, 0, 6, 3, 1, 7, 4][Int(p / 0.16) % 8] : -1
        for (i, rect) in keys.enumerated() {
            g.fill(Path(roundedRect: rect, cornerRadius: 2.4), with: .color(i == pressed ? ink.accent : ink.muted))
        }
    }

    private static func drawing(_ g: inout GraphicsContext, _ ink: Ink, _ t: Double) {
        let p = phase(t, 2.8)
        var stroke = Path()
        stroke.move(to: CGPoint(x: 9, y: 34))
        stroke.addCurve(to: CGPoint(x: 28, y: 12), control1: CGPoint(x: 12, y: 18), control2: CGPoint(x: 20, y: 10))
        stroke.addCurve(to: CGPoint(x: 40, y: 34), control1: CGPoint(x: 36, y: 14), control2: CGPoint(x: 32, y: 34))
        stroke.addCurve(to: CGPoint(x: 63, y: 14), control1: CGPoint(x: 48, y: 34), control2: CGPoint(x: 52, y: 12))
        let progress = min(p / 1.6, 1)
        let fade = p > 2.3 ? max(0, 1 - (p - 2.3) / 0.5) : 1
        var c = g
        c.opacity = fade
        c.stroke(stroke, with: .color(ink.muted), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
        let drawn = stroke.trimmedPath(from: 0, to: progress)
        c.stroke(drawn, with: .color(ink.accent), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
        if let tip = drawn.currentPoint {
            c.fill(Path(ellipseIn: CGRect(x: tip.x - 3.4, y: tip.y - 3.4, width: 6.8, height: 6.8)), with: .color(ink.line))
        }
    }

    private static func jump(_ g: inout GraphicsContext, _ ink: Ink, _ t: Double) {
        let p = phase(t, 1.15) / 1.15
        let height = 4 * p * (1 - p)
        let landing = (p < 0.08 || p > 0.92) ? 1.0 : 0.0
        g.fill(Path(roundedRect: CGRect(x: 16, y: 42, width: 40, height: 2.4), cornerRadius: 1.2), with: .color(ink.muted))
        let shadowWidth = 16 * (1 - 0.45 * height)
        g.fill(Path(ellipseIn: CGRect(x: 36 - shadowWidth / 2, y: 39.5, width: shadowWidth, height: 3.2)),
               with: .color(ink.line.opacity(0.22 * (1 - 0.6 * height))))
        let radius: CGFloat = 8.5
        let sx = 1 + 0.18 * landing, sy = 1 - 0.18 * landing
        let cy = 41 - radius * CGFloat(sy) - CGFloat(height) * 26
        var ball = g
        ball.translateBy(x: 36, y: cy)
        ball.scaleBy(x: CGFloat(sx), y: CGFloat(sy))
        ball.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)), with: .color(ink.accent))
    }

    /// A paw print hopping from one side of a fold to the other, and a tap ring where
    /// it sits: catch it before it goes.
    private static func catchCat(_ g: inout GraphicsContext, _ ink: Ink, _ t: Double) {
        let cycle = 2.0
        let p = phase(t, cycle) / cycle
        // The fold, down the middle.
        var fold = Path()
        fold.move(to: CGPoint(x: 36, y: 8))
        fold.addLine(to: CGPoint(x: 36, y: 42))
        g.stroke(fold, with: .color(ink.muted), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
        // Sits left, leaps, sits right, leaps back.
        let left = CGPoint(x: 20, y: 30), right = CGPoint(x: 52, y: 30)
        func leap(_ from: CGPoint, _ to: CGPoint, _ u: Double) -> CGPoint {
            let e = CGFloat(u * u * (3 - 2 * u))
            return CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e - CGFloat(sin(u * .pi)) * 18)
        }
        let at: CGPoint
        let sitting: Double
        switch p {
        case ..<0.35: at = left; sitting = p / 0.35
        case ..<0.5: at = leap(left, right, (p - 0.35) / 0.15); sitting = -1
        case ..<0.85: at = right; sitting = (p - 0.5) / 0.35
        default: at = leap(right, left, (p - 0.85) / 0.15); sitting = -1
        }
        if sitting >= 0 {
            // The tap, halfway through the sit.
            let ring = bump(sitting, 0.3, 0.5)
            if ring > 0 {
                let r = 9 + CGFloat(ring) * 6
                g.stroke(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)),
                         with: .color(ink.line.opacity(0.5 * ring)), lineWidth: 1.6)
            }
        }
        g.fill(PawPrintShape().path(in: CGRect(x: at.x - 9, y: at.y - 9, width: 18, height: 18)), with: .color(ink.accent))
    }
}

#Preview("Mission art") {
    LazyVGrid(columns: [GridItem(), GridItem()], spacing: 12) {
        ForEach(MissionKind.allCases) { kind in
            MissionArt(kind: kind)
                .frame(height: 60)
                .padding()
                .background(Color(artHex: 0x1E1C19), in: RoundedRectangle(cornerRadius: 20))
        }
    }
    .padding()
}
