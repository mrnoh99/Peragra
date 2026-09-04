import { useRef, useState } from "react";
import { Modal } from "./Modal";
import {
  extractPlacesFromImages,
  fileToBase64,
  guessNearestAddress,
  isSupportedImageMediaType,
  AIExtractionError,
  type AIExtractedPlace,
} from "../lib/aiExtract";
import { readPhotoExif } from "../lib/photoExif";
import { geocodePlace } from "../lib/geocode";
import { selectActiveApiKey, useAISettingsStore } from "../store/useAISettingsStore";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type Place, type PlaceCategory } from "../types";

interface OnSitePhoto {
  id: string;
  file: File;
}

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
  const apiKey = useAISettingsStore(selectActiveApiKey);

  const [name, setName] = useState(place.name);
  const [category, setCategory] = useState<PlaceCategory>(place.category);
  const [address, setAddress] = useState(place.address);
  const [phone, setPhone] = useState(place.phone ?? "");
  const [notes, setNotes] = useState(place.notes);
  const [saving, setSaving] = useState(false);

  const [onSitePhotos, setOnSitePhotos] = useState<OnSitePhoto[]>([]);
  const [isProcessingPhotos, setIsProcessingPhotos] = useState(false);
  const [photoError, setPhotoError] = useState<string | null>(null);
  const [photoMessage, setPhotoMessage] = useState<string | null>(null);
  // A coordinate read from a photo's EXIF data since the sheet opened —
  // applied on Save instead of immediately, so Cancel still discards it
  // like every other field here.
  const [pendingCoords, setPendingCoords] = useState<{ lat: number; lng: number } | null>(null);
  const uploadPhotosInputRef = useRef<HTMLInputElement>(null);

  const canSubmit = name.trim().length > 0;

  function handleUploadPhotosChange(e: React.ChangeEvent<HTMLInputElement>) {
    const picked = Array.from(e.target.files ?? []);
    if (uploadPhotosInputRef.current) uploadPhotosInputRef.current.value = "";
    if (picked.length === 0) return;
    setOnSitePhotos((prev) => [...prev, ...picked.map((file) => ({ id: crypto.randomUUID(), file }))]);
  }

  function removeOnSitePhoto(id: string) {
    setOnSitePhotos((prev) => prev.filter((p) => p.id !== id));
  }

  /**
   * Sends all accumulated photos to AI in one request (so it can
   * cross-reference them into one result) and uses whatever it finds to
   * fill in fields that are still blank, plus appends any notes found —
   * this only adds information, it never overwrites what's already
   * there. Also reads a coordinate from the photos' own EXIF GPS data
   * (using the first one found) — queued in `pendingCoords` for Save to
   * apply.
   */
  async function fillFromPhotos() {
    if (onSitePhotos.length === 0) return;
    setIsProcessingPhotos(true);
    setPhotoError(null);
    setPhotoMessage(null);

    const photos = onSitePhotos;
    setOnSitePhotos([]);

    let location: { lat: number; lng: number } | null = null;
    for (const photo of photos) {
      const exif = await readPhotoExif(photo.file);
      if (!location && exif.location) location = exif.location;
    }

    let extracted: AIExtractedPlace[] = [];
    let extractionFailureMessage: string | null = null;
    if (apiKey) {
      try {
        const images = await Promise.all(
          photos.map(async ({ file }) => {
            const mediaType = file.type;
            if (!isSupportedImageMediaType(mediaType)) {
              throw new AIExtractionError("That image format isn't supported — try a JPEG or PNG.");
            }
            return { mediaType, base64: await fileToBase64(file) };
          }),
        );
        extracted = await extractPlacesFromImages(images);
      } catch (error) {
        extractionFailureMessage =
          error instanceof AIExtractionError ? error.message : "AI extraction failed.";
      }
    }

    const found = extracted[0] ?? null;
    let filledSomething = false;
    if (found) {
      if (!address.trim() && found.address) {
        setAddress(found.address);
        filledSomething = true;
      }
      if (!phone.trim() && found.telephone) {
        setPhone(found.telephone);
        filledSomething = true;
      }
      if (found.notes) {
        setNotes((prev) => [prev.trim(), found.notes].filter(Boolean).join("\n\n"));
        filledSomething = true;
      }
    }

    if (location) {
      setPendingCoords(location);
    }

    if (extractionFailureMessage) {
      setPhotoError(extractionFailureMessage);
    } else if (!apiKey) {
      setPhotoMessage(
        location
          ? "📍 Location captured from your photo — add an AI extraction API key in Settings to also read details from it."
          : "Add an AI extraction API key in Settings to read details from your photos.",
      );
    } else if (filledSomething && location) {
      setPhotoMessage("✨ Filled in details and captured a location from your photos — review before saving.");
    } else if (filledSomething) {
      setPhotoMessage("✨ Filled in details from your photos — review before saving.");
    } else if (location) {
      setPhotoMessage("📍 Captured a location from your photos — review before saving.");
    } else {
      setPhotoMessage("Didn't find any new details in those photos.");
    }

    setIsProcessingPhotos(false);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setSaving(true);

    const trimmedName = name.trim();
    const trimmedAddress = address.trim();
    const trimmedPhone = phone.trim();
    updatePlace(place.id, {
      name: trimmedName,
      category,
      address: trimmedAddress,
      phone: trimmedPhone || null,
      notes: notes.trim(),
    });

    // A coordinate captured from a photo's own EXIF data is already a
    // real fix — more trustworthy than geocoding an address — so it's
    // used directly instead of the address-change geocode below.
    if (pendingCoords) {
      setPlaceCoords(place.id, pendingCoords, "located");
    } else if (trimmedAddress !== place.address) {
      // Only re-geocode when the address actually changed — otherwise
      // leave the existing coordinates (and geocodeStatus) alone.
      const query = trimmedAddress || trimmedName;
      let located = false;
      try {
        const result = await geocodePlace(query, destination);
        if (result) {
          setPlaceCoords(place.id, { lat: result.lat, lng: result.lng }, "located");
          located = true;
        }
      } catch {
        // fall through to the AI estimate below
      }

      // Best-effort fallback: ask AI for the nearest plausible real
      // address using everything known about the place, then geocode
      // that guess, rather than leaving it unlocated.
      if (!located && apiKey) {
        try {
          const guessedAddress = await guessNearestAddress(destination, {
            name: trimmedName,
            address: trimmedAddress || null,
            telephone: trimmedPhone || null,
            notes: notes.trim() || null,
          });
          if (guessedAddress) {
            const estimate = await geocodePlace(guessedAddress, destination);
            if (estimate) {
              setPlaceCoords(place.id, { lat: estimate.lat, lng: estimate.lng }, "estimated");
              located = true;
            }
          }
        } catch {
          // fall through to "failed" below
        }
      }

      if (!located) {
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

        <div className="rounded-lg border border-dashed border-neutral-300 p-3">
          <label className="mb-1 block text-sm font-medium text-neutral-700">Add info from a photo</label>
          <p className="mb-2 text-xs text-neutral-400">
            Upload a photo of this place (a sign, a menu, ...) and AI reads it to fill in whatever's
            still blank below — it never overwrites what you've already entered. A location read
            from the photo is queued to apply when you save.
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <input
              ref={uploadPhotosInputRef}
              type="file"
              accept="image/*"
              multiple
              onChange={handleUploadPhotosChange}
              className="hidden"
              id="edit-onsite-upload-input"
            />
            <label
              htmlFor="edit-onsite-upload-input"
              className={`cursor-pointer rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50 ${
                isProcessingPhotos ? "pointer-events-none opacity-40" : ""
              }`}
            >
              {onSitePhotos.length === 0 ? "📌 Upload On-Site Photos" : "📌 Add More On-Site Photos"}
            </label>
            {onSitePhotos.map((photo, i) => (
              <span
                key={photo.id}
                className="inline-flex items-center gap-1 rounded-full bg-neutral-100 px-2 py-1 text-xs text-neutral-600"
              >
                {`📌 On-site photo ${i + 1}`}
                <button
                  type="button"
                  onClick={() => removeOnSitePhoto(photo.id)}
                  aria-label={`Remove photo ${i + 1}`}
                  className="text-neutral-400 hover:text-red-500"
                >
                  ×
                </button>
              </span>
            ))}
            {onSitePhotos.length > 0 && (
              <button
                type="button"
                onClick={fillFromPhotos}
                disabled={isProcessingPhotos}
                className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {isProcessingPhotos ? "Reading…" : "✨ Fill In From Photos"}
              </button>
            )}
          </div>
          {(photoError || photoMessage) && (
            <p className={`mt-2 text-xs ${photoError ? "text-amber-600" : "text-neutral-400"}`}>
              {photoError ?? photoMessage}
            </p>
          )}
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
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            Phone <span className="font-normal text-neutral-400">(optional)</span>
          </label>
          <input
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="Phone number"
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
          {saving ? "Saving…" : "Save changes"}
        </button>
      </form>
    </Modal>
  );
}
