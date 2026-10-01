import SwiftUI

/// Home: the day at a glance. A greeting on the sky of where you are, the weather glance (which opens the Weather
/// tab), then On this day. Pull to refresh refreshes both.
struct HomeScreen: View {
    @Environment(WeatherModel.self) private var weather
    @Environment(OnThisDayModel.self) private var onThisDay
    @Environment(\.colorScheme) private var scheme
    let openWeather: () -> Void

    var body: some View {
        let forecast = weather.forecast
        let sky = forecast.map { Sky(code: $0.current.code).gradient(night: $0.isNightNow, dark: scheme == .dark) }
            ?? Sky.neutral(dark: scheme == .dark)
        SkyPage(skyTop: sky[0], onRefresh: refresh) { onHeroBottom in
            Hero(colors: sky, leading: true, top: 16, onBottom: onHeroBottom) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dateLine(context.date))
                            .font(.bodyMedium)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(greeting(hour: Calendar.current.component(.hour, from: context.date)))
                            .font(.headline1)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 16)
                WeatherGlance(openWeather: openWeather)
                    .padding(.horizontal, Metrics.pageMargin)
                if let day = onThisDay.day, day.date == LocalDate.today(), let pick = day.current {
                    Spacer().frame(height: 24)
                    SectionHeading("On this day")
                    Spacer().frame(height: 12)
                    OnThisDayCard(day: day, pick: pick, onAnother: day.picks.count > 1 ? {
                        withAnimation(.easeOut(duration: 0.25)) { onThisDay.another() }
                    } : nil)
                    .padding(.horizontal, Metrics.pageMargin)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Spacer().frame(height: 24)
            }
            .readableWidth()
            .animation(.easeOut(duration: 0.3), value: onThisDay.day?.date)
        }
    }

    private func refresh() async {
        async let w: Void = weather.refresh()
        async let h: Void = onThisDay.load(force: true)
        _ = await (w, h)
    }

    /// "Wednesday, October 1" in the phone's own language and order.
    static func dateLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter.string(from: date)
    }
}

/// The weather where you are in one card: icon, place, "Partly cloudy · ↑74° ↓56° · Rain 60%", and the temperature in
/// both units. Tapping opens the Weather tab. While there's no forecast the same frame says why.
private struct WeatherGlance: View {
    @Environment(WeatherModel.self) private var model
    let openWeather: () -> Void

    var body: some View {
        if let f = model.forecast {
            loaded(f)
        } else if let failure = model.failure {
            message(icon: "exclamationmark.triangle.fill", tint: Palette.error, title: "Couldn't load the weather", text: failure) {
                Button("Try again") { Task { await model.refresh() } }
            }
        } else {
            loading
        }
    }

    private func loaded(_ f: Forecast) -> some View {
        let unit = model.unit
        let name = model.place?.name ?? "My location"
        let today = f.today
        let todayRain = Precip.dayRain(f, today.date)
        let rain = !todayRain.dry && Precip.showDayChance(todayRain.chance) ? todayRain.chance : nil
        let condition = describeWeatherCode(f.current.code)
        let range = "↑\(formatDegrees(today.highC, unit)) ↓\(formatDegrees(today.lowC, unit))"
        // Don't say rain twice: when the sky already is rain (or snow, or storms), the chance stands alone.
        let chance = rain.map { dryConditions.contains(condition) ? "\(todayRain.noun) \($0)%" : "\($0)% chance" }
        let spoken = [
            name,
            formatBothUnits(f.current.tempC, unit),
            condition.lowercased(),
            "high \(formatDegrees(today.highC, unit)), low \(formatDegrees(today.lowC, unit))",
            rain.map { "\($0) percent chance of \(todayRain.noun.lowercased())" },
        ].compactMap { $0 }.joined(separator: ", ") + ". Opens Weather."
        return Button(action: openWeather) {
            HStack(spacing: 12) {
                WeatherIcon(code: f.current.code, night: f.isNightNow, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        if model.placeSource == .device {
                            Image(systemName: "location.fill").font(.caption2)
                        }
                        Text(name).font(.titleMedium).lineLimit(1)
                    }
                    .foregroundStyle(Palette.onSurface)
                    // One line when it fits; otherwise the chance moves to a second line whole.
                    ViewThatFits(in: .horizontal) {
                        Text(([condition, range] + [chance].compactMap { $0 }).joined(separator: " · ")).lineLimit(1)
                        Text("\(condition) · \(range)" + (chance.map { "\n\($0)" } ?? "")).lineLimit(2)
                    }
                    .font(.bodyMedium)
                    .foregroundStyle(Palette.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DualTemp(c: f.current.tempC, unit: unit, font: .system(.title, weight: .semibold), alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.outline)
            }
            .padding(16)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
    }

    /// Bars in the shape of the loaded card, so nothing jumps when it lands.
    private var loading: some View {
        HStack(spacing: 12) {
            Circle().fill(Palette.skeleton).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(width: 120, height: 16)
                SkeletonBar(width: 200, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoundedRectangle(cornerRadius: 12).fill(Palette.skeleton).frame(width: 44, height: 28)
        }
        .padding(16)
        .frame(minHeight: 72)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the weather")
    }

    private func message<Actions: View>(icon: String, tint: Color, title: String, text: String,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.titleMedium).foregroundStyle(Palette.onSurface)
                Text(text).font(.bodyMedium).foregroundStyle(Palette.onSurfaceVariant)
                actions().font(.labelLarge).padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .card()
    }
}

/// Conditions that aren't precipitation, so the rain chance needs its word.
private let dryConditions: Set<String> = ["Clear sky", "Mainly clear", "Partly cloudy", "Overcast", "Fog", "Unknown"]
