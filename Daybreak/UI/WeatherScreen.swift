import SwiftUI
import UIKit

/// A day's page on one of the Weather tab's pages.
struct DayRoute: Hashable {
    let pageId: String
    let date: LocalDate
}

/// Height of the floating row of buttons over the sky.
private let topRowHeight: CGFloat = 44

/// The Weather tab, ported from Android's WeatherScreen: a page per place (where you are, then the places you've
/// added), swiped sideways, under a floating row with where you are in the pages, Refresh, Add place and Places.
/// With no places at all, a page that says how to start. Each page
/// has the sky with the summary, the temperature in both units, the condition and today's High, Low and rain; then
/// feels-like, humidity and wind; the next 12 hours; sunrise, sunset and UV; and the next 10 days. Pull to refresh.
/// Tapping a day opens its page.
struct WeatherScreen: View {
    @Environment(WeatherModel.self) private var model
    @State private var path: [DayRoute] =
        LaunchOptions.openDay.map { [DayRoute(pageId: Place.currentLocationId, date: $0)] } ?? []
    @State private var selection = Place.currentLocationId
    @State private var searching = false
    @State private var managing = false
    /// A place just added, to turn to once its page exists (Android waits for it the same way).
    @State private var pendingSelection: String?

    var body: some View {
        NavigationStack(path: $path) {
            let pages = model.pages
            Group {
                if pages.isEmpty {
                    EmptyState(onSearch: { searching = true }, onUseLocation: { model.setUseCurrentLocation(true) })
                } else {
                    pager(pages)
                }
            }
            .overlay(alignment: .top) {
                TopRow(pages: pages, selection: selection, onAdd: { searching = true }, onPlaces: { managing = true })
            }
            .background(Palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DayRoute.self) { route in
                DayScreen(route: route)
            }
            .sheet(isPresented: $searching) {
                SearchScreen(savedIds: model.savedIds) { place in
                    pendingSelection = model.add(place)
                    searching = false
                }
            }
            .sheet(isPresented: $managing) {
                // A place added from Places closes it and turns to the new page, as on Android.
                PlacesScreen(onAdded: { id in
                    managing = false
                    pendingSelection = id
                })
            }
            .task(id: pendingSelection) {
                // A tick after the page is added, so the pager has laid it out before turning to it.
                guard let pending = pendingSelection else { return }
                try? await Task.sleep(for: .milliseconds(50))
                if model.page(pending) != nil { withAnimation { selection = pending } }
                pendingSelection = nil
            }
            .onChange(of: pages.map(\.id), initial: true) { _, ids in
                // The page showing was removed (or never was): the first.
                if !ids.contains(selection), let first = ids.first { selection = first }
            }
        }
    }

