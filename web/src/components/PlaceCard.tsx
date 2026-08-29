import { useState } from "react";
import { PLACE_CATEGORIES, type Collection, type Place } from "../types";
import { useStore } from "../store/useStore";

const CATEGORY_ICON: Record<string, string> = {
  restaurant: "🍽️",
  cafe: "☕",
  attraction: "🎡",
  shopping: "🛍️",
  hotel: "🏨",
  nightlife: "🌃",
  other: "📍",
};

export function PlaceCard({
  place,
  collections,
}: {
  place: Place;
  collections: Collection[];
}) {
  const toggleVisited = useStore((s) => s.toggleVisited);
  const deletePlace = useStore((s) => s.deletePlace);
  const togglePlaceCollection = useStore((s) => s.togglePlaceCollection);
  const [showCollections, setShowCollections] = useState(false);

  const categoryLabel =
    PLACE_CATEGORIES.find((c) => c.value === place.category)?.label ?? "Other";

  return (
    <div className="rounded-xl border border-black/5 bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span>{CATEGORY_ICON[place.category] ?? "📍"}</span>
            <h3
              className={`truncate font-semibold text-neutral-900 ${
                place.visited ? "text-neutral-400 line-through" : ""
              }`}
            >
              {place.name}
            </h3>
          </div>
          <p className="mt-0.5 text-xs font-medium uppercase tracking-wide text-brand-600">
            {categoryLabel}
          </p>
          {place.address && (
            <p className="mt-1 text-sm text-neutral-500">{place.address}</p>
          )}
          {place.notes && <p className="mt-1 text-sm text-neutral-600">{place.notes}</p>}
          {place.geocodeStatus === "failed" && (
            <p className="mt-1 text-xs text-amber-600">
              Couldn't locate this on the map — try adding a more specific address.
            </p>
          )}
          {place.instagramUrl && (
            <a
              href={place.instagramUrl}
              target="_blank"
              rel="noreferrer"
              className="mt-2 inline-flex items-center gap-1 text-xs font-medium text-pink-600 hover:underline"
            >
              📷 View original Instagram post
            </a>
          )}
        </div>
        <div className="flex shrink-0 flex-col items-end gap-1">
          <button
            onClick={() => toggleVisited(place.id)}
            className={`rounded-full px-2.5 py-1 text-xs font-medium ${
              place.visited
                ? "bg-green-100 text-green-700"
                : "bg-neutral-100 text-neutral-500 hover:bg-neutral-200"
            }`}
          >
            {place.visited ? "Visited" : "Mark visited"}
          </button>
          <button
            onClick={() => deletePlace(place.id)}
            className="text-xs text-neutral-400 hover:text-red-500"
          >
            Remove
          </button>
        </div>
      </div>

      {collections.length > 0 && (
        <div className="mt-3 border-t border-neutral-100 pt-3">
          <button
            onClick={() => setShowCollections((v) => !v)}
            className="text-xs font-medium text-neutral-500 hover:text-neutral-700"
          >
            {place.collectionIds.length > 0
              ? `In ${place.collectionIds.length} list${place.collectionIds.length > 1 ? "s" : ""}`
              : "Add to list"}{" "}
            {showCollections ? "▲" : "▼"}
          </button>
          {showCollections && (
            <div className="mt-2 flex flex-wrap gap-1.5">
              {collections.map((c) => {
                const active = place.collectionIds.includes(c.id);
                return (
                  <button
                    key={c.id}
                    onClick={() => togglePlaceCollection(place.id, c.id)}
                    className={`rounded-full border px-2.5 py-1 text-xs ${
                      active
                        ? "border-brand-500 bg-brand-50 text-brand-700"
                        : "border-neutral-200 text-neutral-600 hover:bg-neutral-50"
                    }`}
                  >
                    {c.name}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
