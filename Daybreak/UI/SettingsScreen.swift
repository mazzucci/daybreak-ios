import SwiftUI

/// The Settings tab (Android's SettingsScreen, as far as the iOS app goes so far): which unit is shown large, the
/// places, and which cards Home shows, then the app's name and version. More sections arrive with their features.
struct SettingsScreen: View {
    @Environment(WeatherModel.self) private var weather
    @AppStorage(SettingsStore.onThisDayKey) private var onThisDay = true
    @State private var managingPlaces = false

    var body: some View {
        @Bindable var weather = weather
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Text("Temperature").font(.titleMedium).foregroundStyle(Palette.onSurface)
                        Spacer(minLength: 0)
                        // The chosen unit is the big number; the other one is shown small next to it.
                        Picker("Temperature", selection: $weather.unit) {
                            Text("°F first").tag(TempUnit.f)
                            Text("°C first").tag(TempUnit.c)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Palette.surfaceContainer)

                Section {
                    Button {
                        managingPlaces = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Places").font(.titleMedium).foregroundStyle(Palette.onSurface)
                                Text(placesSummary).font(.bodySmall).foregroundStyle(Palette.onSurfaceVariant)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.outline)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                } header: {
                    SectionTitle("Weather")
                }
                .listRowBackground(Palette.surfaceContainer)

                Section {
                    SettingsSwitch(
                        title: "On this day on Home",
                        text: "A cheerful moment from today's date in history, with a picture, fetched once a day. Wikipedia and its image servers see your IP address and the date.",
                        isOn: $onThisDay
                    )
                } header: {
                    SectionTitle("Fun")
                } footer: {
                    Text("Daybreak \(Self.version)")
                        .font(.footnote)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                .listRowBackground(Palette.surfaceContainer)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Settings")
            .sheet(isPresented: $managingPlaces) {
                PlacesScreen(onAdded: { _ in managingPlaces = false })
            }
        }
    }

    /// "Current location, Lisbon and Porto", or how many past three.
    private var placesSummary: String {
        var names = weather.useCurrentLocation ? ["Current location"] : []
        names += weather.saved.compactMap(\.place?.name)
        switch names.count {
        case 0: return "None yet"
        case 1: return names[0]
        case 2, 3: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        default: return "\(names.count) places"
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

/// A section's title, as Android's: small, in the primary colour, in sentence case.
private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.titleSmall).foregroundStyle(Palette.primary).textCase(nil)
    }
}

/// A switch with its title and a line on what it does; VoiceOver hears the title, then the line as a hint.
private struct SettingsSwitch: View {
    let title: String
    let text: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.titleMedium).foregroundStyle(Palette.onSurface)
                Text(text).font(.bodySmall).foregroundStyle(Palette.onSurfaceVariant)
            }
        }
        .tint(Palette.primary)
        .padding(.vertical, 4)
        .accessibilityLabel(title)
        .accessibilityHint(text)
    }
}
