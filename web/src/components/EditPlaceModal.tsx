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
import { getCurrentLocation } from "../lib/currentLocation";
import { geocodePlace, reverseGeocode } from "../lib/geocode";
import { searchNearbyPlaces, type NearbyPlaceCandidate } from "../lib/nearbyPlaces";
import { selectActiveApiKey, useAISettingsStore } from "../store/useAISettingsStore";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type Place, type PlaceCategory } from "../types";

interface OnSitePhoto {
  id: string;
  file: File;
  // Camera-sourced photos are taken right now, right here — that path
  // uses a live GPS fix instead of the photo's own EXIF/location data,
  // which an uploaded photo (not necessarily taken here or now) relies on.
  source: "camera" | "upload";
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
  const movePlaceToBoard = useStore((s) => s.movePlaceToBoard);
  const trips = useStore((s) => s.trips);
  const apiKey = useAISettingsStore(selectActiveApiKey);

  const [name, setName] = useState(place.name);
  const [boardId, setBoardId] = useState(place.tripId);
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
  // Real nearby places, offered as pickable candidates once a photo's
  // location is known — picking one is an explicit choice, so unlike the
  // AI/reverse-geocode fallbacks above it does overwrite
  // name/address/phone/category with the selection.
  const [nearbyCandidates, setNearbyCandidates] = useState<NearbyPlaceCandidate[]>([]);
  const [hasSearchedNearby, setHasSearchedNearby] = useState(false);
  const [isRefiningNearbySearch, setIsRefiningNearbySearch] = useState(false);
  const uploadPhotosInputRef = useRef<HTMLInputElement>(null);
  const cameraInputRef = useRef<HTMLInputElement>(null);

  // A screenshot of a map app (Google/Naver/Kakao/Apple Maps) showing
  // this place's own info card — read on demand, then shown for review
  // before applying, since (unlike the on-site-photo flow above, which
  // only ever fills in blanks) this is meant to let a wrong/outdated
  // name or address be corrected, which means it has to be allowed to
  // overwrite what's already there.
  const [mapScreenshotFile, setMapScreenshotFile] = useState<File | null>(null);
  const [isReadingMapScreenshot, setIsReadingMapScreenshot] = useState(false);
  const [mapScreenshotError, setMapScreenshotError] = useState<string | null>(null);
  const [mapScreenshotResult, setMapScreenshotResult] = useState<AIExtractedPlace | null>(null);
  const mapScreenshotInputRef = useRef<HTMLInputElement>(null);

  const canSubmit = name.trim().length > 0;

  function handleUploadPhotosChange(e: React.ChangeEvent<HTMLInputElement>) {
    const picked = Array.from(e.target.files ?? []);
    if (uploadPhotosInputRef.current) uploadPhotosInputRef.current.value = "";
    if (picked.length === 0) return;
    setOnSitePhotos((prev) => [
      ...prev,
      ...picked.map((file) => ({ id: crypto.randomUUID(), file, source: "upload" as const })),
    ]);
  }

  function handleCameraChange(e: React.ChangeEvent<HTMLInputElement>) {
    const picked = Array.from(e.target.files ?? []);
    if (cameraInputRef.current) cameraInputRef.current.value = "";
    if (picked.length === 0) return;
    setOnSitePhotos((prev) => [
      ...prev,
      ...picked.map((file) => ({ id: crypto.randomUUID(), file, source: "camera" as const })),
    ]);
  }

  function removeOnSitePhoto(id: string) {
    setOnSitePhotos((prev) => prev.filter((p) => p.id !== id));
  }

