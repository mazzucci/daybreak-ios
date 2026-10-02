import SwiftUI

/// A page that starts with a sky (Home, Weather and a day): scrolls, pulls to refresh (when it can), shows the sky's colour above it when
/// pulled down, and fades a strip of the sky in behind the status bar once the sky has scrolled away, so the white
/// clock and icons never sit on the cards.
struct SkyPage<Content: View>: View {
    /// The sky's top colour.
    let skyTop: Color
    var onRefresh: (@MainActor () async -> Void)? = nil
    /// Debug only: a section to scroll to once [ready] (the `-scrollTo` launch argument, for screenshots).
    var scrollAnchor: String? = nil
    var ready = false
    @ViewBuilder var content: (_ onHeroBottom: @escaping (CGFloat) -> Void) -> Content

    @State private var heroBottom: CGFloat = .greatestFiniteMagnitude
    @State private var safeTop: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content { heroBottom = $0 }
                }
                .background(alignment: .bottom) {
                    // Under the cards (and behind the sky's rounded corners); above it, the sky colour shows.
                    Palette.background.padding(.top, 60)
                }
            }
            .task(id: ready) {
                guard ready, let scrollAnchor else { return }
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo(scrollAnchor, anchor: .top)
            }
        }
        .scrollIndicators(.hidden)
        .modifier(Refreshable(action: onRefresh))
        .background(alignment: .top) {
            GeometryReader { proxy in
                skyTop.frame(height: proxy.size.height / 2).ignoresSafeArea(edges: .top)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            Color.clear.frame(height: 0)
                .background(skyTop.opacity(scrimOpacity).ignoresSafeArea(edges: .top))
                .allowsHitTesting(false)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { safeTop = $0 }
    }

    /// Fully there by the time the sky's bottom edge reaches the status bar.
    private var scrimOpacity: Double {
        let fade: CGFloat = 24
        return Double(min(1, max(0, (fade - (heroBottom - safeTop)) / fade)))
    }
}

/// Pull to refresh, when there's something to refresh.
private struct Refreshable: ViewModifier {
    let action: (@MainActor () async -> Void)?

    func body(content: Content) -> some View {
        if let action { content.refreshable { await action() } } else { content }
    }
}

/// The gradient block at the top of Home and Weather. Content is white; the gradient reaches up behind the status
/// bar (the page puts its top colour there).
struct Hero<Content: View>: View {
    let colors: [Color]
    var leading = false
    var top: CGFloat = 16
    var onBottom: ((CGFloat) -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: leading ? .leading : .center, spacing: 0) { content }
            .foregroundStyle(.white)
            .frame(maxWidth: Metrics.readableWidth - 2 * Metrics.pageMargin, alignment: leading ? .leading : .center)
            .padding(.horizontal, Metrics.pageMargin)
            .padding(.top, top)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Metrics.heroCorner,
                                              bottomTrailingRadius: Metrics.heroCorner, style: .continuous))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { onBottom?($0) }
    }
}

/// A section title with something small at its other end ("Updated 8 min ago"); the extra moves under the title when
/// both don't fit on one line.
struct SectionHeading<Extra: View>: View {
    let title: String
    @ViewBuilder var extra: Extra

    init(_ title: String, @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.title = title
        self.extra = extra()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                heading
                Spacer(minLength: 12)
                extra
            }
            VStack(alignment: .leading, spacing: 2) {
                heading
                extra
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.pageMargin)
    }

    private var heading: some View {
        Text(title).font(.titleMedium).foregroundStyle(Palette.onSurface).accessibilityAddTraits(.isHeader)
    }
}

/// A temperature in the primary unit with the other unit small and muted underneath ("71°" over "21°C").
struct DualTemp: View {
    let c: Double
    let unit: TempUnit
    var font: Font = .titleMedium
    var color: Color = Palette.onSurface
    var alignment: HorizontalAlignment = .center
    /// If set, the primary value is centred in a line this tall, to line up with the other cells in a row.
    var line: CGFloat? = nil

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(formatDegrees(c, unit))
                .font(font)
                .foregroundStyle(color)
                .frame(height: line)
            Text(formatTemp(c, unit.other))
                .font(.labelSmall)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A labelled value on a card ("Humidity 58%"), with an optional small [detail] line, and for the wind an arrow and
/// "from the SW" (or "calm" under 2 km/h).
struct StatTile: View {
    let label: String
    let value: String
    var detail: String? = nil
    var compact = false
    var direction: Double? = nil
    var windKmh: Double? = nil

    var body: some View {
        let calm = windKmh.map(isCalm) ?? false
        VStack(spacing: 0) {
            Text(label)
                .font(.labelMedium)
                .foregroundStyle(Palette.onSurfaceVariant)
            Spacer().frame(height: 6)
            Text(value)
                .font(compact ? .titleMedium : .titleLarge)
                .foregroundStyle(Palette.onSurface)
            if calm {
                Text("calm").font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
            } else if let direction {
                WindFrom(degrees: direction)
            }
            if let detail {
                Text(detail).font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, value, calm ? "calm" : direction.map(formatWindFromSpoken), detail]
            .compactMap { $0 }.joined(separator: " "))
    }
}

/// A row of equal-height tiles, so a tile with a detail line doesn't stand taller than its neighbours.
struct TileRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Metrics.pageMargin)
    }
}

/// A small arrow showing where the wind blows (downwind, north up), then "from the SW".
struct WindFrom: View {
    let degrees: Double
    @ScaledMetric(relativeTo: .caption2) private var arrow: CGFloat = 9

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.up")
                .font(.system(size: arrow, weight: .bold))
                .rotationEffect(.degrees(degrees + 180))
            Text(formatWindFrom(degrees))
        }
        .font(.labelSmall)
        .foregroundStyle(Palette.onSurfaceVariant)
    }
}

/// Lays its children out in rows, wrapping onto the next when one doesn't fit, each row centred.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width && !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// A rounded label-and-value chip on the sky ("High 74°"), with an optional [secondary] value after it, such as the
/// other unit ("High 74° 23°C"), which moves under the value when the pill doesn't fit on one line.
struct HeroPill: View {
    let label: String
    let value: String
    var spoken: String? = nil
    var secondary: String? = nil

    var body: some View {
        FlowLayout(spacing: 5, lineSpacing: 0) {
            HStack(spacing: 6) {
                Text(label).font(.labelMedium)
                Text(value).font(.titleMedium)
            }
            if let secondary {
                Text(secondary).font(.labelMedium).opacity(0.85)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(spoken ?? value)")
    }
}

/// The plain-language block on the sky (the summary).
struct SummaryBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.bodyLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Message and actions, for errors and the location prompt.
struct StateCard<Actions: View>: View {
    let systemImage: String
    let title: String
    let text: String
    var tint: Color = Palette.primary
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(tint)
            Spacer().frame(height: 12)
            Text(title).font(.titleLarge).foregroundStyle(Palette.onSurface)
            Spacer().frame(height: 8)
            Text(text).font(.bodyMedium).foregroundStyle(Palette.onSurfaceVariant)
            Spacer().frame(height: 20)
            actions
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity)
        .card()
        .padding(.horizontal, Metrics.pageMargin)
    }
}

/// A grey bar in the shape of text that's still on its way.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14

    var body: some View {
        Capsule().fill(Palette.skeleton).frame(width: width, height: height)
    }
}
