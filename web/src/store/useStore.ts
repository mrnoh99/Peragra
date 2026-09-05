import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Collection, GeocodeStatus, Place, PlaceCategory, Trip } from "../types";

function makeId(): string {
  return crypto.randomUUID();
}

interface NewPlaceInput {
  tripId: string;
  name: string;
  category: PlaceCategory;
  address: string;
  phone: string | null;
  notes: string;
  instagramUrl: string | null;
  collectionIds: string[];
}

interface AppState {
  trips: Trip[];
  places: Place[];
  collections: Collection[];

  addTrip: (input: {
    name: string;
    destination: string;
    coverEmoji: string;
    startDate: string | null;
    endDate: string | null;
  }) => Trip;
  updateTrip: (tripId: string, patch: Partial<Pick<Trip, "name" | "destination" | "coverEmoji" | "startDate" | "endDate">>) => void;
  deleteTrip: (tripId: string) => void;

  addPlace: (input: NewPlaceInput) => Place;
  updatePlace: (placeId: string, patch: Partial<Place>) => void;
  updatePlacesCategory: (placeIds: string[], category: PlaceCategory) => void;
  deletePlace: (placeId: string) => void;
  /** Moves a place to a different board. Custom-list membership doesn't
   *  carry over (those lists belong to the old board), but visited/
   *  favorite status is preserved and re-synced against the new board's
   *  own Visited/Favorites lists. */
  movePlaceToBoard: (placeId: string, newTripId: string) => void;
  setPlaceCoords: (
    placeId: string,
    coords: { lat: number; lng: number } | null,
    status: GeocodeStatus,
  ) => void;
  toggleVisited: (placeId: string) => void;
  toggleFavorite: (placeId: string) => void;
  /** Marks a place visited at a specific moment (rather than toggleVisited's
   *  always-now) — for a place whose visit demonstrably already happened,
   *  like one logged from an on-site photo taken at a known time. Keeps the
   *  trip's default "Visited" list in sync the same way toggleVisited does. */
  markVisitedAt: (placeId: string, timestamp: number) => void;

  addCollection: (tripId: string, name: string) => Collection;
  deleteCollection: (collectionId: string) => void;
  togglePlaceCollection: (placeId: string, collectionId: string) => void;
  addPlacesToCollection: (placeIds: string[], collectionId: string) => void;
  /** Finds the trip's auto-created "Visited" list, creating it if this
   *  trip predates the feature. */
  ensureVisitedCollection: (tripId: string) => Collection;
  /** Same as ensureVisitedCollection, for the auto-created "Favorites" list. */
  ensureFavoritesCollection: (tripId: string) => Collection;
}

