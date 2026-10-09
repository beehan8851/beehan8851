import SwiftUI

// MARK: - Choices

/// The app icons on offer. Classic is the one the app ships with; the others are
/// the cat in its other moods, and are Premium.
///
/// The artwork is drawn here, from the same `CatArt` as everywhere else: the
/// picker shows these views, and the PNGs in the asset catalog are rendered from
/// them, so the two cannot drift apart.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case classic
    case startled
    case night
    case proud
    case unimpressed

    var id: String { rawValue }

    /// The asset catalog name passed to `setAlternateIconName`; nil for the primary icon.
    var alternateIconName: String? {
        switch self {
        case .classic: nil
        case .startled: "AppIcon-Startled"
        case .night: "AppIcon-Night"
        case .proud: "AppIcon-Proud"
        case .unimpressed: "AppIcon-Unimpressed"
        }
    }

    var isPremium: Bool { self != .classic }

    /// The choice behind an icon name the system reports. An unknown name — one a
    /// later version dropped — reads as Classic.
    init(alternateIconName name: String?) {
        self = Self.allCases.first { $0.alternateIconName == name } ?? .classic
    }
}

// MARK: - Artwork

/// One icon, drawn on a 1024-point square and scaled to `size`. Square: the system
/// (or the picker) rounds the corners.
struct AppIconArt: View {
    let choice: AppIconChoice
    /// The dark Home Screen variant.
    var dark = false
    var size: CGFloat = 1024

    private static let yolk = Color(artHex: 0xFFC629)
    private static let ink = Color(artHex: 0x1B1A17)
    private static let paper = Color(artHex: 0xF4F2ED)

    var body: some View {
        art
            .frame(width: 1024, height: 1024)
            .clipped()
            .scaleEffect(size / 1024)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var ground: CatMascot.Ground { dark || choice == .night ? .dark : .light }

    @ViewBuilder
    private var art: some View {
        switch choice {
        case .classic:
            // The cat bats the Z away: no snooze.
            ZStack {
                dark ? Self.ink : Self.yolk
                cat(.ringing, width: 880, time: 0.31)
                    .offset(x: -130, y: 200)
                Text(verbatim: "Z")
                    .font(.system(size: 300, weight: .black).width(.expanded))
                    .foregroundStyle(dark ? Self.yolk : Self.ink)
                    .rotationEffect(.degrees(22))
                    .offset(x: 300, y: -120)
                Text(verbatim: "z")
                    .font(.system(size: 120, weight: .black).width(.expanded))
                    .foregroundStyle((dark ? Self.yolk : Self.ink).opacity(0.85))
                    .rotationEffect(.degrees(30))
                    .offset(x: 400, y: -390)
            }
        case .startled:
            ZStack {
                dark ? Self.ink : Self.yolk
                cat(.startled, width: 840, time: 0)
                    .offset(x: 6, y: 34)
            }
        case .night:
            ZStack {
                dark ? Color(artHex: 0x0F0E0C) : Self.ink
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                    SparkleShape()
                        .fill(Self.yolk.opacity(star.opacity))
                        .frame(width: star.size, height: star.size)
                        .offset(x: star.x, y: star.y)
                }
                cat(.sleeping, width: 900, time: 0.6)
                    .offset(x: -10, y: 90)
            }
        case .proud:
            // On paper, standing in front of a yolk sun, like the cat in the game.
            ZStack {
                dark ? Self.ink : Self.paper
                Circle()
                    .fill(dark ? Color(artHex: 0x3A3120) : Self.yolk)
                    .frame(width: 760, height: 760)
                    .offset(y: 70)
                cat(.proud, width: 780, time: 0.6)
                    .offset(x: 0, y: 170)
            }
        case .unimpressed:
            ZStack {
                dark ? Self.ink : Self.yolk
                cat(.grumpy, width: 820, time: 1.0)
                    .offset(x: 0, y: 150)
            }
        }
    }

    private func cat(_ mood: CatMascot.Mood, width: CGFloat, time: Double) -> some View {
        Canvas { context, size in
            CatArt.draw(mood, ground: ground, in: &context, size: size, time: time)
        }
        .frame(width: width, height: width / CatArt.aspectRatio(for: mood))
    }

    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (-330, -330, 70, 1), (300, -360, 44, 0.8), (380, -170, 30, 0.6), (-400, -120, 28, 0.55), (120, -420, 26, 0.5),
    ]
}

extension AppIconArt {
    /// The icon as the Home Screen shows it: corners rounded, a hairline so the
    /// paper icon keeps its edge on a paper page.
    func iconShape(_ size: CGFloat) -> some View {
        AppIconArt(choice: choice, dark: dark, size: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            }
    }
}
