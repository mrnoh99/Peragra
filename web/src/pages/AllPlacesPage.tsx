import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { EditPlaceModal } from "../components/EditPlaceModal";
import { useStore } from "../store/useStore";
import { PLACE_CATEGORIES, type Place, type PlaceCategory } from "../types";

/**
 * A single list combining every place across every trip — the "Your
 * Trips" screen only lets you view/edit one trip at a time otherwise, so
 * this is the one place to see and fix up everything at once. Each row
 * carries its own trip as a badge (linking back to that trip) since
 * places here don't share one destination or one set of lists the way
 * they do inside a single trip.
 */
export function AllPlacesPage() {
  const trips = useStore((s) => s.trips);
  const places = useStore((s) => s.places);
  const toggleVisited = useStore((s) => s.toggleVisited);
  const toggleFavorite = useStore((s) => s.toggleFavorite);
  const deletePlace = useStore((s) => s.deletePlace);

  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<PlaceCategory | "all">("all");
  const [tripFilter, setTripFilter] = useState<string>("all");
  const [editingPlace, setEditingPlace] = useState<Place | null>(null);

  const tripById = useMemo(() => new Map(trips.map((t) => [t.id, t])), [trips]);

  const filtered = useMemo(() => {
    return places.filter((p) => {
      if (tripFilter !== "all" && p.tripId !== tripFilter) return false;
      if (categoryFilter !== "all" && p.category !== categoryFilter) return false;
      if (search.trim()) {
        const q = search.trim().toLowerCase();
        if (
          !p.name.toLowerCase().includes(q) &&
          !p.address.toLowerCase().includes(q) &&
          !p.notes.toLowerCase().includes(q)
        ) {
          return false;
        }
      }
      return true;
    });
  }, [places, tripFilter, categoryFilter, search]);

  const sorted = useMemo(() => [...filtered].sort((a, b) => b.createdAt - a.createdAt), [filtered]);

  return (
    <div>
      <Link to="/" className="text-sm text-neutral-500 hover:text-neutral-700">
        ← All trips
      </Link>
      <div className="mb-6 mt-2">
        <h1 className="text-2xl font-bold text-neutral-900">All places</h1>
        <p className="mt-1 text-sm text-neutral-500">
          Every place saved across all your trips, in one list.
        </p>
      </div>

      {places.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-neutral-300 bg-white/60 px-6 py-16 text-center text-sm text-neutral-500">
          No places saved yet — add some from within a trip.
        </div>
      ) : (
        <>
          <div className="mb-4 flex flex-wrap gap-2">
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search places…"
              className="min-w-[180px] flex-1 rounded-lg border border-neutral-300 px-3 py-1.5 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
            <select
              value={tripFilter}
              onChange={(e) => setTripFilter(e.target.value)}
              className="rounded-lg border border-neutral-300 px-2 py-1.5 text-sm"
            >
              <option value="all">All trips</option>
              {trips.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.coverEmoji} {t.name}
                </option>
              ))}
            </select>
            <select
              value={categoryFilter}
              onChange={(e) => setCategoryFilter(e.target.value as PlaceCategory | "all")}
              className="rounded-lg border border-neutral-300 px-2 py-1.5 text-sm"
            >
              <option value="all">All categories</option>
              {PLACE_CATEGORIES.map((c) => (
                <option key={c.value} value={c.value}>
                  {c.label}
                </option>
              ))}
            </select>
          </div>

          <p className="mb-2 text-xs text-neutral-400">
            {sorted.length} place{sorted.length === 1 ? "" : "s"}
          </p>

          {sorted.length === 0 ? (
            <p className="rounded-lg border border-dashed border-neutral-300 py-8 text-center text-sm text-neutral-400">
              No places match.
            </p>
          ) : (
            <div className="space-y-2">
              {sorted.map((place) => {
                const trip = tripById.get(place.tripId);
                return (
                  <div
                    key={place.id}
                    className="flex items-start gap-3 rounded-lg border border-neutral-200 bg-white p-3"
                  >
                    <button
                      onClick={() => toggleVisited(place.id)}
                      aria-label={place.visited ? "Mark not visited" : "Mark visited"}
                      className={`mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full border text-xs ${
                        place.visited
                          ? "border-green-500 bg-green-500 text-white"
                          : "border-neutral-300 text-transparent"
                      }`}
                    >
                      ✓
                    </button>
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-1.5">
                        {trip && (
                          <Link
                            to={`/trips/${trip.id}`}
                            className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs font-medium text-neutral-600 hover:bg-neutral-200"
                          >
                            {trip.coverEmoji} {trip.name}
                          </Link>
                        )}
                        <span className="text-xs font-semibold uppercase tracking-wide text-neutral-400">
                          {PLACE_CATEGORIES.find((c) => c.value === place.category)?.label}
                        </span>
                      </div>
                      <p className={`mt-1 font-medium ${place.visited ? "text-red-600" : "text-neutral-900"}`}>
                        {place.name}
                      </p>
                      {place.address && <p className="text-sm text-neutral-500">{place.address}</p>}
                    </div>
                    <div className="flex shrink-0 items-center gap-3">
                      <button
                        onClick={() => toggleFavorite(place.id)}
                        aria-label="Toggle favorite"
                        className={place.favorite ? "text-yellow-500" : "text-neutral-300 hover:text-neutral-400"}
                      >
                        ★
                      </button>
                      <button
                        onClick={() => setEditingPlace(place)}
                        className="text-xs font-medium text-neutral-500 hover:text-neutral-700"
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => {
                          if (confirm(`Delete "${place.name}"?`)) deletePlace(place.id);
                        }}
                        className="text-xs font-medium text-neutral-400 hover:text-red-500"
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </>
      )}

      {editingPlace && (
        <EditPlaceModal
          place={editingPlace}
          destination={tripById.get(editingPlace.tripId)?.destination ?? ""}
          onClose={() => setEditingPlace(null)}
        />
      )}
    </div>
  );
}
