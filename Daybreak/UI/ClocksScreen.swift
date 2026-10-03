import SwiftUI

/// Clocks (Android's ClocksScreen): your phone's time as the page's headline, then your saved clocks measured against
/// it ("Tomorrow · +10 h"), ticking each minute, and a converter that shows one moment in every clock at once. Add a
/// clock searches places, with your weather places offered first; Edit reorders and deletes them (a swipe deletes
/// too).
struct ClocksScreen: View {
    @Environment(ClocksModel.self) private var model
    @Environment(WeatherModel.self) private var weather
    @State private var adding = false
    @State private var editMode: EditMode = .inactive
    /// The converter's picks: minutes past midnight (nil for now), today or tomorrow, and the clock the time is in
    /// (nil for your phone).
    @State private var minutes: Int?
    @State private var dayOffset = 0
    @State private var fromId: String?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                list(now: context.date)
            }
            .environment(\.editMode, $editMode)
            // Removing the last clock ends editing; the Edit button goes with the list.
            .onChange(of: model.clocks.isEmpty) { _, empty in if empty { editMode = .inactive } }
            // A clock removed while the time is in it: back to your phone and to now, since the picked time was that
            // clock's. With no clocks left the converter goes, and its picks with it, as on Android.
            .onChange(of: model.clocks.map(\.id)) { _, ids in
                if ids.isEmpty {
                    (minutes, dayOffset, fromId) = (nil, 0, nil)
                } else if let id = fromId, !ids.contains(id) {
                    (minutes, fromId) = (nil, nil)
                }
            }
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
            // Nothing to convert to until there's a clock; the empty card already says how to add one.
            if !model.clocks.isEmpty {
                let conversion = convert(clocks: model.clocks, now: now, here: here, fromId: fromId, minutes: minutes,
                                         dayOffset: dayOffset)
                Section {
                    Converter(conversion: conversion, clocks: model.clocks, here: here, minutes: $minutes,
                              dayOffset: $dayOffset, fromId: $fromId)
                        .listRowBackground(Palette.surfaceContainer)
                } header: {
                    Text("Convert")
                        .font(.titleMedium)
                        .foregroundStyle(Palette.onSurface)
                        .textCase(nil)
                        .padding(.leading, -16)
                        .accessibilityAddTraits(.isHeader)
                }
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

/// The converter (Android's Converter): pick a time, a day and where that time is (your phone or any clock), and
/// every other clock shows the same moment. Defaults to now, today, your phone. A clock that's removed while it's
/// picked goes back to your phone and to now, since the picked time was that clock's.
private struct Converter: View {
    let conversion: Conversion
    let clocks: [Clock]
    let here: TimeZone
    @Binding var minutes: Int?
    @Binding var dayOffset: Int
    @Binding var fromId: String?

    var body: some View {
        let fromZone = conversion.fromZone
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 8, lineSpacing: 8, leading: true) {
                // The system's time picker, in the zone the time is in.
                DatePicker("Time", selection: timeBinding(fromZone), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.timeZone, fromZone)
                    // The picker speaks its own value.
                    .accessibilityLabel("Time")
                if minutes != nil {
                    // Back to the ticking time.
                    Button("Now") { minutes = nil }
                        .buttonStyle(.bordered)
                        .tint(Palette.primary)
                }
                Menu {
                    Picker("Day", selection: $dayOffset) {
                        Text("Today").tag(0)
                        Text("Tomorrow").tag(1)
                    }
                } label: {
                    Chip(text: conversion.dayLabel)
                }
                .accessibilityLabel("Day, \(conversion.dayLabel)")
                Menu {
                    Picker("Where the time is", selection: $fromId) {
                        Text("\(cityOf(here)) (your phone)").tag(String?.none)
                        ForEach(clocks.filter { $0.zone != nil }) { clock in
                            Text(clock.name).tag(String?.some(clock.id))
                        }
                    }
                } label: {
                    Chip(text: "in \(conversion.fromName)")
                }
                .accessibilityLabel("Where the time is, \(conversion.fromName)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(conversion.heading)
                .font(.bodySmall)
                .foregroundStyle(Palette.onSurfaceVariant)
                .padding(.top, 12)
            ForEach(conversion.rows) { row in
                HStack(spacing: 12) {
                    DayNightDisc(night: row.night)
                    // The name takes what the time leaves; at large sizes the time moves under it.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            Text(row.name).font(.titleMedium).foregroundStyle(Palette.onSurface).lineLimit(1)
                                .layoutPriority(1)
                            Spacer(minLength: 0)
                            timeAndNote(row, alignment: .trailing).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.titleMedium).foregroundStyle(Palette.onSurface)
                            timeAndNote(row, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.spoken)
            }
        }
        .padding(.vertical, 8)
    }

    private func timeAndNote(_ row: ConvertedRow, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(keepUnitsTogether(row.timeLabel)).font(.titleMedium).foregroundStyle(Palette.onSurface).lineLimit(1)
            if let note = row.note {
                Text(note).font(.labelSmall).foregroundStyle(Palette.onSurfaceVariant)
            }
        }
    }

    /// The picked time as a moment the picker shows in [zone]; picking sets the minutes past midnight.
    private func timeBinding(_ zone: TimeZone) -> Binding<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let m = conversion.moment
        let date = calendar.date(from: DateComponents(year: m.date.year, month: m.date.month, day: m.date.day,
                                                      hour: m.hour, minute: m.minute)) ?? Date()
        return Binding(
            get: { date },
            set: { picked in
                let parts = calendar.dateComponents([.hour, .minute], from: picked)
                minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// A rounded choice with a drop-down mark, like Android's assist chips.
private struct Chip: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.labelLarge)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Palette.onSurface)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.surfaceContainerHigh, in: Capsule())
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
