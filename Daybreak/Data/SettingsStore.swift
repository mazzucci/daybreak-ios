import Foundation

/// The app's settings that aren't about places (Android's SettingsRepository): which unit is shown large, and which
/// cards Home shows. Kept in UserDefaults; views that only show or flip a switch read the same keys with @AppStorage.
struct SettingsStore {
    static let unitKey = "primary_unit"
    static let onThisDayKey = "on_this_day_enabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// °F first unless °C was chosen, as Android's default.
    var unit: TempUnit {
        get { defaults.string(forKey: Self.unitKey).flatMap(TempUnit.init(rawValue:)) ?? .f }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.unitKey) }
    }

    /// On this day on Home: on by default.
    var onThisDayEnabled: Bool {
        get { defaults.object(forKey: Self.onThisDayKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.onThisDayKey) }
    }
}
