import { create } from "zustand";
import { persist } from "zustand/middleware";

export type MapProvider = "free" | "google" | "naver";

interface MapSettingsState {
  mapProvider: MapProvider;
  googleMapsApiKey: string | null;
  naverClientId: string | null;
  setMapProvider: (provider: MapProvider) => void;
  setGoogleMapsApiKey: (key: string | null) => void;
  setNaverClientId: (key: string | null) => void;
}

/**
 * Which map/geocoding provider to use, and the user's own API key/Client
 * ID if they've opted into Google or Naver — stored only in this
 * browser's localStorage. "free" (Leaflet/OpenStreetMap) needs no API key
 * and is the default; switching to "google" or "naver" without a
 * key/Client ID set just falls back to free.
 */
export const useMapSettingsStore = create<MapSettingsState>()(
  persist(
    (set) => ({
      mapProvider: "free",
      googleMapsApiKey: null,
      naverClientId: null,
      setMapProvider: (provider) => set({ mapProvider: provider }),
      setGoogleMapsApiKey: (key) =>
        set({ googleMapsApiKey: key && key.trim() ? key.trim() : null }),
      setNaverClientId: (key) => set({ naverClientId: key && key.trim() ? key.trim() : null }),
    }),
    { name: "peragra-map-settings" },
  ),
);

export function isGoogleMapsActive(): boolean {
  const { mapProvider, googleMapsApiKey } = useMapSettingsStore.getState();
  return mapProvider === "google" && !!googleMapsApiKey;
}

export function isNaverMapsActive(): boolean {
  const { mapProvider, naverClientId } = useMapSettingsStore.getState();
  return mapProvider === "naver" && !!naverClientId;
}
