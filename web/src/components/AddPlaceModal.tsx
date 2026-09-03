import { useMemo, useRef, useState } from "react";
import { Modal } from "./Modal";
import { InstagramEmbed } from "./InstagramEmbed";
import { geocodePlace } from "../lib/geocode";
import { isInstagramPostUrl, normalizeInstagramUrl } from "../lib/instagram";
import { parsePlaces } from "../lib/captionParser";
import {
  extractPlacesFromImage,
  extractPlacesFromText,
  fileToBase64,
  guessMissingAddresses,
  guessNearestAddress,
  isSupportedImageMediaType,
  AIExtractionError,
  type AIExtractedPlace,
} from "../lib/aiExtract";
import { parseKmlPlaces } from "../lib/kml";
import { selectActiveApiKey, useAISettingsStore } from "../store/useAISettingsStore";
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
  // Set only for places imported from a KML file — they already carry
  // real coordinates from Google Maps, so saving skips geocoding by
  // address/name and uses these directly.
  lat?: number;
  lng?: number;
}

/** Reading more screenshots than this in one AI pass gets slow and costly
 * for what's still just "a few saved posts" — this caps it. */
const MAX_SCREENSHOTS = 3;

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
  const setPlaceCoords = useStore((s) => s.setPlaceCoords);
  const apiKey = useAISettingsStore(selectActiveApiKey);

  const [instagramInput, setInstagramInput] = useState("");
  const [captionText, setCaptionText] = useState("");
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
  const fileInputRef = useRef<HTMLInputElement>(null);
  const kmlInputRef = useRef<HTMLInputElement>(null);

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
    source: "pattern" | "ai",
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
    // a name-only fallback (the parser's last resort: any short,
    // non-hashtag line) can still fire on pure noise, so check for at
    // least one real address rather than just "found a name".
    const withAddress = places.filter((p) => p.address).length;
    const hasAddress = withAddress > 0;
    if (usable.length === 0 || !hasAddress) {
      setExtractResultMessage(null);
      if (source === "pattern") {
        setExtractError(
          apiKey
            ? "Couldn't find a usable address in that text — try ✨ Find places (AI) instead."
            : "Couldn't find any places in that text.",
        );
      } else {
        setExtractError("AI couldn't find a usable address there — try a clearer screenshot, or edit the place below manually.");
      }
    } else {
      setExtractError(null);
      const label = source === "ai" ? "AI" : "Pattern matching";
      setExtractResultMessage(
        `${label} found ${usable.length} place${usable.length === 1 ? "" : "s"} (${withAddress} with an address) — review below before saving.`,
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

  function handleKmlFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setExtractError(null);
    setExtractResultMessage(null);
    if (kmlInputRef.current) kmlInputRef.current.value = "";

    const reader = new FileReader();
    reader.onload = () => {
      const text = reader.result;
      if (typeof text !== "string") {
        setExtractError("Couldn't read that file.");
        return;
      }
      const places = parseKmlPlaces(text);
      const usable = places.filter((p) => p.name);
      if (usable.length === 0) {
        setExtractError("Couldn't find any places in that KML file.");
        return;
      }
      setRows(
        usable.map((p) =>
          makeRow({
            name: p.name ?? "",
            address: p.address ?? "",
            lat: p.lat ?? undefined,
            lng: p.lng ?? undefined,
          }),
        ),
      );
      setExtractResultMessage(
        `Imported ${usable.length} place${usable.length === 1 ? "" : "s"} from KML — review below before saving.`,
      );
    };
    reader.onerror = () => setExtractError("Couldn't read that file.");
    reader.readAsText(file);
  }

  function handlePatternExtract() {
    setExtractError(null);
    setExtractResultMessage(null);
    replaceRowsFromExtraction(parsePlaces(captionText), "pattern");
  }

  async function handleAIExtract() {
    if (!apiKey) return;
    setExtractError(null);
    setExtractResultMessage(null);
    try {
      let results: AIExtractedPlace[];
      if (screenshotFiles.length > 0) {
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
        results = allResults;
      } else if (captionText.trim()) {
        setAiProgress({ current: 0, total: 1 });
        results = await extractPlacesFromText(captionText);
        setAiProgress({ current: 1, total: 1 });
      } else {
        setExtractError("Paste a caption or upload a screenshot first.");
        return;
      }
      replaceRowsFromExtraction(results, "ai");
    } catch (error) {
      setExtractError(error instanceof AIExtractionError ? error.message : "AI extraction failed.");
    } finally {
      setAiProgress(null);
    }
  }

  /**
   * Geocodes a row's own address/name; if that fails and an AI API key is
   * configured, falls back to asking AI for its best guess at the nearest
   * plausible real address (using the row's name, address, phone, and
   * notes as context) and geocodes that instead — marked "estimated"
   * rather than "located" so the UI can flag it as approximate. Only
   * "failed" once both the real geocode and the AI estimate come up
   * empty (or there's no API key to try the estimate with at all).
   */
  async function geocodeAndStore(placeId: string, row: CandidateRow) {
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

      if (row.lat !== undefined && row.lng !== undefined) {
        // Imported from KML — already has real coordinates from Google
        // Maps, so there's nothing to geocode.
        setPlaceCoords(place.id, { lat: row.lat, lng: row.lng }, "located");
        continue;
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
            Caption text <span className="font-normal text-neutral-400">(optional)</span>
          </label>
          <p className="mb-2 text-xs text-neutral-400">
            If a post recommends one place or several, paste the caption below and use free
            pattern matching — or attach a screenshot and let AI read and organize it completely
            (requires an AI extraction API key in Settings; on-device text recognition struggles with
            stylized graphics, so this app doesn't try to guess at photo text itself).
          </p>
          <textarea
            value={captionText}
            onChange={(e) => setCaptionText(e.target.value)}
            rows={3}
            placeholder="Paste the post's caption here…"
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
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
                📷 {screenshotFiles.length === 0 ? "Upload screenshots" : "Add another screenshot"}
              </label>
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

            <span className="mx-1 h-4 w-px bg-neutral-200" />

            <button
              type="button"
              onClick={handlePatternExtract}
              disabled={!captionText.trim()}
              className="rounded-lg bg-neutral-800 px-3 py-1.5 text-xs font-medium text-white hover:bg-neutral-700 disabled:cursor-not-allowed disabled:opacity-40"
            >
              🔍 Find places (free)
            </button>
            {apiKey && (
              <button
                type="button"
                onClick={handleAIExtract}
                disabled={aiProgress !== null || (!captionText.trim() && screenshotFiles.length === 0)}
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

        <div className="rounded-lg border border-dashed border-neutral-300 p-3">
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            Import from Google Maps <span className="font-normal text-neutral-400">(optional)</span>
          </label>
          <p className="mb-2 text-xs text-neutral-400">
            Google has no API for reading a Saved-places list directly — export one as KML from{" "}
            <a
              href="https://mymaps.google.com"
              target="_blank"
              rel="noreferrer"
              className="text-brand-600 underline"
            >
              Google My Maps
            </a>{" "}
            and upload it here. Imported places already carry real coordinates, so they skip
            geocoding entirely.
          </p>
          <input
            ref={kmlInputRef}
            type="file"
            accept=".kml"
            onChange={handleKmlFile}
            className="hidden"
            id="kml-import-input"
          />
          <label
            htmlFor="kml-import-input"
            className="inline-block cursor-pointer rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50"
          >
            📥 Upload a .kml file
          </label>
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
            anything above — use caption text or a screenshot for that. Paste it only if you want
            the original post embedded here for reference.
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
