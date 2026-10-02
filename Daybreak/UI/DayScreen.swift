import SwiftUI
import UIKit

/// Bars stop growing at this many mm an hour, so one downpour doesn't flatten the rest.
private let barCapMm = 4.0

/// Hours a day's bar chart has, one bar each: the day's stamps, 00:00 to 23:00.
private let chartHours = 24

/// One day in full, opened from a row of the 10-day list (Android's DayScreen): the day's sky with its name,
/// condition, high and low in both units and how warm or cold it'll feel; the temperature hour by hour; the rain (or
/// snow) card; wind; and sun and UV. Pushed over the Weather tab, with the system back button.
struct DayScreen: View {
    let date: LocalDate
    @Environment(WeatherModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let forecast = model.forecast {
                if let day = forecast.day(date) {
                    DayPage(placeName: model.place?.name ?? "My location", forecast: forecast, day: day,
                            unit: model.unit)
                } else {
                    // The forecast moved on (a new day) and this one has gone from it.
                    Color.clear.onAppear { dismiss() }
                }
            } else {
                DayLoading()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DayPage: View {
    let placeName: String
    let forecast: Forecast
    let day: DaySummary
    let unit: TempUnit
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let date = day.date
        let rain = Precip.dayRain(forecast, date)
        let today = forecast.today.date
        let isToday = date == today
        let sky = Sky(code: day.code).gradient(night: false, dark: scheme == .dark)
        let hours = HourCell.day(forecast, date)
        SkyPage(skyTop: sky[0]) { onHeroBottom in
            Hero(colors: sky, top: 12, onBottom: onHeroBottom) {
                DayHeader(placeName: placeName, forecast: forecast, day: day, unit: unit)
            }
            VStack(spacing: 0) {
                Spacer().frame(height: 24)
                SectionHeading("Hour by hour")
                Spacer().frame(height: 12)
                if !hours.isEmpty {
                    HourStrip(cells: hours, unit: unit, highlightFirst: isToday)
                }
                Spacer().frame(height: 16)
                RainCard(rain: rain, unit: unit)
                    .padding(.horizontal, Metrics.pageMargin)
                if date.epochDay - today.epochDay >= 2 && rain.amountShown {
                    Text("Amounts this far ahead are rough; the chance is the better guide.")
                        .font(.labelSmall)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metrics.pageMargin + 4)
                        .padding(.vertical, 8)
                }
                WindTiles(day: day, unit: unit)
                SunAndUv(day: day)
                Spacer().frame(height: 24)
            }
            .readableWidth()
        }
        .modifier(SkyBar(color: sky[0]))
    }
}

/// The navigation bar in the sky's top colour, so it reads as part of the sky, with white content and a white status
/// bar. (With the bar's background hidden, its colour scheme doesn't apply and the clock turns dark once the page
/// scrolls.)
private struct SkyBar: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        let bar = content
            .toolbarBackground(color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        if #available(iOS 26, *) { bar.scrollEdgeEffectHidden(true, for: .top) } else { bar }
    }
}

/// The day page while its forecast is still on its way: a plain sky and a line saying so.
private struct DayLoading: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let sky = Sky.neutral(dark: scheme == .dark)
        SkyPage(skyTop: sky[0]) { _ in
            Hero(colors: sky) { Spacer().frame(height: 48) }
            Spacer().frame(height: 48)
            Text("Getting the forecast…")
                .font(.bodyMedium)
                .foregroundStyle(Palette.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.pageMargin)
        }
        .modifier(SkyBar(color: sky[0]))
    }
}

/// The day's name and date, its condition, and pills for the high and low (both units) and, when it's 3° or more
/// away at either end, the feels-like range, on the day's sky.
private struct DayHeader: View {
    let placeName: String
    let forecast: Forecast
    let day: DaySummary
    let unit: TempUnit

    var body: some View {
        let today = forecast.today.date
        let title = day.date == today ? "Today" : day.date == today.plusDays(1) ? "Tomorrow" : weekdayName(day.date)
        // "Thursday, October 8" for today and tomorrow (whose title isn't a weekday), "October 8" otherwise.
        let dateLine = title == "Today" || title == "Tomorrow"
            ? "\(weekdayName(day.date)), \(formatLongDate(day.date))"
            : formatLongDate(day.date)
        let other = unit.other
        let feels = forecast.hoursOf(day.date).compactMap(\.feelsLikeC)
        VStack(spacing: 0) {
            Spacer().frame(height: 4)
            Text(title)
                .font(.headline1)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Spacer().frame(height: 2)
            Text("\(dateLine) · \(placeName)")
                .font(.bodyMedium)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 16)
            HStack(spacing: 8) {
                WeatherIcon(code: day.code, night: false, palette: .mono(.white), size: 30)
                Text(describeWeatherCode(day.code)).font(.titleLarge)
            }
            Spacer().frame(height: 12)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                HeroPill(label: "High", value: formatDegrees(day.highC, unit), spoken: formatBothUnits(day.highC, unit),
                         secondary: formatTemp(day.highC, other))
                HeroPill(label: "Low", value: formatDegrees(day.lowC, unit), spoken: formatBothUnits(day.lowC, unit),
                         secondary: formatTemp(day.lowC, other))
                if let hi = feels.max(), let lo = feels.min(), feelsWorthAPill(hi, lo, day, unit) {
                    HeroPill(label: "Feels like",
                             value: "\(formatDegrees(hi, unit)) / \(formatDegrees(lo, unit))",
                             spoken: "high \(formatBothUnits(hi, unit)), low \(formatBothUnits(lo, unit))",
                             secondary: "\(formatTemp(hi, other)) / \(formatTemp(lo, other))")
                }
            }
        }
    }
}

