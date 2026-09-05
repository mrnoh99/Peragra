# Peragra (Web)

Browser version of Peragra — helps you save the places you find (on
Instagram, in a photo, or on a map) so you actually visit them later. For
each board, save a place — optionally alongside the Instagram post link
that inspired it — and Peragra keeps a searchable listing, plots it on a
map, and lets you sort saved places into custom lists (e.g. "Must eat", "If
we have time").

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
- **AI-powered extraction** — add your own API key in Settings (⚙️ in the
  header) to extract places with Claude instead: more accurate on messy or
  unlabeled captions, and the only way to read a screenshot. Reading and
  organizing text from a photo is done entirely by AI (Claude reads the
  image directly via vision) — this app doesn't run local OCR on photos,
  since on-device text recognition proved unreliable on stylized graphics
  (a Reels cover, a title overlay) during testing. This app has no server,
  so the key is used to call the AI provider directly from your browser
  and is stored only in this browser's local storage. Routed through a
  third-party OpenAI-compatible gateway (factchat-cloud.mindlogic.ai)
  rather than Anthropic's own API, per explicit instruction — the key is
  one issued by that gateway, and caption/screenshot data passes through
  it rather than going only to Anthropic. The model is also pickable in
  Settings (Claude Sonnet 5 by default) from the gateway's own catalog, or
  any other model ID it supports via a "Custom…" option.
- **Listing** — every saved place as a card: category, address, notes,
  visited status, and a link back to the original Instagram post. Every
  saved place is editable after the fact (name, address, category, notes)
  — fixing an extraction mistake re-geocodes it if the address changed.
- **Map** — saved places are geocoded (via OpenStreetMap Nominatim) and
  plotted on an interactive Leaflet map, color-coded by category. Free by
  default — switch to Google Maps in Settings with your own Google Maps
  API key if you'd rather use that (switches both the map and geocoding).
- **KML export/import with Google Maps** — Google has no API for reading
  or writing a personal Saved-places list directly, so this is the closest
  real bridge: export a trip as a KML file titled "Peragra - &lt;trip&gt;"
  and import it into a new [Google My Maps](https://mymaps.google.com)
  map, or export a My Maps map as KML and import that back into Peragra.
  Imported places already carry real coordinates, so they skip geocoding.
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
- `openai` SDK (`dangerouslyAllowBrowser`), pointed at a third-party
  OpenAI-compatible gateway (factchat-cloud.mindlogic.ai) rather than
  Anthropic's own API, for AI-powered extraction — called directly from
  the browser with the user's own (gateway-issued) API key, no backend.
  This is also the only path that reads screenshots: there's no local OCR
  step. Response JSON is validated with Zod after the fact rather than via
  a provider-native structured-output feature, since the gateway's support
  for that is undocumented

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

## Deployment (GitHub Pages)

The app deploys as a static site to GitHub Pages, built by
[`.github/workflows/deploy-web.yml`](../.github/workflows/deploy-web.yml) on
every push that touches `web/`. Two things in the app are already set up for
this specifically:

- `vite.config.ts` sets `base: "/Peragra/"` — required because a GitHub
  Pages project site (as opposed to a custom domain or `<user>.github.io`
  itself) is served from a `/<repo-name>/` subpath, and assets built with
  the default root-relative paths would 404 under that prefix.
- `main.tsx` uses React Router's `HashRouter`, not `BrowserRouter` — GitHub
  Pages is static file hosting with no server-side rewrites, so reloading a
  path like `/trips/abc` directly would 404. Hash routes (`/#/trips/abc`)
  always resolve to `index.html`, since the server never sees anything
  after the `#`.

**One manual, one-time step is still required** — enabling Pages itself
isn't something a workflow file or a `git push` can do:

1. On GitHub, go to the repo's **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions**.
3. Push to (or merge into) a branch the workflow watches — currently `main`
   and `claude/travel-planning-app-9ou1mc` — and the `deploy-web` workflow
   run's summary will show the live URL once it finishes (also visible on
   the Pages settings page after the first successful run):
   `https://<owner>.github.io/Peragra/`.

If the branch this was developed on isn't `main`, update the `branches:`
list in the workflow file (or just merge to `main`, which it already
watches).
