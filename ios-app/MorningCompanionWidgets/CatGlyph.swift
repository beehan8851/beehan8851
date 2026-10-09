import SwiftUI
import WidgetKit

/// The app's cat for the widget and Live Activities: its head only, which is what
/// still reads at 14 points. Self-contained because the extension shares no code
/// with the app (the app's full cat is `CatMascot`). Three moods are enough out here —
/// waiting, ringing and asleep for the sleep activity — and in accented or vibrant
/// rendering it collapses to a silhouette on purpose.
struct CatGlyph: View {
    enum Mood { case waiting, ringing, sleeping }
    var mood: Mood = .waiting
    var size: CGFloat = 24

    @Environment(\.widgetRenderingMode) private var renderingMode

    private static let fur = Color(red: 1.0, green: 0.984, blue: 0.969)       // #FFFBF7
    private static let shade = Color(red: 0.929, green: 0.898, blue: 0.847)   // #EDE5D8
    private static let pink = Color(red: 0.961, green: 0.627, blue: 0.545)    // #F5A08B
    private static let ink = Color(red: 0.110, green: 0.102, blue: 0.090)     // #1C1A17

    var body: some View {
        Canvas { g, box in
            let mono = renderingMode != .fullColor
            let k = min(box.width / 80, box.height / 72)
            var c = g
            c.translateBy(x: (box.width - 80 * k) / 2, y: (box.height - 72 * k) / 2)
            c.scaleBy(x: k, y: k)

            let earTilt: CGFloat = mood == .sleeping ? 3 : 0
            let leftEar = Self.roundedTriangle(CGPoint(x: 10, y: 36), CGPoint(x: 36, y: 22), CGPoint(x: 14 - earTilt, y: 2 + earTilt), radius: 4)
            let rightEar = Self.roundedTriangle(CGPoint(x: 70, y: 36), CGPoint(x: 44, y: 22), CGPoint(x: 66 + earTilt, y: 2 + earTilt), radius: 4)
            let head = Self.head
            let body = mono ? Color.white : Self.fur
            c.fill(leftEar, with: .color(body))
            c.fill(rightEar, with: .color(body))
            if !mono {
                c.fill(Self.roundedTriangle(CGPoint(x: 18, y: 30), CGPoint(x: 32, y: 24), CGPoint(x: 17 - earTilt, y: 11 + earTilt), radius: 2), with: .color(Self.pink))
                c.fill(Self.roundedTriangle(CGPoint(x: 62, y: 30), CGPoint(x: 48, y: 24), CGPoint(x: 63 + earTilt, y: 11 + earTilt), radius: 2), with: .color(Self.pink))
            }
            c.fill(head, with: .color(body))
            if !mono {
                c.fill(head.subtracting(head.offsetBy(dx: 4, dy: -5)), with: .color(Self.shade))
            }

            let eyeInk: Color = mono ? Color.black.opacity(0.85) : Self.ink
            for x in [CGFloat(27), 53] {
                let y: CGFloat = 46
                switch mood {
                case .sleeping:
                    c.fill(Self.lid(center: CGPoint(x: x, y: y), halfWidth: 7, sag: 4, thickness: 2.8), with: .color(eyeInk))
                case .waiting:
                    c.fill(Path(ellipseIn: CGRect(x: x - 3.6, y: y - 4.6, width: 7.2, height: 9.2)), with: .color(eyeInk))
                case .ringing:
                    c.fill(Path(ellipseIn: CGRect(x: x - 4.4, y: y - 5.4, width: 8.8, height: 10.8)), with: .color(eyeInk))
                }
            }
            if !mono {
                c.fill(Self.roundedTriangle(CGPoint(x: 36.5, y: 53), CGPoint(x: 43.5, y: 53), CGPoint(x: 40, y: 57.5), radius: 1.2), with: .color(Self.pink))
            }
            if mood == .ringing {
                c.fill(Path(roundedRect: CGRect(x: 36.5, y: 59, width: 7, height: 5.5), cornerRadius: 2.8), with: .color(eyeInk))
            }
        }
        .frame(width: size, height: size * 72 / 80)
        .accessibilityHidden(true)
    }

    /// The head: a soft square, a little wider at the cheeks.
    private static let head: Path = {
        var p = Path()
        let steps = 96
        for i in 0..<steps {
            let th = Double(i) / Double(steps) * 2 * .pi
            let e = 2 / 2.45
            let ct = cos(th), st = sin(th)
            var x = 34 * CGFloat(copysign(pow(abs(ct), e), ct))
            let y = 26 * CGFloat(copysign(pow(abs(st), e), st))
            x *= 1 + 0.07 * (y / 26)
            let point = CGPoint(x: 40 + x, y: 44 + y)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }()

    private static func roundedTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2))
        p.addArc(tangent1End: a, tangent2End: b, radius: radius)
        p.addArc(tangent1End: b, tangent2End: c, radius: radius)
        p.addArc(tangent1End: c, tangent2End: a, radius: radius)
        p.closeSubpath()
        return p
    }

    /// A closed eye: a crescent bowing down, pointed at both corners.
    private static func lid(center: CGPoint, halfWidth l: CGFloat, sag s1: CGFloat, thickness: CGFloat) -> Path {
        let s2 = max(s1 - thickness, 0.5)
        let r1 = (s1 * s1 + l * l) / (2 * s1)
        let r2 = (s2 * s2 + l * l) / (2 * s2)
        let outer = Path(ellipseIn: CGRect(x: center.x - r1, y: center.y + s1 - 2 * r1, width: 2 * r1, height: 2 * r1))
        let inner = Path(ellipseIn: CGRect(x: center.x - r2, y: center.y + s2 - 2 * r2, width: 2 * r2, height: 2 * r2))
        return outer.subtracting(inner)
    }
}
