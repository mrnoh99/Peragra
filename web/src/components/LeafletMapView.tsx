import { useEffect, useMemo } from "react";
import { MapContainer, Marker, Popup, TileLayer, useMap } from "react-leaflet";
import L from "leaflet";
import type { Place } from "../types";
import { googleMapsUrl } from "../lib/googleMapsUrl";
import { kakaoMapUrl } from "../lib/kakaoMapUrl";
import { naverMapUrl } from "../lib/naverMapUrl";
import { tmapUrl } from "../lib/tmapUrl";

const CATEGORY_ICON: Record<string, string> = {
  restaurant: "🍽️",
  cafe: "☕",
  attraction: "🎡",
  shopping: "🛍️",
  hotel: "🏨",
  nightlife: "🌃",
  other: "📍",
};

function makeIcon(category: string, visited: boolean) {
  return L.divIcon({
    className: "",
    html: `<div style="
      display:flex;align-items:center;justify-content:center;
      width:32px;height:32px;border-radius:9999px;
      background:${visited ? "#a3a3a3" : "#f9532c"};
      border:2px solid white;box-shadow:0 1px 4px rgba(0,0,0,0.35);
      font-size:16px;">${CATEGORY_ICON[category] ?? "📍"}</div>`,
    iconSize: [32, 32],
    iconAnchor: [16, 16],
    popupAnchor: [0, -16],
  });
}

function FitBounds({ points }: { points: [number, number][] }) {
  const map = useMap();
  useEffect(() => {
    if (points.length === 0) return;
    if (points.length === 1) {
      map.setView(points[0], 14);
    } else {
      map.fitBounds(L.latLngBounds(points), { padding: [40, 40] });
    }
  }, [map, points]);
  return null;
}

export function LeafletMapView({ places, destination }: { places: Place[]; destination: string }) {
  const located = useMemo(
    () => places.filter((p): p is Place & { lat: number; lng: number } => p.lat !== null && p.lng !== null),
    [places],
  );
  const points = useMemo<[number, number][]>(
    () => located.map((p) => [p.lat, p.lng]),
    [located],
  );

  const unlocated = places.length - located.length;

  return (
    <div>
      {unlocated > 0 && (
        <p className="mb-2 text-xs text-amber-600">
          {unlocated} place{unlocated > 1 ? "s" : ""} couldn't be placed on the map — add a more
          specific address to locate them.
        </p>
      )}
      <div className="h-[500px] w-full overflow-hidden rounded-2xl border border-black/5 shadow-sm">
        {located.length === 0 ? (
          <div className="grid h-full place-items-center bg-neutral-50 text-sm text-neutral-400">
            No located places yet — save a place with an address to see it here.
          </div>
        ) : (
          <MapContainer center={points[0]} zoom={13} scrollWheelZoom>
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            <FitBounds points={points} />
            {located.map((place) => {
              const kakaoUrl = kakaoMapUrl(place);
              const naverUrl = naverMapUrl(place);
              const tmapDestinationUrl = tmapUrl(place);
              return (
                <Marker
                  key={place.id}
                  position={[place.lat, place.lng]}
                  icon={makeIcon(place.category, place.visited)}
                >
                  <Popup>
                    <div className="min-w-[160px]">
                      <p className="font-semibold">{place.name}</p>
                      {place.address && (
                        <p className="text-xs text-neutral-500">{place.address}</p>
                      )}
                      <div className="mt-1 flex flex-col items-start gap-0.5">
                        <a
                          href={googleMapsUrl(place, destination)}
                          target="_blank"
                          rel="noreferrer"
                          className="text-xs text-brand-600 underline"
                        >
                          Open in Google Maps
                        </a>
                        {naverUrl && (
                          <a href={naverUrl} className="text-xs text-green-600 underline">
                            Open in Naver Map
                          </a>
                        )}
                        {kakaoUrl && (
                          <a
                            href={kakaoUrl}
                            target="_blank"
                            rel="noreferrer"
                            className="text-xs text-amber-600 underline"
                          >
                            Open in Kakao Map
                          </a>
                        )}
                        {tmapDestinationUrl && (
                          <a href={tmapDestinationUrl} className="text-xs text-sky-600 underline">
                            Open in Tmap
                          </a>
                        )}
                      </div>
                      {place.instagramUrl && (
                        <a
                          href={place.instagramUrl}
                          target="_blank"
                          rel="noreferrer"
                          className="text-xs text-pink-600 underline"
                        >
                          View on Instagram
                        </a>
                      )}
                    </div>
                  </Popup>
                </Marker>
              );
            })}
          </MapContainer>
        )}
      </div>
    </div>
  );
}
