# Peragra

Peragra turns the places you've saved on Instagram into an organized travel
plan. For each trip, save a place — optionally alongside the Instagram post
link that inspired it — and Peragra keeps a searchable listing, plots it on a
map, and lets you sort saved places into custom lists (e.g. "Must eat", "If we
have time").

This repo has two clients sharing the same product:

- **iOS app** (this directory) — native Swift/SwiftUI, iPhone-first.
- **Web app** — [`web/`](web/), React/TypeScript, runs in any browser.

Each client has its own local storage (SwiftData on iOS, `localStorage` on
web) — they don't currently sync with each other.

## Features (both clients)

- **Trips** — create a trip per destination, with dates and a cover icon.
- **Save places from Instagram** — paste a post/reel link and it's shown
  embedded next to your notes. Instagram doesn't expose a user's Saved
  collection through any public API, so both apps work from links you bring
  over yourself rather than an automatic import.
- **Listing** — every saved place as a card/row: category, address, notes,
  visited status, and a link back to the original Instagram post. Searchable
  and filterable by category.
- **Map** — saved places are geocoded and plotted on an interactive map,
  color-coded by category.
- **Lists (collections)** — group places within a trip into custom lists and
  filter the listing/map by list.
- **Local persistence** — no account or backend required.

## iOS app

Native Swift/SwiftUI app, targeting iOS 17+, iPhone-first.

- SwiftData for local persistence (`Trip`, `Place`, `PlaceCollection` models)
- MapKit (`Map`/`Marker`, iOS 17 API) for the map view, `CLGeocoder` for
  address → coordinate lookups (no API key needed)
- `WKWebView` loading Instagram's public `embed.js` for inline post previews
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates the
  `.xcodeproj` from `project.yml`, so the project file itself isn't committed

### Getting started (macOS + Xcode required)

This project was authored without access to Xcode/macOS, so the Swift code
has been carefully written and reviewed but has **not been compiled or run in
a simulator**. Please do a build in Xcode as your first step and report back
anything that doesn't compile.

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (once):
   ```bash
   brew install xcodegen
   ```
2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
3. Open `Peragra.xcodeproj` in Xcode 15+ and run on an iPhone simulator (iOS
   17+) or device.

Whenever you add/remove/move Swift files, re-run `xcodegen generate` (or just
add the file inside Xcode — either keeps `project.yml`'s `sources` glob in
sync automatically since it points at the whole `Peragra/` folder).

### iOS project layout

```
project.yml                   XcodeGen project spec (source of truth)
Peragra/
  App/PeragraApp.swift        App entry point, SwiftData container setup
  Models/                     Trip, Place, PlaceCollection (@Model), PlaceCategory
  Services/                   GeocodingService (CLGeocoder), InstagramLink (URL parsing)
  Views/
    Trips/                    Trips list, add-trip sheet, trip detail (Listing/Map tabs)
    Places/                   Listing rows, map view, add-place sheet, Instagram embed
  Assets.xcassets/            App icon placeholder + accent color
```

### iOS known limitations

- No automatic import from Instagram's Saved collection — not possible via
  any public API. You bring the post link over yourself.
- No app icon artwork included (`AppIcon.appiconset` is an empty placeholder)
  — add real icon images before shipping.
- Currently iPhone-only (`TARGETED_DEVICE_FAMILY: "1"` in `project.yml`); add
  `"2"` there to support iPad as well.

## Web app

React + TypeScript + Vite app in [`web/`](web/) — see
[`web/README.md`](web/README.md) for details.

```bash
cd web
npm install
npm run dev
```

Uses Leaflet/OpenStreetMap for the map, OpenStreetMap Nominatim for
geocoding, and the same Instagram `embed.js` technique as the iOS app —
verified with a production build, lint, and an end-to-end smoke test.
