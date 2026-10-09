import SwiftUI

// MARK: - Time drum

/// The alarm time as two drums of large numerals — hour and minute, and AM/PM where
/// the locale keeps a 12-hour clock — for the hero band at the top of the editor:
/// ink numerals on yolk by day, yolk numerals on ink in the dark appearance.
/// Each drum snaps to a row, ticks under the finger, and is one adjustable element
/// for VoiceOver (swipe up or down to change it).
struct TimeDrumPicker: View {
    /// 0–23.
    @Binding var hour: Int
    @Binding var minute: Int

    private let clock = ClockStyle.current

    var body: some View {
        ZStack {
            // The reading line: where the chosen time sits.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignTokens.Colors.heroFigure.opacity(0.1))
                .frame(height: DrumColumn.rowHeight)
            HStack(spacing: 0) {
                if clock.uses12Hour && clock.periodFirst { periodDrum }
                DrumColumn(
                    values: clock.uses12Hour ? Array(1...12) : Array(0...23),
                    selection: hourBinding,
                    label: String(localized: "Hour", comment: "Time picker, VoiceOver label of the hour drum"),
                    text: { clock.uses12Hour ? "\($0)" : String(format: "%02d", $0) },
                    width: 104
                )
                Text(verbatim: ":")
                    .font(.system(size: 46, weight: .bold).width(.expanded))
                    .foregroundStyle(DesignTokens.Colors.heroFigure)
                    .offset(y: -4)
                    .accessibilityHidden(true)
                DrumColumn(
                    values: Array(0...59),
                    selection: $minute,
                    label: String(localized: "Minute", comment: "Time picker, VoiceOver label of the minute drum"),
                    text: { String(format: "%02d", $0) },
                    width: 104
                )
                if clock.uses12Hour && !clock.periodFirst { periodDrum }
            }
        }
        .frame(height: DrumColumn.rowHeight * 3)
    }

    private var periodDrum: some View {
        DrumColumn(
            values: [0, 1],
            selection: periodBinding,
            label: String(localized: "AM or PM", comment: "Time picker, VoiceOver label of the AM/PM drum"),
            text: { $0 == 0 ? clock.amSymbol : clock.pmSymbol },
            width: 70,
            fontSize: 22
        )
    }

    private var hourBinding: Binding<Int> {
        guard clock.uses12Hour else { return $hour }
        return Binding(
            get: { hour % 12 == 0 ? 12 : hour % 12 },
            set: { hour = ($0 % 12) + (hour >= 12 ? 12 : 0) }
        )
    }

    private var periodBinding: Binding<Int> {
        Binding(
            get: { hour >= 12 ? 1 : 0 },
            set: { hour = (hour % 12) + ($0 == 1 ? 12 : 0) }
        )
    }
}

// MARK: - Clock style

private struct ClockStyle {
    let uses12Hour: Bool
    let periodFirst: Bool
    let amSymbol: String
    let pmSymbol: String

    static var current: ClockStyle {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        let format = formatter.dateFormat ?? "HH:mm"
        return ClockStyle(
            uses12Hour: format.contains("a"),
            periodFirst: format.trimmingCharacters(in: .whitespaces).hasPrefix("a"),
            amSymbol: formatter.amSymbol,
            pmSymbol: formatter.pmSymbol
        )
    }
}

// MARK: - One drum

private struct DrumColumn: View {
    static let rowHeight: CGFloat = 62

    let values: [Int]
    @Binding var selection: Int
    let label: String
    let text: (Int) -> String
    let width: CGFloat
    var fontSize: CGFloat = 54

    @State private var position: Int?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { value in
                    let row = Self.rowHeight
                    Text(verbatim: text(value))
                        .font(.system(size: fontSize, weight: .bold).width(.expanded).monospacedDigit())
                        .foregroundStyle(DesignTokens.Colors.heroFigure)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: width, height: Self.rowHeight)
                        .visualEffect { content, proxy in
                            // Rows shrink and fade with their distance from the reading line.
                            // The scroll view's space starts at its content margin, one row
                            // down, so the reading line is half a row from its origin.
                            let mid = proxy.frame(in: .scrollView(axis: .vertical)).midY
                            let distance = min(abs(mid - row * 0.5) / row, 1.5)
                            return content
                                .scaleEffect(1 - distance * 0.24)
                                .opacity(1 - distance * 0.5)
                        }
                        .id(value)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .contentMargins(.vertical, Self.rowHeight, for: .scrollContent)
        .frame(width: width, height: Self.rowHeight * 3)
        .onAppear { position = selection }
        .onChange(of: position) { _, new in
            if let new, new != selection { selection = new }
        }
        .onChange(of: selection) { _, new in
            if position != new { withAnimation(.snappy) { position = new } }
        }
        .sensoryFeedback(.selection, trigger: position)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(text(selection))
        .accessibilityAdjustableAction { direction in
            guard let index = values.firstIndex(of: selection) else { return }
            switch direction {
            case .increment: if index + 1 < values.count { selection = values[index + 1] }
            case .decrement: if index > 0 { selection = values[index - 1] }
            @unknown default: break
            }
        }
    }
}

#Preview {
    struct Host: View {
        @State private var hour = 7
        @State private var minute = 30
        var body: some View {
            TimeDrumPicker(hour: $hour, minute: $minute)
                .padding()
                .background(DesignTokens.Colors.heroBand, in: RoundedRectangle(cornerRadius: 28))
                .padding()
        }
    }
    return Host()
}
