import SwiftUI
import UIKit

/// Design tokens. Yolk, ink and paper; SF Pro Expanded for the voice, SF Pro for the
/// reading. Hierarchy comes from type and spacing. Solid colours, no glow, no glass.
enum DesignTokens {

    /// Colour: yolk, ink and paper. Yolk is the morning — the band on Today, the ring,
    /// the primary button, the one thing to look at. Ink is the night and the type.
    /// Paper carries everything else. Solid colours only; yolk is a surface, never
    /// text on a light ground (it would not read).
    enum Colors {

        // MARK: Brand

        static let yolk = Color(hex: 0xFFC629)
        static let ink  = Color(hex: 0x1B1A17)
        /// Secondary type on yolk: ink at 70 %, flattened so it measures 5.2:1.
        static let onYolkSecondary = Color(hex: 0x5F4E1C)

        // MARK: Surfaces

        /// The page.
        static let background = adaptive(light: 0xF4F2ED, dark: 0x131210)
        /// The page of a focused, full-screen moment.
        static let canvas = adaptive(light: 0xF4F2ED, dark: 0x131210)
        /// A grouped section sitting on `background`.
        static let surfacePrimary = adaptive(light: 0xFFFFFF, dark: 0x1E1D1A)
        /// A recessed fill inside a section: a key, an inset field.
        static let surfaceSecondary = adaptive(light: 0xECE9E2, dark: 0x2A2825)
        /// Something that floats above a section: menus, popovers.
        static let surfaceElevated = adaptive(light: 0xFFFFFF, dark: 0x262421)
        /// Mission tiles: ink on the light page, a raised ink on the dark one.
        static let tile = adaptive(light: 0x1E1C19, dark: 0x262421)
        static let onTile = Color(hex: 0xF4F2ED)
        static let separator = adaptive(light: 0xE3DFD6, dark: 0x2E2C28)

        // MARK: Bands

        /// The day band (the ring, a won mission): yolk in both appearances. Kept for
        /// the moments that are meant to be loud.
        static let dayBand = yolk
        /// A headline card that may be yolk: yolk on the light page, ink on the dark one.
        /// A screen-wide block of yellow at night is a lamp switched on in a dark room.
        static let heroBand = adaptive(light: 0xFFC629, dark: 0x22201D)
        /// Type on `heroBand`.
        static let onHero = adaptive(light: 0x1B1A17, dark: 0xF4F2ED)
        static let onHeroSecondary = adaptive(light: 0x5F4E1C, dark: 0xA8A39A)
        /// The one big figure on `heroBand`: ink on yolk, yolk on ink.
        static let heroFigure = adaptive(light: 0x1B1A17, dark: 0xFFC629)
        /// The night band (Today at night, Sleep): ink, raised a step on the dark page.
        static let nightBand = adaptive(light: 0x1B1A17, dark: 0x22201D)
        static let night = nightBand
        static let heroCard = nightBand
        static let nightRaised = Color(hex: 0x2A2825)
        static let nightText = Color(hex: 0xF4F2ED)
        static let nightTextSecondary = Color(hex: 0xA8A39A)
        static let nightTextTertiary = Color(hex: 0x6E6A63)
        /// The accent on ink: yolk (11:1).
        static let nightAccent = yolk

        // MARK: Accent

        /// Yolk as a surface: primary buttons, a selected day, a badge. Carries ink.
        static let accentFill = yolk
        /// Type and glyphs on `accentFill`.
        static let onAccent = ink
        /// The accent as type, glyph and control tint: ink on the light page (toggles,
        /// links, selected icons), yolk on the dark one.
        static let accent = adaptive(light: 0x1B1A17, dark: 0xFFC629)

        /// Former names.
        static let ember        = accentFill
        static let emberText    = accent
        static let onEmber      = onAccent
        static let emberStrong  = adaptive(light: 0x000000, dark: 0xFFD45E)
        /// A quiet yolk wash, for a selected row.
        static let emberSubtle  = Color(hex: 0xFFC629).opacity(0.22)
        static let gold         = yolk
        static let goldSoft     = Color(hex: 0xFFE27F)

        // MARK: Text

        static let textPrimary   = adaptive(light: 0x1B1A17, dark: 0xF4F2ED)
        static let textSecondary = adaptive(light: 0x6B665E, dark: 0xA8A39A)
        /// Glyphs and large numerals only; not body text.
        static let textTertiary  = adaptive(light: 0xA29D94, dark: 0x6E6A63)
        static let textDisabled  = adaptive(light: 0xC9C5BD, dark: 0x45423D)

        // MARK: Streak

        /// A morning won: an ink paw print on paper, a yolk one in the dark.
        static let streakFlame  = adaptive(light: 0x1B1A17, dark: 0xFFC629)
        /// A morning missed: an alarm was set and the mission was not finished.
        static let streakMissed = adaptive(light: 0xC8463A, dark: 0xFF7A6B)
        /// A day with no alarm.
        static let streakRest   = adaptive(light: 0xD3CFC6, dark: 0x3A3733)

        // MARK: Semantic

        static let success     = adaptive(light: 0x2F8F5B, dark: 0x5FC28A)
        static let destructive = adaptive(light: 0xC8362B, dark: 0xFF6B5E)
        static let warning     = adaptive(light: 0x9A6A00, dark: 0xFFC629)

        /// The laser game's dot, and only that: red because a laser pointer is.
        static let laser = Color(hex: 0xF0402F)

        // MARK: Helpers

        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(UIColor { t in
                t.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
            })
        }
    }

    /// 8pt grid, with the two half-steps a dense list row needs.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let s:   CGFloat = 16
        static let m:   CGFloat = 24
        static let l:   CGFloat = 32
        static let xl:  CGFloat = 48
    }

    /// Moderate radii, only where a shape needs one.
    enum Radius {
        static let xs:  CGFloat = 6
        /// Keys, fields, small controls.
        static let s:   CGFloat = 10
        /// A grouped section.
        static let m:   CGFloat = 14
        /// Primary buttons.
        static let l:   CGFloat = 14
        /// The bands: Today, Sleep, Progress, the editor's time.
        static let xl:  CGFloat = 28
    }

    /// Control heights, all above the 44pt target floor.
    enum Size {
        static let row:      CGFloat = 44
        static let button:   CGFloat = 54
        static let buttonLG: CGFloat = 56
        static let tabIcon:  CGFloat = 26
    }

    /// Animation durations in seconds
    enum Motion {
        static let immediate: Double = 0.120
        static let controls:  Double = 0.240
        static let screen:    Double = 0.400
        static let ambient:   Double = 0.800
    }
}

// MARK: - Hex initialisers

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8)  & 0xFF) / 255,
            blue:  CGFloat( hex        & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}
