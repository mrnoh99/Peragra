import { useMemo, useRef, useState } from "react";
import { Modal } from "./Modal";
import { InstagramEmbed } from "./InstagramEmbed";
import { readPhotoExif } from "../lib/photoExif";
import { geocodePlace, reverseGeocode } from "../lib/geocode";
import { searchNearbyPlaces, type NearbyPlaceCandidate } from "../lib/googleNearbyPlaces";
import { isInstagramPostUrl, normalizeInstagramUrl } from "../lib/instagram";
import {
  extractPlacesFromImage,
  extractPlacesFromImages,
  fileToBase64,
  guessMissingAddresses,
  guessNearestAddress,
  isSupportedImageMediaType,
  AIExtractionError,
  type AIExtractedPlace,
} from "../lib/aiExtract";
import { selectActiveApiKey, useAISettingsStore } from "../store/useAISettingsStore";
import { useMapSettingsStore } from "../store/useMapSettingsStore";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type PlaceCategory } from "../types";

interface CandidateRow {
  id: string;
  selected: boolean;
  name: string;
  address: string;
  phone: string;
  // Anything else recognized about this specific place (hours, price, a
  // recommended item, why it was recommended, ...) — combined with the
  // form's own manual Notes field at save time, not a replacement for it.
  notes: string;
  category: PlaceCategory;
  // Set when this row came from the on-site photo flow rather than
  // AI-extracted address text — geocodeAndStore uses these directly
  // instead of geocoding, since a photo's own location is more
  // trustworthy than any address string.
  manualLat?: number;
  manualLng?: number;
  // The moment the on-site photo was actually taken, if this row came
  // from that flow — used as the saved place's createdAt instead of
  // whenever Save happens to be clicked, in case reviewing the row (or
  // waiting on AI extraction) took a while.
  capturedAt?: number;
}

/** Reading more screenshots than this in one AI pass gets slow and costly
 * for what's still just "a few saved posts" — this caps it. */
const MAX_SCREENSHOTS = 10;

interface OnSitePhoto {
  id: string;
  file: File;
}

