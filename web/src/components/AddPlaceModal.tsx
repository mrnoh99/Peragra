import { useMemo, useRef, useState } from "react";
import { Modal } from "./Modal";
import { InstagramEmbed } from "./InstagramEmbed";
import { geocodePlace } from "../lib/geocode";
import { isInstagramPostUrl, normalizeInstagramUrl } from "../lib/instagram";
import { parsePlaces } from "../lib/captionParser";
import { recognizeCaptionImage } from "../lib/ocr";
import {
  extractPlacesFromImage,
  extractPlacesFromText,
  fileToBase64,
  isSupportedImageMediaType,
  AIExtractionError,
} from "../lib/aiExtract";
import { useAISettingsStore } from "../store/useAISettingsStore";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type PlaceCategory } from "../types";

interface CandidateRow {
  id: string;
  selected: boolean;
  name: string;
  address: string;
  category: PlaceCategory;
}

function makeRow(partial?: Partial<CandidateRow>): CandidateRow {
  return {
    id: crypto.randomUUID(),
    selected: true,
    name: "",
    address: "",
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
  const apiKey = useAISettingsStore((s) => s.apiKey);

  const [instagramInput, setInstagramInput] = useState("");
  const [captionText, setCaptionText] = useState("");
  const [notes, setNotes] = useState("");
  const [rows, setRows] = useState<CandidateRow[]>([makeRow()]);
  const [saving, setSaving] = useState(false);

  const [screenshotFile, setScreenshotFile] = useState<File | null>(null);
  const [ocrLoading, setOcrLoading] = useState(false);
  const [aiLoading, setAiLoading] = useState(false);
  const [extractError, setExtractError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

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

  function replaceRowsFromExtraction(
    places: { name: string | null; address: string | null }[],
    source: "pattern" | "ai",
  ) {
    const usable = places.filter((p) => p.name);
    if (usable.length > 0) {
      setRows(usable.map((p) => makeRow({ name: p.name ?? "", address: p.address ?? "" })));
    }

    // The whole point of extraction is getting an address onto the map —
    // a name-only fallback (the parser's last resort: any short,
    // non-hashtag line) can still fire on pure noise, so check for at
    // least one real address rather than just "found a name". OCR reads
    // plain-text screenshots reliably, but garbles decorative text baked
    // into a photo (a Reels cover, a graphic with a title overlay) into
    // exactly this kind of nonsense fragment — confirmed by testing. When
    // that's the likely cause, point at AI extraction, which reads the
    // image directly instead of chaining through OCR. (Not shown when AI
    // extraction itself is what just failed.)
    const hasAddress = places.some((p) => p.address);
    if (usable.length === 0 || !hasAddress) {
      if (source === "pattern" && screenshotFile && !apiKey) {
        setExtractError(
          "Couldn't find a usable address in that text. This often happens with stylized " +
            "graphics (like a Reels cover) where text recognition struggles — add an Anthropic " +
            "API key in Settings to extract with AI instead, which reads the image directly.",
        );
      } else if (source === "pattern" && screenshotFile && apiKey) {
        setExtractError(
          "Couldn't find a usable address in that text — try ✨ Find places (AI) instead, it " +
            "reads the image directly rather than relying on text recognition.",
        );
      } else {
        setExtractError("Couldn't find any places in that text.");
      }
    }
  }

  async function handleScreenshotChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setScreenshotFile(file);
    setExtractError(null);
    setOcrLoading(true);
    try {
      const text = await recognizeCaptionImage(file);
      if (text) {
        setCaptionText((prev) => (prev.trim() ? `${prev}\n${text}` : text));
      }
    } catch {
      // OCR is just a convenience for the free pattern-match path; AI
      // extraction can still use the image directly via vision.
    } finally {
      setOcrLoading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  function handlePatternExtract() {
    setExtractError(null);
    replaceRowsFromExtraction(parsePlaces(captionText), "pattern");
  }

  async function handleAIExtract() {
    if (!apiKey) return;
    setExtractError(null);
    setAiLoading(true);
    try {
      let results;
      if (screenshotFile) {
        const mediaType = screenshotFile.type;
        if (!isSupportedImageMediaType(mediaType)) {
          throw new AIExtractionError("That image format isn't supported — try a JPEG or PNG.");
        }
        const base64 = await fileToBase64(screenshotFile);
        results = await extractPlacesFromImage(apiKey, base64, mediaType);
      } else if (captionText.trim()) {
        results = await extractPlacesFromText(apiKey, captionText);
      } else {
        setExtractError("Paste a caption or upload a screenshot first.");
        return;
      }
      replaceRowsFromExtraction(results, "ai");
    } catch (error) {
      setExtractError(error instanceof AIExtractionError ? error.message : "AI extraction failed.");
    } finally {
      setAiLoading(false);
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const toSave = rows.filter((r) => r.selected && r.name.trim());
    if (toSave.length === 0) return;
    setSaving(true);

    for (const row of toSave) {
      const place = addPlace({
        tripId,
        name: row.name.trim(),
        category: row.category,
        address: row.address.trim(),
        notes: notes.trim(),
        instagramUrl,
        collectionIds: defaultCollectionId ? [defaultCollectionId] : [],
      });

      try {
        const query = row.address.trim() || row.name.trim();
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
    <Modal title="Save places" onClose={onClose}>
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
            If a post recommends one place or several, paste the caption below — or upload a
            screenshot of it — and extract them into the list below to review before saving.
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
              onChange={handleScreenshotChange}
              className="hidden"
              id="caption-screenshot-input"
            />
            <label
              htmlFor="caption-screenshot-input"
              className="cursor-pointer rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50"
            >
              📷 {screenshotFile ? "Replace screenshot" : "Upload a screenshot"}
            </label>
            {ocrLoading && <span className="text-xs text-neutral-400">Reading text…</span>}
            {screenshotFile && !ocrLoading && (
              <span className="text-xs text-neutral-400">{screenshotFile.name}</span>
            )}

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
                disabled={aiLoading || (!captionText.trim() && !screenshotFile)}
                className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {aiLoading ? "Asking AI…" : "✨ Find places (AI)"}
              </button>
            )}
          </div>
          {extractError && <p className="mt-2 text-xs text-amber-600">{extractError}</p>}
        </div>

        <div>
          <div className="mb-1 flex items-center justify-between">
            <label className="block text-sm font-medium text-neutral-700">
              Places to save ({selectedCount} selected)
            </label>
            <button
              type="button"
              onClick={() => setRows((prev) => [...prev, makeRow()])}
              className="text-xs font-medium text-brand-600 hover:underline"
            >
              + Add place
            </button>
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
