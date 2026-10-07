import SwiftUI

/// How Cat Naps looks: cushions in soft print colours with an ink line around each,
/// and on them the white cat curled up asleep, or sitting up wide awake when it has
/// been put too close to another. Drawn in code like the rest of the cat.
enum CatNapArt {
    static let ink = Color(artHex: 0x1C1A17)
    static let fur = Color(artHex: 0xFFFCF8)
    static let furShade = Color(artHex: 0xE6DCCB)
    static let earInner = Color(artHex: 0xF7A38E)
    static let nose = Color(artHex: 0xF08B76)
    /// The stripes over a row, column or cushion with two cats in it.
    static let clash = Color(artHex: 0xD9483B)

    /// Nine cushions at most, as many as a 9 × 9 board needs, in an order that keeps
    /// neighbours in a small board apart.
    static let cushions: [Color] = [
        Color(artHex: 0xFFC629), // yolk
        Color(artHex: 0x9CC5E0), // sky
        Color(artHex: 0xF4A27A), // apricot
        Color(artHex: 0xA9C79B), // sage
        Color(artHex: 0xC9B6E4), // lilac
        Color(artHex: 0xE9D3AE), // oat
        Color(artHex: 0xF2B4C2), // rose
        Color(artHex: 0x86CDBF), // mint
        Color(artHex: 0xD3DA8C), // pistachio
    ]

    static func cushion(_ region: Int) -> Color { cushions[region % cushions.count] }

    /// The colour's name, for VoiceOver.
    static func cushionName(_ region: Int) -> String {
        switch region % cushions.count {
        case 0: String(localized: "yolk", comment: "Cat Naps: a cushion's colour, VoiceOver")
        case 1: String(localized: "sky", comment: "Cat Naps: a cushion's colour, VoiceOver")
        case 2: String(localized: "apricot", comment: "Cat Naps: a cushion's colour, VoiceOver")
        case 3: String(localized: "sage", comment: "Cat Naps: a cushion's colour, VoiceOver")
        case 4: String(localized: "lilac", comment: "Cat Naps: a cushion's colour, VoiceOver")
        case 5: String(localized: "oat", comment: "Cat Naps: a cushion's colour, VoiceOver")
        case 6: String(localized: "rose", comment: "Cat Naps: a cushion's colour, VoiceOver")
        case 7: String(localized: "mint", comment: "Cat Naps: a cushion's colour, VoiceOver")
        default: String(localized: "pistachio", comment: "Cat Naps: a cushion's colour, VoiceOver")
        }
    }

    // MARK: - The board

    /// The cushions and the lines, `cell` points to a side. Thin lines between cells
    /// of one cushion, thick ones where two cushions meet and around the edge.
    static func drawBoard(size n: Int, regions: [Int], cell: CGFloat, in g: inout GraphicsContext,
                          clashing: Set<Int> = [], marks: Set<Int> = [], thick: CGFloat = 3) {
        let side = cell * CGFloat(n)
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        let corner = cell * 0.22
        g.clip(to: Path(roundedRect: frame, cornerRadius: corner, style: .continuous))

        for index in 0..<(n * n) {
            let rect = CGRect(x: CGFloat(index % n) * cell, y: CGFloat(index / n) * cell, width: cell, height: cell)
            g.fill(Path(rect), with: .color(cushion(regions[index])))
        }

        // Stripes over cells that hold the clash.
        if !clashing.isEmpty {
            var stripes = Path()
            let step = max(5, cell / 5)
            var x = -side
            while x < side {
                stripes.move(to: CGPoint(x: x, y: side))
                stripes.addLine(to: CGPoint(x: x + side, y: 0))
                x += step
            }
            for index in clashing {
                let rect = CGRect(x: CGFloat(index % n) * cell, y: CGFloat(index / n) * cell, width: cell, height: cell)
                var c = g
                c.clip(to: Path(rect))
                c.fill(Path(rect), with: .color(clash.opacity(0.16)))
                c.stroke(stripes, with: .color(clash.opacity(0.55)), lineWidth: max(1.2, cell / 22))
            }
        }

        var thin = Path()
        for i in 1..<n {
            let p = CGFloat(i) * cell
            thin.move(to: CGPoint(x: p, y: 0)); thin.addLine(to: CGPoint(x: p, y: side))
            thin.move(to: CGPoint(x: 0, y: p)); thin.addLine(to: CGPoint(x: side, y: p))
        }
        g.stroke(thin, with: .color(ink.opacity(0.18)), lineWidth: 1)

        var walls = Path()
        for row in 0..<n {
            for column in 0..<n {
                let here = regions[row * n + column]
                if column < n - 1, regions[row * n + column + 1] != here {
                    let x = CGFloat(column + 1) * cell
                    walls.move(to: CGPoint(x: x, y: CGFloat(row) * cell))
                    walls.addLine(to: CGPoint(x: x, y: CGFloat(row + 1) * cell))
                }
                if row < n - 1, regions[(row + 1) * n + column] != here {
                    let y = CGFloat(row + 1) * cell
                    walls.move(to: CGPoint(x: CGFloat(column) * cell, y: y))
                    walls.addLine(to: CGPoint(x: CGFloat(column + 1) * cell, y: y))
                }
            }
        }
        g.stroke(walls, with: .color(ink), style: StrokeStyle(lineWidth: thick, lineCap: .square))

        for index in marks {
            let c = CGPoint(x: (CGFloat(index % n) + 0.5) * cell, y: (CGFloat(index / n) + 0.5) * cell)
            let r = cell * 0.11
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - r, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
            cross.move(to: CGPoint(x: c.x + r, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x - r, y: c.y + r))
            g.stroke(cross, with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: max(1.5, cell / 22), lineCap: .round))
        }