/// The feels-like range earns its pill once it's 3° or more (in the unit shown) from the high or the low.
func feelsWorthAPill(_ feelsHighC: Double, _ feelsLowC: Double, _ day: DaySummary, _ unit: TempUnit) -> Bool {
    abs(degrees(feelsHighC, unit) - degrees(day.highC, unit)) >= feelsLikeGap
        || abs(degrees(feelsLowC, unit) - degrees(day.lowC, unit)) >= feelsLikeGap
}

/// The day's strongest wind with where it comes from (or "calm"), and its strongest gust; nothing when neither is
/// known.
private struct WindTiles: View {
    let day: DaySummary
    let unit: TempUnit

    var body: some View {
        if day.windMaxKmh != nil || day.gustMaxKmh != nil {
            TileRow {
                if let wind = day.windMaxKmh {
                    StatTile(label: "Wind", value: keepUnitsTogether("Up to \(formatWind(wind, unit))"),
                             direction: day.windDirectionDeg, windKmh: wind)
                }
                if let gust = day.gustMaxKmh {
                    StatTile(label: "Gusts", value: keepUnitsTogether("Up to \(formatWind(gust, unit))"))
                }
            }
            .padding(.top, 16)
        }
    }
}

/// The day's rain (or snow): a verdict with the chance word, total and hours; when in the day it falls; a bar per
/// hour with the chance every three hours; the parts of the day that aren't dry, which add up to the verdict; and a
/// line when it carries on after midnight.
struct RainCard: View {
    let rain: DayRain
    let unit: TempUnit

    var body: some View {
        let verdict = Precip.verdict(rain, unit)
        let timing = rain.amountShown ? rain.timing.map(Precip.timingSentence) : nil
        let showChart = rain.complete && rain.amountShown
            && rain.counted.contains { ($0.precipMm ?? 0) >= Precip.hourAmountMinMm }
        let rows = rain.rows
        // A card titled "Snow" doesn't say "snow" again on every row; "Rain" and "Rain and snow" do, where it's snow.
        let snowWord = rain.mix != .snow
        let carryOn = rain.dry ? nil : rain.carryOn.map { Precip.carryOnLine($0, unit) }
        VStack(alignment: .leading, spacing: 0) {
            Text(rain.title).font(.titleMedium).foregroundStyle(Palette.onSurface)
            Spacer().frame(height: 8)
            Text(keepUnitsTogether(verdict)).font(.titleLarge).foregroundStyle(Palette.onSurface)
            if let timing {
                Spacer().frame(height: 2)
                Text(keepUnitsTogether(timing)).font(.bodyMedium).foregroundStyle(Palette.onSurfaceVariant)
            }
            if showChart {
                Spacer().frame(height: 16)
                RainChart(rain: rain)
            }
            if !rows.isEmpty {
                Spacer().frame(height: showChart ? 16 : 12)
                VStack(spacing: 10) {
                    ForEach(rows.indices, id: \.self) { i in
                        PeriodRow(period: rows[i], unit: unit, snowWord: snowWord)
                    }
                }
            }
            if let carryOn {
                Spacer().frame(height: 8)
                Text(keepUnitsTogether(carryOn)).font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(verdict: verdict, timing: timing, rows: rows, carryOn: carryOn))
    }

    private func spoken(verdict: String, timing: String?, rows: [RainPeriod], carryOn: String?) -> String {
        var parts = [rain.title, verdict.replacingOccurrences(of: " · ", with: ", ")]
        if let timing { parts.append(timing) }
        for p in rows {
            parts.append("\(p.name), \(formatHour(p.labelStart)) to \(formatHour(p.labelEnd)), \(p.spoken(unit))")
        }
        if let carryOn { parts.append(carryOn.hasSuffix(".") ? String(carryOn.dropLast()) : carryOn) }
        return parts.joined(separator: ". ")
    }
}

/// A bar per hour of the day, its height the amount (capped at 4 mm an hour, where the bar darkens), with the chance
/// under every third hour ("·" below 10%) and the time every six. Each value is drawn over the hour it falls in, the
/// hour before its stamp, so the first bar is the hour before midnight that opens the day's figures (see [Precip]).
/// Only the hours the verdict counts get a bar. One blue at different heights stands in for light, moderate and
/// heavy. Hidden from VoiceOver: the verdict and the rows carry the same numbers.
private struct RainChart: View {
    let rain: DayRain
    @State private var width: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 64

