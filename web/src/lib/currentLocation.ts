/**
 * One-shot fetch of the device's current coordinate, for tagging a place
 * with exactly where its "Take Photo Here" photo was taken — wraps the
 * callback-based Geolocation API as a single Promise. Resolves to null
 * (rather than throwing) on any failure — permission denied, no
 * geolocation support, or a timeout — since the caller treats "couldn't
 * get a location" as a fallback case, not an error to surface loudly.
 */
export function getCurrentLocation(): Promise<{ lat: number; lng: number } | null> {
  if (!("geolocation" in navigator)) return Promise.resolve(null);

  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (position) => resolve({ lat: position.coords.latitude, lng: position.coords.longitude }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: 8000, maximumAge: 0 },
    );
  });
}
