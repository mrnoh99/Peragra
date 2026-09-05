import type { PlaceCategory } from "../types";

export interface NearbyPlaceCandidate {
  placeId: string;
  name: string;
  address: string | null;
  phone: string | null;
  lat: number;
  lng: number;
  category: PlaceCategory;
}
