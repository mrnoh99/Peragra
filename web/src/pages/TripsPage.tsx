import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Modal } from "../components/Modal";
import { EMOJI_CHOICES } from "../lib/emojiChoices";
import { useStore } from "../store/useStore";

export function TripsPage() {
  const trips = useStore((s) => s.trips);
  const places = useStore((s) => s.places);
  const addTrip = useStore((s) => s.addTrip);
  const deleteTrip = useStore((s) => s.deleteTrip);
  const [showCreate, setShowCreate] = useState(false);

  const placeCountByTrip = useMemo(() => {
    const counts = new Map<string, number>();
    for (const place of places) {
      counts.set(place.tripId, (counts.get(place.tripId) ?? 0) + 1);
    }
    return counts;
  }, [places]);

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-neutral-900">Your boards</h1>
          <p className="mt-1 text-sm text-neutral-500">
            Save the places you find — from Instagram, photos, or a map — and visit them later.
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <Link
            to="/all-places"
            className="rounded-lg border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-50"
          >
            All places
          </Link>
          <button
            onClick={() => setShowCreate(true)}
            className="rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-brand-600"
          >
            + New board
          </button>
        </div>
      </div>

      {trips.length === 0 ? (
        <EmptyState onCreate={() => setShowCreate(true)} />
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {trips.map((trip) => (
            <div
              key={trip.id}
              className="group relative overflow-hidden rounded-2xl border border-black/5 bg-white p-5 shadow-sm transition hover:shadow-md"
            >
              <Link to={`/trips/${trip.id}`} className="block">
                <div className="mb-3 text-3xl">{trip.coverEmoji}</div>
                <h3 className="font-semibold text-neutral-900">{trip.name}</h3>
                <p className="text-sm text-neutral-500">{trip.destination}</p>
                <p className="mt-3 text-xs font-medium text-brand-600">
                  {placeCountByTrip.get(trip.id) ?? 0} saved places
                </p>
              </Link>
              <button
                onClick={(e) => {
                  e.preventDefault();
                  if (confirm(`Delete "${trip.name}" and all its saved places?`)) {
                    deleteTrip(trip.id);
                  }
                }}
                className="absolute right-3 top-3 hidden h-7 w-7 place-items-center rounded-full bg-white text-neutral-400 hover:text-red-500 group-hover:grid"
                aria-label="Delete board"
              >
                🗑
              </button>
            </div>
          ))}
        </div>
      )}

      {showCreate && (
        <CreateTripModal
          onClose={() => setShowCreate(false)}
          onCreate={(input) => {
            addTrip(input);
            setShowCreate(false);
          }}
        />
      )}
    </div>
  );
}

function EmptyState({ onCreate }: { onCreate: () => void }) {
  return (
    <div className="rounded-2xl border border-dashed border-neutral-300 bg-white/60 px-6 py-16 text-center">
      <div className="text-4xl">🧭</div>
      <h2 className="mt-3 text-lg font-semibold text-neutral-800">No boards yet</h2>
      <p className="mx-auto mt-1 max-w-sm text-sm text-neutral-500">
        Create a board for a destination, then start importing the restaurants, cafes and
        attractions you've saved on Instagram.
      </p>
      <button
        onClick={onCreate}
        className="mt-5 rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600"
      >
        Create your first board
      </button>
    </div>
  );
}

function CreateTripModal({
  onClose,
  onCreate,
}: {
  onClose: () => void;
  onCreate: (input: {
    name: string;
    destination: string;
    coverEmoji: string;
    startDate: string | null;
    endDate: string | null;
  }) => void;
}) {
  const [name, setName] = useState("");
  const [destination, setDestination] = useState("");
  const [emoji, setEmoji] = useState(EMOJI_CHOICES[0]);

  const canSubmit = name.trim().length > 0 && destination.trim().length > 0;

  return (
    <Modal title="New board" onClose={onClose}>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (!canSubmit) return;
          onCreate({
            name: name.trim(),
            destination: destination.trim(),
            coverEmoji: emoji,
            startDate: null,
            endDate: null,
          });
        }}
        className="space-y-4"
      >
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">Board name</label>
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Tokyo Spring Trip"
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">Destination</label>
          <input
            value={destination}
            onChange={(e) => setDestination(e.target.value)}
            placeholder="Tokyo, Japan"
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
          Create board
        </button>
      </form>
    </Modal>
  );
}
