export type PlaceCategory =
  | "restaurant"
  | "cafe"
  | "attraction"
  | "shopping"
  | "hotel"
  | "nightlife"
  | "other";

export const PLACE_CATEGORIES: { value: PlaceCategory; label: string }[] = [
  { value: "restaurant", label: "Restaurant" },
  { value: "cafe", label: "Cafe" },
  { value: "attraction", label: "Attraction" },
  { value: "shopping", label: "Shopping" },
  { value: "hotel", label: "Hotel" },
  { value: "nightlife", label: "Nightlife" },
  { value: "other", label: "Other" },
];

// "estimated" marks a place located via an AI best-guess address rather
// than a real geocoder match on the address/name the user gave — used
// when ordinary geocoding fails and AI is asked to guess the nearest
// plausible location instead. Distinguished from "located" so the UI can
// flag it as approximate rather than implying precision it doesn't have.
export type GeocodeStatus = "pending" | "located" | "estimated" | "failed" | "manual";

export interface Place {
  id: string;
  tripId: string;
  name: string;
  category: PlaceCategory;
  address: string;
  phone: string | null;
  notes: string;
  instagramUrl: string | null;
  lat: number | null;
  lng: number | null;
  geocodeStatus: GeocodeStatus;
  visited: boolean;
  favorite: boolean;
  collectionIds: string[];
  createdAt: number;
}

export interface Collection {
  id: string;
  tripId: string;
  name: string;
  // Marks the one auto-created, undeletable "Visited" list every trip
  // gets — kept in sync with each place's `visited` flag in both
  // directions, rather than a regular user-managed list.
  isVisitedList?: boolean;
  createdAt: number;
}

export interface Trip {
  id: string;
  name: string;
  destination: string;
  coverEmoji: string;
  startDate: string | null;
  endDate: string | null;
  createdAt: number;
}
