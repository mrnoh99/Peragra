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

export type GeocodeStatus = "pending" | "located" | "failed" | "manual";

export interface Place {
  id: string;
  tripId: string;
  name: string;
  category: PlaceCategory;
  address: string;
  notes: string;
  instagramUrl: string | null;
  lat: number | null;
  lng: number | null;
  geocodeStatus: GeocodeStatus;
  visited: boolean;
  collectionIds: string[];
  createdAt: number;
}

export interface Collection {
  id: string;
  tripId: string;
  name: string;
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
