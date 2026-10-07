import SwiftUI
import UIKit

/// Root 5-tab navigation shell (Today / Alarms / Sleep / Play / Settings). The streak
/// that was the Progress tab opens from its card on Today.
/// Tab selection is bound to AppContainer.selectedTabIndex for programmatic switching
/// (e.g., mission success transitions to the Today tab).
///
/// The system tab bar is hidden for the app's own: an ink bar with grey items, the
/// chosen one on a yolk lens. On iOS 26 the system bar ignores item colours, and its
/// default — black symbols on light glass — was the one thing on screen that did not
/// belong to the app.
///
/// The bar floats over the tabs rather than insetting them: a safe-area inset on the
/// TabView never reaches the scroll views inside it, so the last rows of every screen
/// sat under the bar. Each tab root makes its own room with `inkTabBarClearance()`,
/// and a pushed screen that wants the whole height says `hidesInkTabBar()`.
struct AppTabBarView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.pageLayout) private var pageLayout
    @State private var bar = InkTabBarState()

    var body: some View {
        let selection = Binding(
            get: { container.selectedTabIndex },
            set: { container.selectedTabIndex = $0 }
        )
        TabView(selection: selection) {
            NavigationStack { TodayView().inkTabBarClearance().toolbar(.hidden, for: .tabBar) }.tag(0)
            NavigationStack { AlarmsView().inkTabBarClearance().toolbar(.hidden, for: .tabBar) }.statusPageBeside().tag(1)
            NavigationStack { SleepView().inkTabBarClearance().toolbar(.hidden, for: .tabBar) }.tag(2)
            NavigationStack { PlayView().inkTabBarClearance().toolbar(.hidden, for: .tabBar) }.statusPageBeside().tag(3)
            NavigationStack { SettingsView().inkTabBarClearance().toolbar(.hidden, for: .tabBar) }.statusPageBeside().tag(4)
        }
        .toolbar(.hidden, for: .tabBar)
        .environment(bar)
        .overlay(alignment: .bottom) {
            if bar.isShown {
                // Open on a Duo, the bar keeps to the right page, under the thumb and
                // off the fold.
                HStack(spacing: PageLayout.gutter) {
                    if pageLayout == .spread { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    InkTabBar(selection: selection, items: Self.items)
                        .frame(maxWidth: .infinity)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: bar.isShown)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            bar.keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            bar.keyboardVisible = false
        }
        .tint(DesignTokens.Colors.accent)
    }

    static let items: [InkTabBar.Item] = [
        .init(tag: 0, title: String(localized: "Today", comment: "Tab label"), symbol: "sunrise"),
        .init(tag: 1, title: String(localized: "Alarms", comment: "Tab label"), symbol: "alarm"),
        .init(tag: 2, title: String(localized: "Sleep", comment: "Tab label"), symbol: "moon.zzz"),
        .init(tag: 3, title: String(localized: "Play", comment: "Tab label"), symbol: "gamecontroller"),
        .init(tag: 4, title: String(localized: "Settings", comment: "Tab label"), symbol: "gearshape"),
    ]
}

// MARK: - Room for the bar

/// Whether the ink bar is on screen. It steps aside for the keyboard, as the system
/// bar does, and for pushed screens that ask it to.
@Observable
final class InkTabBarState {
    var keyboardVisible = false
    fileprivate(set) var hiders = 0
    var isShown: Bool { !keyboardVisible && hiders == 0 }

    fileprivate func hide() { hiders += 1 }
    fileprivate func unhide() { hiders = max(hiders - 1, 0) }
}

extension View {
    /// Room at the bottom of a tab's root for the floating bar, so its last row can
    /// scroll clear of it.
    func inkTabBarClearance() -> some View {
        modifier(InkTabBarClearance())
    }

    /// Hides the ink bar while this (pushed) screen is showing.
    func hidesInkTabBar() -> some View {
        modifier(HidesInkTabBar())
    }
}

private struct InkTabBarClearance: ViewModifier {
    @Environment(InkTabBarState.self) private var bar: InkTabBarState?

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: bar?.isShown == false ? 0 : InkTabBar.clearance)
                .allowsHitTesting(false)
        }
    }
}

private struct HidesInkTabBar: ViewModifier {
    @Environment(InkTabBarState.self) private var bar: InkTabBarState?

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .onAppear { bar?.hide() }
            .onDisappear { bar?.unhide() }
    }
}

// MARK: - Ink tab bar

struct InkTabBar: View {
    struct Item: Identifiable {
        let tag: Int
        let title: String
        let symbol: String
        var id: Int { tag }
    }

    @Binding var selection: Int
    let items: [Item]

    /// The bar's height above the bottom safe area, plus a breath of space.
    static let clearance: CGFloat = 50 + 12 + DesignTokens.Spacing.xxs + 12

    @Namespace private var lens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let idle = Color(hex: 0x8C877F)
    private static let bar = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x2A2825) : UIColor(hex: 0x1B1A17) })

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let chosen = item.tag == selection
                Button {
                    guard !chosen else { return }
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { selection = item.tag }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol)
                            .symbolVariant(chosen ? .fill : .none)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 24)
                        Text(item.title)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(chosen ? DesignTokens.Colors.ink : Self.idle)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background {
                        if chosen {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(DesignTokens.Colors.yolk)
                                .matchedGeometryEffect(id: "lens", in: lens)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .background(Self.bar, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.bottom, DesignTokens.Spacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }
}

// MARK: - Bar appearance

/// Large titles in SF Pro Expanded, in the app's ink. Set once at launch.
enum BrandAppearance {
    @MainActor
    static func apply() {
        let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF4F2ED) : UIColor(hex: 0x1B1A17) }
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = [
            .font: scaled(UIFont.systemFont(ofSize: 32, weight: .heavy, width: .expanded), style: .largeTitle),
            .foregroundColor: ink,
        ]
        navigationBar.titleTextAttributes = [
            .font: scaled(UIFont.systemFont(ofSize: 17, weight: .bold, width: .expanded), style: .headline),
            .foregroundColor: ink,
        ]
    }

    private static func scaled(_ font: UIFont, style: UIFont.TextStyle) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
}

#Preview {
    AppTabBarView()
        .environment(AppContainer.preview())
}
