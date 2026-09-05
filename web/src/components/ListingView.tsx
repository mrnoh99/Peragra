import { useState } from "react";
import { PLACE_CATEGORIES, type Collection, type Place, type PlaceCategory, type Trip } from "../types";
import { useStore } from "../store/useStore";
import { PlaceCard } from "./PlaceCard";
import { googleMapsDirectionsUrl } from "../lib/googleMapsUrl";
import { kakaoMapDirectionsUrl } from "../lib/kakaoMapUrl";
import { naverMapDirectionsUrl } from "../lib/naverMapUrl";
import { tmapDirectionsUrl } from "../lib/tmapUrl";
import { openCustomSchemeUrl } from "../lib/customSchemeUrl";

export function ListingView({
  places,
  collections,
  destination,
  distancesById,
  otherBoards,
}: {
  /** Already filtered and sorted by the parent (shared with the Map tab). */
  places: Place[];
  collections: Collection[];
  destination: string;
  distancesById: Map<string, number>;
  /** Every board except this one, for the bulk "Move to board" picker. */
  otherBoards: Trip[];
}) {
  const [isSelecting, setIsSelecting] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [showListPicker, setShowListPicker] = useState(false);
  const [isSendingToMap, setIsSendingToMap] = useState(false);
  const [mapError, setMapError] = useState<string | null>(null);
  const [showMapMenu, setShowMapMenu] = useState(false);
  const updatePlacesCategory = useStore((s) => s.updatePlacesCategory);
  const addPlacesToCollection = useStore((s) => s.addPlacesToCollection);
  const movePlacesToBoard = useStore((s) => s.movePlacesToBoard);

  function toggleSelecting() {
    setIsSelecting((v) => !v);
    setSelectedIds(new Set());
    setShowListPicker(false);
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

  function applyBulkMoveToBoard(newTripId: string) {
    movePlacesToBoard([...selectedIds], newTripId);
    setSelectedIds(new Set());
    setIsSelecting(false);
  }

  // A place can belong to any number of lists at once, so this only ever
  // adds (never removes, never closes the selection) — the same
  // selection can be sent to several lists one after another.
  function applyBulkAddToList(collectionId: string) {
    addPlacesToCollection([...selectedIds], collectionId);
  }

  /** Whether every currently-selected place already belongs to this list. */
  function isCollectionOnAllSelected(collectionId: string): boolean {
    const selected = places.filter((p) => selectedIds.has(p.id));
    return selected.length > 0 && selected.every((p) => p.collectionIds.includes(collectionId));
  }

  function sendSelectedToGoogleMaps() {
    setShowMapMenu(false);
    // Keep the current list order (not selection-click order) so the
    // resulting route reads top-to-bottom the way the list does.
    const selectedPlaces = places.filter((p) => selectedIds.has(p.id));
    window.open(googleMapsDirectionsUrl(selectedPlaces, destination), "_blank", "noreferrer");
  }

  async function sendSelectedToKakaoMap() {
    setShowMapMenu(false);
    setMapError(null);
    setIsSendingToMap(true);
    try {
      const selectedPlaces = places.filter((p) => selectedIds.has(p.id));
      const url = await kakaoMapDirectionsUrl(selectedPlaces);
      if (!url) {
        setMapError("Couldn't get your current location — allow location access for this site and try again.");
        return;
      }
      window.open(url, "_blank", "noreferrer");
    } finally {
      setIsSendingToMap(false);
    }
  }

  async function sendSelectedToNaverMap() {
    setShowMapMenu(false);
    setMapError(null);
    setIsSendingToMap(true);
    try {
      const selectedPlaces = places.filter((p) => selectedIds.has(p.id));
      const url = await naverMapDirectionsUrl(selectedPlaces);
      if (!url) {
        setMapError("Couldn't get your current location — allow location access for this site and try again.");
        return;
      }
      openCustomSchemeUrl(url);
    } finally {
      setIsSendingToMap(false);
    }
  }

  function sendSelectedToTmap() {
    setShowMapMenu(false);
    setMapError(null);
    // Unlike Kakao/Naver, Tmap needs no explicit starting coordinate, so
    // this needs no location lookup and isn't async.
    const selectedPlaces = places.filter((p) => selectedIds.has(p.id));
    const url = tmapDirectionsUrl(selectedPlaces);
    if (!url) {
      setMapError("None of the selected places have a located position yet.");
      return;
    }
    openCustomSchemeUrl(url);
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
          {otherBoards.length > 0 && (
            <select
              disabled={selectedIds.size === 0}
              value=""
              onChange={(e) => {
                if (e.target.value) applyBulkMoveToBoard(e.target.value);
              }}
              className="rounded-lg border border-neutral-300 px-2 py-1.5 text-sm disabled:opacity-50"
            >
              <option value="" disabled>
                Move to board…
              </option>
              {otherBoards.map((board) => (
                <option key={board.id} value={board.id}>
                  {board.coverEmoji} {board.name}
                </option>
              ))}
            </select>
          )}
          {collections.length > 0 && (
            <div className="relative">
              <button
                type="button"
                onClick={() => setShowListPicker((v) => !v)}
                disabled={selectedIds.size === 0}
                className="rounded-lg border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-600 hover:bg-neutral-50 disabled:opacity-50"
              >
                📋 Send to list… {showListPicker ? "▲" : "▼"}
              </button>
              {showListPicker && (
                <div className="absolute left-0 top-full z-10 mt-1 flex min-w-[10rem] flex-col gap-0.5 rounded-lg border border-neutral-200 bg-white p-1.5 shadow-lg">
                  {collections.map((c) => {
                    const onAll = isCollectionOnAllSelected(c.id);
                    return (
                      <button
                        key={c.id}
                        type="button"
                        onClick={() => applyBulkAddToList(c.id)}
                        className={`whitespace-nowrap rounded px-2 py-1 text-left text-sm ${
                          onAll ? "bg-brand-50 text-brand-700" : "text-neutral-600 hover:bg-neutral-50"
                        }`}
                      >
                        {onAll ? "✓ " : ""}
                        {c.name}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          )}
          <div className="relative">
            <button
              type="button"
              onClick={() => setShowMapMenu((v) => !v)}
              disabled={selectedIds.size === 0 || isSendingToMap}
              className="rounded-lg border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-600 hover:bg-neutral-50 disabled:opacity-50"
            >
              {isSendingToMap ? "Locating…" : `🗺️ Open in Map ${showMapMenu ? "▲" : "▼"}`}
            </button>
            {showMapMenu && (
              <div className="absolute left-0 top-full z-10 mt-1 flex min-w-[10rem] flex-col gap-0.5 rounded-lg border border-neutral-200 bg-white p-1.5 shadow-lg">
                <button
                  type="button"
                  onClick={sendSelectedToGoogleMaps}
                  className="whitespace-nowrap rounded px-2 py-1 text-left text-sm text-neutral-600 hover:bg-neutral-50"
                >
                  Google Maps
                </button>
                <button
                  type="button"
                  onClick={sendSelectedToNaverMap}
                  className="whitespace-nowrap rounded px-2 py-1 text-left text-sm text-neutral-600 hover:bg-neutral-50"
                >
                  Naver Map
                </button>
                <button
                  type="button"
                  onClick={sendSelectedToKakaoMap}
                  className="whitespace-nowrap rounded px-2 py-1 text-left text-sm text-neutral-600 hover:bg-neutral-50"
                >
                  Kakao Map
                </button>
                <button
                  type="button"
                  onClick={sendSelectedToTmap}
                  className="whitespace-nowrap rounded px-2 py-1 text-left text-sm text-neutral-600 hover:bg-neutral-50"
                >
                  Tmap
                </button>
              </div>
            )}
          </div>
        </div>
      )}
      {mapError && (
        <p className="-mt-2 mb-4 text-xs text-amber-600">{mapError}</p>
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
