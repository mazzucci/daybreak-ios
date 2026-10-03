import SwiftUI
import UIKit

/// The tabs, in Android's order: Home, Weather, Habits, Clocks, Settings.
enum AppTab: String, Hashable {
    case home, weather, habits, clocks, settings

    /// Home and Weather start with a sky, so the status bar's text is light there.
    var hasSky: Bool { self == .home || self == .weather }
}

struct RootView: View {
    @State private var selection: AppTab = LaunchOptions.initialTab ?? .home
    @State private var weather = WeatherModel()
    @State private var onThisDay = OnThisDayModel()
    @State private var clocks = ClocksModel()
    @Environment(StatusBarStyle.self) private var statusBar
    @AppStorage(SettingsStore.onThisDayKey) private var onThisDayEnabled = true

    var body: some View {
        TabView(selection: $selection) {
            HomeScreen(openWeather: { selection = .weather }, openSettings: { selection = .settings })
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            WeatherScreen()
                .tabItem { Label("Weather", systemImage: "cloud.sun") }
                .tag(AppTab.weather)
            ComingSoonScreen(
                title: "Habits", systemImage: "checkmark.square",
                text: "The habits you're building or breaking, each with a goal: streaks, points and a 12-week map, and today's on Home to log with a tap."
            )
            .tabItem { Label("Habits", systemImage: "checkmark.square") }
            .tag(AppTab.habits)
            ClocksScreen()
            .tabItem { Label("Clocks", systemImage: "clock") }
            .tag(AppTab.clocks)
            SettingsScreen()
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .tint(Palette.primary)
        .environment(weather)
        .environment(onThisDay)
        .environment(clocks)
        .onAppear { statusBar.light = selection.hasSky }
        .onChange(of: selection) { _, tab in statusBar.light = tab.hasSky }
        .task {
            async let w: Void = weather.refreshAll()
            async let h: Void = loadOnThisDay()
            _ = await (w, h)
        }
        // Turned on in Settings: fetch today's history now, so it's there on Home.
        .onChange(of: onThisDayEnabled) { _, on in
            if on { Task { await onThisDay.load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                // A new day's history, and a forecast that's more than a quarter of an hour old.
                async let w: Void = weather.refreshAll(olderThan: 15 * 60)
                async let h: Void = loadOnThisDay()
                _ = await (w, h)
            }
        }
    }

    /// Today's history, unless On this day is off in Settings (then Wikipedia isn't asked at all).
    private func loadOnThisDay() async {
        if SettingsStore().onThisDayEnabled { await onThisDay.load() }
    }
}

/// A tab that isn't built yet: what it will do, in a sentence.
private struct ComingSoonScreen: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Coming soon", systemImage: systemImage)
            } description: {
                Text(text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
            .navigationTitle(title)
        }
    }
}

/// Launch arguments for taking screenshots without tapping (`-initialTab weather -scrollTo days`). Debug builds only.
enum LaunchOptions {
    static var initialTab: AppTab? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "initialTab").flatMap(AppTab.init(rawValue:))
        #else
        nil
        #endif
    }

    /// Days from today (0 is today): the day page to open over the Weather tab at launch.
    static var openDay: LocalDate? {
        #if DEBUG
        UserDefaults.standard.object(forKey: "openDay") == nil
            ? nil : LocalDate.today().plusDays(UserDefaults.standard.integer(forKey: "openDay"))
        #else
        nil
        #endif
    }

    /// "hours" or "days": the Weather section to scroll to once the forecast is in.
    static var scrollTo: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "scrollTo")
        #else
        nil
        #endif
    }
}
