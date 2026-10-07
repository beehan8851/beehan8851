import SwiftUI

// MARK: - Pages

/// How many pages the window has. iPhone Duo opens like a book, and its inner screen
/// is two outer screens side by side: 7.58" against 5.36" is √2, the same shape
/// turned on its side. Open, the app lays out as two pages with the fold between
/// them; closed, or as one of two apps side by side, it is one page, as on any iPhone.
nonisolated enum PageLayout: Equatable, Sendable {
    case single
    case spread

    /// The fold, down the middle of a spread. Nothing is put on it.
    static let gutter: CGFloat = 28

    /// Two pages when the window lies open like a book: clearly wider than tall, tall
    /// enough to read, and wide enough for two phone-width pages. An iPhone in
    /// portrait never is.
    init(size: CGSize) {
        let wide = size.width >= size.height * 1.2 && size.width >= 2 * 360 + Self.gutter
        self = wide && size.height >= 500 ? .spread : .single
    }
}

extension EnvironmentValues {
    @Entry var pageLayout: PageLayout = .single
    /// Whether this phone opens like a book, so that one page now may be two later.
    /// Nothing sets it on a real device yet: the SDK that can tell has not shipped.
    /// The Duo emulator sets it.
    @Entry var deviceFolds: Bool = false
}

extension View {
    /// Measures the window and tells everything inside how many pages it has.
    func readsPageLayout() -> some View {
        modifier(PageLayoutReader())
    }
}

private struct PageLayoutReader: ViewModifier {
    @State private var layout = PageLayout.single

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: PageLayout.self) { PageLayout(size: $0.size) } action: { layout = $0 }
            .environment(\.pageLayout, layout)
    }
}

/// Two pages of the same width with the fold between them.
struct Spread<Left: View, Right: View>: View {
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(alignment: .top, spacing: PageLayout.gutter) {
            left.frame(maxWidth: .infinity)
            right.frame(maxWidth: .infinity)
        }
    }
}

// MARK: - The cat the fold wakes

/// What the cat does when the book opens: it was lying in the fold, so it stretches
/// across it — front paws out on the left page, rump up on the right, a yawn at the
/// top of it — and then hops off to where it lives. Plays each time `cue` changes;
/// `playing` is true for as long as it is on the page, so the screen can hide its own
/// cat meanwhile (there is only one cat). Nothing under Reduce Motion.
struct FoldStretch: View {
    let cue: Int
    @Binding var playing: Bool
    var ground: CatMascot.Ground? = nil
    var width: CGFloat = 300

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.distantPast
    @State private var hop = 0
    /// Faded in and out on a view that stays put: taken out of the hierarchy mid-fade,
    /// the drawing would stop on whatever frame it had reached.
    @State private var shown = false

    /// The stretch, then the hop off the fold.
    static let stretch: TimeInterval = 2.2
    static let hopLength: TimeInterval = 0.5

    var body: some View {
        ZStack {
            if playing {
                StretchingCat(start: start, ground: ground)
                    .frame(width: width)
                    .catMotion(.hop, trigger: hop, size: width * 0.5)
                    .opacity(shown ? 1 : 0)
                    .scaleEffect(shown ? 1 : 0.94, anchor: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: cue) {
            guard cue > 0, !reduceMotion else { return }
            start = .now
            playing = true
            withAnimation(.easeOut(duration: 0.25)) { shown = true }
            Haptics.impact(.soft)
            try? await Task.sleep(for: .seconds(Self.stretch))
            hop += 1
            // Up and down again, then gone from the fold while the drawing still runs.
            try? await Task.sleep(for: .seconds(Self.hopLength))
            withAnimation(.easeIn(duration: 0.18)) { shown = false }
            try? await Task.sleep(for: .seconds(0.2))
            playing = false
        }
    }
}

/// The stretch, played from `start`: the front reaches out over a second, the yawn
/// opens at the top of it and closes, and the cat draws itself back in.
struct StretchingCat: View {
    let start: Date
    var ground: CatMascot.Ground? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { g, size in
                CatArt.drawStretch(in: &g, size: size, ground: ground ?? (colorScheme == .dark ? .dark : .light),
                                   time: context.date.timeIntervalSinceReferenceDate,
                                   reach: Self.reach(at: t), yawn: Self.yawn(at: t))
            }
        }
        .aspectRatio(CatArt.stretchDesignSize.width / CatArt.stretchDesignSize.height, contentMode: .fit)
    }

    private static func ease(_ x: Double) -> CGFloat {
        let x = min(max(x, 0), 1)
        return CGFloat(x * x * (3 - 2 * x))
    }

    static func reach(at t: Double) -> CGFloat {
        switch t {
        case ..<0.15: 0
        case ..<1.15: ease((t - 0.15) / 1.0)
        case ..<1.75: 1
        default: 1 - 0.65 * ease((t - 1.75) / 0.45)
        }
    }

    static func yawn(at t: Double) -> CGFloat {
        switch t {
        case ..<0.55: 0
        case ..<0.95: ease((t - 0.55) / 0.4)
        case ..<1.45: 1
        default: 1 - ease((t - 1.45) / 0.4)
        }
    }
}