    var body: some View {
        let date = rain.date
        // Slot i holds the value stamped i:00, which fell from (i - 1):00 to i:00.
        let counted = Dictionary(rain.counted.map { ($0.time.hour, $0.precipMm ?? 0) }, uniquingKeysWith: { a, _ in a })
        let chances = Dictionary(rain.hours.map { ($0.time.hour, $0.precipChance) }, uniquingKeysWith: { a, _ in a })
        // "40%" when three bars leave room for "100%", else plain numbers.
        let withPercent = width > 0 && width * 3 / CGFloat(chartHours) >= labelSmallWidth("100%", typeSize) + 4
        let chanceSlots = Array(stride(from: 1, to: chartHours, by: 3))
        let times = [0, 6, 12, 18]
        VStack(spacing: 0) {
            Canvas { context, size in
                let slot = size.width / CGFloat(chartHours)
                let gap = min(4, slot * 0.3)
                let bar = slot - gap
                let floor = size.height - 1
                context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                             with: .color(Palette.outlineVariant))
                for (index, mm) in counted where mm >= Precip.hourAmountMinMm {
                    let height = max(CGFloat(min(mm, barCapMm) / barCapMm) * floor, 3)
                    let rect = CGRect(x: CGFloat(index) * slot + gap / 2, y: floor - height, width: bar, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2),
                                 with: .color(mm >= barCapMm ? Palette.rainHeavy : Palette.rain))
                }
            }
            .frame(height: min(barHeight, 96))
            Spacer().frame(height: 4)
            // The chance under the bars that end at 1, 4, 7 … 10 PM.
            TickRow(centres: chanceSlots.map { CGFloat($0) + 0.5 }) {
                ForEach(chanceSlots, id: \.self) { slot in
                    let chance = chances[slot] ?? 0
                    let shown = Precip.showHourChance(chance)
                    Text(shown ? "\(chance)\(withPercent ? "%" : "")" : "·")
                        .foregroundStyle(shown && Precip.highlightChance(chance) ? Palette.rain : Palette.onSurfaceVariant)
                }
            }
            Spacer().frame(height: 2)
            // The times sit on the boundaries between bars: midnight is one bar in.
            TickRow(centres: times.map { CGFloat($0) + 1 }) {
                ForEach(times, id: \.self) { hour in
                    Text(formatHour(date.atTime(hour))).foregroundStyle(Palette.onSurfaceVariant)
                }
            }
        }
        .font(.labelSmall)
        .lineLimit(1)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityHidden(true)
    }
}

/// How wide [text] is in the labelSmall style (caption2, medium) at [typeSize].
private func labelSmallWidth(_ text: String, _ typeSize: DynamicTypeSize) -> CGFloat {
    let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
    let size = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits).pointSize
    return ceil((text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium)]).width)
}

/// Labels centred on [centres] (in bars from the left edge), kept inside the row at its ends. When large text leaves
/// no room, a label that would touch the one before it is left out, so they thin out rather than overlap.
private struct TickRow: Layout {
    let centres: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var free = bounds.minX
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let centre = bounds.minX + (i < centres.count ? centres[i] : 0) * bounds.width / CGFloat(chartHours)
            let x = min(max(centre - size.width / 2, bounds.minX), max(bounds.maxX - size.width, bounds.minX))
            if x >= free {
                view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
                free = x + size.width + 4
            } else {
                // Out of sight, rather than on top of its neighbour (an unplaced view would sit in the middle, and a
                // zero proposal still draws an ellipsis).
                view.place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.minY), proposal: ProposedViewSize(size))
            }
        }
    }
}

/// "Daytime  7 AM–7 PM ……… 90% · 11 mm · 5 h"; the numbers move under the name when large text leaves no room.
private struct PeriodRow: View {
    let period: RainPeriod
    let unit: TempUnit
    let snowWord: Bool

    var body: some View {
        let name = VStack(alignment: .leading, spacing: 0) {
            Text(period.name).font(.titleSmall).foregroundStyle(Palette.onSurface)
            Text(keepUnitsTogether("\(formatHour(period.labelStart))–\(formatHour(period.labelEnd))"))
                .font(.labelSmall)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        let numbers = Text(keepUnitsTogether(period.describe(unit, snowWord: snowWord)))
            .font(.bodyMedium)
            .foregroundStyle(Palette.onSurface)
        ViewThatFits(in: .horizontal) {
            HStack {
                name.fixedSize()
                Spacer(minLength: 12)
                numbers.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                name
                numbers
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
