import SwiftUI

/// A game's intro or its result: the picture over the words on one page; open like
/// a book, the picture on the left page and the words and buttons on the right, so
/// nothing sits on the fold. The board itself is one surface across both pages: a
/// cat can jump the fold.
struct GamePage<Top: View, Picture: View, Words: View>: View {
    var spacing: CGFloat
    @ViewBuilder var top: Top
    @ViewBuilder var picture: Picture
    /// Everything under the picture, ending with the buttons.
    @ViewBuilder var words: Words

    @Environment(\.pageLayout) private var pageLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if pageLayout == .spread && !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: PageLayout.gutter) {
                VStack(spacing: spacing) {
                    top
                    Spacer(minLength: 0)
                    picture
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: spacing) {
                    Spacer(minLength: 0)
                    words
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: spacing) {
                top
                Spacer(minLength: 0)
                picture
                words
            }
            .frame(maxWidth: 520)
        }
    }
}
