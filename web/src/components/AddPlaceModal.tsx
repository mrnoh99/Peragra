import { useMemo, useRef, useState } from "react";
import { Modal } from "./Modal";
import { InstagramEmbed } from "./InstagramEmbed";
import { geocodePlace } from "../lib/geocode";
import { isInstagramPostUrl, normalizeInstagramUrl } from "../lib/instagram";
import { parseCaption } from "../lib/captionParser";
import { recognizeCaptionImage } from "../lib/ocr";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type PlaceCategory } from "../types";

export function AddPlaceModal({
  tripId,
  destination,
  defaultCollectionId,
  onClose,
}: {
  tripId: string;
  destination: string;
  defaultCollectionId?: string;
  onClose: () => void;
}) {
  const addPlace = useStore((s) => s.addPlace);
  const setPlaceCoords = useStore((s) => s.setPlaceCoords);

  const [instagramInput, setInstagramInput] = useState("");
  const [name, setName] = useState("");
  const [category, setCategory] = useState<PlaceCategory>("restaurant");
  const [address, setAddress] = useState("");
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);

  const [captionText, setCaptionText] = useState("");
  const [ocrLoading, setOcrLoading] = useState(false);
  const [ocrError, setOcrError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const instagramUrl = isInstagramPostUrl(instagramInput)
    ? normalizeInstagramUrl(instagramInput)
    : null;
  const canSubmit = name.trim().length > 0;

  const detected = useMemo(() => parseCaption(captionText), [captionText]);
  const hasDetection = Boolean(detected.name || detected.address);
  const detectionAlreadyApplied =
    (!detected.name || name.trim() === detected.name) &&
    (!detected.address || address.trim() === detected.address);

  function applyDetected() {
    if (detected.name && !name.trim()) setName(detected.name);
    if (detected.address && !address.trim()) setAddress(detected.address);
  }

  async function handleScreenshotChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setOcrLoading(true);
    setOcrError(null);
    try {
      const text = await recognizeCaptionImage(file);
      if (!text) {
        setOcrError("Couldn't find any readable text in that image.");
      } else {
        setCaptionText((prev) => (prev.trim() ? `${prev}\n${text}` : text));
      }
    } catch {
      setOcrError("Couldn't read text from that image — try pasting the caption instead.");
    } finally {
      setOcrLoading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setSaving(true);

    const place = addPlace({
      tripId,
      name: name.trim(),
      category,
      address: address.trim(),
      notes: notes.trim(),
      instagramUrl,
      collectionIds: defaultCollectionId ? [defaultCollectionId] : [],
    });

    try {
      const query = address.trim() || name.trim();
      const result = await geocodePlace(query, destination);
      if (result) {
        setPlaceCoords(place.id, { lat: result.lat, lng: result.lng }, "located");
      } else {
        setPlaceCoords(place.id, null, "failed");
      }
    } catch {
      setPlaceCoords(place.id, null, "failed");
    }

    setSaving(false);
    onClose();
  }

  return (
    <Modal title="Save a place" onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            Instagram post link{" "}
            <span className="font-normal text-neutral-400">(optional)</span>
          </label>
          <input
            value={instagramInput}
            onChange={(e) => setInstagramInput(e.target.value)}
            placeholder="https://www.instagram.com/p/..."
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
          <p className="mt-1 text-xs text-neutral-400">
            Paste the link from a post you saved. Instagram doesn't let apps read your Saved
            collection directly, so bring the link over and we'll show the post alongside your
            notes.
          </p>
          {instagramInput && !instagramUrl && (
            <p className="mt-1 text-xs text-amber-600">
              That doesn't look like an instagram.com/p/... or /reel/... link.
            </p>
          )}
          {instagramUrl && (
            <div className="mt-2 max-h-64 overflow-y-auto rounded-lg border border-neutral-200 p-2">
              <InstagramEmbed url={instagramUrl} />
            </div>
          )}
        </div>

        <div className="rounded-lg border border-dashed border-neutral-300 p-3">
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            Caption text <span className="font-normal text-neutral-400">(optional)</span>
          </label>
          <p className="mb-2 text-xs text-neutral-400">
            Instagram won't hand over a post's caption automatically, but if the shop's name and
            address are written in it, paste the caption below — or upload a screenshot of it and
            we'll read the text for you — and we'll try to pull them out.
          </p>
          <textarea
            value={captionText}
            onChange={(e) => setCaptionText(e.target.value)}
            rows={3}
            placeholder="Paste the post's caption here…"
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
          <div className="mt-2 flex items-center gap-2">
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              onChange={handleScreenshotChange}
              className="hidden"
              id="caption-screenshot-input"
            />
            <label
              htmlFor="caption-screenshot-input"
              className="cursor-pointer rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50"
            >
              📷 Upload a screenshot of the caption
            </label>
            {ocrLoading && <span className="text-xs text-neutral-400">Reading text…</span>}
          </div>
          {ocrError && <p className="mt-1 text-xs text-amber-600">{ocrError}</p>}

          {hasDetection && !detectionAlreadyApplied && (
            <div className="mt-2 rounded-lg bg-brand-50 p-2 text-xs text-brand-800">
              Detected{detected.name ? ` name "${detected.name}"` : ""}
              {detected.name && detected.address ? " and" : ""}
              {detected.address ? ` address "${detected.address}"` : ""}.{" "}
              <button
                type="button"
                onClick={applyDetected}
                className="font-semibold underline hover:no-underline"
              >
                Use this
              </button>
            </div>
          )}
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">Place name</label>
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Ichiran Ramen Shibuya"
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">Category</label>
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value as PlaceCategory)}
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          >
            {PLACE_CATEGORIES.map((c) => (
              <option key={c.value} value={c.value}>
                {c.label}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            Address <span className="font-normal text-neutral-400">(improves map accuracy)</span>
          </label>
          <input
            value={address}
            onChange={(e) => setAddress(e.target.value)}
            placeholder="e.g. Shibuya, Tokyo"
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
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
          {saving ? "Saving & locating…" : "Save place"}
        </button>
      </form>
    </Modal>
  );
}
