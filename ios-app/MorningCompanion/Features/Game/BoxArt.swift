import SwiftUI

/// The box the cat hides in: ink cardboard, the flaps a shade lighter, a strip of
/// yolk tape over the seam when it is shut and a yolk label with a paw on the front.
/// Front on, drawn in two layers so the cat can sit between them: `back` (the inside
/// and the back flap) under the cat, `front` (the front wall and its two flaps) over
/// it. `open` 0…1 swings the flaps from lying shut across the top to splayed out.
enum BoxArt {
    /// Wider than the box: the open flaps reach out past its sides. The box itself
    /// is the middle 104 of the width.
    static let designSize = CGSize(width: 168, height: 112)
    /// Where the box is in the design space.
    static let body = CGRect(x: 32, y: 46, width: 104, height: 62)
    /// Where the front wall's top edge is, down from the top, as a share of the
    /// height: the cat's head shows above it.
    static let rim: CGFloat = 46 / 112

    enum Layer { case back, front }

    /// What the box stands on: ink on paper, and a few shades lighter on an ink card,
    /// where an ink box would vanish.
    enum Ground { case paper, ink }

    private static func wall(_ ground: Ground) -> Color { Color(artHex: ground == .paper ? 0x1E1C19 : 0x4A4640) }
    private static func flap(_ ground: Ground) -> Color { Color(artHex: ground == .paper ? 0x34312C : 0x5E5952) }
    private static let inside = Color(artHex: 0x0B0A09)
    private static let yolk = Color(artHex: 0xFFC629)

    static func draw(_ layer: Layer, in context: inout GraphicsContext, size: CGSize, open: CGFloat,
                     ground: Ground = .paper) {
        let wall = wall(ground), flap = flap(ground)
        let k = min(size.width / designSize.width, size.height / designSize.height)
        var g = context
        g.translateBy(x: (size.width - designSize.width * k) / 2, y: (size.height - designSize.height * k) / 2)
        g.scaleBy(x: k, y: k)
        // The box was drawn at (8, 38); the room around it is for the flaps.
        g.translateBy(x: 24, y: 8)
        let open = min(max(open, 0), 1)

        switch layer {
        case .back:
            guard open > 0 else { return }
            // The back flap, standing up behind the opening.
            g.fill(Path(roundedRect: CGRect(x: 18, y: 38 - 22 * open, width: 84, height: 22 * open), cornerRadius: 3),
                   with: .color(flap))
            // The dark inside, seen over the front wall.
            g.fill(Path(CGRect(x: 10, y: 30, width: 100, height: 9)), with: .color(inside.opacity(Double(open))))

        case .front:
            g.fill(Path(roundedRect: CGRect(x: 8, y: 38, width: 104, height: 62), cornerRadius: 7), with: .color(wall))
            // A darker line under the rim, where the flaps fold.
            g.fill(Path(CGRect(x: 8, y: 38, width: 104, height: 3)), with: .color(inside.opacity(0.6)))
            label(&g, center: CGPoint(x: 60, y: 72))

            // The flaps, hinged at the rim's ends: shut, they lie across the top and
            // meet in the middle; open, they swing up and a little out — not so far that
            // they reach into the next box in the row.
            let angle = Angle.degrees(-105 * Double(open))
            var left = g
            left.translateBy(x: 8, y: 38)
            left.rotate(by: angle)
            left.fill(Path(roundedRect: CGRect(x: 0, y: -9, width: 52, height: 9), cornerRadius: 2.5), with: .color(flap))
            var right = g
            right.translateBy(x: 112, y: 38)
            right.rotate(by: -angle)
            right.fill(Path(roundedRect: CGRect(x: -52, y: -9, width: 52, height: 9), cornerRadius: 2.5), with: .color(flap))

            // Tape over the seam, only while it is shut.
            let taped = max(0, 1 - Double(open) * 4)
            if taped > 0 {
                g.fill(Path(CGRect(x: 53, y: 29, width: 14, height: 9)), with: .color(yolk.opacity(taped)))
                g.fill(Path(CGRect(x: 53, y: 38, width: 14, height: 9)), with: .color(yolk.opacity(taped)))
            }
        }
    }

    /// A yolk label with an ink paw print.
    private static func label(_ g: inout GraphicsContext, center c: CGPoint) {
        g.fill(Path(roundedRect: CGRect(x: c.x - 17, y: c.y - 12, width: 34, height: 24), cornerRadius: 5), with: .color(yolk))
        let ink = Color(artHex: 0x1C1A17)
        g.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 1, width: 12, height: 10)), with: .color(ink))
        for (dx, dy) in [(-8.5, -4.0), (-3.0, -8.5), (3.0, -8.5), (8.5, -4.0)] as [(CGFloat, CGFloat)] {
            g.fill(Path(ellipseIn: CGRect(x: c.x + dx - 2.6, y: c.y + dy - 2.6, width: 5.2, height: 5.2)), with: .color(ink))
        }
    }
}