    /// Pages side by side, snapping one at a time. (A paging TabView is a UIKit page controller, which clips the sky
    /// below the status bar and takes over the status bar's colour.)
    private func pager(_ pages: [PlaceWeather]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages) { page in
                    // Once, even if a row is tapped twice before the day slides in.
                    WeatherPage(page: page, onOpenDay: { date in
                        let route = DayRoute(pageId: page.id, date: date)
                        if path.last != route { path.append(route) }
                    })
                    .containerRelativeFrame(.horizontal)
                    .id(page.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding(get: { selection }, set: { if let id = $0 { selection = id } }))
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// The Weather tab with no places: a plain sky, then how to start (Android's EmptyState).
private struct EmptyState: View {
    let onSearch: () -> Void
    let onUseLocation: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let sky = Sky.neutral(dark: scheme == .dark)
        SkyPage(skyTop: sky[0], scrimExtra: topRowHeight) { onHeroBottom in
            Hero(colors: sky, top: topRowHeight + 4, onBottom: onHeroBottom) {
                Spacer().frame(height: 8)
                Text("Weather").font(.headline1).accessibilityAddTraits(.isHeader)
                Spacer().frame(height: 2)
                Text("Local forecasts, in °F and °C").font(.bodyMedium)
                Spacer().frame(height: 24)
            }
            VStack(spacing: 0) {
                BrandMark(size: 120).accessibilityHidden(true)
                Spacer().frame(height: 24)
                Text("Pick a place to start")
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(Palette.onSurface)
                Spacer().frame(height: 8)
                Text("Search for any city, or use your current location. You can save as many places as you like and swipe between them.")
                    .font(.bodyMedium)
                    .foregroundStyle(Palette.onSurfaceVariant)
                Spacer().frame(height: 28)
                Button(action: onSearch) {
                    Label("Search for a city", systemImage: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                Spacer().frame(height: 12)
                Button(action: onUseLocation) {
                    Label("Use my location", systemImage: "location.fill").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
            }
            .multilineTextAlignment(.center)
            .tint(Palette.primary)
            .padding(.horizontal, Metrics.pageMargin)
            .padding(.vertical, 40)
            .readableWidth()
        }
    }
}

/// Over the sky, below the status bar: where you are in the pages on the left; Refresh, Add place and Places on the
/// right, in white (every page starts with a sky, so they always stand out).
private struct TopRow: View {
    let pages: [PlaceWeather]
    let selection: String
    let onAdd: () -> Void
    let onPlaces: () -> Void

    var body: some View {
        let page = pages.first { $0.id == selection }
        HStack(spacing: 4) {
            if pages.count > 1, let index = pages.firstIndex(where: { $0.id == selection }) {
                PageIndicator(count: pages.count, current: index,
                              name: pages[index].place?.name ?? "My location")
                    .padding(.leading, 16)
                    // Only informative: a swipe that starts on it still turns the page.
                    .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
            if let page {
                Button {
                    Task { await page.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise").frame(width: topRowHeight, height: topRowHeight)
                }
                .accessibilityLabel("Refresh")
            }
            Button(action: onAdd) {
                Image(systemName: "plus").frame(width: topRowHeight, height: topRowHeight)
            }
            .accessibilityLabel("Add place")
            Button(action: onPlaces) {
                Image(systemName: "list.bullet").frame(width: topRowHeight, height: topRowHeight)
            }
            .accessibilityLabel("Places")
        }
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.trailing, 6)
        .frame(height: topRowHeight)
    }
}

/// Where you are in the pages: dots for a few, a "3 / 12" label for many. Only informative (the pages are swiped), so
/// it's one VoiceOver element naming the page.
private struct PageIndicator: View {
    let count: Int
    let current: Int
    let name: String
    private static let maxDots = 6

    var body: some View {
        Group {
            if count <= Self.maxDots {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(.white.opacity(i == current ? 1 : 0.45))
                            .frame(width: i == current ? 18 : 8, height: 8)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: current)
            } else {
                Text("\(current + 1) / \(count)")
                    .font(.labelLarge)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.18), in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count): \(name)")
    }
}

/// One place's page.
private struct WeatherPage: View {
    let page: PlaceWeather
    let onOpenDay: (LocalDate) -> Void
    @Environment(WeatherModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let forecast = page.forecast
        let night = forecast?.isNightNow ?? false
        let sky = forecast.map { Sky(code: $0.current.code).gradient(night: night, dark: scheme == .dark) }
            ?? Sky.neutral(dark: scheme == .dark)
        let scrollAnchor = page.isCurrentLocation ? LaunchOptions.scrollTo : nil
        SkyPage(skyTop: sky[0], onRefresh: { await page.refresh() }, scrollAnchor: scrollAnchor,
                ready: forecast != nil, scrimExtra: topRowHeight) { onHeroBottom in
            Hero(colors: sky, top: topRowHeight + 4, onBottom: onHeroBottom) {
                PlaceHeader(place: page.place, source: page.source)
                if let forecast {
                    HeroForecast(forecast: forecast, unit: model.unit, night: night)
                } else {
                    Spacer().frame(height: 24)
                }
            }
            Group {
                if let forecast {
                    if page.locationDenied { LocationOffCard(place: page.place) }
                    WeatherBody(forecast: forecast, unit: model.unit, night: night,
                                weekend: weekendDays(page.place?.countryCode), fetchedAt: page.fetchedAt,
                                refreshFailed: page.refreshFailed, onOpenDay: onOpenDay)
                } else if let failure = page.failure {
                    Spacer().frame(height: 24)
                    StateCard(systemImage: "exclamationmark.triangle.fill", title: "Couldn't load the weather",
                              text: failure, tint: Palette.error) {
                        Button("Try again") { Task { await page.refresh() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    LoadingSkeleton()
                }
            }
            .readableWidth()
            Spacer().frame(height: 24)
        }
    }
}

/// The place's name, and "Current location" (with the location mark) or its region and country under it.
private struct PlaceHeader: View {
    let place: Place?
    let source: PlaceWeather.Source

    var body: some View {
        VStack(spacing: 2) {
            Text(place?.name ?? "My location")
                .font(.headline1)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if place != nil {
                if source == .device {
                    Label("Current location", systemImage: "location.fill")
                        .font(.bodyMedium)
                        .labelStyle(TightLabelStyle())
                } else if let detail = place?.detail {
                    Text(detail).font(.bodyMedium)
                }
            }
        }
        .padding(.top, 8)
    }
}

/// An icon and a title with little space between, the icon a size smaller.
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Summary, big temperature, condition and today's range, all on the sky.
private struct HeroForecast: View {
    let forecast: Forecast
    let unit: TempUnit
    let night: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var bigSize: CGFloat = 96

    var body: some View {
        let cur = forecast.current
        let rain = Precip.dayRain(forecast, forecast.today.date)
        let pill = rainPill(rain, unit)
        VStack(spacing: 0) {
            Spacer().frame(height: 20)
            SummaryBlock(text: Summary.describe(forecast, unit))
            Spacer().frame(height: 16)
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(formatTemp(cur.tempC, unit))
                    .font(.system(size: min(bigSize, 140), weight: .light))
                    .kerning(-3)
                    .minimumScaleFactor(0.6)
                Text(formatTemp(cur.tempC, unit.other))
                    .font(.system(.title2, weight: .medium))
            }
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(formatTemp(cur.tempC, unit)), \(formatTemp(cur.tempC, unit.other)), \(cur.description)")
            HStack(spacing: 8) {
                WeatherIcon(code: cur.code, night: night, palette: .mono(.white), size: 30)
                Text(cur.description).font(.titleLarge)
            }
            .accessibilityHidden(true)
            Spacer().frame(height: 16)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                HeroPill(label: "High", value: formatDegrees(forecast.today.highC, unit),
                         spoken: formatBothUnits(forecast.today.highC, unit))
                HeroPill(label: "Low", value: formatDegrees(forecast.today.lowC, unit),
                         spoken: formatBothUnits(forecast.today.lowC, unit))
                HeroPill(label: rain.noun, value: pill.value, spoken: pill.spoken)
            }
        }
    }
}

/// Shown while location is off: where the forecast is for instead, and the way to turn location on.
private struct LocationOffCard: View {
    let place: Place?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.slash.fill")
                .font(.title3)
                .foregroundStyle(Palette.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Location is off").font(.titleMedium).foregroundStyle(Palette.onSurface)
                Text("Showing \(place?.name ?? "a nearby city"). Allow location to see the weather where you are.")
                    .font(.bodyMedium)
                    .foregroundStyle(Palette.onSurfaceVariant)
                Button("Allow location") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.labelLarge)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card()
        .padding(.horizontal, Metrics.pageMargin)
        .padding(.top, 20)
    }
}

/// Detail tiles, the hourly strip, the sun, This week and the 10-day list, below the sky. This week is worked out
/// for the place's current hour, and moves on with the clock.
private struct WeatherBody: View {
    let forecast: Forecast
    let unit: TempUnit
    let night: Bool
    /// The place's weekend days, for This week's best day.
    let weekend: Set<DayOfWeek>
    let fetchedAt: Date?
    let refreshFailed: Bool
    let onOpenDay: (LocalDate) -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: outlookMoment(forecast, context.date))
        }
    }

    private func content(now: LocalDateTime) -> some View {
        let cur = forecast.current
        let days = forecast.upcomingDays()
        // Every day's rain, worked out once for the outlook and the 10-day list.
        let rains = days.map { Precip.dayRain(forecast, $0.date) }
        let outlook = weekOutlook(forecast, unit, weekend: weekend, now: now, rains: rains)
        return VStack(spacing: 0) {
            Spacer().frame(height: 20)
            TileRow {
                StatTile(label: "Feels like", value: formatDegrees(cur.feelsLikeC, unit),
                         detail: formatTemp(cur.feelsLikeC, unit.other))
                StatTile(label: "Humidity", value: "\(cur.humidity)%")
                let gust = forecast.nextHours.first?.gustKmh
                StatTile(label: "Wind", value: formatWind(cur.windKmh, unit),
                         detail: gust.flatMap { $0 > cur.windKmh ? "Gusts \(formatWind($0, unit))" : nil },
                         direction: cur.windDirectionDeg, windKmh: cur.windKmh)
            }
            Spacer().frame(height: 24).id("hours")
            SectionHeading("Next \(forecast.nextHours.count) hours") {
                UpdatedLine(fetchedAt: fetchedAt, refreshFailed: refreshFailed)
            }
            Spacer().frame(height: 12)
            HourStrip(cells: HourCell.next(forecast, nightNow: night), unit: unit)
            SunAndUv(day: forecast.today)
            Spacer().frame(height: 24).id("week")
            WeekOutlookSection(outlook: outlook, today: forecast.today.date, onOpenDay: onOpenDay)
            if days.count > 1 {
                Spacer().frame(height: 24).id("days")
                SectionHeading("Next \(days.count) days") {
                    Text("Tap a day for details").font(.labelMedium).foregroundStyle(Palette.onSurfaceVariant)
                }
                Spacer().frame(height: 12)
                DailyList(days: days, rains: rains, today: forecast.today.date, unit: unit, bestDate: outlook.bestDate,
                          onOpenDay: onOpenDay)
            }
        }
    }
}

/// "Updated 8 min ago" from the app's own fetch time; past 90 minutes it turns amber and suggests pulling to refresh.
/// After a failed refresh it says so, in amber: "Couldn't refresh · updated 2 hours ago". Ticks each minute.
private struct UpdatedLine: View {
    let fetchedAt: Date?
    let refreshFailed: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            let updated = fetchedAt.map { formatUpdated($0, now: context.date) }
            let stale = fetchedAt.map { isStale($0, now: context.date) } ?? false
            let text = refreshFailed
                ? ["Couldn't refresh", updated.map { $0.prefix(1).lowercased() + $0.dropFirst() }].compactMap { $0 }.joined(separator: " · ")
                : stale ? "\(updated ?? "") · pull to refresh" : updated ?? ""
            Text(text)
                .font(.labelMedium)
                .foregroundStyle(refreshFailed || stale ? Palette.attention : Palette.onSurfaceVariant)
        }
    }
}

