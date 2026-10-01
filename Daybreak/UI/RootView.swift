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
    @Environment(StatusBarStyle.self) private var statusBar

    var body: some View {
        TabView(selection: $selection) {
            HomeScreen(openWeather: { selection = .weather })
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
            ComingSoonScreen(
                title: "Clocks", systemImage: "clock",
                text: "The places you call or work with: each one's time, how far ahead or behind you it is, and a converter for any moment."
            )
            .tabItem { Label("Clocks", systemImage: "clock") }
            .tag(AppTab.clocks)
            ComingSoonScreen(
                title: "Settings", systemImage: "gearshape",
                text: "°F or °C first, which cards show on Home, your places, and your dates.",
                footer: "Daybreak \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
            )
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .tint(Palette.primary)
        .environment(weather)
        .environment(onThisDay)
        .onAppear { statusBar.light = selection.hasSky }
        .onChange(of: selection) { _, tab in statusBar.light = tab.hasSky }
        .task {
            async let w: Void = weather.refresh()
            async let h: Void = onThisDay.load()
            _ = await (w, h)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                // A new day's history, and a forecast that's more than a quarter of an hour old.
                async let w: Void = weather.refreshIfOlder(than: 15 * 60)
                async let h: Void = onThisDay.load()
                _ = await (w, h)
            }
        }
    }
}

/// A tab that isn't built yet: what it will do, in a sentence.
private struct ComingSoonScreen: View {
    let title: String
    let systemImage: String
    let text: String
    var footer: String? = nil

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Coming soon", systemImage: systemImage)
            } description: {
                Text(text)
            }
            .safeAreaInset(edge: .bottom) {
                if let footer {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .padding(.bottom, 12)
                }
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

    /// "hours" or "days": the Weather section to scroll to once the forecast is in.
    static var scrollTo: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "scrollTo")
        #else
        nil
        #endif
    }
}
