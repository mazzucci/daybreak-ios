# Daybreak for iOS

A native SwiftUI version of [Daybreak](https://github.com/mazzucci/Daybreak), a personal app for the start of your day. The Android app (Kotlin, Jetpack Compose) is the reference: this one matches its behaviour, copy, palette and look, but shares no code with it and is free to feel native to iOS.

This is the **first prototype**: the tab shell, location, the Weather tab and Home's weather glance and "On this day".

## What's in it so far

- **Tabs**, in Android's order: Home, Weather, Habits, Clocks, Settings. Habits and Clocks say "Coming soon" with a sentence on what they'll do.
- **Settings**: **Temperature** ("°F first" or "°C first", everywhere in the app), **Places**, and **On this day on Home** (off, Wikipedia isn't asked at all and Home says "Turn on more cards in Settings"), then "Daybreak 0.1.0". Kept on the phone.
- **Location.** CoreLocation with the When-In-Use permission (asked for on first launch), named by reverse geocoding ("Weston"). If you say no, the forecast is for the city of your phone's time zone, found with Open-Meteo's geocoding (else New York), with a "Location is off" card and a way to Settings.
- **Places**: the Weather tab has a page per place, swiped sideways: where you are first, then the places you've added, with dots (or "3 / 12") for where you are and Refresh, Add place and Places over the sky. **Places** turns the current location on or off and lists the saved places, to drag into another order (Edit) or delete (Edit, or a swipe); with no places at all, the Weather tab and Home's glance say how to start (Home's also offers "Use my location", which Android's doesn't). **Add a place** searches Open-Meteo's geocoding as you type ("Lisbon", "Springfield"), says which results are already saved, and turns to the new page. Saved places and each page's last forecast are kept on the phone.
- **Weather**, ported from Android's WeatherScreen:
  - the sky (its colours follow the condition and day or night), the place, the summary line ("68° and clear sky now, with a high of 75° and a low of 57°. No rain expected."), the temperature in °F with °C alongside, the condition, and the High, Low and rain pills;
  - Feels like, Humidity, and Wind with its direction ("↗ from the SW") and gusts;
  - the next 12 hours, with each hour's rain chance and amount and the feels-like line when it's 3° or more off. The **"Now" cell shows the current conditions**, so it always agrees with the sky above it (Android's "Now" cell used the hourly forecast for the current hour; that bug isn't copied);
  - sunrise, sunset and the UV index;
  - **This week** (Android's outlook): how good each of the next seven days is for being outside, as a line for today ("Mixed day: rain most of the day"), a few lines for the week (wet spells, the dry turn, the best day, wind, heat, cold snaps, frost) and a strip of bars by score with rain and snow marks and "Best"; tap a day for its page. Home's glance carries the today line;
  - the next 10 days on one shared temperature scale, with "Best" under this week's best day, with rain chances and day totals by Android's rain rules (`Precip`), and days 8 to 10 lighter under "less certain";
  - **tap a day** for its page (Android's day page): the day's sky with its name, date, condition, High and Low in both units and the feels-like range when it's 3° or more off; the temperature hour by hour (today's from "Now", which shows the current conditions, as on the Weather tab); the rain or snow card, with the verdict, when in the day it falls, a bar per hour with the chance every three hours, the parts of the day that aren't dry and a line when it carries on after midnight; the day's strongest wind and gusts; sunrise, sunset and UV. Swipe or tap back to return;
  - "Updated 8 min ago" (amber with "pull to refresh" past 90 minutes; "Couldn't refresh · updated 2 hours ago" after a failed refresh), and pull to refresh. The last forecast is kept on the phone, so a launch shows it at once.
- **Home**: the date and greeting on the sky ("Good evening"), the weather glance (place, condition, ↑high ↓low, rain chance, the temperature in both units; tap it for the Weather tab), and **On this day**: one cheerful moment from today's date in history from Wikipedia's feed (grim items filtered out, the rest scored, no two from the same decade, the day's picks the same all day and the same as on Android), with a Commons picture that fills the frame when it's a landscape photo or sits whole as a "poster" over a blurred copy of itself otherwise, "1868 · 158 years ago", the text, the article link, "From Wikipedia · CC BY-SA", "Picture" and "Another". Pull to refresh refreshes both.
- **Look**: the system font with Dynamic Type, light and dark mode, Android's "Open sky" palette and card style, safe areas respected, content kept to a readable width on iPad.

Not yet: Coming up, Habits, Clocks, Tonight's sky, the meme, the widget. See "Known gaps" below.

Data comes from [Open-Meteo](https://open-meteo.com/) (forecast and geocoding, no key) and [Wikipedia's "On this day" feed](https://en.wikipedia.org/api/rest_v1/) (no key; text CC BY-SA, pictures from Wikimedia Commons). Requests to Wikimedia carry the User-Agent `Daybreak/<version> (https://github.com/mazzucci/Daybreak)`, as Wikimedia asks.

## Building

Needs Xcode 26.5 or later (the project uses Xcode 16+ synchronized folders) and an iOS 26.5 simulator. The app's deployment target is iOS 17.0, iPhone and iPad.

```sh
# Build for the iPhone 17 simulator
xcodebuild -project Daybreak.xcodeproj -scheme Daybreak \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build build

# Run the unit tests
xcodebuild test -project Daybreak.xcodeproj -scheme Daybreak \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build

# Build if needed, boot the simulator, install, set the location to Weston, MA and launch
scripts/run-in-simulator.sh          # or --ipad for the iPad Pro 13-inch
```

Or open `Daybreak.xcodeproj` in Xcode and press Run.

**Why a committed, hand-written project and no XcodeGen:** the `.xcodeproj` uses *file-system synchronized groups* (Xcode 16's `objectVersion 77`), so it lists folders, not files. Adding, moving or deleting a Swift file or a test fixture needs no project edit and causes no merge conflicts, which was the main reason to reach for XcodeGen. It builds from a fresh clone with nothing to install, on a Mac with no Homebrew and no admin rights. The scheme is shared (`xcshareddata`), so `xcodebuild -scheme Daybreak` and the test action work from the command line.

### On a device (an iPad, with a free Apple ID)

1. In Xcode → Settings → Accounts, add your Apple ID (a free "Personal Team" is enough).
2. Select the Daybreak target → Signing & Capabilities: tick "Automatically manage signing", pick your Personal Team, and change the bundle identifier to something unique to you (`app.daybreak.ios` may be taken; for example `app.daybreak.ios.<yourname>`).
3. Connect the iPad by USB, unlock it and tap "Trust This Computer"; it appears in Xcode's run destinations (Window → Devices and Simulators shows its pairing).
4. On the iPad, turn on Settings → Privacy & Security → Developer Mode (it asks to restart), and confirm after the restart.
5. Run. The first time, the iPad will refuse to open the app until you trust the developer: Settings → General → VPN & Device Management → your Apple ID → Trust.

A free Apple ID's apps expire after 7 days (run from Xcode again to renew), and it can sign at most 3 apps per device.

## Working with the build Mac

Code is edited and committed on Linux; the Mac (`ssh mac`, user `agent`, no GitHub credentials) only builds, tests and runs. A bare repo on the Mac is the go-between:

```sh
# On Linux, once
git remote add mac mac:src/daybreak-ios.git

# On Linux, each time
git push mac main

# On the Mac: the first time
cd ~/src && git clone ~/src/daybreak-ios.git
# then each time
cd ~/src/daybreak-ios && git pull
```

Screenshots: `xcrun simctl io booted screenshot ~/shots/home.png`, then `scp mac:shots/home.png .` on Linux. In Debug builds, launch arguments pick what's on screen without tapping: `xcrun simctl launch booted app.daybreak.ios -initialTab weather -scrollTo days` (`-scrollTo hours` or `days`; `-onThisDayIndex 2` starts On this day on another pick; `-openDay 1` opens tomorrow's page over the Weather tab). Dark mode: `xcrun simctl ui booted appearance dark`.

## Project layout

```
Daybreak.xcodeproj           hand-written, synchronized folders; shared scheme "Daybreak"
Daybreak/
  App/                       launch (UIKit scene hosting SwiftUI, for the per-tab status bar), the app's models
  Domain/                    pure logic ported from Android: Precip, OnThisDay, Formatting, Models, Summary,
                             LocalDate/LocalDateTime, Kotlin's Random (so the day's picks match Android's)
  Data/                      Open-Meteo, Wikipedia, the On this day store, the picture loader, location
  UI/                        theme and palette, sky gradients, drawn weather icons, Home, Weather, the card
  Assets.xcassets            app icon (drawn by scripts/make-app-icon.swift), accent colour
DaybreakTests/               Swift Testing; Fixtures/ holds Android's JSON fixtures
scripts/                     run-in-simulator.sh, make-app-icon.swift
```

## Tests

`DaybreakTests` (Swift Testing, 84 tests) ports Android's tests on Android's own fixtures:

- `PrecipTests`: the rain and snow rules: thresholds, the classifier, amounts in mm, cm and inches, verdicts, the day's parts and timing, on hand-made days and a real 10-day Alps forecast.
- `OnThisDayTests` and `OnThisDayFeedTests`: the grim filter (including Android's regression table of real items), scoring, choosing the day's picks, subjects and pictures, text tidying, and the real feeds for five dates.
- `OpenMeteoParserTests`: parsing forecasts and geocoding results, including nulls and polar days.
- `PlacesTests`: saved places (added once, moved, removed, kept in order with every field, corrupt data read as none), the pages (where you are first), the current location on and off (and no pages at all), and search (two letters at least, results, "No places found", failures, a new query replacing the last).
- `OutdoorScoreTests` and `WeekOutlookTests`: Android's tests for the outdoor score and This week, on the same inputs; `ThisWeekWiringTests`: what the card and Home rely on.
- `DayPageTests`: the day page's hours (today's from "Now"), when the feels-like range gets a pill, and the no-break spaces between numbers and units.

## Known gaps

- No explanations of the tiles, Coming up, Tonight's sky, meme, widget or background refresh.
- Habits and Clocks are placeholders; Settings has only what the app has so far.
- Times follow the phone's 12/24-hour setting; dates and copy are English, as on Android.
