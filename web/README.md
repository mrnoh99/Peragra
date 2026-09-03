# Peragra (Web)

Browser version of Peragra — turns the places you've saved on Instagram into
an organized travel plan. For each trip, save a place — optionally alongside
the Instagram post link that inspired it — and Peragra keeps a searchable
listing, plots it on a map, and lets you sort saved places into custom lists
(e.g. "Must eat", "If we have time").

Same product as the native iOS app in `../Peragra`, built for the browser.

## Features

- **Trips** — create a trip per destination, with dates and a cover icon.
- **Save places from Instagram** — paste a post/reel link and it's shown
  embedded next to your notes. Instagram doesn't expose a user's Saved
  collection through any public API, so this app works from links you bring
  over yourself rather than an automatic import.
- **Caption detection, one place or several** — paste the post's caption
  text, then extract it into an editable list of places to review, check,
  and edit before saving — handles a caption recommending a single spot
  just as well as a numbered "5 cafes I loved" post. Free, pattern-matching
  based, no API key needed, and works on text you paste in.
- **AI-powered extraction** — add your own Anthropic API key in Settings
  (⚙️ in the header) to extract places with Claude instead: more accurate
  on messy or unlabeled captions, and the only way to read a screenshot.
  Reading and organizing text from a photo is done entirely by AI (Claude
  reads the image directly via vision) — this app doesn't run local OCR on
  photos, since on-device text recognition proved unreliable on stylized
  graphics (a Reels cover, a title overlay) during testing. This app has no
  server, so the key is used to call Anthropic's API directly from your
  browser and is stored only in this browser's local storage.
- **Listing** — every saved place as a card: category, address, notes,
  visited status, and a link back to the original Instagram post. Every
  saved place is editable after the fact (name, address, category, notes)
  — fixing an extraction mistake re-geocodes it if the address changed.
- **Map** — saved places are geocoded (via OpenStreetMap Nominatim) and
  plotted on an interactive Leaflet map, color-coded by category. Free by
  default — switch to Google Maps in Settings with your own Google Maps
  API key if you'd rather use that (switches both the map and geocoding).
- **Lists (collections)** — group places within a trip into custom lists and
  filter the listing/map by list.
- **Local persistence** — everything is stored in the browser via
  `localStorage`; no account or backend required.

## Tech stack

- React 19 + TypeScript + Vite
- Tailwind CSS v4
- Zustand (with `persist` middleware) for state
- React Router
- Leaflet / react-leaflet for maps, OpenStreetMap Nominatim for geocoding —
  the default, no API key required. Google Maps JS API + Google Geocoding
  API as an opt-in alternative (own API key, entered in Settings) — loaded
  as a plain script tag, no `@react-google-maps/api` dependency
- Instagram's public `embed.js` for post embeds, called directly from the
  browser like the map/geocoding APIs — no API keys required
- `@anthropic-ai/sdk` (`dangerouslyAllowBrowser`) + Zod structured outputs
  for AI-powered extraction, called directly from the browser with the
  user's own API key — no backend. This is also the only path that reads
  screenshots: there's no local OCR step

## Getting started

```bash
npm install
npm run dev
```

Then open the printed local URL. Create a trip, then "Save a place" — paste
an Instagram post link (optional) and fill in the place name/address to see
it appear in the listing and on the map.

## Scripts

- `npm run dev` — start the dev server
- `npm run build` — type-check and build for production
- `npm run lint` — run Oxlint
- `npm run preview` — preview the production build
