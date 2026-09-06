import { useRef, useState, type ChangeEvent } from "react";
import { Modal } from "./Modal";
import { parseSharedPlacesText, type SharedPlace } from "../lib/sharePlaces";
import { geocodePlaceByAddressOrName } from "../lib/geocode";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type PlaceCategory } from "../types";

interface ReviewRow extends SharedPlace {
  id: string;
  selected: boolean;
}

/**
 * The receiving side of "share places": paste the text from someone's
 * "Copy as text", or pick the file from their "Save as file", parse it
 * deterministically (no AI involved — the payload is already structured),
 * then review/deselect before adding to this board. Each added place is
 * geocoded fresh, since a coordinate from the sender's board means
 * nothing on this one.
 */
export function ImportPlacesModal({
  tripId,
  destination,
  onClose,
}: {
  tripId: string;
  destination: string;
  onClose: () => void;
}) {
  const addPlace = useStore((s) => s.addPlace);
  const setPlaceCoords = useStore((s) => s.setPlaceCoords);
  const allPlaces = useStore((s) => s.places);

  const [pastedText, setPastedText] = useState("");
  const [rows, setRows] = useState<ReviewRow[] | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  function tryParse(text: string) {
    const places = parseSharedPlacesText(text);
    if (!places) {
      setParseError("That doesn't look like a Peragra places share — paste the text exactly as copied, or choose the .json file.");
      setRows(null);
      return;
    }
    setParseError(null);
    setRows(places.map((p) => ({ ...p, id: crypto.randomUUID(), selected: true })));
  }

  async function handleFileChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    const text = await file.text();
    setPastedText(text);
    tryParse(text);
  }

  function updateRow(id: string, patch: Partial<ReviewRow>) {
    setRows((prev) => prev?.map((r) => (r.id === id ? { ...r, ...patch } : r)) ?? null);
  }

  function toggleAll() {
    setRows((prev) => {
      if (!prev) return prev;
      const allSelected = prev.every((r) => r.selected);
      return prev.map((r) => ({ ...r, selected: !allSelected }));
    });
  }

  async function handleAdd() {
    if (!rows) return;
    const selected = rows.filter((r) => r.selected);
    if (selected.length === 0) return;
    setSaving(true);

    for (const row of selected) {
      const place = addPlace({
        tripId,
        name: row.name.trim(),
        category: row.category,
        address: row.address.trim(),
        phone: row.phone?.trim() || null,
        notes: row.notes.trim(),
        instagramUrl: null,
        linkUrl: row.linkUrl?.trim() || null,
        collectionIds: [],
      });

      const siblingPlaces = allPlaces.filter((p) => p.tripId === tripId);
      try {
        const result = await geocodePlaceByAddressOrName(place, destination, siblingPlaces);
        setPlaceCoords(place.id, result, result ? "located" : "failed");
      } catch {
        setPlaceCoords(place.id, null, "failed");
      }
    }

    setSaving(false);
    onClose();
  }

  return (
    <Modal title="Import shared places" onClose={onClose}>
      {!rows ? (
        <div className="space-y-3">
          <p className="text-sm text-neutral-500">
            Paste text from someone's "Copy as text" share, or choose the .json file from their
            "Save as file" share.
          </p>
          <textarea
            value={pastedText}
            onChange={(e) => setPastedText(e.target.value)}
            rows={6}
            placeholder="Paste the shared places text here…"
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 font-mono text-xs focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
          {parseError && <p className="text-xs text-amber-600">{parseError}</p>}
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => tryParse(pastedText)}
              disabled={!pastedText.trim()}
              className="rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
            >
              Parse text
            </button>
            <input
              ref={fileInputRef}
              type="file"
              accept="application/json,.json"
              onChange={handleFileChange}
              className="hidden"
              id="import-places-file-input"
            />
            <label
              htmlFor="import-places-file-input"
              className="cursor-pointer rounded-lg border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-50"
            >
              Choose file…
            </label>
          </div>
        </div>
      ) : (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm font-medium text-neutral-700">
              {rows.filter((r) => r.selected).length} of {rows.length} selected
            </p>
            <button
              type="button"
              onClick={toggleAll}
              className="text-sm font-medium text-brand-600 hover:underline"
            >
              {rows.every((r) => r.selected) ? "Deselect all" : "Select all"}
            </button>
          </div>
          <div className="max-h-96 space-y-2 overflow-y-auto">
            {rows.map((row) => (
              <div key={row.id} className="rounded-lg border border-neutral-200 p-2">
                <div className="flex items-start gap-2">
                  <input
                    type="checkbox"
                    checked={row.selected}
                    onChange={(e) => updateRow(row.id, { selected: e.target.checked })}
                    className="mt-2"
                    aria-label={`Include ${row.name}`}
                  />
                  <div className="flex-1 space-y-1.5">
                    <input
                      value={row.name}
                      onChange={(e) => updateRow(row.id, { name: e.target.value })}
                      className="w-full rounded border border-neutral-200 px-2 py-1 text-sm font-medium"
                      placeholder="Name"
                    />
                    <div className="flex gap-1.5">
                      <select
                        value={row.category}
                        onChange={(e) => updateRow(row.id, { category: e.target.value as PlaceCategory })}
                        className="rounded border border-neutral-200 px-1.5 py-1 text-xs"
                      >
                        {PLACE_CATEGORIES.map((c) => (
                          <option key={c.value} value={c.value}>
                            {c.label}
                          </option>
                        ))}
                      </select>
                      <input
                        value={row.address}
                        onChange={(e) => updateRow(row.id, { address: e.target.value })}
                        placeholder="Address"
                        className="flex-1 rounded border border-neutral-200 px-2 py-1 text-xs"
                      />
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => {
                setRows(null);
                setParseError(null);
              }}
              className="rounded-lg border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-50"
            >
              Back
            </button>
            <button
              type="button"
              onClick={handleAdd}
              disabled={saving || rows.every((r) => !r.selected)}
              className="flex-1 rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
            >
              {saving
                ? "Adding & locating…"
                : `Add ${rows.filter((r) => r.selected).length} place${rows.filter((r) => r.selected).length === 1 ? "" : "s"}`}
            </button>
          </div>
        </div>
      )}
    </Modal>
  );
}