export const useStore = create<AppState>()(
  persist(
    (set, get) => ({
      trips: [],
      places: [],
      collections: [],

      addTrip: (input) => {
        const trip: Trip = {
          id: makeId(),
          name: input.name,
          destination: input.destination,
          coverEmoji: input.coverEmoji,
          startDate: input.startDate,
          endDate: input.endDate,
          createdAt: Date.now(),
        };
        const favoritesCollection: Collection = {
          id: makeId(),
          tripId: trip.id,
          name: "Favorites",
          isFavoritesList: true,
          createdAt: Date.now(),
        };
        const visitedCollection: Collection = {
          id: makeId(),
          tripId: trip.id,
          name: "Visited",
          isVisitedList: true,
          createdAt: Date.now(),
        };
        set((state) => ({
          trips: [trip, ...state.trips],
          collections: [...state.collections, favoritesCollection, visitedCollection],
        }));
        return trip;
      },

      updateTrip: (tripId, patch) => {
        set((state) => ({
          trips: state.trips.map((t) => (t.id === tripId ? { ...t, ...patch } : t)),
        }));
      },

      deleteTrip: (tripId) => {
        set((state) => ({
          trips: state.trips.filter((t) => t.id !== tripId),
          places: state.places.filter((p) => p.tripId !== tripId),
          collections: state.collections.filter((c) => c.tripId !== tripId),
        }));
      },

      addPlace: (input) => {
        const place: Place = {
          id: makeId(),
          tripId: input.tripId,
          name: input.name,
          category: input.category,
          address: input.address,
          phone: input.phone,
          notes: input.notes,
          instagramUrl: input.instagramUrl,
          lat: null,
          lng: null,
          geocodeStatus: "pending",
          visited: false,
          visitedAt: null,
          favorite: false,
          collectionIds: input.collectionIds,
          createdAt: Date.now(),
        };
        set((state) => ({ places: [place, ...state.places] }));
        return place;
      },

      updatePlace: (placeId, patch) => {
        set((state) => ({
          places: state.places.map((p) => (p.id === placeId ? { ...p, ...patch } : p)),
        }));
      },

      updatePlacesCategory: (placeIds, category) => {
        const idSet = new Set(placeIds);
        set((state) => ({
          places: state.places.map((p) => (idSet.has(p.id) ? { ...p, category } : p)),
        }));
      },

      deletePlace: (placeId) => {
        set((state) => ({ places: state.places.filter((p) => p.id !== placeId) }));
      },

      movePlaceToBoard: (placeId, newTripId) => {
        const place = get().places.find((p) => p.id === placeId);
        if (!place || place.tripId === newTripId) return;
        const newCollectionIds: string[] = [];
        if (place.visited) newCollectionIds.push(get().ensureVisitedCollection(newTripId).id);
        if (place.favorite) newCollectionIds.push(get().ensureFavoritesCollection(newTripId).id);
        set((state) => ({
          places: state.places.map((p) =>
            p.id === placeId ? { ...p, tripId: newTripId, collectionIds: newCollectionIds } : p,
          ),
        }));
      },

      setPlaceCoords: (placeId, coords, status) => {
        get().updatePlace(placeId, {
          lat: coords?.lat ?? null,
          lng: coords?.lng ?? null,
          geocodeStatus: status,
        });
      },

      toggleVisited: (placeId) => {
        const place = get().places.find((p) => p.id === placeId);
        if (!place) return;
        const willBeVisited = !place.visited;
        const visitedCollection = get().ensureVisitedCollection(place.tripId);
        set((state) => ({
          places: state.places.map((p) => {
            if (p.id !== placeId) return p;
            const collectionIds = willBeVisited
              ? p.collectionIds.includes(visitedCollection.id)
                ? p.collectionIds
                : [...p.collectionIds, visitedCollection.id]
              : p.collectionIds.filter((id) => id !== visitedCollection.id);
            return { ...p, visited: willBeVisited, visitedAt: willBeVisited ? Date.now() : null, collectionIds };
          }),
        }));
      },

      markVisitedAt: (placeId, timestamp) => {
        const place = get().places.find((p) => p.id === placeId);
        if (!place) return;
        const visitedCollection = get().ensureVisitedCollection(place.tripId);
        set((state) => ({
          places: state.places.map((p) => {
            if (p.id !== placeId) return p;
            const collectionIds = p.collectionIds.includes(visitedCollection.id)
              ? p.collectionIds
              : [...p.collectionIds, visitedCollection.id];
            return { ...p, visited: true, visitedAt: timestamp, collectionIds };
          }),
        }));
      },

      toggleFavorite: (placeId) => {
        const place = get().places.find((p) => p.id === placeId);
        if (!place) return;
        const willBeFavorite = !place.favorite;
        const favoritesCollection = get().ensureFavoritesCollection(place.tripId);
        set((state) => ({
          places: state.places.map((p) => {
            if (p.id !== placeId) return p;
            const collectionIds = willBeFavorite
              ? p.collectionIds.includes(favoritesCollection.id)
                ? p.collectionIds
                : [...p.collectionIds, favoritesCollection.id]
              : p.collectionIds.filter((id) => id !== favoritesCollection.id);
            return { ...p, favorite: willBeFavorite, collectionIds };
          }),
        }));
      },

      addCollection: (tripId, name) => {
        const collection: Collection = {
          id: makeId(),
          tripId,
          name,
          createdAt: Date.now(),
        };
        set((state) => ({ collections: [...state.collections, collection] }));
        return collection;
      },

      deleteCollection: (collectionId) => {
        // The auto-created Visited/Favorites lists aren't user-deletable
        // — the UI never shows a delete control for them, but guard here
        // too.
        const collection = get().collections.find((c) => c.id === collectionId);
        if (collection?.isVisitedList || collection?.isFavoritesList) return;
        set((state) => ({
          collections: state.collections.filter((c) => c.id !== collectionId),
          places: state.places.map((p) => ({
            ...p,
            collectionIds: p.collectionIds.filter((id) => id !== collectionId),
          })),
        }));
      },

      togglePlaceCollection: (placeId, collectionId) => {
        // Toggling membership in the Visited/Favorites list is another
        // way of marking a place visited/favorite — keep those flags in
        // sync so either control (the checkbox/star or this list) works
        // the same.
        const collection = get().collections.find((c) => c.id === collectionId);
        set((state) => ({
          places: state.places.map((p) => {
            if (p.id !== placeId) return p;
            const has = p.collectionIds.includes(collectionId);
            const willBeVisited = collection?.isVisitedList ? !has : p.visited;
            return {
              ...p,
              collectionIds: has
                ? p.collectionIds.filter((id) => id !== collectionId)
                : [...p.collectionIds, collectionId],
              visited: willBeVisited,
              visitedAt: collection?.isVisitedList ? (willBeVisited ? Date.now() : null) : p.visitedAt,
              favorite: collection?.isFavoritesList ? !has : p.favorite,
            };
          }),
        }));
      },

      addPlacesToCollection: (placeIds, collectionId) => {
        // Adds rather than toggles — a bulk selection can mix places
        // already in the list with ones that aren't, and "send to list"
        // should only ever add, never accidentally remove someone who
        // was already there. Adding to the Visited/Favorites list also
        // sets that flag, same as togglePlaceCollection.
        const idSet = new Set(placeIds);
        const collection = get().collections.find((c) => c.id === collectionId);
        set((state) => ({
          places: state.places.map((p) => {
            if (!idSet.has(p.id) || p.collectionIds.includes(collectionId)) return p;
            return {
              ...p,
              collectionIds: [...p.collectionIds, collectionId],
              visited: collection?.isVisitedList ? true : p.visited,
              visitedAt: collection?.isVisitedList ? Date.now() : p.visitedAt,
              favorite: collection?.isFavoritesList ? true : p.favorite,
            };
          }),
        }));
      },

      ensureVisitedCollection: (tripId) => {
        const existing = get().collections.find((c) => c.tripId === tripId && c.isVisitedList);
        if (existing) return existing;
        const collection: Collection = {
          id: makeId(),
          tripId,
          name: "Visited",
          isVisitedList: true,
          createdAt: Date.now(),
        };
        set((state) => ({ collections: [...state.collections, collection] }));
        return collection;
      },

      ensureFavoritesCollection: (tripId) => {
        const existing = get().collections.find((c) => c.tripId === tripId && c.isFavoritesList);
        if (existing) return existing;
        const collection: Collection = {
          id: makeId(),
          tripId,
          name: "Favorites",
          isFavoritesList: true,
          createdAt: Date.now(),
        };
        set((state) => ({ collections: [...state.collections, collection] }));
        return collection;
      },
    }),
    { name: "peragra-store" },
  ),
);
