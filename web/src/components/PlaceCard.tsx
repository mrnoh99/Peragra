import { useRef, useState } from "react";
import { PLACE_CATEGORIES, type Collection, type Place } from "../types";
import { useStore } from "../store/useStore";
import { EditPlaceModal } from "./EditPlaceModal";
import { googleMapsUrl } from "../lib/googleMapsUrl";
import { geocodePlaceByAddressOrName } from "../lib/geocode";
import { kakaoMapUrl } from "../lib/kakaoMapUrl";
import { naverMapUrl } from "../lib/naverMapUrl";
import { tmapUrl } from "../lib/tmapUrl";
import { openCustomSchemeUrl } from "../lib/customSchemeUrl";

/** A manually-typed link often has no "https://" — this adds one so it's
 *  actually clickable (browsers resolve a bare "instagram.com/..." href
 *  as a relative path, not the address it looks like) and so hostname
 *  parsing below actually works. */
function normalizeLinkHref(url: string): string {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(url) ? url : `https://${url}`;
}

/** Whether a manually-entered link points at Instagram — used to label it
 *  "Instagram" instead of the generic "Website" on the card. */
function isInstagramLink(url: string): boolean {
  try {
    return new URL(normalizeLinkHref(url)).hostname.replace(/^www\./, "") === "instagram.com";
  } catch {
    return false;
  }
}

