import { useEffect, useMemo, useState } from "react";
import { Link, Navigate, useNavigate, useParams } from "react-router-dom";
import { AddPlaceModal } from "../components/AddPlaceModal";
import { ListingView } from "../components/ListingView";
import { MapView } from "../components/MapView";
import { PlaceFilterBar, type SortMode } from "../components/PlaceFilterBar";
import { distanceKm } from "../lib/distance";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type Collection, type Place, type PlaceCategory } from "../types";

type Tab = "listing" | "map";

const CATEGORY_ORDER = new Map(PLACE_CATEGORIES.map((c, i) => [c.value, i]));

export function TripDetailPage() {
  const { tripId } = useParams<{ tripId: string }>();
  const navigate = useNavigate();
  const trips = useStore((s) => s.trips);
  const deleteTrip = useStore((s) => s.deleteTrip);
  const allPlaces = useStore((s) => s.places);
  const allCollections = useStore((s) => s.collections);
  const addCollection = useStore((s) => s.addCollection);
  const deleteCollection = useStore((s) => s.deleteCollection);
  const ensureVisitedCollection = useStore((s) => s.ensureVisitedCollection);
  const ensureFavoritesCollection = useStore((s) => s.ensureFavoritesCollection);

  const trip = useMemo(() => trips.find((t) => t.id === tripId), [trips, tripId]);
  const otherBoards = useMemo(() => trips.filter((t) => t.id !== tripId), [trips, tripId]);
  const places = useMemo(
    () => allPlaces.filter((p) => p.tripId === tripId),
    [allPlaces, tripId],
  );
  // Default lists are pinned ahead of whatever order the user's own
  // lists were created in — Favorites right after "All places", then
  // Visited, then the auto-created country lists, matching the sidebar's
  // fixed reading order.
  const defaultListRank = (c: Collection) => (c.isFavoritesList ? 0 : c.isVisitedList ? 1 : c.isCountryList ? 2 : 3);
  const collections = useMemo(() => {
    const tripCollections = allCollections.filter((c) => c.tripId === tripId);
    return [...tripCollections].sort((a, b) => {
      const rankDiff = defaultListRank(a) - defaultListRank(b);
      if (rankDiff !== 0) return rankDiff;
      if (a.isCountryList && b.isCountryList) return a.name.localeCompare(b.name);
      return 0;
    });
  }, [allCollections, tripId]);
  // Auto country lists are filter-only — a place's membership is fully
  // derived from its address, so they're excluded from the manual "Add to
  // list"/"Send to list" pickers where the user assigns lists by hand.
  const manualCollections = useMemo(() => collections.filter((c) => !c.isCountryList), [collections]);

  // Trips created before the Visited/Favorites-list feature don't have
  // them yet — back-fill lazily so they always show in the sidebar, not
  // just after the first place gets marked visited/favorited.
  useEffect(() => {
    if (!tripId) return;
    ensureVisitedCollection(tripId);
    ensureFavoritesCollection(tripId);
  }, [tripId, ensureVisitedCollection, ensureFavoritesCollection]);

  const [tab, setTab] = useState<Tab>("listing");
  const [showAddPlace, setShowAddPlace] = useState(false);
  // A place shows up while every currently-toggled-on list contains it
  // (AND, not OR) — several lists can be active at once.
  const [activeCollectionIds, setActiveCollectionIds] = useState<Set<string>>(new Set());
  const [newListName, setNewListName] = useState("");
  // Set by ListingView's bulk "Show on Map", so the Map tab can narrow to
  // just that selection instead of the full filtered listing — cleared
  // when the Map tab is opened directly instead.
  const [mapFilterIds, setMapFilterIds] = useState<string[] | null>(null);
  // Set by a marker's "View place card" link, so the Listing tab can
  // scroll to and briefly highlight that place — cleared a couple seconds
  // later, same as PlaceCard's own transient "Copied" badge.
  const [highlightedPlaceId, setHighlightedPlaceId] = useState<string | null>(null);

  function viewPlaceInListing(placeId: string) {
    setTab("listing");
    setHighlightedPlaceId(placeId);
    window.setTimeout(() => setHighlightedPlaceId((current) => (current === placeId ? null : current)), 2000);
  }

  // Search/category/visited/favorites/sort — shared by the Listing and Map
  // tabs (via PlaceFilterBar below) so switching tabs doesn't reset what
  // you were looking at, and the map can be narrowed down the same way.
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<PlaceCategory | "all">("all");
  const [hideVisited, setHideVisited] = useState(false);
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const [sortMode, setSortMode] = useState<SortMode>("default");
  const [distanceFromId, setDistanceFromId] = useState<string>("");

  // What's actually on screen right now — respects the selected list, same
  // as the Map tab already did.
  const visiblePlaces = useMemo(
    () =>
      activeCollectionIds.size === 0
        ? places
        : places.filter((p) => [...activeCollectionIds].every((id) => p.collectionIds.includes(id))),
    [places, activeCollectionIds],
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

  const mapPlaces = useMemo(
    () => (mapFilterIds ? sorted.filter((p) => mapFilterIds.includes(p.id)) : sorted),
    [sorted, mapFilterIds],
  );

  const visitedCount = useMemo(() => places.filter((p) => p.visited).length, [places]);
  const favoritesCount = useMemo(() => places.filter((p) => p.favorite).length, [places]);

  if (!tripId) return <Navigate to="/" replace />;
  if (!trip) {
    return (
      <div className="py-16 text-center text-sm text-neutral-500">
        Board not found. <Link to="/" className="text-brand-600 underline">Back to boards</Link>
      </div>
    );
  }

  return (
    <div>
      <Link to="/" className="text-sm text-neutral-500 hover:text-neutral-700">
        ← Your boards
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
            onClick={() => setShowAddPlace(true)}
            className="rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-brand-600"
          >
            + Add places
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
              onClick={() => setActiveCollectionIds(new Set())}
              className={`block w-full rounded-lg px-3 py-1.5 text-left text-sm ${
                activeCollectionIds.size === 0
                  ? "bg-brand-50 font-medium text-brand-700"
                  : "text-neutral-600 hover:bg-neutral-100"
              }`}
            >
              All places
            </button>
            {collections.map((c) => {
              const active = activeCollectionIds.has(c.id);
              return (
                <div key={c.id} className="group flex items-center gap-1">
                  <button
                    onClick={() =>
                      setActiveCollectionIds((prev) => {
                        const next = new Set(prev);
                        if (next.has(c.id)) next.delete(c.id);
                        else next.add(c.id);
                        return next;
                      })
                    }
                    className={`block w-full truncate rounded-lg px-3 py-1.5 text-left text-sm ${
                      active ? "bg-brand-50 font-medium text-brand-700" : "text-neutral-600 hover:bg-neutral-100"
                    }`}
                  >
                    {active ? "✓ " : ""}
                    {c.isFavoritesList ? "⭐ " : c.isVisitedList ? "✅ " : c.isCountryList ? "🌍 " : ""}
                    {c.name}
                    {c.isFavoritesList && (
                      <span className="ml-1 text-xs text-neutral-400">({favoritesCount})</span>
                    )}
                    {c.isVisitedList && (
                      <span className="ml-1 text-xs text-neutral-400">({visitedCount})</span>
                    )}
                    {c.isCountryList && (
                      <span className="ml-1 text-xs text-neutral-400">
                        ({places.filter((p) => p.collectionIds.includes(c.id)).length})
                      </span>
                    )}
                  </button>
                  {!c.isVisitedList && !c.isFavoritesList && !c.isCountryList && (
                    <button
                      onClick={() => {
                        if (!confirm(`Delete the list "${c.name}"?`)) return;
                        setActiveCollectionIds((prev) => {
                          const next = new Set(prev);
                          next.delete(c.id);
                          return next;
                        });
                        deleteCollection(c.id);
                      }}
                      className="shrink-0 pr-1 text-xs text-neutral-400 hover:text-red-500"
                      aria-label={`Delete ${c.name}`}
                    >
                      ✕
                    </button>
                  )}
                </div>
              );
            })}
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
              onClick={() => {
                setTab("map");
                setMapFilterIds(null);
              }}
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
              <div className="mt-5 flex flex-wrap items-center justify-center gap-2">
                <button
                  onClick={() => setShowAddPlace(true)}
                  className="rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600"
                >
                  Add your first place
                </button>
                <button
                  onClick={() => {
                    if (confirm(`Delete the empty board "${trip.name}"?`)) {
                      deleteTrip(tripId);
                      navigate("/");
                    }
                  }}
                  className="rounded-lg border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-500 hover:border-red-300 hover:text-red-500"
                >
                  Delete this board
                </button>
              </div>
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
                <ListingView
                  places={sorted}
                  collections={manualCollections}
                  destination={trip.destination}
                  distancesById={distancesById}
                  otherBoards={otherBoards}
                  highlightedPlaceId={highlightedPlaceId}
                  onViewSelectedOnMap={(ids) => {
                    setMapFilterIds(ids);
                    setTab("map");
                  }}
                />
              ) : (
                <>
                  {mapFilterIds && (
                    <div className="mb-3 flex items-center justify-between rounded-lg border border-brand-200 bg-brand-50 px-3 py-2 text-sm text-brand-700">
                      <span>
                        Showing {mapPlaces.length} selected place{mapPlaces.length === 1 ? "" : "s"}
                      </span>
                      <button
                        onClick={() => setMapFilterIds(null)}
                        className="font-medium underline hover:no-underline"
                      >
                        Show all
                      </button>
                    </div>
                  )}
                  <MapView places={mapPlaces} destination={trip.destination} onSelectPlace={viewPlaceInListing} />
                </>
              )}
            </>
          )}
        </div>
      </div>

      {showAddPlace && (
        <AddPlaceModal
          tripId={tripId}
          destination={trip.destination}
          defaultCollectionId={activeCollectionIds.size === 1 ? [...activeCollectionIds][0] : undefined}
          onClose={() => setShowAddPlace(false)}
        />
      )}

    </div>
  );
}
