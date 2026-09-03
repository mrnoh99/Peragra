import { useEffect, useMemo, useRef, useState } from "react";
import { loadGoogleMapsScript } from "../lib/googleMapsLoader";
import type { Place } from "../types";

const CATEGORY_ICON: Record<string, string> = {
  restaurant: "🍽️",
  cafe: "☕",
  attraction: "🎡",
  shopping: "🛍️",
  hotel: "🏨",
  nightlife: "🌃",
  other: "📍",
};

/**
 * Renders saved places on a Google Map, for people who've opted into
 * Google Maps in Settings with their own API key. Loads Google's JS Maps
 * API directly (no @react-google-maps/api dependency — this app avoids
 * adding wrapper libraries where a plain script tag + imperative API call
 * does the job, same as the Instagram embed).
 */
export function GoogleMapView({ places, apiKey }: { places: Place[]; apiKey: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [loadError, setLoadError] = useState(false);
  const located = useMemo(
    () => places.filter((p): p is Place & { lat: number; lng: number } => p.lat !== null && p.lng !== null),
    [places],
  );

  useEffect(() => {
    let cancelled = false;
    loadGoogleMapsScript(apiKey)
      .then(() => {
        if (cancelled || !containerRef.current || !window.google) return;
        setLoadError(false);
        const { maps } = window.google;

        const map = new maps.Map(containerRef.current, {
          center: { lat: located[0]?.lat ?? 0, lng: located[0]?.lng ?? 0 },
          zoom: 13,
        });

        const bounds = new maps.LatLngBounds();
        const infoWindow = new maps.InfoWindow();

        for (const place of located) {
          const position = { lat: place.lat, lng: place.lng };
          const marker = new maps.Marker({
            position,
            map,
            opacity: place.visited ? 0.5 : 1,
            label: { text: CATEGORY_ICON[place.category] ?? "📍", fontSize: "16px" },
          });
          marker.addListener("click", () => {
            // Built as DOM nodes with textContent, not an HTML string, so
            // a place name/address containing markup (pasted from an
            // Instagram caption, say) can't inject into the page.
            const content = document.createElement("div");
            const nameEl = document.createElement("div");
            nameEl.style.fontWeight = "600";
            nameEl.textContent = place.name;
            content.appendChild(nameEl);
            if (place.address) {
              const addressEl = document.createElement("div");
              addressEl.style.color = "#737373";
              addressEl.style.fontSize = "12px";
              addressEl.textContent = place.address;
              content.appendChild(addressEl);
            }
            infoWindow.setContent(content);
            infoWindow.open(map, marker);
          });
          bounds.extend(position);
        }

        if (located.length > 1) map.fitBounds(bounds, 40);
      })
      .catch(() => {
        if (!cancelled) setLoadError(true);
      });
    return () => {
      cancelled = true;
    };
  }, [apiKey, located]);

  if (loadError) {
    return (
      <div className="grid h-full place-items-center bg-neutral-50 px-6 text-center text-sm text-neutral-400">
        Couldn't load Google Maps — check your API key in Settings, or switch back to the free
        map.
      </div>
    );
  }

  return <div ref={containerRef} className="h-full w-full" />;
}
