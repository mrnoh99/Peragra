import { useState } from "react";
import { PLACE_CATEGORIES, type Collection, type Place, type PlaceCategory } from "../types";
import { useStore } from "../store/useStore";
import { PlaceCard } from "./PlaceCard";

export function ListingView({
  places,
  collections,
  destination,
  distancesById,
}: {
  /** Already filtered and sorted by the parent (shared with the Map tab). */
  places: Place[];
  collections: Collection[];
  destination: string;
  distancesById: Map<string, number>;
}) {
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

  return (
    <div>
      <div className="mb-4 flex justify-end">
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

      {places.length === 0 ? (
        <p className="rounded-xl border border-dashed border-neutral-300 bg-white/50 py-10 text-center text-sm text-neutral-500">
          No places match yet.
        </p>
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {places.map((place) => (
            <PlaceCard
              key={place.id}
              place={place}
              collections={collections}
              destination={destination}
              selectable={isSelecting}
              selected={selectedIds.has(place.id)}
              onToggleSelect={() => toggleSelected(place.id)}
              distanceKm={distancesById.get(place.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
}
