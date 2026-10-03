import SwiftUI
import UIKit

/// "This week" on a Weather page (Android's WeekOutlookSection): the heading, then [WeekOutlookCard]. Android's
/// "How it works" link waits for the explanations, which aren't ported yet.
struct WeekOutlookSection: View {
    let outlook: WeekOutlook
    let today: LocalDate
    let onOpenDay: (LocalDate) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SectionHeading("This week")
            Spacer().frame(height: 12)
            WeekOutlookCard(outlook: outlook, today: today, onOpenDay: onOpenDay)
                .padding(.horizontal, Metrics.pageMargin)
        }
    }
}

/// The outlook: the today line in titleMedium, the week lines under it, then a strip of the seven days, each a bar
/// rising from a shared baseline as tall as its score and coloured by its tier, a rain or snow glyph under wet days,
/// and "Best" under the best day. Each day opens its details. The lines are one VoiceOver element, and each day says
/// what it is ("Saturday, best day, great for being outside, dry").
struct WeekOutlookCard: View {
    let outlook: WeekOutlook
    let today: LocalDate
    let onOpenDay: (LocalDate) -> Void

    var body: some View {
        let anyBest = outlook.days.contains { $0.isBest }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(keepUnitsTogether(outlook.today.text))
                    .font(.titleMedium)
                    .foregroundStyle(Palette.onSurface)
                ForEach(outlook.week.indices, id: \.self) { i in
                    Text(keepUnitsTogether(outlook.week[i].text))
                        .font(.bodyMedium)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(outlook.spoken)
            if !outlook.days.isEmpty {
                Spacer().frame(height: 16)
                DayStrip(days: outlook.days, today: today, onOpenDay: onOpenDay)
                    .padding(.horizontal, 8)
            }
        }
        // The "Best" row ends in its own air; without it the strip needs a little more under it.
        .padding(.top, 16)
        .padding(.bottom, anyBest ? 8 : 12)
        .card()
    }
}

/// The tallest a day's bar can be; a bar rises from the baseline by the day's score.
private let barHeight: CGFloat = 52
private let barWidth: CGFloat = 14
private let glyphSize: CGFloat = 16
/// A stay-in day's bar is never shorter than this share of [barHeight], so its colour still shows.
private let minFill: CGFloat = 0.18

/// The strip's day names for columns [room] wide, measured by [widthOf]: "Today" and "Fri", "Sat"…; all three-letter
/// when "Today" doesn't fit; initials when those don't either. With no width yet, the long names.
func dayStripLabels(_ dates: [LocalDate], today: LocalDate, room: CGFloat, widthOf: (String) -> CGFloat) -> [String] {
    let short = dates.map { String(weekdayName($0).prefix(3)) }
    let withToday = dates.enumerated().map { $1 == today ? "Today" : short[$0] }
    func fits(_ names: [String]) -> Bool { names.allSatisfy { widthOf($0) <= room } }
    if room <= 0 || fits(withToday) { return withToday }
    if fits(short) { return short }
    return dates.map { String(weekdayName($0).prefix(1)) }
}

/// One column per day. The names are "Today" and "Fri", "Sat"…; all three-letter when "Today" doesn't fit a column,
/// and initials when those don't either (a narrow phone at a large font). Same for "Best", which becomes a star. The
/// bars grow from the baseline once, when the strip first appears.
private struct DayStrip: View {
    let days: [OutlookDay]
    let today: LocalDate
    let onOpenDay: (LocalDate) -> Void
    @State private var width: CGFloat = 0
    @State private var grown = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Columns get their share of the width, with a little air between names.
        let room = width / CGFloat(max(days.count, 1)) - 4
        let labels = dayStripLabels(days.map(\.date), today: today, room: room) { textWidth($0, .footnote, .bold) }
        // Before the first layout there's no width yet: the word, until it's measured.
        let bestFits = room <= 0 || textWidth("Best", .caption2, .medium) <= room
        let anyBest = days.contains { $0.isBest }
        let anyWet = days.contains { $0.rain == .wet }
        HStack(spacing: 0) {
            ForEach(days.indices, id: \.self) { i in
                DayColumn(day: days[i], label: labels[i], isToday: days[i].date == today, showGlyphRow: anyWet,
                          showBestRow: anyBest, bestAsWord: bestFits, grown: grown) { onOpenDay(days[i].date) }
                    .frame(maxWidth: .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear {
            guard !grown else { return }
            if reduceMotion { grown = true } else { withAnimation(.easeOut(duration: 0.3)) { grown = true } }
        }
    }

    /// How wide [text] is in [style] at [weight] at the current text size.
    private func textWidth(_ text: String, _ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let size = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
        return ceil((text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)]).width)
    }
}

private struct DayColumn: View {
    let day: OutlookDay
    let label: String
    let isToday: Bool
    let showGlyphRow: Bool
    let showBestRow: Bool
    let bestAsWord: Bool
    let grown: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Text(label)
                    // Today stands out by colour as well as weight, so it still does as an initial.
                    .font(.system(.footnote, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? Palette.primary : day.isBest ? Palette.onSurface : Palette.onSurfaceVariant)
                    .lineLimit(1)
                    .fixedSize()
                Spacer().frame(height: 6)
                ScoreBar(score: day.score, tier: day.tier, grown: grown)
                // The baseline: a hairline across the column, meeting its neighbours' into one.
                Rectangle().fill(Palette.outlineVariant).frame(height: 1)
                // The glyph row is there for every day once any day is wet, so the bars line up.
                if showGlyphRow {
                    Spacer().frame(height: 6)
                    ZStack {
                        if day.rain == .wet {
                            WeatherIcon(code: day.snow ? 73 : 63, size: glyphSize)
                        }
                    }
                    .frame(width: glyphSize, height: glyphSize)
                }
                if showBestRow {
                    Spacer().frame(height: 2)
                    ZStack {
                        if day.isBest {
                            if bestAsWord {
                                Text("Best").font(.labelSmall).foregroundStyle(Palette.success).fixedSize()
                            } else {
                                Image(systemName: "star.fill").font(.labelSmall).foregroundStyle(Palette.success)
                            }
                        }
                        // Holds the row's height on the days without it, one line however narrow the column.
                        Text("Best").font(.labelSmall).lineLimit(1).hidden()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details")
    }
}

/// A bar standing on the baseline, as tall as the score and in the tier's colour, rounded at the top; for a day with
/// no score (today, in the evening), a short dash on the baseline.
private struct ScoreBar: View {
    let score: Int?
    let tier: OutlookTier?
    let grown: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            if let score, let tier {
                let fraction = minFill + (1 - minFill) * CGFloat(min(max(score, 0), 100)) / 100
                UnevenRoundedRectangle(topLeadingRadius: barWidth / 2, topTrailingRadius: barWidth / 2)
                    .fill(color(tier))
                    .frame(height: barHeight * fraction)
                    .scaleEffect(x: 1, y: grown ? 1 : 0, anchor: .bottom)
            } else {
                Rectangle().fill(Palette.outlineVariant).frame(height: 3)
            }
        }
        .frame(width: barWidth, height: barHeight, alignment: .bottom)
    }

    private func color(_ tier: OutlookTier) -> Color {
        switch tier {
        case .great: Palette.outlookGreat
        case .good: Palette.outlookGood
        case .meh, .stayIn: Palette.outlookRest
        }
    }
}