/// One card of an [HourStrip]. [rain] is the hour whose values fall in the card's hour (stamped at its end); without
/// it the rain lines are left out (the day page has its own rain card).
struct HourCell {
    let label: String
    let code: Int
    let night: Bool
    let tempC: Double
    let feelsLikeC: Double?
    var rain: HourForecast? = nil

    /// The Weather tab's next hours. The first card is "Now" and shows the current conditions, not the hourly
    /// forecast for this hour (which can disagree with the sky above it).
    static func next(_ forecast: Forecast, nightNow: Bool) -> [HourCell] {
        let cur = forecast.current
        return forecast.nextHours.enumerated().map { i, hour in
            i == 0
                ? HourCell(label: "Now", code: cur.code, night: nightNow, tempC: cur.tempC, feelsLikeC: cur.feelsLikeC,
                           rain: forecast.rainDuring(hour))
                : HourCell(label: formatHour(hour.time), code: hour.code, night: forecast.isNight(hour),
                           tempC: hour.tempC, feelsLikeC: hour.feelsLikeC, rain: forecast.rainDuring(hour))
        }
    }

    /// A day page's hours, 12 AM to 11 PM; today's start at the current hour, as "Now" with the current conditions.
    static func day(_ forecast: Forecast, _ date: LocalDate) -> [HourCell] {
        let isToday = date == forecast.today.date
        let cur = forecast.current
        let nowHour = cur.time.truncatedToHour
        let hours = forecast.hoursOf(date).filter { !isToday || $0.time >= nowHour }
        return hours.enumerated().map { i, hour in
            isToday && i == 0
                ? HourCell(label: "Now", code: cur.code, night: forecast.isNightNow, tempC: cur.tempC,
                           feelsLikeC: cur.feelsLikeC)
                : HourCell(label: formatHour(hour.time), code: hour.code, night: forecast.isNight(hour),
                           tempC: hour.tempC, feelsLikeC: hour.feelsLikeC)
        }
    }
}

