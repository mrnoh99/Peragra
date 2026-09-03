import { useRef, useState } from "react";
import { PLACE_CATEGORIES, type Collection, type Place } from "../types";
import { useStore } from "../store/useStore";
import { EditPlaceModal } from "./EditPlaceModal";
import { googleMapsUrl } from "../lib/googleMapsUrl";

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
  destination,
  selectable = false,
  selected = false,
  onToggleSelect,
  distanceKm,
}: {
  place: Place;
  collections: Collection[];
  destination: string;
  selectable?: boolean;
  selected?: boolean;
  onToggleSelect?: () => void;
  /** Shown as "N km away" when sorting by distance from a reference place. */
  distanceKm?: number;
}) {
  const toggleVisited = useStore((s) => s.toggleVisited);
  const toggleFavorite = useStore((s) => s.toggleFavorite);
  const deletePlace = useStore((s) => s.deletePlace);
  const togglePlaceCollection = useStore((s) => s.togglePlaceCollection);
  const [showCollections, setShowCollections] = useState(false);
  const [editing, setEditing] = useState(false);
  const [copied, setCopied] = useState(false);
  const longPressTimer = useRef<number | null>(null);

  const categoryLabel =
    PLACE_CATEGORIES.find((c) => c.value === place.category)?.label ?? "Other";

  function copyForMaps() {
    const text = place.address ? `${place.name}, ${place.address}` : place.name;
    navigator.clipboard
      ?.writeText(text)
      .then(() => {
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1500);
      })
      .catch(() => {});
  }

  function startLongPress() {
    longPressTimer.current = window.setTimeout(copyForMaps, 550);
  }

  function cancelLongPress() {
    if (longPressTimer.current !== null) {
      window.clearTimeout(longPressTimer.current);
      longPressTimer.current = null;
    }
  }

  return (
    <div
      className="relative rounded-xl border border-black/5 bg-white p-4 shadow-sm"
      onPointerDown={startLongPress}
      onPointerUp={cancelLongPress}
      onPointerLeave={cancelLongPress}
      onPointerCancel={cancelLongPress}
      onContextMenu={(e) => e.preventDefault()}
    >
      {copied && (
        <div className="absolute right-3 top-3 z-10 rounded-full bg-neutral-900/90 px-2.5 py-1 text-xs font-medium text-white">
          Copied for Google Maps
        </div>
      )}
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-start gap-2">
          {selectable && (
            <input
              type="checkbox"
              checked={selected}
              onChange={onToggleSelect}
              className="mt-1.5 h-4 w-4 shrink-0"
            />
          )}
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <button
                onClick={() => toggleFavorite(place.id)}
                aria-label={place.favorite ? "Remove from favorites" : "Mark as favorite"}
                className={`shrink-0 leading-none ${
                  place.favorite ? "text-amber-400" : "text-neutral-300 hover:text-amber-300"
                }`}
              >
                {place.favorite ? "★" : "☆"}
              </button>
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
              {distanceKm !== undefined && (
                <span className="ml-2 text-neutral-400">
                  · {distanceKm < 1 ? `${Math.round(distanceKm * 1000)} m` : `${distanceKm.toFixed(1)} km`} away
                </span>
              )}
            </p>
            {place.address && (
              <p className="mt-1 text-sm text-neutral-500">{place.address}</p>
            )}
            {place.phone && <p className="mt-0.5 text-sm text-neutral-500">☎ {place.phone}</p>}
            {place.notes && <p className="mt-1 text-sm text-neutral-600">{place.notes}</p>}
            {place.geocodeStatus === "failed" && (
              <p className="mt-1 text-xs text-amber-600">
                Couldn't locate this on the map — try adding a more specific address.
              </p>
            )}
            {place.geocodeStatus === "estimated" && (
              <p className="mt-1 text-xs text-neutral-400">
                📍 Approximate location — AI's best guess, since the given address couldn't be
                found on the map.
              </p>
            )}
            <a
              href={googleMapsUrl(place, destination)}
              target="_blank"
              rel="noreferrer"
              className="mt-2 inline-flex items-center gap-1 text-xs font-medium text-brand-600 hover:underline"
            >
              🗺️ Open in Google Maps
            </a>
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
          <div className="flex gap-2">
            <button
              onClick={() => setEditing(true)}
              className="text-xs text-neutral-400 hover:text-brand-600"
            >
              Edit
            </button>
            <button
              onClick={() => deletePlace(place.id)}
              className="text-xs text-neutral-400 hover:text-red-500"
            >
              Remove
            </button>
          </div>
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

      {editing && (
        <EditPlaceModal place={place} destination={destination} onClose={() => setEditing(false)} />
      )}
    </div>
  );
}
