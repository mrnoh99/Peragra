import { PLACE_CATEGORIES, type Place, type PlaceCategory } from "../types";

export type SortMode = "default" | "name" | "distance";

const selectClass =
  "rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500";

function toggleChipClass(active: boolean) {
  return `shrink-0 whitespace-nowrap rounded-full border px-3 py-1.5 text-xs font-medium ${
    active
      ? "border-brand-500 bg-brand-50 text-brand-700"
      : "border-neutral-200 text-neutral-500 hover:bg-neutral-50"
  }`;
}

/**
 * The search/category/visited/favorites/sort controls, shared by the
 * Listing and Map tabs (via TripDetailPage, which owns the filter state
 * and computes the filtered+sorted place list both tabs render) so
 * switching tabs doesn't reset what you were looking at, and the map can
 * be narrowed down the same way the list can.
 *
 * Laid out as one wrapping toolbar row — search/category/sort on the
 * left, the two on/off filters as toggle chips pinned to the right —
 * rather than stacked rows, so it reads as a single control cluster.
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
    <div className="mb-4 flex flex-wrap items-center gap-2">
      <input
        value={search}
        onChange={(e) => onSearchChange(e.target.value)}
        placeholder="Search saved places…"
        className={`min-w-[160px] flex-1 ${selectClass}`}
      />
      <select
        value={categoryFilter}
        onChange={(e) => onCategoryFilterChange(e.target.value as PlaceCategory | "all")}
        className={selectClass}
      >
        <option value="all">All categories ({totalCount})</option>
        {PLACE_CATEGORIES.map((c) => (
          <option key={c.value} value={c.value}>
            {c.label} ({categoryCounts.get(c.value) ?? 0})
          </option>
        ))}
      </select>
      <select
        value={sortMode}
        onChange={(e) => onSortModeChange(e.target.value as SortMode)}
        className={selectClass}
      >
        <option value="default">Sort: By category</option>
        <option value="name">Sort: Name (A–Z)</option>
        <option value="distance">Sort: Distance from…</option>
      </select>
      {sortMode === "distance" && (
        <select
          value={distanceFromId}
          onChange={(e) => onDistanceFromIdChange(e.target.value)}
          className={selectClass}
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
        <span className="text-xs text-neutral-400">Pick a located place to sort by.</span>
      )}

      <div className="ml-auto flex items-center gap-1.5">
        <button
          type="button"
          onClick={() => onHideVisitedChange(!hideVisited)}
          className={toggleChipClass(hideVisited)}
        >
          Hide visited
        </button>
        <button
          type="button"
          onClick={() => onFavoritesOnlyChange(!favoritesOnly)}
          className={toggleChipClass(favoritesOnly)}
        >
          ★ Favorites only
        </button>
      </div>
    </div>
  );
}
