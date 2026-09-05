import { loadGoogleMapsScript } from "./googleMapsLoader";
import type { NearbyPlaceCandidate } from "./nearbyPlaceCandidate";
import type { PlaceCategory } from "../types";

export type { NearbyPlaceCandidate };

// This app's categories, mapped to Google Places API (New) primary
// types — used to narrow a search via includedPrimaryTypes when the
// person supplies a category hint (e.g. the plain nearby list was too
// ambiguous to tell which result is right).
const PRIMARY_TYPES_BY_CATEGORY: Record<PlaceCategory, string[]> = {
  restaurant: ["restaurant", "meal_takeaway", "meal_delivery", "bakery", "food_court"],
  cafe: ["cafe", "coffee_shop"],
  attraction: [
    "tourist_attraction",
    "museum",
    "art_gallery",
    "park",
    "landmark",
    "place_of_worship",
    "church",
    "temple",
    "zoo",
    "amusement_park",
    "aquarium",
  ],
  shopping: [
    "store",
    "shopping_mall",
    "clothing_store",
    "supermarket",
    "convenience_store",
    "book_store",
    "department_store",
    "electronics_store",
    "gift_shop",
  ],
  hotel: ["lodging", "hotel"],
  nightlife: ["bar", "night_club", "pub", "casino"],
  other: [],
};

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
 * geocode. An optional category hint narrows the search (via
 * includedPrimaryTypes) for when the plain nearby list is too ambiguous
 * to tell which result is right. Requires the user's own Google Maps API
 * key with the Places API enabled; returns an empty list on any failure
 * (no key, API not enabled, network error) so callers just fall back to
 * their existing reverse-geocode behavior.
 */
export async function searchNearbyPlacesGoogle(
  lat: number,
  lng: number,
  apiKey: string,
  categoryHint?: PlaceCategory,
): Promise<NearbyPlaceCandidate[]> {
  try {
    await loadGoogleMapsScript(apiKey);
  } catch (error) {
    console.warn("Failed to load Google Maps:", error);
    return [];
  }
  if (!window.google?.maps?.places) return [];

  try {
    const { Place, SearchNearbyRankPreference } = (await window.google.maps.importLibrary(
      "places",
    )) as google.maps.PlacesLibrary;
    const includedPrimaryTypes = categoryHint ? PRIMARY_TYPES_BY_CATEGORY[categoryHint] : undefined;
    const { places } = await Place.searchNearby({
      fields: ["displayName", "formattedAddress", "location", "id", "primaryType", "nationalPhoneNumber"],
      locationRestriction: { center: { lat, lng }, radius: 100 },
      maxResultCount: 8,
      rankPreference: SearchNearbyRankPreference.DISTANCE,
      ...(includedPrimaryTypes && includedPrimaryTypes.length > 0 ? { includedPrimaryTypes } : {}),
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
