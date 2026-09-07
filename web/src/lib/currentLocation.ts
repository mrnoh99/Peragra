export interface LocationFix {
  lat: number;
  lng: number;
  // The browser's own reported accuracy (meters) for this fix — sizes
  // the nearby-places search radius (see nearbyPlaces.ts) rather than
  // assuming one fixed distance always covers this fix's real margin
  // of error.
  accuracy: number | null;
}

export function getCurrentLocation(): Promise<LocationFix | null> {
  if (!("geolocation" in navigator)) return Promise.resolve(null);
  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (position) =>
        resolve({ lat: position.coords.latitude, lng: position.coords.longitude, accuracy: position.coords.accuracy }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: 8000, maximumAge: 0 },
    );
  });
}