  function handleMapScreenshotChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (mapScreenshotInputRef.current) mapScreenshotInputRef.current.value = "";
    if (!file) return;
    setMapScreenshotFile(file);
    setMapScreenshotResult(null);
    setMapScreenshotError(null);
  }

  /**
   * Reads a map app screenshot via AI and shows what it found for
   * review — applying it is a separate, explicit step (applyMapScreenshotResult)
   * since this is the one AI-extraction source in this form that's meant
   * to be able to correct an existing name/address rather than just fill
   * in blanks, so it shouldn't happen silently.
   */
  async function readMapScreenshot() {
    if (!mapScreenshotFile) return;
    if (!apiKey) {
      setMapScreenshotError("Add an AI extraction API key in Settings to read a map screenshot.");
      return;
    }
    setIsReadingMapScreenshot(true);
    setMapScreenshotError(null);
    setMapScreenshotResult(null);
    try {
      const mediaType = mapScreenshotFile.type;
      if (!isSupportedImageMediaType(mediaType)) {
        throw new AIExtractionError("That image format isn't supported — try a JPEG or PNG.");
      }
      const base64 = await fileToBase64(mapScreenshotFile);
      const extracted = await extractPlacesFromImages([{ mediaType, base64 }], "mapScreenshot");
      const found = extracted[0] ?? null;
      if (!found) {
        setMapScreenshotError("Couldn't find a place's info in that screenshot.");
        return;
      }
      setMapScreenshotResult(found);
    } catch (error) {
      setMapScreenshotError(
        error instanceof AIExtractionError ? error.message : "Something went wrong reading that screenshot.",
      );
    } finally {
      setIsReadingMapScreenshot(false);
    }
  }

  function applyMapScreenshotResult() {
    if (!mapScreenshotResult) return;
    setName(mapScreenshotResult.name);
    if (mapScreenshotResult.address) setAddress(mapScreenshotResult.address);
    if (mapScreenshotResult.telephone) setPhone(mapScreenshotResult.telephone);
    if (mapScreenshotResult.notes) {
      setNotes((prev) => [prev.trim(), mapScreenshotResult.notes].filter(Boolean).join("\n\n"));
    }
    setMapScreenshotResult(null);
    setMapScreenshotFile(null);
  }

  function dismissMapScreenshotResult() {
    setMapScreenshotResult(null);
    setMapScreenshotFile(null);
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

    try {
      await fillFromPhotosInner();
    } catch (error) {
      // Belt-and-suspenders: every awaited call in here is already
      // expected to fail gracefully on its own (returning null/empty
      // rather than throwing), but a stuck "Reading…" spinner with no
      // error at all is a much worse failure mode than a generic
      // message — this backstop guarantees the loading state always
      // clears no matter what actually goes wrong below.
      console.error("Fill in from photos failed:", error);
      setPhotoError("Something went wrong reading those photos.");
    } finally {
      setIsProcessingPhotos(false);
    }
  }

  async function fillFromPhotosInner() {
    const photos = onSitePhotos;
    setOnSitePhotos([]);
    setNearbyCandidates([]);

    // A photo taken right now through the camera isn't itself tagged with
    // a location — a live GPS fix stands in for the per-photo EXIF lookup
    // that uploaded photos use instead.
    const hasCameraPhoto = photos.some((p) => p.source === "camera");

    let location: { lat: number; lng: number } | null = null;
    if (hasCameraPhoto) {
      location = await getCurrentLocation();
    }
    for (const photo of photos.filter((p) => p.source === "upload")) {
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
        extracted = await extractPlacesFromImages(images, "onSite");
      } catch (error) {
        extractionFailureMessage =
          error instanceof AIExtractionError ? error.message : "AI extraction failed.";
      }
    }

    // Tracked locally (not read back from the `address` state variable)
    // since setAddress's effect isn't visible until the next render —
    // reading state here after calling it would still see the old value.
    let addressFilled = address.trim().length > 0;

    const found = extracted[0] ?? null;
    let filledSomething = false;
    if (found) {
      if (!addressFilled && found.address) {
        setAddress(found.address);
        addressFilled = true;
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

    // AI extraction only reads text visible in the photo — a photo of a
    // storefront often has none — so a blank address is filled in (never
    // overwritten) from reverse-geocoding the coordinate itself.
    if (location) {
      setPendingCoords(location);
      if (!addressFilled) {
        const reverse = await reverseGeocode(location.lat, location.lng);
        if (reverse) {
          setAddress(reverse.address);
          filledSomething = true;
        }
      }

      // Offer real nearby places to pick from, as a step up from the bare
      // reverse-geocode above — seeded with the category above only if
      // it's been changed from the place's original one, since that's
      // the signal the person actually set it as a hint rather than it
      // just sitting at whatever the place already was.
      setHasSearchedNearby(true);
      const categoryHint = category !== place.category ? category : undefined;
      const candidates = await searchNearbyPlaces(location.lat, location.lng, categoryHint);
      setNearbyCandidates(candidates);
    }

    // `filledSomething` can be true even without an API key (the address
    // may have come from reverse-geocoding the photo's own location, not
    // AI extraction) — checked before the "no API key" message so that
    // case isn't hidden behind it.
    const locationSourceLabel = hasCameraPhoto ? "your current location" : "your photos";
    if (extractionFailureMessage) {
      setPhotoError(extractionFailureMessage);
    } else if (filledSomething && location) {
      setPhotoMessage(
        apiKey
          ? `✨ Filled in details and captured a location from ${locationSourceLabel} — review before saving.`
          : `📍 Filled in the address from ${locationSourceLabel} — add an AI extraction API key in Settings to also read other details from your photos.`,
      );
    } else if (filledSomething) {
      setPhotoMessage("✨ Filled in details from your photos — review before saving.");
    } else if (location) {
      setPhotoMessage(
        apiKey
          ? `📍 Captured a location from ${locationSourceLabel} — review before saving.`
          : `📍 Location captured from ${locationSourceLabel} — add an AI extraction API key in Settings to also read details from your photos.`,
      );
    } else if (!apiKey) {
      setPhotoMessage("Add an AI extraction API key in Settings to read details from your photos.");
    } else {
      setPhotoMessage("Didn't find any new details in those photos.");
    }
  }

  function applyNearbyCandidate(candidate: NearbyPlaceCandidate) {
    setName(candidate.name);
    setAddress(candidate.address ?? "");
    if (candidate.phone) setPhone(candidate.phone);
    setCategory(candidate.category);
    setPendingCoords({ lat: candidate.lat, lng: candidate.lng });
    setNearbyCandidates([]);
    setHasSearchedNearby(false);
  }

  function dismissNearbyCandidates() {
    setNearbyCandidates([]);
    setHasSearchedNearby(false);
  }

  /**
   * When the plain nearby list is too ambiguous to tell which result is
   * the right one, narrowing by a category (restaurant, cafe, ...) the
   * person supplies re-runs the same search scoped to it.
   */
  async function refineNearbySearch(hintCategory: PlaceCategory) {
    if (!pendingCoords) return;
    setIsRefiningNearbySearch(true);
    try {
      const candidates = await searchNearbyPlaces(pendingCoords.lat, pendingCoords.lng, hintCategory);
      setNearbyCandidates(candidates);
    } finally {
      setIsRefiningNearbySearch(false);
    }
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
    if (boardId !== place.tripId) movePlaceToBoard(place.id, boardId);

    // A moved place should geocode against its new board's destination,
    // not the one this modal opened with.
    const effectiveDestination = trips.find((t) => t.id === boardId)?.destination ?? destination;

    // A coordinate captured from a photo's own EXIF data is already a
    // real fix — more trustworthy than geocoding an address — so it's
    // used directly instead of the address-change geocode below.
    if (pendingCoords) {
      setPlaceCoords(place.id, pendingCoords, "located");
    } else if (trimmedAddress !== place.address || boardId !== place.tripId) {
      // Re-geocode when the address changed, or when the place moved to
      // a different board — the same address text can resolve
      // differently once it's disambiguated against a new destination.
      const query = trimmedAddress || trimmedName;
      let located = false;
      try {
        const result = await geocodePlace(query, effectiveDestination);
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
          const guessedAddress = await guessNearestAddress(effectiveDestination, {
            name: trimmedName,
            address: trimmedAddress || null,
            telephone: trimmedPhone || null,
            notes: notes.trim() || null,
          });
          if (guessedAddress) {
            const estimate = await geocodePlace(guessedAddress, effectiveDestination);
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

        {trips.length > 1 && (
          <div>
            <label className="mb-1 block text-sm font-medium text-neutral-700">Board</label>
            <select
              aria-label="Board"
              value={boardId}
              onChange={(e) => setBoardId(e.target.value)}
              className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            >
              {trips.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.coverEmoji} {t.name}
                </option>
              ))}
            </select>
          </div>
        )}

        <div className="rounded-lg border border-dashed border-neutral-300 p-3">
          <label className="mb-1 block text-sm font-medium text-neutral-700">Add info from a photo</label>
          <p className="mb-2 text-xs text-neutral-400">
            Take a photo here or upload one of this place (a sign, a menu, ...) and AI reads it to
            fill in whatever's still blank below — it never overwrites what you've already
            entered. A location read from the photo (or your current location) is queued to apply
            when you save.
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
            <input
              ref={cameraInputRef}
              type="file"
              accept="image/*"
              capture="environment"
              onChange={handleCameraChange}
              className="hidden"
              id="edit-onsite-camera-input"
            />
            <label
              htmlFor="edit-onsite-camera-input"
              className={`cursor-pointer rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50 ${
                isProcessingPhotos ? "pointer-events-none opacity-40" : ""
              }`}
            >
              {onSitePhotos.length === 0 ? "📷 Take Photo Here" : "📷 Take Another Photo"}
            </label>
            {onSitePhotos.map((photo, i) => (
              <span
                key={photo.id}
                className="inline-flex items-center gap-1 rounded-full bg-neutral-100 px-2 py-1 text-xs text-neutral-600"
              >
                {photo.source === "camera" ? `📷 Photo ${i + 1}` : `📌 On-site photo ${i + 1}`}
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
          {!photoError && !photoMessage && onSitePhotos.length > 0 && !apiKey && (
            <p className="mt-2 text-xs text-neutral-400">
              Add an AI extraction API key in Settings to read these photos — AI reads photos
              completely, since on-device text recognition struggles with stylized graphics.
            </p>
          )}
          {hasSearchedNearby && (
            <div className="mt-2 rounded-lg border border-dashed border-brand-300 bg-brand-50/40 p-2">
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
              {nearbyCandidates.length > 0 && (
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
              )}
              <div className="mt-2 flex flex-wrap items-center gap-1">
                <span className="text-xs text-neutral-400">
                  {nearbyCandidates.length === 0 ? "No matches — not sure what it is? Narrow by type:" : "Not the right one? Narrow by type:"}
                </span>
                {PLACE_CATEGORIES.map((c) => (
                  <button
                    key={c.value}
                    type="button"
                    onClick={() => refineNearbySearch(c.value)}
                    disabled={isRefiningNearbySearch}
                    className="rounded-full border border-neutral-300 bg-white px-2 py-0.5 text-xs text-neutral-600 hover:border-brand-400 hover:bg-brand-50 disabled:opacity-40"
                  >
                    {c.label}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="rounded-lg border border-dashed border-neutral-300 p-3">
          <label className="mb-1 block text-sm font-medium text-neutral-700">Correct info from a map screenshot</label>
          <p className="mb-2 text-xs text-neutral-400">
            Upload a screenshot of this place's info card from a map app (Google Maps, Naver Map,
            Kakao Map, ...) and AI reads its name, address, and phone off the screen — unlike the
            photo above, this can correct a name or address that's already filled in, not just add
            to a blank one, so review the result before applying it.
          </p>
          <div className="flex flex-wrap items-center gap-2">
            <input
              ref={mapScreenshotInputRef}
              type="file"
              accept="image/*"
              onChange={handleMapScreenshotChange}
              className="hidden"
              id="edit-map-screenshot-input"
            />
            <label
              htmlFor="edit-map-screenshot-input"
              className={`cursor-pointer rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50 ${
                isReadingMapScreenshot ? "pointer-events-none opacity-40" : ""
              }`}
            >
              🗺️ {mapScreenshotFile ? "Change Map Screenshot" : "Upload Map Screenshot"}
            </label>
            {mapScreenshotFile && (
              <span className="inline-flex items-center gap-1 rounded-full bg-neutral-100 px-2 py-1 text-xs text-neutral-600">
                {mapScreenshotFile.name}
                <button
                  type="button"
                  onClick={dismissMapScreenshotResult}
                  aria-label="Remove map screenshot"
                  className="text-neutral-400 hover:text-red-500"
                >
                  ×
                </button>
              </span>
            )}
            {mapScreenshotFile && !mapScreenshotResult && (
              <button
                type="button"
                onClick={readMapScreenshot}
                disabled={isReadingMapScreenshot}
                className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {isReadingMapScreenshot ? "Reading…" : "🗺️ Read Map Screenshot"}
              </button>
            )}
          </div>
          {mapScreenshotError && <p className="mt-2 text-xs text-amber-600">{mapScreenshotError}</p>}
          {mapScreenshotResult && (
            <div className="mt-2 rounded-lg border border-dashed border-brand-300 bg-brand-50/40 p-2">
              <p className="mb-1.5 text-xs font-medium text-neutral-700">Found on the map:</p>
              <div className="mb-2 rounded-md border border-neutral-200 bg-white px-2 py-1.5 text-xs">
                <span className="font-medium text-neutral-700">{mapScreenshotResult.name}</span>
                {mapScreenshotResult.address && (
                  <span className="block text-neutral-400">{mapScreenshotResult.address}</span>
                )}
                {mapScreenshotResult.telephone && (
                  <span className="block text-neutral-400">{mapScreenshotResult.telephone}</span>
                )}
              </div>
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={applyMapScreenshotResult}
                  className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600"
                >
                  Apply
                </button>
                <button
                  type="button"
                  onClick={dismissMapScreenshotResult}
                  className="rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50"
                >
                  Dismiss
                </button>
              </div>
            </div>
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
