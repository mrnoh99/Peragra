import { useMemo, useState } from "react";
import { PLACE_CATEGORIES, type Collection, type Place, type PlaceCategory } from "../types";
import { PlaceCard } from "./PlaceCard";

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

  const filtered = useMemo(() => {
    return places.filter((p) => {
      if (activeCollectionId && !p.collectionIds.includes(activeCollectionId)) return false;
      if (categoryFilter !== "all" && p.category !== categoryFilter) return false;
      if (hideVisited && p.visited) return false;
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
  }, [places, activeCollectionId, categoryFilter, hideVisited, search]);

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
      </div>

      {filtered.length === 0 ? (
        <p className="rounded-xl border border-dashed border-neutral-300 bg-white/50 py-10 text-center text-sm text-neutral-500">
          No places match yet.
        </p>
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {filtered.map((place) => (
            <PlaceCard
              key={place.id}
              place={place}
              collections={collections}
              destination={destination}
            />
          ))}
        </div>
      )}
    </div>
  );
}
