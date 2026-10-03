import SwiftUI

/// "Places" (Android's PlacesScreen), in a sheet: the current location on or off, then the saved places in the order
/// they're swiped through, and Add place. Edit shows the list's drag handles and delete buttons (a swipe deletes
/// too). Android's up and down buttons are VoiceOver actions here.
struct PlacesScreen: View {
    /// A place was added: its page id.
    let onAdded: (String) -> Void
    @Environment(WeatherModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var searching = false
    @State private var editMode: EditMode = .inactive

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
                    .accessibilityHint("Show the weather where you are as the first page")
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
                                .accessibilityActions {
                                    if i > 0 {
                                        Button("Move \(place.name) up") { model.move(from: i, to: i - 1) }
                                    }
                                    if i < saved.count - 1 {
                                        Button("Move \(place.name) down") { model.move(from: i, to: i + 1) }
                                    }
                                }
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
            .environment(\.editMode, $editMode)
            // Nothing left to edit: out of editing, so the next place doesn't arrive with handles.
            .onChange(of: saved.isEmpty) { _, empty in if empty { editMode = .inactive } }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !saved.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        // Drives the list's own edit mode (a toolbar EditButton doesn't see it).
                        Button(editMode.isEditing ? "Done" : "Edit") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $searching) {
                SearchScreen(savedIds: model.savedIds) { place in
                    searching = false
                    onAdded(model.add(place))
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
