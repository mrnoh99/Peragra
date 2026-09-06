import { useEffect, useState } from "react";
import { PLACE_CATEGORIES, type Collection, type Place, type PlaceCategory, type Trip } from "../types";
import { useStore } from "../store/useStore";
import { buildSharedPlacesPayload, saveSharedPlacesFile, sharedPlacesToText } from "../lib/sharePlaces";
import { PlaceCard } from "./PlaceCard";

export function ListingView({
  places,
  collections,
  destination,
  distancesById,
  otherBoards,
  highlightedPlaceId,
  onViewSelectedOnMap,
}: {
  /** Already filtered and sorted by the parent (shared with the Map tab). */
  places: Place[];
  collections: Collection[];
  destination: string;
  distancesById: Map<string, number>;
  /** Every board except this one, for the bulk "Move to board" picker. */
  otherBoards: Trip[];
  /** Set by a map marker's "View place card" link — scrolls to and
   *  briefly highlights that place's card. */
  highlightedPlaceId?: string | null;
  /** Switches to the Map tab, narrowed to just these place ids. */
  onViewSelectedOnMap: (placeIds: string[]) => void;
}) {
  const [isSelecting, setIsSelecting] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [showListPicker, setShowListPicker] = useState(false);
  const [showSharePicker, setShowSharePicker] = useState(false);
  const [shareMessage, setShareMessage] = useState<string | null>(null);
  const updatePlacesCategory = useStore((s) => s.updatePlacesCategory);
  const togglePlacesCollection = useStore((s) => s.togglePlacesCollection);
  const movePlacesToBoard = useStore((s) => s.movePlacesToBoard);

  useEffect(() => {
    if (!highlightedPlaceId) return;
    document.getElementById(`place-card-${highlightedPlaceId}`)?.scrollIntoView({
      behavior: "smooth",
      block: "center",
    });
  }, [highlightedPlaceId]);

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

  // Toggles the whole selection's membership in this list (never closes
  // the selection) — the same selection can be sent to (or removed from)
  // several lists one after another.
  function applyBulkToggleList(collectionId: string) {
    togglePlacesCollection([...selectedIds], collectionId);
  }

  function toggleSelectAll() {
    setSelectedIds((prev) => (prev.size === places.length ? new Set() : new Set(places.map((p) => p.id))));
  }

  /** Whether every currently-selected place already belongs to this list. */
  function isCollectionOnAllSelected(collectionId: string): boolean {
    const selected = places.filter((p) => selectedIds.has(p.id));
    return selected.length > 0 && selected.every((p) => p.collectionIds.includes(collectionId));
  }

  function viewSelectedOnMap() {
    onViewSelectedOnMap([...selectedIds]);
  }

  async function copySelectedAsText() {
    const selected = places.filter((p) => selectedIds.has(p.id));
    const text = sharedPlacesToText(buildSharedPlacesPayload(selected));
    try {
      await navigator.clipboard.writeText(text);
      setShareMessage(`Copied ${selected.length} place${selected.length === 1 ? "" : "s"} — paste it anywhere to share.`);
    } catch {
      setShareMessage("Couldn't copy to the clipboard.");
    }
    setShowSharePicker(false);
    window.setTimeout(() => setShareMessage(null), 4000);
  }

  async function saveSelectedAsFile() {
    const selected = places.filter((p) => selectedIds.has(p.id));
    try {
      const result = await saveSharedPlacesFile(buildSharedPlacesPayload(selected));
      if (result !== "cancelled") {
        setShareMessage(`Saved ${selected.length} place${selected.length === 1 ? "" : "s"} to a file.`);
        window.setTimeout(() => setShareMessage(null), 4000);
      }
    } catch {
      setShareMessage("Couldn't save the file.");
      window.setTimeout(() => setShareMessage(null), 4000);
    }
    setShowSharePicker(false);
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
          <button
            type="button"
            onClick={toggleSelectAll}
            disabled={places.length === 0}
            className="rounded-lg border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-600 hover:bg-neutral-50 disabled:opacity-50"
          >
            {selectedIds.size === places.length ? "Deselect all" : "Select all"}
          </button>
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
                        onClick={() => applyBulkToggleList(c.id)}
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
          <button
            type="button"
            onClick={viewSelectedOnMap}
            disabled={selectedIds.size === 0}
            className="rounded-lg border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-600 hover:bg-neutral-50 disabled:opacity-50"
          >
            🗺️ Show on Map
          </button>
          <div className="relative">
            <button
              type="button"
              onClick={() => setShowSharePicker((v) => !v)}
              disabled={selectedIds.size === 0}
              className="rounded-lg border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-600 hover:bg-neutral-50 disabled:opacity-50"
            >
              📤 Share… {showSharePicker ? "▲" : "▼"}
            </button>
            {showSharePicker && (
              <div className="absolute left-0 top-full z-10 mt-1 flex min-w-[10rem] flex-col gap-0.5 rounded-lg border border-neutral-200 bg-white p-1.5 shadow-lg">
                <button
                  type="button"
                  onClick={copySelectedAsText}
                  className="whitespace-nowrap rounded px-2 py-1 text-left text-sm text-neutral-600 hover:bg-neutral-50"
                >
                  📋 Copy as text
                </button>
                <button
                  type="button"
                  onClick={saveSelectedAsFile}
                  className="whitespace-nowrap rounded px-2 py-1 text-left text-sm text-neutral-600 hover:bg-neutral-50"
                >
                  💾 Save as file
                </button>
              </div>
            )}
          </div>
          {shareMessage && <span className="text-xs text-neutral-500">{shareMessage}</span>}
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
              highlighted={place.id === highlightedPlaceId}
            />
          ))}
        </div>
      )}
    </div>
  );
}