function formatVisitedDate(timestamp: number): string {
  return new Date(timestamp).toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

/** Notes past this length get a "Show more" toggle instead of always
 *  stretching the card to fit — long enough that a short one-line note
 *  never shows the toggle at all. */
const NOTES_COLLAPSE_THRESHOLD = 140;

const CATEGORY_ICON: Record<string, string> = {
  restaurant: "🍽️",
  cafe: "☕",
  attraction: "🎡",
  shopping: "🛍️",
  hotel: "🏨",
  nightlife: "🌃",
  other: "📍",
};

export function PlaceCard({
  place,
  collections,
  destination,
  selectable = false,
  selected = false,
  onToggleSelect,
  distanceKm,
}: {
  place: Place;
  collections: Collection[];
  destination: string;
  selectable?: boolean;
  selected?: boolean;
  onToggleSelect?: () => void;
  /** Shown as "N km away" when sorting by distance from a reference place. */
  distanceKm?: number;
}) {
  const toggleVisited = useStore((s) => s.toggleVisited);
  const toggleFavorite = useStore((s) => s.toggleFavorite);
  const deletePlace = useStore((s) => s.deletePlace);
  const togglePlaceCollection = useStore((s) => s.togglePlaceCollection);
  const setPlaceCoords = useStore((s) => s.setPlaceCoords);
  const allPlaces = useStore((s) => s.places);
  const [showCollections, setShowCollections] = useState(false);
  const [showMapMenu, setShowMapMenu] = useState(false);
  const [editing, setEditing] = useState(false);
  const [copied, setCopied] = useState(false);
  const [notesExpanded, setNotesExpanded] = useState(false);
  const [isRetryingGeocode, setIsRetryingGeocode] = useState(false);
  const longPressTimer = useRef<number | null>(null);

  // Lets a failed pin be retried without editing the address — e.g. after
  // switching map providers in Settings, or because this fix's own
  // geocodePlaceByAddressOrName fallback (try the name when the address
  // text doesn't resolve) wasn't in effect the first time this ran.
  async function retryGeocode() {
    setIsRetryingGeocode(true);
    try {
      const siblingPlaces = allPlaces.filter((p) => p.tripId === place.tripId && p.id !== place.id);
      const result = await geocodePlaceByAddressOrName(place, destination, siblingPlaces);
      setPlaceCoords(place.id, result, result ? "located" : "failed");
    } catch {
      setPlaceCoords(place.id, null, "failed");
    } finally {
      setIsRetryingGeocode(false);
    }
  }

  const categoryLabel =
    PLACE_CATEGORIES.find((c) => c.value === place.category)?.label ?? "Other";
  const kakaoUrl = kakaoMapUrl(place);
  const naverUrl = naverMapUrl(place);
  const tmapDestinationUrl = tmapUrl(place);

  function copyForMaps() {
    const text = place.address ? `${place.name}, ${place.address}` : place.name;
    navigator.clipboard
      ?.writeText(text)
      .then(() => {
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1500);
      })
      .catch(() => {});
  }

  function startLongPress() {
    longPressTimer.current = window.setTimeout(copyForMaps, 550);
  }

  function cancelLongPress() {
    if (longPressTimer.current !== null) {
      window.clearTimeout(longPressTimer.current);
      longPressTimer.current = null;
    }
  }

  return (
    <div
      className="relative rounded-xl border border-black/5 bg-white p-4 shadow-sm"
      onPointerDown={startLongPress}
      onPointerUp={cancelLongPress}
      onPointerLeave={cancelLongPress}
      onPointerCancel={cancelLongPress}
      onContextMenu={(e) => e.preventDefault()}
    >
      {copied && (
        <div className="absolute right-3 top-3 z-10 rounded-full bg-neutral-900/90 px-2.5 py-1 text-xs font-medium text-white">
          Copied for Google Maps
        </div>
      )}
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-start gap-2">
          {selectable && (
            <input
              type="checkbox"
              checked={selected}
              onChange={onToggleSelect}
              className="mt-1.5 h-4 w-4 shrink-0"
            />
          )}
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <button
                onClick={() => toggleFavorite(place.id)}
                aria-label={place.favorite ? "Remove from favorites" : "Mark as favorite"}
                className={`shrink-0 leading-none ${
                  place.favorite ? "text-amber-400" : "text-neutral-300 hover:text-amber-300"
                }`}
              >
                {place.favorite ? "★" : "☆"}
              </button>
              <span>{CATEGORY_ICON[place.category] ?? "📍"}</span>
              <h3
                className={`truncate font-semibold ${
                  place.visited ? "text-red-600" : "text-neutral-900"
                }`}
              >
                {place.name}
              </h3>
            </div>
            <p className="mt-0.5 text-xs font-medium uppercase tracking-wide text-neutral-400">
              {categoryLabel}
              {distanceKm !== undefined && (
                <span className="ml-2 normal-case text-neutral-400">
                  · {distanceKm < 1 ? `${Math.round(distanceKm * 1000)} m` : `${distanceKm.toFixed(1)} km`} away
                </span>
              )}
            </p>
            {(place.address || place.phone) && (
              <p className="mt-1 text-sm text-neutral-500">
                {place.address}
                {place.address && place.phone && " · "}
                {place.phone && `☎ ${place.phone}`}
              </p>
            )}
            {place.notes && (
              <div className="mt-1">
                <p className={`text-sm text-neutral-600 ${notesExpanded ? "" : "line-clamp-3"}`}>
                  {place.notes}
                </p>
                {place.notes.length > NOTES_COLLAPSE_THRESHOLD && (
                  <button
                    type="button"
                    onClick={() => setNotesExpanded((v) => !v)}
                    className="mt-0.5 text-xs font-medium text-brand-600 hover:underline"
                  >
                    {notesExpanded ? "Show less" : "Show more"}
                  </button>
                )}
              </div>
            )}
            {place.geocodeStatus === "failed" && (
              <p className="mt-1 text-xs text-amber-600">
                Couldn't locate this on the map — try adding a more specific address, or{" "}
                <button
                  type="button"
                  onClick={retryGeocode}
                  disabled={isRetryingGeocode}
                  className="font-medium underline hover:no-underline disabled:no-underline disabled:opacity-60"
                >
                  {isRetryingGeocode ? "Retrying…" : "retry"}
                </button>
                .
              </p>
            )}
            {place.geocodeStatus === "estimated" && (
              <p className="mt-1 text-xs text-neutral-400">
                📍 Approximate location — AI's best guess, since the given address couldn't be
                found on the map.
              </p>
            )}
            <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs font-medium">
              <div className="relative">
                <button
                  type="button"
                  onClick={() => setShowMapMenu((v) => !v)}
                  className="inline-flex items-center gap-1 text-brand-600 hover:underline"
                >
                  🗺️ Open in Map {showMapMenu ? "▲" : "▼"}
                </button>
                {showMapMenu && (
                  <div className="absolute left-0 top-full z-10 mt-1 flex min-w-[9rem] flex-col gap-0.5 rounded-lg border border-neutral-200 bg-white p-1.5 shadow-lg">
                    <a
                      href={googleMapsUrl(place, destination)}
                      target="_blank"
                      rel="noreferrer"
                      onClick={() => setShowMapMenu(false)}
                      className="whitespace-nowrap rounded px-2 py-1 text-left text-neutral-600 hover:bg-neutral-50"
                    >
                      Google Maps
                    </a>
                    {naverUrl && (
                      // Not a plain <a href> — nmap:// needs
                      // openCustomSchemeUrl's own launch mechanism (an
                      // invisible anchor click, not a direct navigation)
                      // to actually switch to the app reliably; see that
                      // function for why. It also handles Android's
                      // intent:// wrapping and Safari's own "address is
                      // invalid" alert when the app isn't installed.
                      <button
                        type="button"
                        onClick={() => {
                          setShowMapMenu(false);
                          openCustomSchemeUrl(naverUrl);
                        }}
                        className="whitespace-nowrap rounded px-2 py-1 text-left text-neutral-600 hover:bg-neutral-50"
                      >
                        Naver Map
                      </button>
                    )}
                    {kakaoUrl && (
                      <a
                        href={kakaoUrl}
                        target="_blank"
                        rel="noreferrer"
                        onClick={() => setShowMapMenu(false)}
                        className="whitespace-nowrap rounded px-2 py-1 text-left text-neutral-600 hover:bg-neutral-50"
                      >
                        Kakao Map
                      </a>
                    )}
                    {tmapDestinationUrl && (
                      // Same reason as Naver Map above.
                      <button
                        type="button"
                        onClick={() => {
                          setShowMapMenu(false);
                          openCustomSchemeUrl(tmapDestinationUrl);
                        }}
                        className="whitespace-nowrap rounded px-2 py-1 text-left text-neutral-600 hover:bg-neutral-50"
                      >
                        Tmap
                      </button>
                    )}
                  </div>
                )}
              </div>
              {place.instagramUrl && (
                <a
                  href={place.instagramUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center gap-1 text-pink-600 hover:underline"
                >
                  📷 Instagram
                </a>
              )}
              {place.linkUrl && (
                <a
                  href={normalizeLinkHref(place.linkUrl)}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center gap-1 text-brand-600 hover:underline"
                >
                  {isInstagramLink(place.linkUrl) ? "📷 Instagram" : "🔗 Website"}
                </a>
              )}
            </div>
          </div>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-1.5">
          <button
            onClick={() => toggleVisited(place.id)}
            className={`rounded-full px-2.5 py-1 text-xs font-medium ${
              place.visited
                ? "bg-green-100 text-green-700"
                : "bg-neutral-100 text-neutral-500 hover:bg-neutral-200"
            }`}
          >
            {place.visited ? "Visited" : "Mark visited"}
          </button>
          {place.visited && place.visitedAt && (
            <span className="text-xs text-neutral-400">{formatVisitedDate(place.visitedAt)}</span>
          )}
          <div className="flex gap-2">
            <button
              onClick={() => setEditing(true)}
              className="text-xs text-neutral-400 hover:text-brand-600"
            >
              Edit
            </button>
            <button
              onClick={() => {
                if (confirm(`Remove "${place.name}"?`)) deletePlace(place.id);
              }}
              className="text-xs text-neutral-400 hover:text-red-500"
            >
              Remove
            </button>
          </div>
        </div>
      </div>

      {collections.length > 0 && (
        <div className="mt-3 border-t border-neutral-100 pt-2">
          <button
            onClick={() => setShowCollections((v) => !v)}
            className="text-xs font-medium text-neutral-400 hover:text-neutral-600"
          >
            {place.collectionIds.length > 0
              ? `In ${place.collectionIds.length} list${place.collectionIds.length > 1 ? "s" : ""}`
              : "Add to list"}{" "}
            {showCollections ? "▲" : "▼"}
          </button>
          {showCollections && (
            <div className="mt-2 flex flex-wrap gap-1.5">
              {collections.map((c) => {
                const active = place.collectionIds.includes(c.id);
                return (
                  <button
                    key={c.id}
                    onClick={() => togglePlaceCollection(place.id, c.id)}
                    className={`rounded-full border px-2.5 py-1 text-xs ${
                      active
                        ? "border-brand-500 bg-brand-50 text-brand-700"
                        : "border-neutral-200 text-neutral-600 hover:bg-neutral-50"
                    }`}
                  >
                    {c.name}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      )}

      {editing && (
        <EditPlaceModal place={place} destination={destination} onClose={() => setEditing(false)} />
      )}
    </div>
  );
}
