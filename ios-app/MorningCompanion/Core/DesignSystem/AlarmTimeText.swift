import SwiftUI

/// An alarm time set large: the digits at full size, the AM/PM marker small beside
/// them, where the locale puts it ("6:30 AM", "오전 6:30"). On a 24-hour clock it is
/// just the digits. One component, so every big time in the app is set the same way.
struct AlarmTimeText: View {
    let time: AlarmTime
    var size: CGFloat = 48
    var weight: Font.Weight = .semibold
    var color: Color = DesignTokens.Colors.textPrimary
    var periodColor: Color? = nil

    var body: some View {
        let parts = time.displayParts
        HStack(alignment: .firstTextBaseline, spacing: size * 0.08) {
            if let period = parts.period, parts.periodFirst {
                periodText(period)
            }
            Text(parts.time)
                .tracking(size >= 40 ? -size * 0.02 : 0)
                .mcScaledFont(size, weight: weight)
                .foregroundStyle(color)
            if let period = parts.period, !parts.periodFirst {
                periodText(period)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(time.displayString)
    }

    private func periodText(_ period: String) -> some View {
        Text(period)
            .mcScaledFont(max(13, size * 0.34), weight: .semibold, relativeTo: .title3)
            .foregroundStyle(periodColor ?? color.opacity(0.7))
    }
}

extension AlarmTime {
    /// The time split for display: the digits, the day-period marker if the locale
    /// uses a 12-hour clock, and whether that marker comes first.
    var displayParts: (time: String, period: String?, periodFirst: Bool) {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        guard let format = formatter.dateFormat, format.contains("a") else {
            return (displayString, nil, false)
        }
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        guard let date = Calendar.current.date(from: comps) else { return (displayString, nil, false) }
        let periodFirst = format.trimmingCharacters(in: .whitespaces).hasPrefix("a")
        formatter.dateFormat = format
            .replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)
        let period = hour < 12 ? formatter.amSymbol : formatter.pmSymbol
        return (formatter.string(from: date), period, periodFirst)
    }
}
