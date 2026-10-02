# Daybreak for iOS: notes for coding agents

A native SwiftUI port of the Android app **mazzucci/Daybreak** (Kotlin, Jetpack Compose). The Android repo is the
behaviour reference: match its behaviour, copy (wording) and look for whatever you build, and read its
`docs/design/shell.md` and the matching Kotlin (`app/src/main/java/app/daybreak/...`) before porting a feature. The
two apps share no code. See README.md for what's built so far and the known gaps.

## Prerequisites (on the Mac)

- Xcode 26.5 or later, selected (`xcode-select -p` shows `/Applications/Xcode.app/...`), and the iOS 26.5 simulator
  runtime with an "iPhone 17" and an "iPad Pro 13-inch (M5)" (`xcrun simctl list devices available`).
- Nothing else: no XcodeGen, no Homebrew, no packages. The `.xcodeproj` is committed and hand-written.

## Commands (from the repo root, fresh clone)

```sh
# Build for the iPhone 17 simulator (products in ./build, which is git-ignored)
xcodebuild -project Daybreak.xcodeproj -scheme Daybreak \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build build

# Unit tests (Swift Testing), on the iPhone 17 simulator
xcodebuild test -project Daybreak.xcodeproj -scheme Daybreak \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build

# Build if needed, open Simulator, boot, install, set the location to Weston, MA (42.36,-71.29) and launch
scripts/run-in-simulator.sh            # iPhone 17
scripts/run-in-simulator.sh --ipad     # iPad Pro 13-inch (M5)
scripts/run-in-simulator.sh build/Build/Products/Debug-iphonesimulator/Daybreak.app   # a prebuilt app
```

Over SSH (no GUI login session) Simulator.app can't open its window; the script says so and carries on, and the
simulator runs headless, which is all screenshots need.

The same steps by hand:

```sh
xcrun simctl boot "iPhone 17"; xcrun simctl bootstatus "iPhone 17" -b
xcrun simctl install "iPhone 17" build/Build/Products/Debug-iphonesimulator/Daybreak.app
xcrun simctl privacy "iPhone 17" grant location app.daybreak.ios   # skips the permission prompt
xcrun simctl location "iPhone 17" set 42.36,-71.29
xcrun simctl launch "iPhone 17" app.daybreak.ios
```

## Screenshots

```sh
mkdir -p ~/shots
xcrun simctl io "iPhone 17" screenshot ~/shots/home.png
xcrun simctl ui "iPhone 17" appearance dark      # or light
```

Debug builds read launch arguments so a screen can be shown without tapping:

- `-initialTab weather` (home, weather, habits, clocks, settings)
- `-scrollTo hours` or `-scrollTo days` (Weather, once the forecast is in)
- `-onThisDayIndex 2` (start On this day on another of the day's picks)
- `-openDay 1` (open a day's page over the Weather tab, in days from today: 0 is today)

```sh
xcrun simctl launch "iPhone 17" app.daybreak.ios -initialTab weather -scrollTo days
sleep 8 && xcrun simctl io "iPhone 17" screenshot ~/shots/weather-days.png
```

Look at every screenshot: check nothing is clipped, wrapped badly or misaligned, in light and dark and on the iPad.

## Layout

```
Daybreak.xcodeproj    objectVersion 77 with file-system synchronized groups: it lists the folders, not the
                      files, so new .swift files and fixtures are picked up with no project edit. Shared scheme.
Daybreak/App          AppDelegate/SceneDelegate (UIKit lifecycle so the root hosting controller can set the status
                      bar per tab), WeatherModel (the Weather tab's pages: PlaceWeather for where you are, then
                      the saved places), PlaceSearch ("Add a place"), OnThisDayModel (@Observable, @MainActor)
Daybreak/Domain       pure, tested logic ported from Android's domain/: Precip.swift (rain rules), OnThisDay.swift
                      (filter, scoring, picks), Formatting.swift, Models.swift, Summary.swift, LocalTime.swift
                      (zone-free LocalDate/LocalDateTime), KotlinRandom.swift (Kotlin's Random, bit for bit)
Daybreak/Data         OpenMeteo.swift (request + parser), Wikipedia.swift (feed + parser), OnThisDayStore.swift
                      (the day's picks, cached in UserDefaults), SavedPlacesStore.swift, ImageLoader.swift,
                      LocationService.swift
Daybreak/UI           Theme.swift (Android's palette as dynamic colours, type scale, card style), Sky.swift (hero
                      gradients), WeatherIcon.swift (Android's drawn icons), Components.swift, HomeScreen.swift,
                      WeatherScreen.swift (a NavigationStack over a paging ScrollView of places), SearchScreen.swift, PlacesScreen.swift, DayScreen.swift (a day's page, pushed from the
                      10-day list), OnThisDayCard.swift, RootView.swift (tabs, placeholders)
DaybreakTests         Swift Testing suites ported from Android's tests: PrecipTests, OnThisDayTests,
                      OnThisDayFeedTests, OpenMeteoParserTests, DayPageTests, PlacesTests; Fixtures/ holds Android's JSON fixtures, copied
                      from app/src/test/resources/fixtures in the Android repo
scripts               run-in-simulator.sh; make-app-icon.swift (`swift scripts/make-app-icon.swift` redraws the icon)
```

## Conventions

- **Port, don't reinvent.** Domain code mirrors the Kotlin closely (names, thresholds, comments, copy) so the two can
  be compared line by line; port its tests too, on the same fixtures. Keep the Kotlin's doc comments' reasoning.
- **Forecast times are wall-clock and zone-free** (`LocalDateTime`, as Open-Meteo sends them with `timezone=auto`).
  Don't turn them into `Date`. Use `Date` only for real instants (fetch time, "now").
- **Numbers as on Android:** `roundToInt` (halves up) rather than `.rounded()`, `formatFixed` rather than
  `String(format:)` for amounts, a true minus sign in temperatures, US formatting.
- **Swift 6 language mode**, strict concurrency: domain types are `Sendable` structs; models are `@MainActor
  @Observable`; network work is `async`.
- **Look:** colours only from `Palette` (dynamic light/dark), text styles from the `Font` extension (Dynamic Type),
  `.card()` for cards, `Metrics.pageMargin` (20) at the sides, `.readableWidth()` so iPad lines stay short. SF
  Symbols for chrome; weather glyphs are drawn (`WeatherIcon`), as on Android.
- **Accessibility:** each card or cell is one VoiceOver element with a spoken label in the Android app's words
  (both units, "60 percent chance of rain").
- Copy is English, in the Android app's voice: plain, sentence case, no exclamation marks.
- Work happens on the Mac, in `~/Projects/daybreak-ios`, with `gh` signed in. Each change goes in on its own small
  branch and pull request, with tests; CI (`.github/workflows/ci.yml`: the unit tests on an iPhone simulator on
  GitHub's macOS runner) must pass before it's merged. Commit messages end with the Co-Authored-By line the session
  asks for.