/// A row of hour cards: label, icon, temperature in both units, then muted lines for the feels-like temperature
/// (once any hour is 3° or more off), the chance of rain (10% and up, blue from 40%) and the amount (by the shared
/// rules). The first card is highlighted when [highlightFirst] (it's "Now").
struct HourStrip: View {
    let cells: [HourCell]
    let unit: TempUnit
    var highlightFirst = true
    @State private var widths: [Int: CGFloat] = [:]

    var body: some View {
        let notable = cells.map { feelsLikeWorthShowing($0.tempC, $0.feelsLikeC, unit) != nil }
        let feelsLine = notable.contains(true)
        let chances = cells.map { $0.rain.flatMap { Precip.showHourChance($0.precipChance) ? $0.precipChance : nil } }
        let amounts = cells.map { $0.rain.flatMap { Precip.hourAmount($0, unit) } }
        let chanceLine = chances.contains { $0 != nil }
        let amountLine = amounts.contains { $0 != nil }
        let width = max(52, widths.values.max() ?? 0)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(cells.indices, id: \.self) { i in
                    let cell = cells[i]
                    VStack(spacing: 0) {
                        Text(cell.label).font(.labelMedium).foregroundStyle(Palette.onSurface)
                        Spacer().frame(height: 8)
                        WeatherIcon(code: cell.code, night: cell.night, size: 30)
                        Spacer().frame(height: 8)
                        DualTemp(c: cell.tempC, unit: unit)
                        if feelsLine {
                            Text(cell.feelsLikeC.map { "feels \(formatDegrees($0, unit))" } ?? " ")
                                .font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
                        }
                        if chanceLine || amountLine { Spacer().frame(height: 4) }
                        if chanceLine {
                            let chance = chances[i]
                            Text(chance.map { "\($0)%" } ?? " ")
                                .font(.labelSmall)
                                .foregroundStyle(chance.map(Precip.highlightChance) == true ? Palette.rain : Palette.onSurfaceVariant)
                        }
                        if amountLine {
                            Text(amounts[i] ?? " ").font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[i] = $0 }
                    .frame(minWidth: width)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .card(i == 0 && highlightFirst ? Palette.primaryContainer : Palette.surfaceContainer)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(cell, notable: notable[i], chance: chances[i]))
                }
            }
            .padding(.horizontal, Metrics.pageMargin)
        }
        .scrollIndicators(.hidden)
    }

    private func spoken(_ cell: HourCell, notable: Bool, chance: Int?) -> String {
        [
            cell.label,
            formatBothUnits(cell.tempC, unit),
            notable ? cell.feelsLikeC.map { "feels like \(formatBothUnits($0, unit))" } : nil,
            chance.map { "\($0)% chance of \(cell.rain.map(Precip.isSnowHour) == true ? "snow" : "rain")" },
            cell.rain.flatMap { Precip.hourAmountSpoken($0, unit) },
        ].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Sunrise, sunset and UV for [day]; skipped when the forecast has none of them.
struct SunAndUv: View {
    let day: DaySummary

    var body: some View {
        let daylight = day.daylight
        if daylight != .unknown || day.uvIndexMax != nil {
            TileRow {
                switch daylight {
                case .normal:
                    StatTile(label: "Sunrise", value: formatClock(day.sunrise!), compact: true)
                    StatTile(label: "Sunset", value: formatClock(day.sunset!),
                             detail: day.sunset!.date != day.date ? "next day" : nil, compact: true)
                case .polarNight:
                    StatTile(label: "Daylight", value: "None", detail: "Polar night")
                case .midnightSun:
                    StatTile(label: "Daylight", value: "24 hours", detail: "Midnight sun")
                case .unknown:
                    EmptyView()
                }
                if let uv = day.uvIndexMax {
                    StatTile(label: "UV index", value: "\(roundToInt(uv))", detail: describeUv(uv))
                }
            }
            .padding(.top, 16)
        }
    }
}

/// One row per day: name, icon with the rain chance under it, the low–high range on a bar shared by the whole list
/// (so warmer and cooler days line up), and the day's rain or snow total at the end, by the same rules as everywhere
/// else. Every column is as wide as its widest entry, so the bars line up. Days from the eighth on are drawn lighter
/// under a "less certain" rule, with their date under the weekday. This week's best day says "Best" under its name.
/// Tapping a row opens the day.
private struct DailyList: View {
    let days: [DaySummary]
    let rains: [DayRain]
    let today: LocalDate
    let unit: TempUnit
    var bestDate: LocalDate? = nil
    let onOpenDay: (LocalDate) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var line: CGFloat = 22

    var body: some View {
        let listLow = days.map(\.lowC).min() ?? 0
        let listHigh = days.map(\.highC).max() ?? 0
        let totals = rains.map { Precip.dayAmount($0, unit) }
        let totalsAtEnd = totals.contains { $0 != nil } && !typeSize.isAccessibilitySize
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(days.indices, id: \.self) { i in
                if i == lessCertainFrom { LessCertainRule() }
                let day = days[i]
                let rain = rains[i]
                let chance = !rain.dry && Precip.showDayChance(rain.chance) ? rain.chance : nil
                let lessCertain = i >= lessCertainFrom
                GridRow(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(formatDayLabel(day.date, today: today))
                            .font(.titleSmall)
                            .foregroundStyle(Palette.onSurface)
                            .frame(height: line)
                        if lessCertain {
                            Text(formatShortDate(day.date)).font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
                        }
                        if day.date == bestDate {
                            Text("Best").font(.labelSmall).foregroundStyle(Palette.success)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(day, rain, chance: chance, lessCertain: lessCertain))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens details")

                    VStack(spacing: 0) {
                        WeatherIcon(code: day.code, size: 26).frame(height: line)
                        if let chance {
                            Text("\(chance)%")
                                .font(.labelSmall)
                                .foregroundStyle(Precip.highlightChance(chance) ? Palette.rain : Palette.onSurfaceVariant)
                                .fixedSize()
                        }
                    }
                    .frame(minWidth: 30)
                    .padding(.trailing, 12)
                    .gridColumnAlignment(.center)
                    .accessibilityHidden(true)

                    DualTemp(c: day.lowC, unit: unit, font: .bodyMedium, color: Palette.onSurfaceVariant,
                             alignment: .trailing, line: line)
                        .padding(.trailing, 8)
                        .gridColumnAlignment(.trailing)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        RangeBar(low: day.lowC, high: day.highC, min: listLow, max: listHigh)
                            .frame(height: line)
                        if !totalsAtEnd, let total = totals[i] {
                            Text(rain.showsSnow ? "\(total) snow" : total)
                                .font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 8)
                    .accessibilityHidden(true)

                    DualTemp(c: day.highC, unit: unit, font: .titleSmall, alignment: .leading, line: line)
                        .gridColumnAlignment(.leading)
                        .accessibilityHidden(true)

                    if totalsAtEnd {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(totals[i] ?? "").frame(height: line)
                            if totals[i] != nil && rain.showsSnow { Text("snow") }
                        }
                        .font(.labelSmall)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 6)
                        .gridColumnAlignment(.trailing)
                        .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { onOpenDay(day.date) }
                .opacity(lessCertain ? 0.6 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .card()
        .padding(.horizontal, Metrics.pageMargin)
    }

    private func spoken(_ day: DaySummary, _ rain: DayRain, chance: Int?, lessCertain: Bool) -> String {
        var s = formatDayName(day.date, today: today)
        if lessCertain { s += ", \(formatLongDate(day.date))" }
        if day.date == bestDate { s += ", best day this week" }
        s += ", \(describeWeatherCode(day.code)), high \(formatBothUnits(day.highC, unit)), low \(formatBothUnits(day.lowC, unit))"
        if let chance { s += ", \(chance)% chance of \(rain.noun.lowercased())" }
        else if !rain.dry { s += ", a small chance of \(rain.noun.lowercased())" }
        if let amount = Precip.dayAmountSpoken(rain, unit) { s += ", \(amount)" }
        if lessCertain { s += ", less certain" }
        return s
    }
}

/// A hairline with "less certain" in it, above the days beyond a week.
private struct LessCertainRule: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Palette.outlineVariant).frame(height: 1)
            Text("less certain").font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant).fixedSize()
            Rectangle().fill(Palette.outlineVariant).frame(height: 1)
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

/// A track spanning [min]–[max] with the [low]–[high] segment filled cool to warm.
private struct RangeBar: View {
    let low: Double
    let high: Double
    let min: Double
    let max: Double

    var body: some View {
        GeometryReader { proxy in
            let span = max - min > 0 ? max - min : 1
            let start = Swift.min(Swift.max((low - min) / span, 0), 1)
            let end = Swift.min(Swift.max((high - min) / span, start), 1)
            let w = proxy.size.width
            // At least a dot, so a day with no range still shows where it sits.
            let segment = Swift.max(CGFloat(end - start) * w, 6)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceContainerHighest)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.rain, Palette.sun], startPoint: .leading, endPoint: .trailing))
                    .frame(width: segment)
                    .offset(x: Swift.min(CGFloat(start) * w, w - segment))
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Grey blocks in the shape of the loaded layout, so the page doesn't jump when data arrives.
private struct LoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 20)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Metrics.cardCorner).fill(Palette.skeleton).frame(height: 76)
                }
            }
            Spacer().frame(height: 24)
            SkeletonBar(width: 120, height: 18)
            Spacer().frame(height: 12)
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Metrics.cardCorner).fill(Palette.skeleton).frame(height: 138)
                }
            }
            Spacer().frame(height: 32)
            Text("Getting the forecast…")
                .font(.bodyMedium)
                .foregroundStyle(Palette.onSurfaceVariant)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Metrics.pageMargin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the forecast")
    }
}
