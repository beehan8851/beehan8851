import SwiftUI

/// The streak as a picture to send someone: yolk, the number set huge in ink, the
/// week's paw prints, and the cat — proud, and wearing whatever it has earned. Fixed
/// at 4 : 5, the shape a feed shows whole, and always in the light appearance: it is
/// a picture of the app's morning colour, not of the phone's setting.
struct StreakShareCard: View {
    let streak: Int
    let week: [DayCell]

    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        let phrase = CountPhrase(String(localized: "\(streak) days in a row", comment: "Streak on Today and Progress: the number is set large and the words small beside it. Keep the number in the text; the app cuts the phrase where it sits."), count: streak)
        ZStack(alignment: .topLeading) {
            DesignTokens.Colors.yolk
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Dawnwick")
                    .font(.system(size: 15, weight: .heavy).width(.expanded))
                    .foregroundStyle(DesignTokens.Colors.ink.opacity(0.75))
                Spacer(minLength: 0)
                if !phrase.before.isEmpty {
                    Text(phrase.before)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.ink)
                }
                Text(phrase.number)
                    .font(.system(size: 140, weight: .heavy).width(.expanded))
                    .foregroundStyle(DesignTokens.Colors.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(phrase.after)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.ink)
                    .frame(maxWidth: 200, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        DayGlyph(outcome: day.outcome)
                            .frame(width: 22, height: 22)
                            .frame(maxWidth: .infinity)
                    }
                }
                // Clear of the cat in the corner.
                .frame(maxWidth: 180)
            }
            .padding(28)
            CatMascot(mood: .proud, ground: .light, animated: false)
                .frame(width: 150)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 20)
                .padding(.bottom, 22)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// The card rendered to an image, three times over for a sharp picture.
    @MainActor
    static func image(streak: Int, week: [DayCell], dressing: CatDressing) -> Image? {
        let renderer = ImageRenderer(content: StreakShareCard(streak: streak, week: week)
            .environment(\.colorScheme, .light)
            .environment(\.catDressing, dressing))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

#Preview {
    StreakShareCard(streak: 12, week: [])
}
