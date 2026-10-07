import SwiftUI

/// The Play tab: the morning games, each on an ink card with its picture, what it
/// trains and its record. Short games for the first minutes of the day — never a
/// mission, never in the way of an alarm.
struct PlayView: View {
    @State private var playing: MorningGame?
    @State private var bests: [MorningGame: Int] = PlayView.readBests()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text(String(localized: "Short games for the first minutes of the day: one for the hands, one for the fingers, one for the eyes, and a puzzle for the head.", comment: "Play tab: the line under the title"))
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DesignTokens.Spacing.xs)
                ForEach(MorningGame.allCases) { game in
                    tile(game)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.top, DesignTokens.Spacing.xs)
            .padding(.bottom, DesignTokens.Spacing.l)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(DesignTokens.Colors.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Play", comment: "Tab label"))
        .navigationBarTitleDisplayMode(.large)
        .morningGame($playing) { bests = Self.readBests() }
    }

    private func tile(_ game: MorningGame) -> some View {
        let best = bests[game] ?? 0
        // Words beside the picture; at the largest text sizes, the picture goes under.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DesignTokens.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DesignTokens.Spacing.s))
        return Button { playing = game } label: {
            layout {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(game.skill.uppercased())
                        .font(.system(.caption, weight: .heavy).width(.expanded))
                        .foregroundStyle(DesignTokens.Colors.yolk)
                    Text(game.title)
                        .mcScaledFont(21, weight: .heavy, relativeTo: .title3)
                        .foregroundStyle(DesignTokens.Colors.onTile)
                    Text(game.detail(best: best))
                        .font(.mcFootnote)
                        .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The picture, with the play button tucked into its corner.
                game.poster(width: 112)
                    .padding(.trailing, 22)
                    .padding(.bottom, 14)
                    .overlay(alignment: .bottomTrailing) { PlayDisc(size: 36) }
                    .accessibilityHidden(true)
            }
            .padding(DesignTokens.Spacing.s)
            .padding(.leading, DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.tile, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(game.hint)
    }

    private static func readBests() -> [MorningGame: Int] {
        Dictionary(uniqueKeysWithValues: MorningGame.allCases.map { ($0, $0.best()) })
    }
}

#Preview {
    NavigationStack { PlayView() }
}
