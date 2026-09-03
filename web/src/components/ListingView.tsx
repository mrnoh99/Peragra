import { useMemo, useState } from "react";
import { distanceKm } from "../lib/distance";
import { PLACE_CATEGORIES, type Collection, type Place, type PlaceCategory } from "../types";
import { useStore } from "../store/useStore";
import { PlaceCard } from "./PlaceCard";

type SortMode = "default" | "name" | "distance";

const CATEGORY_ORDER = new Map(PLACE_CATEGORIES.map((c, i) => [c.value, i]));

export function ListingView({
  places,
  collections,
  activeCollectionId,
  destination,
}: {
  places: Place[];
  collections: Collection[];
  activeCollectionId: string | null;
  destination: string;
}) {
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<PlaceCategory | "all">("all");
  const [hideVisited, setHideVisited] = useState(false);
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const [sortMode, setSortMode] = useState<SortMode>("default");
  const [distanceFromId, setDistanceFromId] = useState<string>("");
  const [isSelecting, setIsSelecting] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const updatePlacesCategory = useStore((s) => s.updatePlacesCategory);

  function toggleSelecting() {
    setIsSelecting((v) => !v);
    setSelectedIds(new Set());
  }

  function toggleSelected(placeId: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(placeId)) next.delete(placeId);
      else next.add(placeId);
      return next;
    });
  }

  function applyBulkCategory(category: PlaceCategory) {
    updatePlacesCategory([...selectedIds], category);
    setSelectedIds(new Set());
    setIsSelecting(false);
  }

  const filtered = useMemo(() => {
    return places.filter((p) => {
      if (activeCollectionId && !p.collectionIds.includes(activeCollectionId)) return false;
      if (categoryFilter !== "all" && p.category !== categoryFilter) return false;
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
  }, [places, activeCollectionId, categoryFilter, hideVisited, favoritesOnly, search]);

  const distanceFrom = useMemo(() => {
    const ref = places.find((p) => p.id === distanceFromId);
    return ref && ref.lat !== null && ref.lng !== null ? { lat: ref.lat, lng: ref.lng } : null;
  }, [places, distanceFromId]);

  const sorted = useMemo(() => {
    if (sortMode === "name") {
      return [...filtered].sort((a, b) => a.name.localeCompare(b.name));
    }
    if (sortMode === "distance" && distanceFrom) {
      return [...filtered].sort((a, b) => {
        const da = a.lat !== null && a.lng !== null ? distanceKm(distanceFrom, { lat: a.lat, lng: a.lng }) : Infinity;
        const db = b.lat !== null && b.lng !== null ? distanceKm(distanceFrom, { lat: b.lat, lng: b.lng }) : Infinity;
        return da - db;
      });
    }
    // Default: grouped by category (in the app's usual category order),
    // alphabetical by name within each group.
    return [...filtered].sort((a, b) => {
      if (a.category !== b.category) {
        return CATEGORY_ORDER.get(a.category)! - CATEGORY_ORDER.get(b.category)!;
      }
      return a.name.localeCompare(b.name);
    });
  }, [filtered, sortMode, distanceFrom]);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search saved places…"
          className="min-w-[180px] flex-1 rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
        />
        <select
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value as PlaceCategory | "all")}
          className="rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
        >
          <option value="all">All categories</option>
          {PLACE_CATEGORIES.map((c) => (
            <option key={c.value} value={c.value}>
              {c.label}
            </option>
          ))}
        </select>
        <label className="flex items-center gap-1.5 text-sm text-neutral-600">
          <input
            type="checkbox"
            checked={hideVisited}
            onChange={(e) => setHideVisited(e.target.checked)}
          />
          Hide visited
        </label>
        <label className="flex items-center gap-1.5 text-sm text-neutral-600">
          <input
            type="checkbox"
            checked={favoritesOnly}
            onChange={(e) => setFavoritesOnly(e.target.checked)}
          />
          ★ Favorites only
        </label>
        <button
          onClick={toggleSelecting}
          className={`rounded-lg border px-3 py-2 text-sm font-medium ${
            isSelecting
              ? "border-brand-500 bg-brand-50 text-brand-700"
              : "border-neutral-300 text-neutral-600 hover:bg-neutral-50"
          }`}
        >
          {isSelecting ? "Cancel" : "Select"}
        </button>
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <label className="flex items-center gap-1.5 text-sm text-neutral-600">
          Sort by
          <select
            value={sortMode}
            onChange={(e) => setSortMode(e.target.value as SortMode)}
            className="rounded-lg border border-neutral-300 px-2 py-1.5 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          >
            <option value="default">By Category</option>
            <option value="name">Name (A–Z)</option>
            <option value="distance">Distance from…</option>
          </select>
        </label>
        {sortMode === "distance" && (
          <select
            value={distanceFromId}
            onChange={(e) => setDistanceFromId(e.target.value)}
            className="rounded-lg border border-neutral-300 px-2 py-1.5 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          >
            <option value="">Choose a place…</option>
            {places
              .filter((p) => p.lat !== null && p.lng !== null)
              .map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
          </select>
        )}
        {sortMode === "distance" && !distanceFrom && distanceFromId === "" && (
          <span className="text-xs text-neutral-400">
            Pick a located place to sort the rest by distance from it.
          </span>
        )}
      </div>

      {isSelecting && (
        <div className="mb-4 flex flex-wrap items-center gap-3 rounded-lg border border-brand-200 bg-brand-50 px-3 py-2">
          <span className="text-sm font-medium text-brand-700">
            {selectedIds.size === 0 ? "Select places to edit" : `${selectedIds.size} selected`}
          </span>
          <select
            disabled={selectedIds.size === 0}
            value=""
            onChange={(e) => {
              if (e.target.value) applyBulkCategory(e.target.value as PlaceCategory);
            }}
            className="rounded-lg border border-neutral-300 px-2 py-1.5 text-sm disabled:opacity-50"
          >
            <option value="" disabled>
              Change category to…
            </option>
            {PLACE_CATEGORIES.map((c) => (
              <option key={c.value} value={c.value}>
                {c.label}
              </option>
            ))}
          </select>
        </div>
      )}

      {sorted.length === 0 ? (
        <p className="rounded-xl border border-dashed border-neutral-300 bg-white/50 py-10 text-center text-sm text-neutral-500">
          No places match yet.
        </p>
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {sorted.map((place) => (
            <PlaceCard
              key={place.id}
              place={place}
              collections={collections}
              destination={destination}
              selectable={isSelecting}
              selected={selectedIds.has(place.id)}
              onToggleSelect={() => toggleSelected(place.id)}
              distanceKm={
                sortMode === "distance" && distanceFrom && place.lat !== null && place.lng !== null
                  ? distanceKm(distanceFrom, { lat: place.lat, lng: place.lng })
                  : undefined
              }
            />
          ))}
        </div>
      )}
    </div>
  );
}
