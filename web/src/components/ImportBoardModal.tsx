import { useRef, useState, type ChangeEvent } from "react";
import { Modal } from "./Modal";
import { parseBackup, type BackupData } from "../lib/backup";
import { useStore } from "../store/useStore";

/**
 * The receiving side of "share a whole board": paste the text from
 * someone's "Copy as text" board export, or pick the file from their
 * "Save as file" export, then add it as a brand-new board (fresh ids for
 * everything, so it can never collide with or overwrite what's already
 * here) — unlike restoring a whole-app backup, which replaces everything.
 */
export function ImportBoardModal({ onClose, onImported }: { onClose: () => void; onImported: (tripId: string) => void }) {
  const importBoardData = useStore((s) => s.importBoardData);

  const [pastedText, setPastedText] = useState("");
  const [preview, setPreview] = useState<BackupData | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  function tryParse(text: string) {
    try {
      const data = parseBackup(text);
      if (data.trips.length === 0) {
        setParseError("That file doesn't contain any boards.");
        setPreview(null);
        return;
      }
      setParseError(null);
      setPreview(data);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : "That doesn't look like a Peragra board export.");
      setPreview(null);
    }
  }

  async function handleFileChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    const text = await file.text();
    setPastedText(text);
    tryParse(text);
  }

  function handleImport() {
    if (!preview) return;
    const newTrips = importBoardData(preview);
    if (newTrips[0]) onImported(newTrips[0].id);
  }

  return (
    <Modal title="Import a shared board" onClose={onClose}>
      {!preview ? (
        <div className="space-y-3">
          <p className="text-sm text-neutral-500">
            Paste text from someone's "Copy as text" board share, or choose the .json file from
            their "Save as file" share.
          </p>
          <textarea
            value={pastedText}
            onChange={(e) => setPastedText(e.target.value)}
            rows={6}
            placeholder="Paste the shared board text here…"
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
              id="import-board-file-input"
            />
            <label
              htmlFor="import-board-file-input"
              className="cursor-pointer rounded-lg border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-50"
            >
              Choose file…
            </label>
          </div>
        </div>
      ) : (
        <div className="space-y-3">
          <p className="text-sm font-medium text-neutral-700">
            Add {preview.trips.length === 1 ? "this board" : `these ${preview.trips.length} boards`}?
          </p>
          <div className="space-y-1.5">
            {preview.trips.map((trip) => {
              const count = preview.places.filter((p) => p.tripId === trip.id).length;
              return (
                <div key={trip.id} className="flex items-center gap-2 rounded-lg border border-neutral-200 p-2 text-sm">
                  <span className="text-xl">{trip.coverEmoji}</span>
                  <div>
                    <p className="font-medium text-neutral-800">{trip.name}</p>
                    <p className="text-xs text-neutral-500">
                      {trip.destination} · {count} place{count === 1 ? "" : "s"}
                    </p>
                  </div>
                </div>
              );
            })}
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => {
                setPreview(null);
                setParseError(null);
              }}
              className="rounded-lg border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-50"
            >
              Back
            </button>
            <button
              type="button"
              onClick={handleImport}
              className="flex-1 rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600"
            >
              Add {preview.trips.length === 1 ? "board" : "boards"}
            </button>
          </div>
        </div>
      )}
    </Modal>
  );
}
