import { useState } from "react";
import { Modal } from "./Modal";
import { geocodePlace } from "../lib/geocode";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type Place, type PlaceCategory } from "../types";

export function EditPlaceModal({
  place,
  destination,
  onClose,
}: {
  place: Place;
  destination: string;
  onClose: () => void;
}) {
  const updatePlace = useStore((s) => s.updatePlace);
  const setPlaceCoords = useStore((s) => s.setPlaceCoords);

  const [name, setName] = useState(place.name);
  const [category, setCategory] = useState<PlaceCategory>(place.category);
  const [address, setAddress] = useState(place.address);
  const [notes, setNotes] = useState(place.notes);
  const [saving, setSaving] = useState(false);

  const canSubmit = name.trim().length > 0;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setSaving(true);

    const trimmedAddress = address.trim();
    updatePlace(place.id, {
      name: name.trim(),
      category,
      address: trimmedAddress,
      notes: notes.trim(),
    });

    // Only re-geocode when the address actually changed — otherwise leave
    // the existing coordinates (and geocodeStatus) alone.
    if (trimmedAddress !== place.address) {
      try {
        const query = trimmedAddress || name.trim();
        const result = await geocodePlace(query, destination);
        if (result) {
          setPlaceCoords(place.id, { lat: result.lat, lng: result.lng }, "located");
        } else {
          setPlaceCoords(place.id, null, "failed");
        }
      } catch {
        setPlaceCoords(place.id, null, "failed");
      }
    }

    setSaving(false);
    onClose();
  }

  return (
    <Modal title="Edit place" onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">Name</label>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Place name"
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>

        <div className="flex gap-2">
          <div className="flex-1">
            <label className="mb-1 block text-sm font-medium text-neutral-700">Address</label>
            <input
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="Address (improves map accuracy)"
              className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-neutral-700">Category</label>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value as PlaceCategory)}
              className="rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            >
              {PLACE_CATEGORIES.map((c) => (
                <option key={c.value} value={c.value}>
                  {c.label}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">Notes</label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            placeholder="What made you save this?"
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>

        <button
          type="submit"
          disabled={!canSubmit || saving}
          className="w-full rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
        >
          {saving ? "Saving…" : "Save changes"}
        </button>
      </form>
    </Modal>
  );
}
