import { useMemo } from "react";
import { GoogleMapView } from "./GoogleMapView";
import { LeafletMapView } from "./LeafletMapView";
import { useMapSettingsStore } from "../store/useMapSettingsStore";
import type { Place } from "../types";

/**
 * Picks the map provider the user configured in Settings — free
 * (Leaflet/OpenStreetMap, the default, no API key) or Google Maps (opt-in,
 * needs the user's own API key). Falls back to free automatically if
 * Google is selected but no key is set.
 */
export function MapView({ places, destination }: { places: Place[]; destination: string }) {
  const mapProvider = useMapSettingsStore((s) => s.mapProvider);
  const googleMapsApiKey = useMapSettingsStore((s) => s.googleMapsApiKey);

  const locatedCount = useMemo(() => places.filter((p) => p.lat !== null && p.lng !== null).length, [places]);
  const unlocated = places.length - locatedCount;

  if (mapProvider !== "google" || !googleMapsApiKey) {
    return <LeafletMapView places={places} destination={destination} />;
  }

  return (
    <div>
      {unlocated > 0 && (
        <p className="mb-2 text-xs text-amber-600">
          {unlocated} place{unlocated > 1 ? "s" : ""} couldn't be placed on the map — add a more
          specific address to locate them.
        </p>
      )}
      <div className="h-[500px] w-full overflow-hidden rounded-2xl border border-black/5 shadow-sm">
        {locatedCount === 0 ? (
          <div className="grid h-full place-items-center bg-neutral-50 text-sm text-neutral-400">
            No located places yet — save a place with an address to see it here.
          </div>
        ) : (
          <GoogleMapView places={places} apiKey={googleMapsApiKey} destination={destination} />
        )}
      </div>
    </div>
  );
}
