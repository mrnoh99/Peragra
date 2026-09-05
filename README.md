# Peragra

Peragra helps you save the places you find — on Instagram, in a photo, or on a
map — so you actually visit them later, instead of losing them in your camera
roll or saved posts. For each board, save a place — optionally alongside the
Instagram post link that inspired it — and Peragra keeps a searchable
listing, plots it on a map, and lets you sort saved places into custom lists
(e.g. "Must eat", "If we have time"). It's more than a trip planner — but it's
a great one too, once your saved spots for a destination are all in one board.

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
- **Caption detection, one place or several** — paste the post's caption
  text and extract it into an editable list of places to review before
  saving, whether the caption recommends a single spot or a numbered list
  of several. Free and pattern-matching based, works on text you paste in.
- **AI-powered extraction** — add your own API key in Settings to extract
  with Claude instead: more accurate on messy captions, and the only way
  to read a screenshot. Reading and organizing text from a photo is done
  entirely by AI (Claude reads the image directly via vision) — neither
  app runs local OCR on photos, since on-device text recognition proved
  unreliable on stylized graphics (a Reels cover, a title overlay) during
  testing. Neither app has a server, so the key is used to call the AI
  provider directly from your browser/device and is stored only locally.
  Routed through a third-party OpenAI-compatible gateway
  (factchat-cloud.mindlogic.ai) rather than Anthropic's own API, per
  explicit instruction — the key is one issued by that gateway, and
  caption/screenshot data passes through it rather than going only to
  Anthropic. The model is also pickable in Settings (Claude Sonnet 5 by
  default) from the gateway's own catalog, or any other model ID it
  supports via a "Custom…" option.
- **Listing** — every saved place as a card/row: category, address, notes,
  visited status, and a link back to the original Instagram post. Searchable
  and filterable by category. Every saved place is editable after the fact
  (name, address, category, notes) — fixing an extraction mistake
  re-geocodes it if the address changed.
- **Map** — saved places are geocoded and plotted on an interactive map,
  color-coded by category. Free by default (Leaflet/OpenStreetMap on web,
  Apple MapKit on iOS) — switch to Google Maps in Settings with your own
  Google Maps API key if you'd rather use that.
- **KML export/import with Google Maps** — Google has no API for reading
  or writing a personal Saved-places list directly, so this is the closest
  real bridge: export a trip as a KML file titled "Peragra - &lt;trip&gt;"
  and import it into a new [Google My Maps](https://mymaps.google.com)
  map, or export a My Maps map as KML and import that back into Peragra.
  Imported places already carry real coordinates, so they skip geocoding.
- **Lists (collections)** — group places within a trip into custom lists and
  filter the listing/map by list.
- **Local persistence** — no account or backend required.

## iOS app

Native Swift/SwiftUI app, targeting iOS 17+, iPhone-first.

- SwiftData for local persistence (`Trip`, `Place`, `PlaceCollection` models)
- MapKit (`Map`/`Marker`, iOS 17 API) for the map view, `CLGeocoder` for
  address → coordinate lookups (no API key needed) — the default. Opting
  into Google Maps in Settings switches both: the map renders via the
  Google Maps JS API loaded into a `WKWebView` (no native Google SDK
  dependency), and geocoding calls the Google Geocoding API directly
  instead, using the same user-supplied key.
- `WKWebView` loading Instagram's public `embed.js` for inline post previews
- Screenshots are picked via `PhotosPicker`; reading and organizing their
  text is done entirely by AI extraction, not on-device OCR (see Features)
- AI extraction calls a third-party OpenAI-compatible gateway
  (factchat-cloud.mindlogic.ai, not Anthropic's own API) directly over
  HTTPS using an API key the user enters in Settings and that's stored in
  the Keychain
- `Peragra.xcodeproj` is committed directly (no XcodeGen, no generation step)
  — clone and open

### Getting started (macOS + Xcode required)

This project was authored without access to Xcode/macOS: the Swift code and
the `.xcodeproj` itself (hand-built, not exported from Xcode) have been
carefully written and reviewed but **not compiled or opened in Xcode**.
Please do a build as your first step and report back anything that doesn't
compile or open cleanly.

1. Clone the repo.
2. Open `Peragra.xcodeproj` in Xcode 15+.
3. Select the `Peragra` scheme and run on an iPhone simulator (iOS 17+) or
   device.

Adding/removing/moving Swift files is done from inside Xcode as usual (drag
into the navigator, or File > New > File) — it edits `project.pbxproj`
directly, same as any normal Xcode project.

### iOS project layout

```
Peragra.xcodeproj/            Committed Xcode project (source of truth)
Peragra/
  App/PeragraApp.swift        App entry point, SwiftData container setup
  Models/                     Trip, Place, PlaceCollection (@Model), PlaceCategory,
                                AISettings, MapSettings
  Services/                    GeocodingService (CLGeocoder/Google dispatch),
                                GoogleGeocodingService, InstagramLink (URL parsing),
                                CaptionParser (name/address heuristics), KMLService
                                (Google Maps export/import), AIExtractionService
                                (AI gateway), KeychainService
  Views/
    Trips/                    Trips list, add-trip sheet, trip detail (Listing/Map tabs)
    Places/                   Listing rows, map view (MapKit/Google dispatch),
                                add/edit-place sheets, Instagram embed
    SettingsSheet.swift       AI extraction API key + map provider settings
  Assets.xcassets/            App icon + accent color
```

### iOS known limitations

- No automatic import from Instagram's Saved collection — not possible via
  any public API. You bring the post link over yourself.
- Currently iPhone-only (`TARGETED_DEVICE_FAMILY = 1` in the project build
  settings); change to `1,2` to support iPad as well.
- `Info.plist` is generated by Xcode from build settings
  (`GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_KEY_*`) rather than a
  committed file — the modern default for new Xcode projects.

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

Deploys to GitHub Pages via
[`.github/workflows/deploy-web.yml`](.github/workflows/deploy-web.yml) —
see [`web/README.md`'s Deployment section](web/README.md#deployment-github-pages)
for the one manual repo-settings step it still needs and the resulting URL.
