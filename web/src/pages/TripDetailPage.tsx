import { useMemo, useState } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import { AddPlaceModal } from "../components/AddPlaceModal";
import { ListingView } from "../components/ListingView";
import { MapView } from "../components/MapView";
import { useStore } from "../store/useStore";

type Tab = "listing" | "map";

export function TripDetailPage() {
  const { tripId } = useParams<{ tripId: string }>();
  const trips = useStore((s) => s.trips);
  const allPlaces = useStore((s) => s.places);
  const allCollections = useStore((s) => s.collections);
  const addCollection = useStore((s) => s.addCollection);
  const deleteCollection = useStore((s) => s.deleteCollection);

  const trip = useMemo(() => trips.find((t) => t.id === tripId), [trips, tripId]);
  const places = useMemo(
    () => allPlaces.filter((p) => p.tripId === tripId),
    [allPlaces, tripId],
  );
  const collections = useMemo(
    () => allCollections.filter((c) => c.tripId === tripId),
    [allCollections, tripId],
  );

  const [tab, setTab] = useState<Tab>("listing");
  const [showAddPlace, setShowAddPlace] = useState(false);
  const [activeCollectionId, setActiveCollectionId] = useState<string | null>(null);
  const [newListName, setNewListName] = useState("");

  const visitedCount = useMemo(() => places.filter((p) => p.visited).length, [places]);

  if (!tripId) return <Navigate to="/" replace />;
  if (!trip) {
    return (
      <div className="py-16 text-center text-sm text-neutral-500">
        Trip not found. <Link to="/" className="text-brand-600 underline">Back to trips</Link>
      </div>
    );
  }

  return (
    <div>
      <Link to="/" className="text-sm text-neutral-500 hover:text-neutral-700">
        ← All trips
      </Link>

      <div className="mt-2 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-neutral-900">
            <span>{trip.coverEmoji}</span>
            {trip.name}
          </h1>
          <p className="text-sm text-neutral-500">
            {trip.destination}
            {trip.startDate && (
              <>
                {" · "}
                {trip.startDate}
                {trip.endDate ? ` – ${trip.endDate}` : ""}
              </>
            )}
          </p>
          <p className="mt-1 text-xs text-neutral-400">
            {places.length} saved place{places.length === 1 ? "" : "s"} · {visitedCount} visited
          </p>
        </div>
        <button
          onClick={() => setShowAddPlace(true)}
          className="rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-brand-600"
        >
          + Save a place
        </button>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-[220px_1fr]">
        <aside className="lg:sticky lg:top-4 lg:self-start">
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-400">
            Lists
          </h2>
          <div className="space-y-1">
            <button
              onClick={() => setActiveCollectionId(null)}
              className={`block w-full rounded-lg px-3 py-1.5 text-left text-sm ${
                activeCollectionId === null
                  ? "bg-brand-50 font-medium text-brand-700"
                  : "text-neutral-600 hover:bg-neutral-100"
              }`}
            >
              All places
            </button>
            {collections.map((c) => (
              <div key={c.id} className="group flex items-center gap-1">
                <button
                  onClick={() => setActiveCollectionId(c.id)}
                  className={`block w-full truncate rounded-lg px-3 py-1.5 text-left text-sm ${
                    activeCollectionId === c.id
                      ? "bg-brand-50 font-medium text-brand-700"
                      : "text-neutral-600 hover:bg-neutral-100"
                  }`}
                >
                  {c.name}
                </button>
                <button
                  onClick={() => {
                    if (activeCollectionId === c.id) setActiveCollectionId(null);
                    deleteCollection(c.id);
                  }}
                  className="hidden shrink-0 pr-1 text-xs text-neutral-400 hover:text-red-500 group-hover:block"
                  aria-label={`Delete ${c.name}`}
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const trimmed = newListName.trim();
              if (!trimmed || !tripId) return;
              addCollection(tripId, trimmed);
              setNewListName("");
            }}
            className="mt-3 flex gap-1"
          >
            <input
              value={newListName}
              onChange={(e) => setNewListName(e.target.value)}
              placeholder="New list…"
              className="w-full min-w-0 rounded-lg border border-neutral-300 px-2 py-1 text-xs focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
            <button
              type="submit"
              className="shrink-0 rounded-lg bg-neutral-800 px-2.5 py-1 text-xs font-medium text-white hover:bg-neutral-700"
            >
              Add
            </button>
          </form>
        </aside>

        <div>
          <div className="mb-4 inline-flex rounded-lg border border-neutral-200 bg-white p-1 text-sm">
            <button
              onClick={() => setTab("listing")}
              className={`rounded-md px-4 py-1.5 font-medium ${
                tab === "listing" ? "bg-brand-500 text-white" : "text-neutral-600"
              }`}
            >
              Listing
            </button>
            <button
              onClick={() => setTab("map")}
              className={`rounded-md px-4 py-1.5 font-medium ${
                tab === "map" ? "bg-brand-500 text-white" : "text-neutral-600"
              }`}
            >
              Map
            </button>
          </div>

          {places.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-neutral-300 bg-white/60 px-6 py-16 text-center">
              <div className="text-4xl">📌</div>
              <h2 className="mt-3 text-lg font-semibold text-neutral-800">
                No places saved yet
              </h2>
              <p className="mx-auto mt-1 max-w-sm text-sm text-neutral-500">
                Paste a link from a post you saved on Instagram, or add a place by hand, to
                start building your {trip.destination} itinerary.
              </p>
              <button
                onClick={() => setShowAddPlace(true)}
                className="mt-5 rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600"
              >
                Save your first place
              </button>
            </div>
          ) : tab === "listing" ? (
            <ListingView
              places={places}
              collections={collections}
              activeCollectionId={activeCollectionId}
              destination={trip.destination}
            />
          ) : (
            <MapView
              places={
                activeCollectionId
                  ? places.filter((p) => p.collectionIds.includes(activeCollectionId))
                  : places
              }
            />
          )}
        </div>
      </div>

      {showAddPlace && (
        <AddPlaceModal
          tripId={tripId}
          destination={trip.destination}
          defaultCollectionId={activeCollectionId ?? undefined}
          onClose={() => setShowAddPlace(false)}
        />
      )}
    </div>
  );
}
