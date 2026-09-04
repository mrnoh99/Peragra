import { useEffect, useMemo, useState } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import { AddPlaceModal } from "../components/AddPlaceModal";
import { ListingView } from "../components/ListingView";
import { MapView } from "../components/MapView";
import { PlaceFilterBar, type SortMode } from "../components/PlaceFilterBar";
import { distanceKm } from "../lib/distance";
import { generateKML } from "../lib/kml";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type Place, type PlaceCategory } from "../types";

type Tab = "listing" | "map";

const CATEGORY_ORDER = new Map(PLACE_CATEGORIES.map((c, i) => [c.value, i]));

export function TripDetailPage() {
  const { tripId } = useParams<{ tripId: string }>();
  const trips = useStore((s) => s.trips);
  const allPlaces = useStore((s) => s.places);
  const allCollections = useStore((s) => s.collections);
  const addCollection = useStore((s) => s.addCollection);
  const deleteCollection = useStore((s) => s.deleteCollection);
  const ensureVisitedCollection = useStore((s) => s.ensureVisitedCollection);

  const trip = useMemo(() => trips.find((t) => t.id === tripId), [trips, tripId]);
  const places = useMemo(
    () => allPlaces.filter((p) => p.tripId === tripId),
    [allPlaces, tripId],
  );
  const collections = useMemo(() => {
    const tripCollections = allCollections.filter((c) => c.tripId === tripId);
    // Visited is a default list — keep it pinned first, ahead of
    // whatever order the user's own lists were created in.
    return [...tripCollections].sort((a, b) => Number(!!b.isVisitedList) - Number(!!a.isVisitedList));
  }, [allCollections, tripId]);

  // Trips created before the Visited-list feature don't have one yet —
  // back-fill it lazily so it always shows in the sidebar, not just after
  // the first place gets marked visited.
  useEffect(() => {
    if (tripId) ensureVisitedCollection(tripId);
  }, [tripId, ensureVisitedCollection]);

  const [tab, setTab] = useState<Tab>("listing");
  const [showAddPlace, setShowAddPlace] = useState(false);
  const [activeCollectionId, setActiveCollectionId] = useState<string | null>(null);
  const [newListName, setNewListName] = useState("");

  // Search/category/visited/favorites/sort — shared by the Listing and Map
  // tabs (via PlaceFilterBar below) so switching tabs doesn't reset what
  // you were looking at, and the map can be narrowed down the same way.
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<PlaceCategory | "all">("all");
  const [hideVisited, setHideVisited] = useState(false);
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const [sortMode, setSortMode] = useState<SortMode>("default");
  const [distanceFromId, setDistanceFromId] = useState<string>("");

  const activeCollection = useMemo(
    () => collections.find((c) => c.id === activeCollectionId) ?? null,
    [collections, activeCollectionId],
  );
  // What's actually on screen right now — respects the selected list, same
  // as the Map tab already did. Export should match what's visible rather
  // than always exporting the whole trip regardless of which list is open.
  const visiblePlaces = useMemo(
    () =>
      activeCollectionId
        ? places.filter((p) => p.collectionIds.includes(activeCollectionId))
        : places,
    [places, activeCollectionId],
  );

  // Everything except the category filter itself — used both to build the
  // list and to count how many places each category option would show, so
  // those counts reflect the other active filters rather than going stale
  // next to them.
  const preCategoryFiltered = useMemo(() => {
    return visiblePlaces.filter((p) => {
      if (hideVisited && p.visited) return false;
      if (favoritesOnly && !p.favorite) return false;
      if (search.trim()) {
        const q = search.trim().toLowerCase();
        if (
          !p.name.toLowerCase().includes(q) &&
          !p.address.toLowerCase().includes(q) &&
          !p.notes.toLowerCase().includes(q)
        ) {
          return false;
        }
      }
      return true;
    });
  }, [visiblePlaces, hideVisited, favoritesOnly, search]);

  const categoryCounts = useMemo(() => {
    const counts = new Map<PlaceCategory, number>();
    for (const p of preCategoryFiltered) {
      counts.set(p.category, (counts.get(p.category) ?? 0) + 1);
    }
    return counts;
  }, [preCategoryFiltered]);

  const categoryFiltered = useMemo(() => {
    if (categoryFilter === "all") return preCategoryFiltered;
    return preCategoryFiltered.filter((p) => p.category === categoryFilter);
  }, [preCategoryFiltered, categoryFilter]);

  const distanceFrom = useMemo(() => {
    const ref = visiblePlaces.find((p) => p.id === distanceFromId);
    return ref && ref.lat !== null && ref.lng !== null ? { lat: ref.lat, lng: ref.lng } : null;
  }, [visiblePlaces, distanceFromId]);

  const sorted = useMemo(() => {
    // Favorited places float to the top no matter which sort mode is
    // active — the mode only decides ordering within/below that.
    const byFavorite = (a: Place, b: Place) => Number(b.favorite) - Number(a.favorite);

    if (sortMode === "name") {
      return [...categoryFiltered].sort((a, b) => byFavorite(a, b) || a.name.localeCompare(b.name));
    }
    if (sortMode === "distance" && distanceFrom) {
      return [...categoryFiltered].sort((a, b) => {
        const da = a.lat !== null && a.lng !== null ? distanceKm(distanceFrom, { lat: a.lat, lng: a.lng }) : Infinity;
        const db = b.lat !== null && b.lng !== null ? distanceKm(distanceFrom, { lat: b.lat, lng: b.lng }) : Infinity;
        return byFavorite(a, b) || da - db;
      });
    }
    // Default: grouped by category (in the app's usual category order),
    // alphabetical by name within each group.
    return [...categoryFiltered].sort((a, b) => {
      const fav = byFavorite(a, b);
      if (fav !== 0) return fav;
      if (a.category !== b.category) {
        return CATEGORY_ORDER.get(a.category)! - CATEGORY_ORDER.get(b.category)!;
      }
      return a.name.localeCompare(b.name);
    });
  }, [categoryFiltered, sortMode, distanceFrom]);

  const distancesById = useMemo(() => {
    if (sortMode !== "distance" || !distanceFrom) return new Map<string, number>();
    const map = new Map<string, number>();
    for (const p of sorted) {
      if (p.lat !== null && p.lng !== null) map.set(p.id, distanceKm(distanceFrom, { lat: p.lat, lng: p.lng }));
    }
    return map;
  }, [sorted, sortMode, distanceFrom]);

  const locatablePlaces = useMemo(
    () => visiblePlaces.filter((p): p is Place & { lat: number; lng: number } => p.lat !== null && p.lng !== null),
    [visiblePlaces],
  );

  const visitedCount = useMemo(() => places.filter((p) => p.visited).length, [places]);
  const locatedCount = useMemo(() => sorted.filter((p) => p.lat !== null).length, [sorted]);

  function exportToGoogleMaps() {
    if (!trip) return;
    const title = activeCollection
      ? `Peragra - ${trip.name} - ${activeCollection.name}`
      : `Peragra - ${trip.name}`;
    const kml = generateKML(title, sorted);
    const blob = new Blob([kml], { type: "application/vnd.google-earth.kml+xml" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${title.replace(/[^\w\- ]+/g, "")}.kml`;
    // Safari (notably iOS Safari) only honors a click on an <a download>
    // that's actually in the document — clicking one that was never
    // appended silently does nothing there, even though Chrome/Firefox
    // don't require it.
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  if (!tripId) return <Navigate to="/" replace />;
  if (!trip) {
    return (
      <div className="py-16 text-center text-sm text-neutral-500">
        Trip not found. <Link to="/" className="text-brand-600 underline">Back to trips</Link>
      </div>
    );
  }

  return (
    <div>
      <Link to="/" className="text-sm text-neutral-500 hover:text-neutral-700">
        ← All trips
      </Link>

      <div className="mt-2 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-neutral-900">
            <span>{trip.coverEmoji}</span>
            {trip.name}
          </h1>
          <p className="text-sm text-neutral-500">
            {trip.destination}
            {trip.startDate && (
              <>
                {" · "}
                {trip.startDate}
                {trip.endDate ? ` – ${trip.endDate}` : ""}
              </>
            )}
          </p>
          <p className="mt-1 text-xs text-neutral-400">
            {places.length} saved place{places.length === 1 ? "" : "s"} · {visitedCount} visited
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <button
            onClick={exportToGoogleMaps}
            disabled={locatedCount === 0}
            className="rounded-lg border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-50 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-transparent"
            title={
              locatedCount === 0
                ? "No places have a map location yet — add an address, or wait for one to be located, first"
                : activeCollection
                  ? `Download a KML of "${activeCollection.name}" to import as a new map in Google My Maps`
                  : "Download a KML file to import as a new map in Google My Maps"
            }
          >
            📤 Export {activeCollection ? `"${activeCollection.name}"` : "to Google Maps"}
          </button>
          <button
            onClick={() => setShowAddPlace(true)}
            className="rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-brand-600"
          >
            + Save a place
          </button>
        </div>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-[220px_1fr]">
        <aside className="lg:sticky lg:top-4 lg:self-start">
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-400">
            Lists
          </h2>
          <div className="space-y-1">
            <button
              onClick={() => setActiveCollectionId(null)}
              className={`block w-full rounded-lg px-3 py-1.5 text-left text-sm ${
                activeCollectionId === null
                  ? "bg-brand-50 font-medium text-brand-700"
                  : "text-neutral-600 hover:bg-neutral-100"
              }`}
            >
              All places
            </button>
            {collections.map((c) => (
              <div key={c.id} className="group flex items-center gap-1">
                <button
                  onClick={() => setActiveCollectionId(c.id)}
                  className={`block w-full truncate rounded-lg px-3 py-1.5 text-left text-sm ${
                    activeCollectionId === c.id
                      ? "bg-brand-50 font-medium text-brand-700"
                      : "text-neutral-600 hover:bg-neutral-100"
                  }`}
                >
                  {c.isVisitedList ? "✅ " : ""}
                  {c.name}
                </button>
                {!c.isVisitedList && (
                  <button
                    onClick={() => {
                      if (activeCollectionId === c.id) setActiveCollectionId(null);
                      deleteCollection(c.id);
                    }}
                    className="hidden shrink-0 pr-1 text-xs text-neutral-400 hover:text-red-500 group-hover:block"
                    aria-label={`Delete ${c.name}`}
                  >
                    ✕
                  </button>
                )}
              </div>
            ))}
          </div>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const trimmed = newListName.trim();
              if (!trimmed || !tripId) return;
              addCollection(tripId, trimmed);
              setNewListName("");
            }}
            className="mt-3 flex gap-1"
          >
            <input
              value={newListName}
              onChange={(e) => setNewListName(e.target.value)}
              placeholder="New list…"
              className="w-full min-w-0 rounded-lg border border-neutral-300 px-2 py-1 text-xs focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
            <button
              type="submit"
              className="shrink-0 rounded-lg bg-neutral-800 px-2.5 py-1 text-xs font-medium text-white hover:bg-neutral-700"
            >
              Add
            </button>
          </form>
        </aside>

        <div>
          <div className="mb-4 inline-flex rounded-lg border border-neutral-200 bg-white p-1 text-sm">
            <button
              onClick={() => setTab("listing")}
              className={`rounded-md px-4 py-1.5 font-medium ${
                tab === "listing" ? "bg-brand-500 text-white" : "text-neutral-600"
              }`}
            >
              Listing
            </button>
            <button
              onClick={() => setTab("map")}
              className={`rounded-md px-4 py-1.5 font-medium ${
                tab === "map" ? "bg-brand-500 text-white" : "text-neutral-600"
              }`}
            >
              Map
            </button>
          </div>

          {places.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-neutral-300 bg-white/60 px-6 py-16 text-center">
              <div className="text-4xl">📌</div>
              <h2 className="mt-3 text-lg font-semibold text-neutral-800">
                No places saved yet
              </h2>
              <p className="mx-auto mt-1 max-w-sm text-sm text-neutral-500">
                Paste a link from a post you saved on Instagram, or add a place by hand, to
                start building your {trip.destination} itinerary.
              </p>
              <button
                onClick={() => setShowAddPlace(true)}
                className="mt-5 rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600"
              >
                Save your first place
              </button>
            </div>
          ) : (
            <>
              <PlaceFilterBar
                search={search}
                onSearchChange={setSearch}
                categoryFilter={categoryFilter}
                onCategoryFilterChange={setCategoryFilter}
                categoryCounts={categoryCounts}
                totalCount={preCategoryFiltered.length}
                hideVisited={hideVisited}
                onHideVisitedChange={setHideVisited}
                favoritesOnly={favoritesOnly}
                onFavoritesOnlyChange={setFavoritesOnly}
                sortMode={sortMode}
                onSortModeChange={setSortMode}
                distanceFromId={distanceFromId}
                onDistanceFromIdChange={setDistanceFromId}
                distanceFromResolved={distanceFrom !== null}
                locatablePlaces={locatablePlaces}
              />
              {tab === "listing" ? (
                <ListingView places={sorted} collections={collections} destination={trip.destination} distancesById={distancesById} />
              ) : (
                <MapView places={sorted} destination={trip.destination} />
              )}
            </>
          )}
        </div>
      </div>

      {showAddPlace && (
        <AddPlaceModal
          tripId={tripId}
          destination={trip.destination}
          defaultCollectionId={activeCollectionId ?? undefined}
          onClose={() => setShowAddPlace(false)}
        />
      )}
    </div>
  );
}
