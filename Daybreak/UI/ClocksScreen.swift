import SwiftUI

/// Clocks (Android's ClocksScreen): your phone's time as the page's headline, then your saved clocks measured against
/// it ("Tomorrow · +10 h"), ticking each minute. Add a clock searches places, with your weather places offered first;
/// Edit reorders and deletes them (a swipe deletes too).
struct ClocksScreen: View {
    @Environment(ClocksModel.self) private var model
    @Environment(WeatherModel.self) private var weather
    @State private var adding = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                list(now: context.date)
            }
            .environment(\.editMode, $editMode)
            // Removing the last clock ends editing; the Edit button goes with the list.
            .onChange(of: model.clocks.isEmpty) { _, empty in if empty { editMode = .inactive } }
            .scrollContentBackground(.hidden)
            // Short lines on an iPad, like the other tabs.
            .frame(maxWidth: Metrics.readableWidth)
            .frame(maxWidth: .infinity)
            .background(Palette.background)
            .navigationTitle("Clocks")
            .toolbar {
                if !model.clocks.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        // Drives the list's own edit mode (a toolbar EditButton doesn't see it).
                        Button(editMode.isEditing ? "Done" : "Edit") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a clock")
                }
            }
            .sheet(isPresented: $adding) {
                SearchScreen(savedIds: model.ids, title: "Add a clock",
                             suggestions: weather.saved.compactMap(\.place)) { place in
                    // A place without a time zone this phone knows can't be a clock: stay on the search.
                    if model.add(place) { adding = false }
                }
            }
        }
    }

    private func list(now: Date) -> some View {
        let here = TimeZone.current
        return List {
            Section {
                if model.clocks.isEmpty {
                    NoClocks { adding = true }
                        .listRowBackground(Palette.surfaceContainer)
                } else {
                    ForEach(Array(model.clocks.enumerated()), id: \.element.id) { i, clock in
                        ClockRow(clock: clock, now: now, here: here)
                            .accessibilityActions {
                                if i > 0 { Button("Move \(clock.name) up") { model.move(from: i, to: i - 1) } }
                                if i < model.clocks.count - 1 {
                                    Button("Move \(clock.name) down") { model.move(from: i, to: i + 1) }
                                }
                                Button("Remove \(clock.name)") { model.remove(clock.id) }
                            }
                            .listRowBackground(Palette.surfaceContainer)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 48 }
                    }
                    .onMove { from, to in
                        guard let source = from.first else { return }
                        model.move(from: source, to: SavedPlaces.finalIndex(from: source, listDestination: to))
                    }
                    .onDelete { rows in
                        let ids = rows.filter { model.clocks.indices.contains($0) }.map { model.clocks[$0].id }
                        ids.forEach(model.remove)
                    }
                }
            } header: {
                // The phone's own time heads the list, lined up with the title and the card's edge (a header is
                // inset to the card's contents). A header rather than a row: a row clipped the first letter's stem.
                DeviceClock(now: now, here: here)
                    .textCase(nil)
                    .padding(.leading, -16)
                    .padding(.bottom, 12)
            }
        }
    }
}

/// The phone's own time, large, over "Los Angeles · your phone · UTC−7".
private struct DeviceClock: View {
    let now: Date
    let here: TimeZone
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 45

    var body: some View {
        let seconds = here.secondsFromGMT(for: now)
        let time = formatClock(LocalDateTime.from(now, utcOffsetSeconds: seconds))
        VStack(alignment: .leading, spacing: 2) {
            Text(time)
                .font(.system(size: min(size, 72)))
                .foregroundStyle(Palette.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // No-break spaces around the dots, so a wrapped line never ends on one.
            Text("\(cityOf(here))\u{00A0}·\u{00A0}your phone\u{00A0}·\u{00A0}\(formatUtc(seconds))")
                .font(.bodyMedium)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(time) in \(cityOf(here)), your phone, \(spokenUtc(seconds))")
    }
}

/// "No clocks yet", what they're for, and "Add a clock".
private struct NoClocks: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("No clocks yet").font(.titleMedium).foregroundStyle(Palette.onSurface)
            Text("Add the places you call, work with or miss.")
                .font(.bodyMedium)
                .foregroundStyle(Palette.onSurfaceVariant)
            Button("Add a clock", action: onAdd)
                .buttonStyle(.bordered)
                .tint(Palette.primary)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

/// One clock: the day or night disc, the name over "Tomorrow · +10 h", and the time over its UTC offset. When the
/// time would squeeze the name (large text) it moves to its own line under the name. A clock whose zone this phone
/// doesn't know still shows, so it can be removed.
private struct ClockRow: View {
    let clock: Clock
    let now: Date
    let here: TimeZone

    var body: some View {
        let r = clock.zone.map { readClock(now, here: here, there: $0) }
        let time = r.map { formatClock($0.time) }
        // The offset's number and unit stay together, as Android's ("+5½ h", "+15 min").
        let detail = r.map {
            "\($0.day) · " + $0.offset.replacingOccurrences(of: " h", with: "\u{00A0}h")
                .replacingOccurrences(of: " min", with: "\u{00A0}min")
        } ?? "This phone doesn't know its time zone"
        let spoken = r.map {
            "\(clock.name), \(time ?? ""), \($0.day.lowercased()), \($0.spoken), \(spokenUtc($0.utcSeconds)), \($0.night ? "night" : "day")"
        } ?? "\(clock.name), time zone unknown"
        HStack(spacing: 12) {
            if let r { DayNightDisc(night: r.night) } else { UnknownDisc() }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    nameAndDetail(detail)
                    Spacer(minLength: 0)
                    if let r, let time {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(time).font(.system(.title2)).foregroundStyle(Palette.onSurface)
                            Text(r.utc).font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
                        }
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    nameAndDetail(detail)
                    if let r, let time {
                        // The time stays on one line; its UTC offset moves under it when they don't fit side by side.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                Text(keepUnitsTogether(time)).font(.titleLarge).lineLimit(1)
                                Text(r.utc).font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(keepUnitsTogether(time)).font(.titleLarge).lineLimit(1)
                                Text(r.utc).font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
                            }
                        }
                        .foregroundStyle(Palette.onSurface)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func nameAndDetail(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(clock.name).font(.titleMedium).foregroundStyle(Palette.onSurface).lineLimit(1)
            Text(detail).font(.bodySmall).foregroundStyle(Palette.onSurfaceVariant)
        }
    }
}

/// A sun on amber for day, a moon on blue for night, like the other cards' glyph discs.
private struct DayNightDisc: View {
    let night: Bool

    var body: some View {
        let color = night ? Palette.primary : Palette.sun
        WeatherIcon(code: 0, night: night, palette: .mono(color), size: 22)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct UnknownDisc: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 17))
            .foregroundStyle(Palette.error)
            .frame(width: 36, height: 36)
            .background(Palette.error.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}
