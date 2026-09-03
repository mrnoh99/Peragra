import { create } from "zustand";
import { persist } from "zustand/middleware";

export type MapProvider = "free" | "google";

interface MapSettingsState {
  mapProvider: MapProvider;
  googleMapsApiKey: string | null;
  setMapProvider: (provider: MapProvider) => void;
  setGoogleMapsApiKey: (key: string | null) => void;
}

/**
 * Which map/geocoding provider to use, and the user's own Google Maps API
 * key if they've opted into it — stored only in this browser's
 * localStorage. "free" (Leaflet/OpenStreetMap) needs no API key and is the
 * default; switching to "google" without a key set just falls back to free.
 */
export const useMapSettingsStore = create<MapSettingsState>()(
  persist(
    (set) => ({
      mapProvider: "free",
      googleMapsApiKey: null,
      setMapProvider: (provider) => set({ mapProvider: provider }),
      setGoogleMapsApiKey: (key) =>
        set({ googleMapsApiKey: key && key.trim() ? key.trim() : null }),
    }),
    { name: "peragra-map-settings" },
  ),
);

export function isGoogleMapsActive(): boolean {
  const { mapProvider, googleMapsApiKey } = useMapSettingsStore.getState();
  return mapProvider === "google" && !!googleMapsApiKey;
}
