import SwiftUI

/// "Places" (Android's PlacesScreen), in a sheet: the current location on or off, then the saved places in the order
/// they're swiped through, and Add place. Edit shows the list's drag handles and delete buttons (a swipe deletes
/// too). Android's up and down buttons are VoiceOver actions here.
struct PlacesScreen: View {
    @Environment(WeatherModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var searching = false

    var body: some View {
        let saved = model.saved.compactMap(\.place)
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { model.useCurrentLocation }, set: { model.setUseCurrentLocation($0) })) {
                        HStack(spacing: 16) {
                            Image(systemName: "location.fill").foregroundStyle(Palette.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current location").font(.titleMedium).foregroundStyle(Palette.onSurface)
                                Text("Show the weather where you are as the first page")
                                    .font(.bodyMedium)
                                    .foregroundStyle(Palette.onSurfaceVariant)
                            }
                        }
                    }
                    .tint(Palette.primary)
                    .accessibilityLabel("Use current location")
                }
                .listRowBackground(Palette.surfaceContainer)

                Section {
                    if saved.isEmpty {
                        Text("Nothing saved yet. Add a city and it appears here, in the order you swipe through them.")
                            .font(.bodyMedium)
                            .foregroundStyle(Palette.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(Array(saved.enumerated()), id: \.element.id) { i, place in
                            PlaceRow(place: place)
                                .accessibilityAction(named: "Move \(place.name) up") { model.move(from: i, to: i - 1) }
                                .accessibilityAction(named: "Move \(place.name) down") { model.move(from: i, to: i + 1) }
                                .listRowBackground(Palette.surfaceContainer)
                        }
                        .onMove { from, to in
                            guard let source = from.first else { return }
                            model.move(from: source, to: SavedPlaces.finalIndex(from: source, listDestination: to))
                        }
                        .onDelete { rows in
                            for i in rows.sorted(by: >) where saved.indices.contains(i) { model.remove(saved[i].id) }
                        }
                    }
                } header: {
                    Text("Saved places")
                        .font(.titleSmall)
                        .foregroundStyle(Palette.primary)
                        .textCase(nil)
                }

                Section {
                    Button {
                        searching = true
                    } label: {
                        Label("Add place", systemImage: "plus")
                            .font(.labelLarge)
                    }
                    .listRowBackground(Palette.surfaceContainer)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !saved.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $searching) {
                SearchScreen(savedIds: model.savedIds) { place in
                    model.add(place)
                    searching = false
                }
            }
        }
    }
}

/// A saved place: its name over its region and country.
private struct PlaceRow: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(place.name).font(.titleMedium).foregroundStyle(Palette.onSurface)
            if let detail = place.detail {
                Text(detail).font(.bodyMedium).foregroundStyle(Palette.onSurfaceVariant)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
