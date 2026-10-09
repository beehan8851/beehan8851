import SwiftUI
import WeatherKit

/// Full weather detail, pushed from the Today screen's weather card.
///
/// Stateless snapshot: it renders the already-loaded `WeatherConditions` and never
/// refetches — a push should not double-hit the providers (and on the WeatherKit-broken
/// path, re-run the whole failing round trip). The "Updated" line keeps that honest.
struct WeatherDetailView: View {
    let weather: WeatherConditions

    @Environment(\.colorScheme) private var colorScheme
    /// Apple's mark and legal page, fetched from WeatherKit when the reading came
    /// from it. Until it arrives, or if it cannot, the mark is set in text and the
    /// link goes to the page WeatherKit itself points at.
    @State private var appleAttribution: WeatherAttribution?

    private var source: WeatherSource? {
        #if DEBUG
        if DebugLaunch.appleWeather { return .weatherKit }
        #endif
        return weather.source
    }

    /// What `WeatherAttribution.legalPageURL` returns; used only until it has.
    private static let appleLegalPage = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    header
                    currentBlock
                    hourlyStrip
                    statGrid
                    attribution
                }
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.bottom, DesignTokens.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(weather.placeName ?? String(localized: "Weather", comment: "Weather detail fallback title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard source == .weatherKit, appleAttribution == nil else { return }
            appleAttribution = try? await WeatherService.shared.attribution
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(weather.placeName ?? String(localized: "Your location", comment: "Weather detail place fallback"))
                .font(.mcTitle2)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.mcFootnote)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            if let capturedAt = weather.capturedAt {
                Text(String(localized: "Updated \(capturedAt.formatted(date: .omitted, time: .shortened))", comment: "When the weather reading was taken"))
                    .font(.mcCaption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Current conditions

    private var currentBlock: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
                Image(systemName: weather.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 56))
                    .foregroundStyle(DesignTokens.Colors.emberText)
                Text("\(WeatherUnits.degrees(weather.temperature))°")
                    .font(.mcDisplay)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            Text(weather.description)
                .font(.mcTitle3)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(String(localized: "H:\(WeatherUnits.degrees(weather.high))° L:\(WeatherUnits.degrees(weather.low))°", comment: "Daily high and low temperature"))
                .font(.mcCallout)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hourly strip

    @ViewBuilder
    private var hourlyStrip: some View {
        if let hourly = weather.hourly, !hourly.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Hourly", comment: "Hourly forecast section title")
                    .font(.mcSubhead)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(hourly) { point in
                            hourlyChip(point)
                        }
                    }
                }
            }
        }
    }

    private func hourlyChip(_ point: HourlyForecastPoint) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text(point.date, format: .dateTime.hour())
                .font(.mcCaption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Image(systemName: point.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.mcTitle3)
                .foregroundStyle(DesignTokens.Colors.emberText)
            Text("\(WeatherUnits.degrees(point.temperature))°")
                .font(.mcHeadline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            // Reserve the row even when dry, so chips stay the same height.
            Text(point.precipitationChance >= 0.1
                 ? "\(Int((point.precipitationChance * 100).rounded()))%"
                 : " ")
                .font(.mcCaption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(width: 56)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .mcSurface()
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: DesignTokens.Spacing.s
        ) {
            if let wind = weather.windSpeed {
                statTile(
                    icon: "wind",
                    title: String(localized: "Wind", comment: "Wind stat title"),
                    value: WeatherUnits.wind(wind)
                )
            }
            if let humidity = weather.humidity {
                statTile(
                    icon: "humidity.fill",
                    title: String(localized: "Humidity", comment: "Humidity stat title"),
                    value: "\(Int((humidity * 100).rounded()))%"
                )
            }
            statTile(
                icon: "umbrella.fill",
                title: String(localized: "Precipitation", comment: "Precipitation stat title"),
                value: "\(Int((weather.precipitationChance * 100).rounded()))%"
            )
        }
    }

    private func statTile(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Label(title, systemImage: icon)
                .font(.mcFootnote)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.mcTitle3)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mcCard()
    }

    // MARK: - Attribution (licensing requirement, not optional)

    /// WeatherKit's terms: the Apple Weather mark, and a link to the page naming the
    /// other data sources, wherever its data is shown. Open-Meteo's licence asks for
    /// a credit line.
    @ViewBuilder
    private var attribution: some View {
        Group {
            switch source {
            case .weatherKit:
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    appleWeatherMark
                    Link(destination: appleAttribution?.legalPageURL ?? Self.appleLegalPage) {
                        Text(String(localized: "Other data sources", comment: "Link to Apple's legal page for weather data, required by WeatherKit"))
                            .underline()
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            case .openMeteo:
                Text(String(localized: "Weather data by Open-Meteo.com", comment: "Open-Meteo attribution, required by their licence"))
            case .stub, .none:
                EmptyView()
            }
        }
        .font(.mcCaption)
        .foregroundStyle(DesignTokens.Colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Apple's own artwork for the mark, in the variant for this appearance; the
    /// same words in text while it loads or if it cannot.
    private var appleWeatherMark: some View {
        let url = appleAttribution.map { colorScheme == .dark ? $0.combinedMarkDarkURL : $0.combinedMarkLightURL }
        return AsyncImage(url: url) { image in
            image.resizable().scaledToFit().frame(height: 12)
        } placeholder: {
            Text(verbatim: "\u{F8FF} Weather")
        }
        .accessibilityLabel(Text(verbatim: "Apple Weather"))
    }
}

private func previewHourly() -> [HourlyForecastPoint] {
    let base = Date()
    var points: [HourlyForecastPoint] = []
    for index in 0..<12 {
        let offset = TimeInterval(index) * 3600
        let temperature = 27 - Double(index % 6)
        let precipitation: Double = index % 3 == 0 ? 0.2 : 0
        points.append(
            HourlyForecastPoint(
                date: base.addingTimeInterval(offset),
                temperature: temperature,
                symbolName: "sun.max.fill",
                precipitationChance: precipitation
            )
        )
    }
    return points
}

#Preview {
    let sample = WeatherConditions(
        temperature: 26,
        high: 33,
        low: 22,
        symbolName: "sun.max.fill",
        description: "Clear",
        precipitationChance: 0.05,
        humidity: 0.31,
        windSpeed: 4,
        hourly: previewHourly(),
        placeName: "Tashkent",
        source: .openMeteo,
        capturedAt: Date()
    )
    return NavigationStack {
        WeatherDetailView(weather: sample)
    }
}
