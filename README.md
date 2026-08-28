# Peragra

Peragra turns the places you've saved on Instagram into an organized travel plan.
For each trip, save a place — optionally alongside the Instagram post link that
inspired it — and Peragra keeps a searchable listing, plots it on a map, and lets
you sort saved places into custom lists (e.g. "Must eat", "If we have time").

## Features

- **Trips** — create a trip per destination, with dates and a cover icon.
- **Save places from Instagram** — paste a post/reel link and it's shown embedded
  next to your notes. Instagram doesn't expose a user's Saved collection through
  any public API, so this app works from links you bring over yourself rather
  than an automatic import.
- **Listing** — every saved place as a card: category, address, notes, visited
  status, and a link back to the original Instagram post.
- **Map** — saved places are geocoded (via OpenStreetMap Nominatim) and plotted
  on an interactive Leaflet map, color-coded by category.
- **Lists (collections)** — group places within a trip into custom lists and
  filter the listing/map by list.
- **Local persistence** — everything is stored in the browser via `localStorage`;
  no account or backend required.

## Tech stack

- React 19 + TypeScript + Vite
- Tailwind CSS v4
- Zustand (with `persist` middleware) for state
- React Router
- Leaflet / react-leaflet for maps
- OpenStreetMap Nominatim for geocoding, Instagram's public `embed.js` for post
  embeds — both called directly from the browser, no API keys required

## Getting started

```bash
npm install
npm run dev
```

Then open the printed local URL. Create a trip, then "Save a place" — paste an
Instagram post link (optional) and fill in the place name/address to see it
appear in the listing and on the map.

## Scripts

- `npm run dev` — start the dev server
- `npm run build` — type-check and build for production
- `npm run lint` — run Oxlint
- `npm run preview` — preview the production build
