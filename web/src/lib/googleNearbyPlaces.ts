import { loadGoogleMapsScript } from "./googleMapsLoader";
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

// Google Places (New) primary-type strings, mapped to this app's own
// category set. Not exhaustive — anything unmapped falls back to "other"
// rather than guessing wrong.
const CATEGORY_BY_PRIMARY_TYPE: Record<string, PlaceCategory> = {
  restaurant: "restaurant",
  meal_takeaway: "restaurant",
  meal_delivery: "restaurant",
  bakery: "restaurant",
  food_court: "restaurant",
  cafe: "cafe",
  coffee_shop: "cafe",
  tourist_attraction: "attraction",
  museum: "attraction",
  art_gallery: "attraction",
  park: "attraction",
  landmark: "attraction",
  place_of_worship: "attraction",
  church: "attraction",
  temple: "attraction",
  zoo: "attraction",
  amusement_park: "attraction",
  aquarium: "attraction",
  store: "shopping",
  shopping_mall: "shopping",
  clothing_store: "shopping",
  supermarket: "shopping",
  convenience_store: "shopping",
  book_store: "shopping",
  department_store: "shopping",
  electronics_store: "shopping",
  gift_shop: "shopping",
  lodging: "hotel",
  hotel: "hotel",
  bar: "nightlife",
  night_club: "nightlife",
  pub: "nightlife",
  casino: "nightlife",
};

function categoryForPrimaryType(primaryType: string | null | undefined): PlaceCategory {
  if (!primaryType) return "other";
  return CATEGORY_BY_PRIMARY_TYPE[primaryType] ?? "other";
}

/**
 * Finds real places near a coordinate via the Places API (New)'s Nearby
 * Search, for presenting as pickable candidates when a GPS fix (from an
 * on-site photo) is the only information available — letting the person
 * confirm which actual place it was rather than trusting a bare reverse
 * geocode. Requires the user's own Google Maps API key with the Places
 * API enabled; returns an empty list on any failure (no key, API not
 * enabled, network error) so callers just fall back to their existing
 * reverse-geocode behavior.
 */
export async function searchNearbyPlaces(
  lat: number,
  lng: number,
  apiKey: string,
): Promise<NearbyPlaceCandidate[]> {
  await loadGoogleMapsScript(apiKey);
  if (!window.google?.maps?.places) return [];

  try {
    const { Place, SearchNearbyRankPreference } = (await window.google.maps.importLibrary(
      "places",
    )) as google.maps.PlacesLibrary;
    const { places } = await Place.searchNearby({
      fields: ["displayName", "formattedAddress", "location", "id", "primaryType", "nationalPhoneNumber"],
      locationRestriction: { center: { lat, lng }, radius: 100 },
      maxResultCount: 8,
      rankPreference: SearchNearbyRankPreference.DISTANCE,
    });

    return places
      .filter((place) => place.location)
      .map((place) => ({
        placeId: place.id,
        name: place.displayName ?? "Unnamed place",
        address: place.formattedAddress ?? null,
        phone: place.nationalPhoneNumber ?? null,
        lat: place.location!.lat(),
        lng: place.location!.lng(),
        category: categoryForPrimaryType(place.primaryType),
      }));
  } catch (error) {
    console.warn("Google nearby places search failed:", error);
    return [];
  }
}