        g.stroke(Path(roundedRect: frame.insetBy(dx: thick / 2, dy: thick / 2), cornerRadius: corner - thick / 2, style: .continuous),
                 with: .color(ink), lineWidth: thick)
    }

    // MARK: - The cat

    /// The cat in a 100 × 100 square: curled asleep, or sitting up with its eyes open
    /// when another cat is too close. `breath` −1…1 lifts the curl a little.
    static func drawCat(in g: inout GraphicsContext, rect: CGRect, awake: Bool, breath: CGFloat = 0) {
        var g = g
        let k = min(rect.width, rect.height) / 100
        g.translateBy(x: rect.midX - 50 * k, y: rect.midY - 50 * k)
        g.scaleBy(x: k, y: k)
        let line = StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)

        if awake {
            drawAwake(&g, line: line)
            return
        }

        let lift = breath * 1.6
        // The curl: one round body, the tail laid along its front.
        let body = Path(ellipseIn: CGRect(x: 14, y: 40 - lift, width: 74, height: 46 + lift))
        g.fill(body, with: .color(fur))
        var shade = g
        shade.clip(to: body)
        shade.fill(Path(ellipseIn: CGRect(x: 10, y: 66, width: 84, height: 30)), with: .color(furShade))
        g.stroke(body, with: .color(ink), style: line)

        var tail = Path()
        tail.move(to: CGPoint(x: 84, y: 68))
        tail.addCurve(to: CGPoint(x: 40, y: 82), control1: CGPoint(x: 84, y: 86), control2: CGPoint(x: 58, y: 88))
        g.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: 12.5, lineCap: .round))
        g.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

        // The head, tucked in at the left, resting on the curl.
        var head = g
        head.translateBy(x: 38, y: 54 - lift * 0.6)
        head.rotate(by: .degrees(-8))
        drawHead(&head, line: line, eyesOpen: false)
    }

    private static func drawAwake(_ g: inout GraphicsContext, line: StrokeStyle) {
        // Sitting up: a pear of a body, the tail straight up behind it.
        var tail = Path()
        tail.move(to: CGPoint(x: 66, y: 78))
        tail.addCurve(to: CGPoint(x: 80, y: 30), control1: CGPoint(x: 84, y: 70), control2: CGPoint(x: 78, y: 46))
        g.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: 12.5, lineCap: .round))
        g.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

        var body = Path()
        body.move(to: CGPoint(x: 36, y: 50))
        body.addCurve(to: CGPoint(x: 28, y: 90), control1: CGPoint(x: 28, y: 62), control2: CGPoint(x: 22, y: 84))
        body.addLine(to: CGPoint(x: 72, y: 90))
        body.addCurve(to: CGPoint(x: 64, y: 50), control1: CGPoint(x: 78, y: 84), control2: CGPoint(x: 72, y: 62))
        body.closeSubpath()
        g.fill(body, with: .color(fur))
        g.stroke(body, with: .color(ink), style: line)

        var head = g
        head.translateBy(x: 50, y: 38)
        drawHead(&head, line: line, eyesOpen: true)
    }

    /// A head centred on the origin, 52 across.
    private static func drawHead(_ g: inout GraphicsContext, line: StrokeStyle, eyesOpen: Bool) {
        let ears: [[CGPoint]] = [
            [CGPoint(x: -24, y: -6), CGPoint(x: -20, y: -30), CGPoint(x: -4, y: -19)],
            [CGPoint(x: 24, y: -6), CGPoint(x: 20, y: -30), CGPoint(x: 4, y: -19)],
        ]
        for ear in ears {
            let path = Path.roundedPolygon(ear, radius: 3)
            g.fill(path, with: .color(fur))
            g.stroke(path, with: .color(ink), style: line)
            let inner = Path.roundedPolygon([
                CGPoint(x: ear[0].x * 0.8, y: -9), CGPoint(x: ear[1].x * 0.95, y: -24), CGPoint(x: ear[2].x * 1.6, y: -17),
            ], radius: 2)
            g.fill(inner, with: .color(earInner))
        }
        let face = Path(ellipseIn: CGRect(x: -26, y: -21, width: 52, height: 44))
        g.fill(face, with: .color(fur))
        g.stroke(face, with: .color(ink), style: line)

        if eyesOpen {
            for x in [-10.5, 10.5] as [CGFloat] {
                g.fill(Path(ellipseIn: CGRect(x: x - 5, y: -6, width: 10, height: 11)), with: .color(ink))
                g.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: -4.5, width: 3.6, height: 3.6)), with: .color(fur))
            }
        } else {
            for x in [-11, 11] as [CGFloat] {
                var lid = Path()
                lid.move(to: CGPoint(x: x - 6, y: 0))
                lid.addQuadCurve(to: CGPoint(x: x + 6, y: 0), control: CGPoint(x: x, y: 6))
                g.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
            }
        }
        g.fill(Path.roundedPolygon([CGPoint(x: -3.5, y: 6), CGPoint(x: 3.5, y: 6), CGPoint(x: 0, y: 10)], radius: 1),
               with: .color(nose))
    }

    /// Zzz, for the solved board: a few seconds' rise and fade, `t` from 0.
    static func drawZ(in g: inout GraphicsContext, rect: CGRect, t: Double, delay: Double) {
        let phase = t - delay
        guard phase > 0 else { return }
        let local = phase.truncatingRemainder(dividingBy: 2.4) / 2.4
        let fade = sin(local * .pi)
        let size = rect.width * 0.34
        g.draw(Text(verbatim: "z").font(.system(size: size, weight: .heavy)).foregroundStyle(ink.opacity(0.75 * fade)),
               at: CGPoint(x: rect.maxX - size * 0.4, y: rect.minY + size * 0.2 - CGFloat(local) * rect.height * 0.5))
    }
}

/// The game's picture on its intro and on the cards: a little board, three cats asleep.
struct CatNapPoster: View {
    var body: some View {
        Canvas { g, size in
            let n = 4
            let cell = min(size.width, size.height) / CGFloat(n)
            var board = g
            board.translateBy(x: (size.width - cell * CGFloat(n)) / 2, y: (size.height - cell * CGFloat(n)) / 2)
            CatNapArt.drawBoard(size: n, regions: Self.regions, cell: cell, in: &board, thick: max(2, cell / 16))
            for index in [1, 7, 8] {
                let rect = CGRect(x: CGFloat(index % n) * cell, y: CGFloat(index / n) * cell, width: cell, height: cell)
                var cat = g
                cat.translateBy(x: (size.width - cell * CGFloat(n)) / 2, y: (size.height - cell * CGFloat(n)) / 2)
                CatNapArt.drawCat(in: &cat, rect: rect.insetBy(dx: cell * 0.06, dy: cell * 0.06), awake: false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// A 4 × 4 cut into four cushions, three of its four cats in place.
    private static let regions = [
        0, 0, 1, 1,
        0, 1, 1, 1,
        2, 2, 3, 1,
        2, 3, 3, 3,
    ]
}
