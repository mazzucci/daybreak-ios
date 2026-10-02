import Foundation
import Testing
@testable import Daybreak

/// Settings: °F first and On this day on by default, and both kept.
@MainActor
struct SettingsTests {
    private func defaults() -> UserDefaults {
        let name = "SettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("°F first and On this day on until changed")
    func defaultsFirst() {
        let settings = SettingsStore(defaults: defaults())
        #expect(settings.unit == .f)
        #expect(settings.onThisDayEnabled)
    }

    @Test("the settings are kept")
    func kept() {
        let d = defaults()
        SettingsStore(defaults: d).unit = .c
        SettingsStore(defaults: d).onThisDayEnabled = false
        #expect(SettingsStore(defaults: d).unit == .c)
        #expect(!SettingsStore(defaults: d).onThisDayEnabled)
    }

    @Test("an unknown stored unit falls back to °F")
    func unknownUnit() {
        let d = defaults()
        d.set("K", forKey: SettingsStore.unitKey)
        #expect(SettingsStore(defaults: d).unit == .f)
    }

    @Test("the unit chosen on the weather model is the one the next launch starts with")
    func unitAcrossLaunches() {
        let d = defaults()
        let places = SavedPlacesStore(defaults: d)
        let model = WeatherModel(live: false, store: places, settings: SettingsStore(defaults: d))
        #expect(model.unit == .f)
        model.unit = .c
        #expect(WeatherModel(live: false, store: places, settings: SettingsStore(defaults: d)).unit == .c)
    }
}
