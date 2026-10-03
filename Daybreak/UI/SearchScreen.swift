import SwiftUI

/// "Add a place" (Android's SearchScreen), in a sheet: a city name, Open-Meteo's matches as you type, and a tap to
/// add one as the last page. Places already saved say so and can't be added twice. Retitled "Add a clock" for
/// Clocks, where [suggestions] (your weather places) are listed under "From your places" before you type.
struct SearchScreen: View {
    let savedIds: Set<String>
    var title = "Add a place"
    var suggestions: [Place] = []
    let onPick: (Place) -> Void
    @State private var search = PlaceSearch()
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    SearchField(text: Binding(get: { search.query }, set: { search.setQuery($0) }),
                                focused: $focused)
                        .padding(.horizontal, 16)
                    Spacer().frame(height: 8)
                    if search.loading {
                        ProgressView().progressViewStyle(.linear).tint(Palette.primary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                    }
                    let blank = search.query.trimmingCharacters(in: .whitespaces).isEmpty
                    if let error = search.error {
                        Hint(text: error)
                    } else if blank && !suggestions.isEmpty {
                        Text("From your places")
                            .font(.titleSmall)
                            .foregroundStyle(Palette.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .accessibilityAddTraits(.isHeader)
                        Results(places: suggestions, savedIds: savedIds, onPick: onPick)
                    } else if blank {
                        Hint(text: "Type a city name, for example Lisbon or Springfield.")
                    }
                    if !search.results.isEmpty {
                        Results(places: search.results, savedIds: savedIds, onPick: onPick)
                    }
                }
                .readableWidth()
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // A moment after the sheet is up: focusing while it's still sliding in doesn't always take.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            focused = true
        }
        // Android clears the search on leaving it; this also stops a request still on its way.
        .onDisappear { search.clear() }
    }
}

/// A card of places to pick from, those already saved marked and not pickable.
private struct Results: View {
    let places: [Place]
    let savedIds: Set<String>
    let onPick: (Place) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(places, id: \.id) { place in
                ResultRow(place: place, saved: savedIds.contains(place.id)) { onPick(place) }
                if place.id != places.last?.id {
                    Divider().overlay(Palette.outlineVariant).padding(.leading, 56)
                }
            }
        }
        .card()
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// The rounded field with a magnifier, "City name" and a clear button once there's text.
private struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.onSurfaceVariant)
            TextField("City name", text: $text)
                .font(.bodyLarge)
                .foregroundStyle(Palette.onSurface)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.onSurfaceVariant)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Palette.surfaceContainerHigh, in: Capsule())
    }
}

/// A match: the pin, the name over its region and country, and "Saved" once it's one of your places.
private struct ResultRow: View {
    let place: Place
    let saved: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 16) {
                Image(systemName: "mappin")
                    .font(.title3)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.titleMedium).foregroundStyle(Palette.onSurface)
                    if let detail = place.detail {
                        Text(detail).font(.bodyMedium).foregroundStyle(Palette.onSurfaceVariant)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if saved {
                    Label("Saved", systemImage: "checkmark")
                        .labelStyle(TightLabelStyle())
                        .font(.labelMedium)
                        .foregroundStyle(Palette.onSecondaryContainer)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Palette.secondaryContainer, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(saved)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([place.name, place.detail, saved ? "saved" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

private struct Hint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.bodyMedium)
            .foregroundStyle(Palette.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
    }
}
