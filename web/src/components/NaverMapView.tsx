import { useEffect, useMemo, useRef, useState } from "react";
import { loadNaverMapsScript } from "../lib/naverMapsLoader";
import { googleMapsUrl } from "../lib/googleMapsUrl";
import { kakaoMapUrl } from "../lib/kakaoMapUrl";
import { naverMapUrl } from "../lib/naverMapUrl";
import { tmapUrl } from "../lib/tmapUrl";
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
 * Renders saved places on a Naver Map, for people who've opted into Naver
 * Maps in Settings with their own NCP Client ID — mirrors GoogleMapView's
 * structure, just against Naver's JS API v3 instead (naver.maps.Map /
 * Marker / InfoWindow rather than google.maps' equivalents).
 */
export function NaverMapView({
  places,
  clientId,
  destination,
}: {
  places: Place[];
  clientId: string;
  destination: string;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [loadErrorMessage, setLoadErrorMessage] = useState<string | null>(null);
  const located = useMemo(
    () => places.filter((p): p is Place & { lat: number; lng: number } => p.lat !== null && p.lng !== null),
    [places],
  );

  useEffect(() => {
    let cancelled = false;
    loadNaverMapsScript(clientId)
      .then(() => {
        if (cancelled || !containerRef.current || !window.naver) return;
        setLoadErrorMessage(null);
        const { maps } = window.naver;

        const first = located[0];
        const map = new maps.Map(containerRef.current, {
          center: new maps.LatLng(first?.lat ?? 37.5665, first?.lng ?? 126.978),
          zoom: 13,
        });

        const bounds = new maps.LatLngBounds();
        const infoWindow = new maps.InfoWindow();

        for (const place of located) {
          const position = new maps.LatLng(place.lat, place.lng);
          const marker = new maps.Marker({
            position,
            map,
            icon: {
              content: `<div style="opacity:${place.visited ? 0.5 : 1};font-size:18px;line-height:1;transform:translate(-50%,-100%);">${CATEGORY_ICON[place.category] ?? "📍"}</div>`,
              anchor: { x: 0, y: 0 },
            },
          });
          maps.Event.addListener(marker, "click", () => {
            // Built as DOM nodes with textContent, not an HTML string, so
            // a place name/address containing markup (pasted from an
            // Instagram caption, say) can't inject into the page.
            const content = document.createElement("div");
            content.style.padding = "4px 2px";
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
            // No target="_blank" for Naver Map/Tmap — they're app-only
            // custom schemes (nmap://, tmap://) with no web fallback, so a
            // new tab would just sit blank behind when the app isn't
            // installed.
            const makeMapLink = (href: string, label: string, color: string, newTab: boolean) => {
              const linkEl = document.createElement("a");
              linkEl.href = href;
              if (newTab) {
                linkEl.target = "_blank";
                linkEl.rel = "noreferrer";
              }
              linkEl.textContent = label;
              linkEl.style.display = "block";
              linkEl.style.marginTop = "4px";
              linkEl.style.fontSize = "12px";
              linkEl.style.color = color;
              return linkEl;
            };
            content.appendChild(makeMapLink(googleMapsUrl(place, destination), "Open in Google Maps", "#2563eb", true));
            const naverUrl = naverMapUrl(place);
            if (naverUrl) content.appendChild(makeMapLink(naverUrl, "Open in Naver Map", "#16a34a", false));
            const kakaoUrl = kakaoMapUrl(place);
            if (kakaoUrl) content.appendChild(makeMapLink(kakaoUrl, "Open in Kakao Map", "#d97706", true));
            const tmapDestinationUrl = tmapUrl(place);
            if (tmapDestinationUrl) content.appendChild(makeMapLink(tmapDestinationUrl, "Open in Tmap", "#0284c7", false));
            infoWindow.setContent(content);
            infoWindow.open(map, marker);
          });
          bounds.extend(position);
        }

        if (located.length > 1) map.fitBounds(bounds);
      })
      .catch((error: unknown) => {
        console.error("Failed to load Naver Maps:", error);
        if (!cancelled) {
          setLoadErrorMessage(error instanceof Error ? error.message : "Couldn't load Naver Maps.");
        }
      });
    return () => {
      cancelled = true;
    };
  }, [clientId, located, destination]);

  if (loadErrorMessage) {
    return (
      <div className="grid h-full place-items-center bg-neutral-50 px-6 text-center text-sm text-neutral-400">
        <div>
          <p>{loadErrorMessage}</p>
          <p className="mt-1">Check your Client ID in Settings, or switch back to the free map.</p>
        </div>
      </div>
    );
  }

  return <div ref={containerRef} className="h-full w-full" />;
}
