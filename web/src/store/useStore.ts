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
  deleteTrip: (tripId: string) => void;

  addPlace: (input: NewPlaceInput) => Place;
  updatePlace: (placeId: string, patch: Partial<Place>) => void;
  deletePlace: (placeId: string) => void;
  setPlaceCoords: (
    placeId: string,
    coords: { lat: number; lng: number } | null,
    status: GeocodeStatus,
  ) => void;
  toggleVisited: (placeId: string) => void;

  addCollection: (tripId: string, name: string) => Collection;
  deleteCollection: (collectionId: string) => void;
  togglePlaceCollection: (placeId: string, collectionId: string) => void;
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
        set((state) => ({ trips: [trip, ...state.trips] }));
        return trip;
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
          notes: input.notes,
          instagramUrl: input.instagramUrl,
          lat: null,
          lng: null,
          geocodeStatus: "pending",
          visited: false,
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

      deletePlace: (placeId) => {
        set((state) => ({ places: state.places.filter((p) => p.id !== placeId) }));
      },

      setPlaceCoords: (placeId, coords, status) => {
        get().updatePlace(placeId, {
          lat: coords?.lat ?? null,
          lng: coords?.lng ?? null,
          geocodeStatus: status,
        });
      },

      toggleVisited: (placeId) => {
        set((state) => ({
          places: state.places.map((p) =>
            p.id === placeId ? { ...p, visited: !p.visited } : p,
          ),
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
        set((state) => ({
          collections: state.collections.filter((c) => c.id !== collectionId),
          places: state.places.map((p) => ({
            ...p,
            collectionIds: p.collectionIds.filter((id) => id !== collectionId),
          })),
        }));
      },

      togglePlaceCollection: (placeId, collectionId) => {
        set((state) => ({
          places: state.places.map((p) => {
            if (p.id !== placeId) return p;
            const has = p.collectionIds.includes(collectionId);
            return {
              ...p,
              collectionIds: has
                ? p.collectionIds.filter((id) => id !== collectionId)
                : [...p.collectionIds, collectionId],
            };
          }),
        }));
      },
    }),
    { name: "peragra-store" },
  ),
);
