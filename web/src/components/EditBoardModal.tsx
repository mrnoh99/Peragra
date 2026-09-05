import { useState } from "react";
import { EMOJI_CHOICES } from "../lib/emojiChoices";
import { useStore } from "../store/useStore";
import type { Trip } from "../types";
import { Modal } from "./Modal";

/** Edits a board's name, destination, and cover icon together — shared by
 *  the boards list and a board's own detail page. */
export function EditBoardModal({ trip, onClose }: { trip: Trip; onClose: () => void }) {
  const updateTrip = useStore((s) => s.updateTrip);
  const [name, setName] = useState(trip.name);
  const [destination, setDestination] = useState(trip.destination);
  const [emoji, setEmoji] = useState(trip.coverEmoji);

  const canSubmit = name.trim().length > 0 && destination.trim().length > 0;

  return (
    <Modal title="Edit board" onClose={onClose}>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (!canSubmit) return;
          updateTrip(trip.id, { name: name.trim(), destination: destination.trim(), coverEmoji: emoji });
          onClose();
        }}
        className="space-y-4"
      >
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">Board name</label>
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">Destination</label>
          <input
            value={destination}
            onChange={(e) => setDestination(e.target.value)}
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">Cover icon</label>
          <div className="flex flex-wrap gap-2">
            {EMOJI_CHOICES.map((choice) => (
              <button
                type="button"
                key={choice}
                onClick={() => setEmoji(choice)}
                className={`grid h-10 w-10 place-items-center rounded-lg border text-xl ${
                  emoji === choice
                    ? "border-brand-500 bg-brand-50"
                    : "border-neutral-200 hover:bg-neutral-50"
                }`}
              >
                {choice}
              </button>
            ))}
          </div>
        </div>
        <button
          type="submit"
          disabled={!canSubmit}
          className="w-full rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
        >
          Save
        </button>
      </form>
    </Modal>
  );
}
