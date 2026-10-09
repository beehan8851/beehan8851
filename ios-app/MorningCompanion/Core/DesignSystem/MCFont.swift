import SwiftUI
import UIKit

/// Type scale. SF Pro Expanded for the voice of the app — times, numbers, titles —
/// and SF Pro for everything you read. Text styles follow Dynamic Type; big numerals
/// that should grow with it use `mcScaledFont`.
extension Font {

    // MARK: Display (SF Pro Expanded, fixed size)

    static func mcDisplay(_ size: CGFloat, weight: DisplayWeight = .semibold) -> Font {
        Font.system(size: size, weight: weight.systemWeight).width(.expanded)
    }

    static let mcDisplayTime96 = mcDisplay(96, weight: .regular)
    static let mcDisplay        = mcDisplay(56)
    static let mcDisplayTime44  = mcDisplay(44, weight: .regular)
    static let mcDisplayTime34  = mcDisplay(34)
    static let mcDisplayHero22  = mcDisplay(22)

    /// Monospaced digits, for numbers that change in place.
    static func mcCountdown(_ style: Font.TextStyle = .largeTitle, weight: Font.Weight = .medium) -> Font {
        Font.system(style).weight(weight).width(.expanded).monospacedDigit()
    }

    // MARK: Text (Dynamic Type)

    static let mcLargeTitle = Font.system(.largeTitle, weight: .bold).width(.expanded)
    static let mcTitle1     = Font.system(.largeTitle, weight: .bold).width(.expanded)
    static let mcTitle2     = Font.system(.title, weight: .bold).width(.expanded)
    static let mcTitle3     = Font.system(.title2, weight: .bold).width(.expanded)
    /// A section title on a page that is not a plain list.
    static let mcSectionTitle = Font.system(.title3, weight: .heavy).width(.expanded)
    static let mcHeadline   = Font.headline
    /// The label of a button: SF Pro, bold.
    static let mcButton     = Font.system(.headline, weight: .bold)
    static let mcBody       = Font.body
    static let mcCallout    = Font.subheadline
    static let mcSubhead    = Font.system(.subheadline, weight: .semibold)
    static let mcFootnote   = Font.footnote
    static let mcFootnoteSemibold = Font.system(.footnote, weight: .semibold)
    static let mcCaption    = Font.caption
    static let mcEyebrow    = Font.system(.caption2, weight: .semibold)
    /// A number in a stat line ("12", "7 h 20"), in the display face.
    static let mcNumber     = Font.system(.title2, weight: .bold).width(.expanded).monospacedDigit()

    enum DisplayWeight {
        case light, regular, medium, semibold
        var systemWeight: Font.Weight {
            switch self {
            case .light:    return .light
            case .regular:  return .regular
            case .medium:   return .medium
            case .semibold: return .semibold
            }
        }
    }
}

/// A system font at a custom size that still follows Dynamic Type.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let width: Font.Width
    private let monospacedDigits: Bool

    init(size: CGFloat, weight: Font.Weight, width: Font.Width, relativeTo style: Font.TextStyle, monospacedDigits: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.width = width
        self.monospacedDigits = monospacedDigits
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight).width(width)
        return content.font(monospacedDigits ? font.monospacedDigit() : font)
    }
}

extension View {
    /// Big numerals and headlines: a fixed design size that scales with the user's text size.
    func mcScaledFont(_ size: CGFloat, weight: Font.Weight = .bold, width: Font.Width = .expanded,
                      relativeTo style: Font.TextStyle = .largeTitle, monospacedDigits: Bool = true) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, width: width, relativeTo: style, monospacedDigits: monospacedDigits))
    }
}
