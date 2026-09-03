import { PLACE_CATEGORIES, type Place, type PlaceCategory } from "../types";

export type SortMode = "default" | "name" | "distance";

/**
 * The search/category/visited/favorites/sort controls, shared by the
 * Listing and Map tabs (via TripDetailPage, which owns the filter state
 * and computes the filtered+sorted place list both tabs render) so
 * switching tabs doesn't reset what you were looking at, and the map can
 * be narrowed down the same way the list can.
 */
export function PlaceFilterBar({
  search,
  onSearchChange,
  categoryFilter,
  onCategoryFilterChange,
  categoryCounts,
  totalCount,
  hideVisited,
  onHideVisitedChange,
  favoritesOnly,
  onFavoritesOnlyChange,
  sortMode,
  onSortModeChange,
  distanceFromId,
  onDistanceFromIdChange,
  distanceFromResolved,
  locatablePlaces,
}: {
  search: string;
  onSearchChange: (value: string) => void;
  categoryFilter: PlaceCategory | "all";
  onCategoryFilterChange: (value: PlaceCategory | "all") => void;
  categoryCounts: Map<PlaceCategory, number>;
  totalCount: number;
  hideVisited: boolean;
  onHideVisitedChange: (value: boolean) => void;
  favoritesOnly: boolean;
  onFavoritesOnlyChange: (value: boolean) => void;
  sortMode: SortMode;
  onSortModeChange: (value: SortMode) => void;
  distanceFromId: string;
  onDistanceFromIdChange: (value: string) => void;
  distanceFromResolved: boolean;
  locatablePlaces: Place[];
}) {
  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <input
          value={search}
          onChange={(e) => onSearchChange(e.target.value)}
          placeholder="Search saved places…"
          className="min-w-[180px] flex-1 rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
        />
        <select
          value={categoryFilter}
          onChange={(e) => onCategoryFilterChange(e.target.value as PlaceCategory | "all")}
          className="rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
        >
          <option value="all">All categories ({totalCount})</option>
          {PLACE_CATEGORIES.map((c) => (
            <option key={c.value} value={c.value}>
              {c.label} ({categoryCounts.get(c.value) ?? 0})
            </option>
          ))}
        </select>
        <label className="flex items-center gap-1.5 text-sm text-neutral-600">
          <input
            type="checkbox"
            checked={hideVisited}
            onChange={(e) => onHideVisitedChange(e.target.checked)}
          />
          Hide visited
        </label>
        <label className="flex items-center gap-1.5 text-sm text-neutral-600">
          <input
            type="checkbox"
            checked={favoritesOnly}
            onChange={(e) => onFavoritesOnlyChange(e.target.checked)}
          />
          ★ Favorites only
        </label>
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <label className="flex items-center gap-1.5 text-sm text-neutral-600">
          Sort by
          <select
            value={sortMode}
            onChange={(e) => onSortModeChange(e.target.value as SortMode)}
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
            onChange={(e) => onDistanceFromIdChange(e.target.value)}
            className="rounded-lg border border-neutral-300 px-2 py-1.5 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          >
            <option value="">Choose a place…</option>
            {locatablePlaces.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        )}
        {sortMode === "distance" && !distanceFromResolved && distanceFromId === "" && (
          <span className="text-xs text-neutral-400">
            Pick a located place to sort the rest by distance from it.
          </span>
        )}
      </div>
    </div>
  );
}