function makeRow(partial?: Partial<CandidateRow>): CandidateRow {
  return {
    id: crypto.randomUUID(),
    selected: true,
    name: "",
    address: "",
    phone: "",
    notes: "",
    category: "restaurant",
    ...partial,
  };
}

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
  const updatePlace = useStore((s) => s.updatePlace);
  const setPlaceCoords = useStore((s) => s.setPlaceCoords);
  const apiKey = useAISettingsStore(selectActiveApiKey);

  const [instagramInput, setInstagramInput] = useState("");
  const [notes, setNotes] = useState("");
  const [rows, setRows] = useState<CandidateRow[]>([makeRow()]);
  const [saving, setSaving] = useState(false);

  const [screenshotFiles, setScreenshotFiles] = useState<File[]>([]);
  /** Set while an AI extraction call is in flight; `total` > 1 when
   * reading multiple screenshots one at a time. */
  const [aiProgress, setAiProgress] = useState<{ current: number; total: number } | null>(null);
  const [extractError, setExtractError] = useState<string | null>(null);
  const [extractResultMessage, setExtractResultMessage] = useState<string | null>(null);
  const [isGuessingAddresses, setIsGuessingAddresses] = useState(false);
  const [isCapturingOnSite, setIsCapturingOnSite] = useState(false);
  const [onSitePhotos, setOnSitePhotos] = useState<OnSitePhoto[]>([]);
  // Real nearby places (from Google's Places API) offered as pickable
  // candidates for the blank row a photo's GPS fix alone produced — set
  // only when that search actually found something, and only relevant to
  // that one row (it's the only case where the row has no AI-found name
  // to already trust).
  const [nearbyCandidates, setNearbyCandidates] = useState<NearbyPlaceCandidate[]>([]);
  const [nearbyCandidateRowId, setNearbyCandidateRowId] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const uploadPhotosInputRef = useRef<HTMLInputElement>(null);

  const instagramUrl = isInstagramPostUrl(instagramInput)
    ? normalizeInstagramUrl(instagramInput)
    : null;

  const selectedCount = useMemo(() => rows.filter((r) => r.selected && r.name.trim()).length, [rows]);
  const canSubmit = selectedCount > 0;

  function updateRow(id: string, patch: Partial<CandidateRow>) {
    setRows((prev) => prev.map((r) => (r.id === id ? { ...r, ...patch } : r)));
  }

  function removeRow(id: string) {
    setRows((prev) => prev.filter((r) => r.id !== id));
  }

  function applyCategoryToSelected(category: PlaceCategory) {
    setRows((prev) => prev.map((r) => (r.selected ? { ...r, category } : r)));
  }

  function applyNearbyCandidate(candidate: NearbyPlaceCandidate) {
    if (!nearbyCandidateRowId) return;
    updateRow(nearbyCandidateRowId, {
      name: candidate.name,
      address: candidate.address ?? "",
      phone: candidate.phone ?? "",
      category: candidate.category,
      manualLat: candidate.lat,
      manualLng: candidate.lng,
    });
    setNearbyCandidates([]);
    setNearbyCandidateRowId(null);
  }

  function dismissNearbyCandidates() {
    setNearbyCandidates([]);
    setNearbyCandidateRowId(null);
  }

  /**
   * Best-effort follow-up to extraction: for rows a caption named but never
   * gave an address, ask AI to guess one from its general knowledge of the
   * destination rather than leaving the place unaddressed (and therefore
   * hard to geocode accurately). Silently a no-op without an API key.
   */
  async function fillMissingAddressesWithAI(targets: { id: string; name: string }[]) {
    if (!apiKey || targets.length === 0) return;
    setIsGuessingAddresses(true);
    try {
      const guesses = await guessMissingAddresses(destination, targets.map((t) => t.name));
      const filledCount = guesses.filter((g) => g !== null).length;
      if (filledCount > 0) {
        setRows((prev) =>
          prev.map((r) => {
            const idx = targets.findIndex((t) => t.id === r.id);
            const guess = idx === -1 ? null : guesses[idx];
            return guess ? { ...r, address: guess } : r;
          }),
        );
        setExtractError(null);
        setExtractResultMessage(
          `✨ AI guessed an address for ${filledCount} place${filledCount === 1 ? "" : "s"} that didn't have one — double-check before saving.`,
        );
      }
    } catch {
      // Best effort — leave those rows addressless if the guess call
      // itself fails; the existing extract result/error message stands.
    } finally {
      setIsGuessingAddresses(false);
    }
  }

  function replaceRowsFromExtraction(
    places: {
      name: string | null;
      address: string | null;
      telephone?: string | null;
      notes?: string | null;
    }[],
  ) {
    const usable = places.filter((p) => p.name);
    let newRows: CandidateRow[] = [];
    if (usable.length > 0) {
      newRows = usable.map((p) =>
        makeRow({
          name: p.name ?? "",
          address: p.address ?? "",
          phone: p.telephone ?? "",
          notes: p.notes ?? "",
        }),
      );
      setRows(newRows);
    }

    // The whole point of extraction is getting an address onto the map —
    // a name-only fallback can still fire on pure noise, so check for at
    // least one real address rather than just "found a name".
    const withAddress = places.filter((p) => p.address).length;
    const hasAddress = withAddress > 0;
    if (usable.length === 0 || !hasAddress) {
      setExtractResultMessage(null);
      setExtractError("AI couldn't find a usable address there — try a clearer screenshot, or edit the place below manually.");
    } else {
      setExtractError(null);
      setExtractResultMessage(
        `AI found ${usable.length} place${usable.length === 1 ? "" : "s"} (${withAddress} with an address) — review below before saving.`,
      );
    }

    if (apiKey) {
      const targets = newRows.filter((r) => !r.address.trim()).map((r) => ({ id: r.id, name: r.name }));
      if (targets.length > 0) {
        void fillMissingAddressesWithAI(targets);
      }
    }
  }

  function handleScreenshotChange(e: React.ChangeEvent<HTMLInputElement>) {
    const picked = Array.from(e.target.files ?? []);
    if (picked.length === 0) return;
    setScreenshotFiles((prev) => [...prev, ...picked].slice(0, MAX_SCREENSHOTS));
    setExtractError(null);
    setExtractResultMessage(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  }

  function removeScreenshot(index: number) {
    setScreenshotFiles((prev) => prev.filter((_, i) => i !== index));
  }

  async function handleAIExtract() {
    if (!apiKey || screenshotFiles.length === 0) return;
    setExtractError(null);
    setExtractResultMessage(null);
    try {
      // Read one screenshot at a time (rather than in parallel) so
      // progress reflects real completions, not just requests fired.
      const allResults: AIExtractedPlace[] = [];
      setAiProgress({ current: 0, total: screenshotFiles.length });
      for (const file of screenshotFiles) {
        const mediaType = file.type;
        if (!isSupportedImageMediaType(mediaType)) {
          throw new AIExtractionError("That image format isn't supported — try a JPEG or PNG.");
        }
        const base64 = await fileToBase64(file);
        const fileResults = await extractPlacesFromImage(base64, mediaType);
        allResults.push(...fileResults);
        setAiProgress((prev) => (prev ? { current: prev.current + 1, total: prev.total } : prev));
      }
      replaceRowsFromExtraction(allResults);
    } catch (error) {
      setExtractError(error instanceof AIExtractionError ? error.message : "AI extraction failed.");
    } finally {
      setAiProgress(null);
    }
  }

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
   * The "Log This Place" flow: read each accumulated photo's own EXIF
   * GPS/timestamp (using the first location and earliest time found across
   * the batch — a photo may lack either), then kick off an AI extraction
   * over all the photos in one request (so the model can cross-reference
   * them — e.g. a storefront sign for the name, a menu photo for prices —
   * into one consolidated result), then replace the candidate rows with
   * whatever AI found (or one blank row to fill in by hand if there's no
   * AI key configured) — all tagged with a coordinate/time so
   * geocodeAndStore and handleSubmit use them directly instead of
   * geocoding an address.
   */
  async function captureOnSitePlace() {
    if (onSitePhotos.length === 0) return;
    setIsCapturingOnSite(true);
    setExtractError(null);
    setExtractResultMessage(null);

    const photos = onSitePhotos;
    setOnSitePhotos([]);

    let location: { lat: number; lng: number } | null = null;
    let capturedAt: number | null = null;
    for (const photo of photos) {
      const exif = await readPhotoExif(photo.file);
      if (!location && exif.location) location = exif.location;
      if (exif.capturedAt !== null && (capturedAt === null || exif.capturedAt < capturedAt)) {
        capturedAt = exif.capturedAt;
      }
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
          error instanceof AIExtractionError
            ? error.message
            : "AI extraction failed — add the place details manually below.";
      }
    }

    const newRows: CandidateRow[] =
      extracted.length === 0
        ? [makeRow({ manualLat: location?.lat, manualLng: location?.lng, capturedAt: capturedAt ?? undefined })]
        : extracted.map((p) =>
            makeRow({
              name: p.name ?? "",
              address: p.address ?? "",
              phone: p.telephone ?? "",
              notes: p.notes ?? "",
              manualLat: location?.lat,
              manualLng: location?.lng,
              capturedAt: capturedAt ?? undefined,
            }),
          );

    // AI extraction only reads text visible in the photo — a photo of a
    // storefront often has none — so a blank address/name is filled in
    // (never overwritten) from reverse-geocoding the coordinate itself.
    let foundNameFromLocation = false;
    if (location) {
      const reverse = await reverseGeocode(location.lat, location.lng);
      if (reverse) {
        for (const row of newRows) {
          if (!row.address.trim()) row.address = reverse.address;
          if (!row.name.trim() && reverse.name) {
            row.name = reverse.name;
            foundNameFromLocation = true;
          }
        }
      }
    }
    setRows(newRows);

    // Offer real nearby places to pick from, as a step up from the bare
    // reverse-geocode above — only worth asking when AI found nothing on
    // its own (there's exactly one blank row) and Google Places access is
    // actually configured.
    setNearbyCandidates([]);
    setNearbyCandidateRowId(null);
    if (extracted.length === 0 && location) {
      const { mapProvider, googleMapsApiKey } = useMapSettingsStore.getState();
      if (mapProvider === "google" && googleMapsApiKey) {
        const candidates = await searchNearbyPlaces(location.lat, location.lng, googleMapsApiKey);
        if (candidates.length > 0) {
          setNearbyCandidates(candidates);
          setNearbyCandidateRowId(newRows[0].id);
        }
      }
    }

    if (extractionFailureMessage) {
      setExtractError(extractionFailureMessage);
    } else if (!location) {
      setExtractError("Couldn't find location info in those photos — add an address below, or upload a photo that has it.");
    } else if (extracted.length === 0) {
      setExtractResultMessage(
        foundNameFromLocation
          ? "📍 Found a place at your photos' location — review below before saving."
          : "📍 Read the location from your photos — fill in the place details below.",
      );
    } else {
      setExtractResultMessage(
        `📍 Read the location from your photos and found ${extracted.length} place${extracted.length === 1 ? "" : "s"} — review below before saving.`,
      );
    }

    setIsCapturingOnSite(false);
  }

  /**
   * Geocodes a row's own address/name; if that fails and an AI API key is
   * configured, falls back to asking AI for its best guess at the nearest
   * plausible real address (using the row's name, address, phone, and
   * notes as context) and geocodes that instead — marked "estimated"
   * rather than "located" so the UI can flag it as approximate. Only
   * "failed" once both the real geocode and the AI estimate come up
   * empty (or there's no API key to try the estimate with at all).
   *
   * A row from the on-site photo flow already has a real location fix, which is
   * more trustworthy than geocoding any address text, so that's used
   * directly instead — skipping geocoding entirely.
   */
  async function geocodeAndStore(placeId: string, row: CandidateRow) {
    if (row.manualLat !== undefined && row.manualLng !== undefined) {
      setPlaceCoords(placeId, { lat: row.manualLat, lng: row.manualLng }, "located");
      return;
    }

    const query = row.address.trim() || row.name.trim();
    try {
      const result = await geocodePlace(query, destination);
      if (result) {
        setPlaceCoords(placeId, { lat: result.lat, lng: result.lng }, "located");
        return;
      }
    } catch {
      // fall through to the AI estimate below
    }

    if (apiKey) {
      try {
        const guessedAddress = await guessNearestAddress(destination, {
          name: row.name.trim(),
          address: row.address.trim() || null,
          telephone: row.phone.trim() || null,
          notes: row.notes.trim() || null,
        });
        if (guessedAddress) {
          const estimate = await geocodePlace(guessedAddress, destination);
          if (estimate) {
            setPlaceCoords(placeId, { lat: estimate.lat, lng: estimate.lng }, "estimated");
            return;
          }
        }
      } catch {
        // fall through to "failed" below
      }
    }

    setPlaceCoords(placeId, null, "failed");
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const toSave = rows.filter((r) => r.selected && r.name.trim());
    if (toSave.length === 0) return;
    setSaving(true);

    for (const row of toSave) {
      const combinedNotes = [row.notes.trim(), notes.trim()].filter(Boolean).join("\n\n");
      const place = addPlace({
        tripId,
        name: row.name.trim(),
        category: row.category,
        address: row.address.trim(),
        phone: row.phone.trim() || null,
        notes: combinedNotes,
        instagramUrl,
        collectionIds: defaultCollectionId ? [defaultCollectionId] : [],
      });
      if (row.capturedAt !== undefined) {
        updatePlace(place.id, { createdAt: row.capturedAt });
      }

      await geocodeAndStore(place.id, row);
    }

    setSaving(false);
    onClose();
  }

  return (
    <Modal title="Save places" onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="rounded-lg border border-dashed border-neutral-300 p-3">
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            Photos
          </label>
          <p className="mb-2 text-xs text-neutral-400">
            Attach up to {MAX_SCREENSHOTS} screenshots of a post and let AI read and organize them
            completely. Or, for a place you want to log with its own location: upload one or more
            photos of it (a sign, a menu, ...) and tap Log This Place — AI cross-references them
            all into one result, and its location and time come from the photos' own data
            (requires an AI extraction API key in Settings; on-device text recognition struggles
            with stylized graphics, so this app doesn't try to guess at photo text itself).
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              multiple
              onChange={handleScreenshotChange}
              className="hidden"
              id="caption-screenshot-input"
            />
            {screenshotFiles.length < MAX_SCREENSHOTS && (
              <label
                htmlFor="caption-screenshot-input"
                className="cursor-pointer rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50"
              >
                🖼️ {screenshotFiles.length === 0 ? "Upload screenshots" : "Add another screenshot"}
              </label>
            )}
            <input
              ref={uploadPhotosInputRef}
              type="file"
              accept="image/*"
              multiple
              onChange={handleUploadPhotosChange}
              className="hidden"
              id="on-site-upload-input"
            />
            <label
              htmlFor="on-site-upload-input"
              className={`cursor-pointer rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50 ${
                isCapturingOnSite ? "pointer-events-none opacity-40" : ""
              }`}
            >
              {isCapturingOnSite
                ? "Reading photos…"
                : onSitePhotos.length === 0
                  ? "📌 Upload On-Site Photos"
                  : "📌 Add More On-Site Photos"}
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
                onClick={captureOnSitePlace}
                disabled={isCapturingOnSite}
                className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {isCapturingOnSite ? "Logging…" : "📍 Log This Place"}
              </button>
            )}
            {screenshotFiles.map((file, i) => (
              <span
                key={`${file.name}-${i}`}
                className="inline-flex items-center gap-1 rounded-full bg-neutral-100 px-2 py-1 text-xs text-neutral-600"
              >
                {file.name}
                <button
                  type="button"
                  onClick={() => removeScreenshot(i)}
                  aria-label={`Remove ${file.name}`}
                  className="text-neutral-400 hover:text-red-500"
                >
                  ×
                </button>
              </span>
            ))}

            {apiKey && (
              <button
                type="button"
                onClick={handleAIExtract}
                disabled={aiProgress !== null || screenshotFiles.length === 0}
                className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {aiProgress
                  ? aiProgress.total > 1
                    ? `Reading screenshot ${Math.min(aiProgress.current + 1, aiProgress.total)}/${aiProgress.total}…`
                    : "Asking AI…"
                  : "✨ Find places (AI)"}
              </button>
            )}
          </div>
          {screenshotFiles.length > 0 && screenshotFiles.length < MAX_SCREENSHOTS && (
            <p className="mt-2 text-xs text-neutral-400">Up to {MAX_SCREENSHOTS} screenshots.</p>
          )}
          {screenshotFiles.length > 0 && !apiKey && (
            <p className="mt-2 text-xs text-neutral-400">
              Add an AI extraction API key in Settings to read these screenshots — AI reads photos
              completely, since on-device text recognition struggles with stylized graphics.
            </p>
          )}
        </div>

        {aiProgress && aiProgress.total > 1 && (
          <div className="h-1 w-full overflow-hidden rounded-full bg-neutral-100">
            <div
              className="h-full rounded-full bg-brand-500 transition-all"
              style={{ width: `${(aiProgress.current / aiProgress.total) * 100}%` }}
            />
          </div>
        )}

        {(extractResultMessage || extractError || isGuessingAddresses) && (
          <p className={`text-xs ${extractError ? "text-amber-600" : "text-neutral-400"}`}>
            {extractError ?? (isGuessingAddresses ? "✨ AI is guessing addresses for places without one…" : extractResultMessage)}
          </p>
        )}

        {nearbyCandidates.length > 0 && (
          <div className="rounded-lg border border-dashed border-brand-300 bg-brand-50/40 p-3">
            <div className="mb-1.5 flex items-center justify-between gap-2">
              <p className="text-xs font-medium text-neutral-700">📍 Is it one of these nearby places?</p>
              <button
                type="button"
                onClick={dismissNearbyCandidates}
                className="text-xs text-neutral-400 hover:text-neutral-600"
              >
                Dismiss
              </button>
            </div>
            <div className="space-y-1">
              {nearbyCandidates.map((candidate) => (
                <button
                  key={candidate.placeId}
                  type="button"
                  onClick={() => applyNearbyCandidate(candidate)}
                  className="block w-full rounded-md border border-neutral-200 bg-white px-2 py-1.5 text-left text-xs hover:border-brand-400 hover:bg-brand-50"
                >
                  <span className="font-medium text-neutral-700">{candidate.name}</span>
                  {candidate.address && <span className="block text-neutral-400">{candidate.address}</span>}
                </button>
              ))}
            </div>
          </div>
        )}

        <div>
          <div className="mb-1 flex flex-wrap items-center justify-between gap-2">
            <label className="block text-sm font-medium text-neutral-700">
              Places to save ({selectedCount} selected)
            </label>
            <div className="flex items-center gap-2">
              <select
                value=""
                disabled={selectedCount === 0}
                onChange={(e) => {
                  if (e.target.value) applyCategoryToSelected(e.target.value as PlaceCategory);
                }}
                className="rounded-lg border border-neutral-300 px-2 py-1 text-xs focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-40"
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
              <button
                type="button"
                onClick={() => setRows((prev) => [...prev, makeRow()])}
                className="text-xs font-medium text-brand-600 hover:underline"
              >
                + Add place
              </button>
            </div>
          </div>
          <div className="space-y-2">
            {rows.map((row) => (
              <div key={row.id} className="rounded-lg border border-neutral-200 p-2.5">
                <div className="flex items-start gap-2">
                  <input
                    type="checkbox"
                    checked={row.selected}
                    onChange={(e) => updateRow(row.id, { selected: e.target.checked })}
                    className="mt-2"
                  />
                  <div className="flex-1 space-y-1.5">
                    <input
                      value={row.name}
                      onChange={(e) => updateRow(row.id, { name: e.target.value })}
                      placeholder="Place name"
                      className="w-full rounded-md border border-neutral-300 px-2 py-1.5 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                    />
                    <div className="flex gap-1.5">
                      <input
                        value={row.address}
                        onChange={(e) => updateRow(row.id, { address: e.target.value })}
                        placeholder="Address (improves map accuracy)"
                        className="w-full min-w-0 rounded-md border border-neutral-300 px-2 py-1.5 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                      />
                      <select
                        value={row.category}
                        onChange={(e) =>
                          updateRow(row.id, { category: e.target.value as PlaceCategory })
                        }
                        className="shrink-0 rounded-md border border-neutral-300 px-2 py-1.5 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                      >
                        {PLACE_CATEGORIES.map((c) => (
                          <option key={c.value} value={c.value}>
                            {c.label}
                          </option>
                        ))}
                      </select>
                    </div>
                    <input
                      value={row.phone}
                      onChange={(e) => updateRow(row.id, { phone: e.target.value })}
                      placeholder="Phone (optional)"
                      className="w-full rounded-md border border-neutral-300 px-2 py-1.5 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                    />
                    <input
                      value={row.notes}
                      onChange={(e) => updateRow(row.id, { notes: e.target.value })}
                      placeholder="Other details (hours, menu, why recommended, ...)"
                      className="w-full rounded-md border border-neutral-300 px-2 py-1.5 text-sm text-neutral-600 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                    />
                    {row.manualLat !== undefined && (
                      <p className="text-xs text-neutral-400">📍 Using a captured location</p>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => removeRow(row.id)}
                    className="mt-1 text-neutral-400 hover:text-red-500"
                    aria-label="Remove"
                  >
                    ✕
                  </button>
                </div>
              </div>
            ))}
            {rows.length === 0 && (
              <p className="rounded-lg border border-dashed border-neutral-300 py-4 text-center text-xs text-neutral-400">
                No places yet — add one above.
              </p>
            )}
          </div>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            Instagram post link{" "}
            <span className="font-normal text-neutral-400">(optional, just a reference)</span>
          </label>
          <input
            value={instagramInput}
            onChange={(e) => setInstagramInput(e.target.value)}
            placeholder="https://www.instagram.com/p/..."
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
          <p className="mt-1 text-xs text-neutral-400">
            Instagram doesn't let apps read a post's info from its link, so this doesn't fill in
            anything above — attach a screenshot for that. Paste it only if you want the original
            post embedded here for reference.
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

        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            Notes <span className="font-normal text-neutral-400">(applies to all above)</span>
          </label>
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
          {saving
            ? "Saving & locating…"
            : `Save ${selectedCount} place${selectedCount === 1 ? "" : "s"}`}
        </button>
      </form>
    </Modal>
  );
}
