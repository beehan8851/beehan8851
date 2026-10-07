#if DEBUG
import SwiftUI

/// Stands in for an iPhone Duo until Xcode has one: the app is laid out at the Duo's
/// sizes and scaled down to fit the simulator. `-mc.debug.duo`:
///   outer   closed — one page
///   inner   open — two pages
///   auto    closed, then opening and closing every few seconds
/// Turned a quarter so the open phone fills the simulator's long side, at the same
/// scale closed and open; screenshots need turning back (`sips -r 270`). Sheets and
/// full-screen covers are presented by the real window and ignore it.
enum DuoMetrics {
    /// Estimates, from Apple's diagonals (5.36", 7.58") at the iPhone 17 Pro's 460 ppi
    /// and the √2 shape both screens share. Replace with the real ones when the SDK
    /// knows the Duo.
    static let outer = CGSize(width: 474, height: 670)
    static let inner = CGSize(width: 948, height: 670)
    /// The status bar and home indicator, roughly.
    static let insets = EdgeInsets(top: 30, leading: 0, bottom: 20, trailing: 0)
}

struct DuoEmulator<Content: View>: View {
    let mode: String
    let content: Content
    @State private var open: Bool

    init(mode: String, @ViewBuilder content: () -> Content) {
        self.mode = mode
        self.content = content()
        _open = State(initialValue: mode == "inner")
    }

    var body: some View {
        GeometryReader { proxy in
            let size = open ? DuoMetrics.inner : DuoMetrics.outer
            let scale = min(proxy.size.width / DuoMetrics.inner.height, proxy.size.height / DuoMetrics.inner.width)
            // The open phone's top edge is the closed one's: opening adds the page below.
            let top = (proxy.size.height - DuoMetrics.inner.width * scale) / 2
            content
                .environment(\.deviceFolds, true)
                .safeAreaPadding(DuoMetrics.insets)
                .frame(width: size.width, height: size.height)
                .background(DesignTokens.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .rotationEffect(.degrees(90))
                .scaleEffect(scale)
                .position(x: proxy.size.width / 2, y: top + size.width * scale / 2)
        }
        .ignoresSafeArea()
        .background(Color(white: 0.1).ignoresSafeArea())
        .task {
            guard mode == "auto" else { return }
            try? await Task.sleep(for: .seconds(2.5))
            while !Task.isCancelled {
                open.toggle()
                try? await Task.sleep(for: .seconds(open ? 6 : 3))
            }
        }
    }
}
#endif
