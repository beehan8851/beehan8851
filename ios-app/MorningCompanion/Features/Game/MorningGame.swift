import SwiftUI

/// The morning games, as Today and the Play tab list them: what each is called, what
/// it asks of you, its record, its picture and the screen it opens.
enum MorningGame: String, CaseIterable, Identifiable {
    case catchCat, laser, boxes, catNaps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catchCat: String(localized: "Catch the cat", comment: "Game title")
        case .laser: String(localized: "Laser", comment: "Laser game title")
        case .boxes: String(localized: "Which box?", comment: "Box game title")
        case .catNaps: String(localized: "Cat Naps", comment: "Cat Naps game title")
        }
    }

    /// One line on what it is, with the record in front once there is one.
    func detail(best: Int) -> String {
        switch self {
        case .catchCat:
            best > 0
                ? String(localized: "Best \(best). Thirty seconds to wake your hands up.", comment: "Today game card detail with the best score")
                : String(localized: "Thirty seconds to wake your hands up.", comment: "Today game card detail")
        case .laser:
            best > 0
                ? String(localized: "Best \(best). Keep the dot out from under its paws.", comment: "Today laser game card detail with the best score")
                : String(localized: "Keep the dot out from under its paws.", comment: "Today laser game card detail")
        case .boxes:
            best > 0
                ? String(localized: "Best \(best). Keep your eye on the cat.", comment: "Today box game card detail with the best score")
                : String(localized: "Keep your eye on the cat.", comment: "Today box game card detail")
        case .catNaps:
            // `best` is the streak of days solved.
            // The hardest level solved today, if any.
            if let top = CatNapRecord.solves(CatNapDay.number(for: .now)).max(by: { $0.key.rawValue < $1.key.rawValue }) {
                String(localized: "\(top.key.title) solved in \(CatNapGameView.clock(top.value.seconds)). New ones tomorrow.", comment: "Today Cat Naps card detail once one of today's puzzles is solved: the level and the time")
            } else if best > 0 {
                String(localized: "Streak \(best). Today's puzzles are waiting.", comment: "Today Cat Naps card detail with the days-in-a-row count")
            } else {
                String(localized: "Easy, medium and hard, new every morning.", comment: "Today Cat Naps card detail")
            }
        }
    }

    /// What it trains, for the Play tab: the three are three different mornings.
    var skill: String {
        switch self {
        case .catchCat: String(localized: "Quick hands", comment: "Play tab: what the catch game trains")
        case .laser: String(localized: "A steady finger", comment: "Play tab: what the laser game trains")
        case .boxes: String(localized: "Sharp eyes", comment: "Play tab: what the box game trains")
        case .catNaps: String(localized: "A clear head", comment: "Play tab: what the Cat Naps puzzle trains")
        }
    }

    var hint: String {
        switch self {
        case .catchCat, .laser: String(localized: "Opens a thirty-second game", comment: "Today game card, VoiceOver hint")
        case .boxes: String(localized: "Opens a game you can get wrong three times", comment: "Today box game card, VoiceOver hint")
        case .catNaps: String(localized: "Opens today's puzzles", comment: "Cat Naps card, VoiceOver hint")
        }
    }

    func best() -> Int {
        switch self {
        case .catchCat: CatchGameRecord.best()
        case .laser: LaserGameRecord.best()
        case .boxes: BoxGameRecord.best()
        case .catNaps: CatNapRecord.streak(today: CatNapDay.number(for: .now))
        }
    }

    /// One game a day on Today, in turn, so the card is not always the same.
    static func ofTheDay(_ date: Date = .now, calendar: Calendar = .current) -> MorningGame {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return allCases[day % allCases.count]
    }

    /// The picture on an ink card.
    @ViewBuilder
    func poster(width: CGFloat) -> some View {
        switch self {
        case .catchCat:
            CatMascot(mood: .ringing, ground: .dark)
                .frame(width: width * 0.62)
                .frame(width: width)
        case .laser:
            LaserPoster(room: false)
                .frame(width: width)
        case .boxes:
            BoxPoster(ground: .ink)
                .frame(width: width)
        case .catNaps:
            CatNapPoster()
                .frame(width: width * 0.6)
                .frame(width: width)
        }
    }

    @ViewBuilder
    var screen: some View {
        switch self {
        case .catchCat: CatchGameView()
        case .laser: LaserGameView()
        case .boxes: BoxGameView()
        case .catNaps: CatNapGameView()
        }
    }
}

extension View {
    /// Presents `game` full screen, the way every game is opened.
    func morningGame(_ game: Binding<MorningGame?>, onDismiss: @escaping () -> Void = {}) -> some View {
        fullScreenCover(item: game, onDismiss: onDismiss) { game in
            game.screen.readsPageLayout().daylightAppearance()
        }
    }
}

/// A game on an ink card: the title and a line, the picture, and the play button.
struct GameCard: View {
    let game: MorningGame
    let best: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: DesignTokens.Spacing.s) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(game.title)
                        .mcScaledFont(20, weight: .heavy, relativeTo: .title3)
                        .foregroundStyle(DesignTokens.Colors.onTile)
                    Text(game.detail(best: best))
                        .font(.mcFootnote)
                        .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                game.poster(width: 112)
                    .accessibilityHidden(true)
                PlayDisc()
            }
            .padding(DesignTokens.Spacing.s)
            .padding(.leading, DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.tile, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityHint(game.hint)
    }
}

/// The yolk play button on a game card.
struct PlayDisc: View {
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.ink)
            .frame(width: size, height: size)
            .background(DesignTokens.Colors.yolk, in: Circle())
            .accessibilityHidden(true)
    }
}
