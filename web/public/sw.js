// Bump this whenever the caching strategy itself changes, so old clients
// drop their stale cache on the next activate rather than keeping it
// forever — it does NOT need to change for ordinary app deploys (hashed
// build assets get fresh URLs on their own, and navigations are always
// network-first below).
const CACHE_NAME = "peragra-cache-v1";
const SCOPE = self.registration.scope;

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

// HashRouter means every route the app has lives at one URL (the scope
// root) with a #fragment the server never sees, so caching that one
// document covers offline navigation for the whole app.
//
// Each branch awaits its cache write before resolving — respondWith()
// only keeps the worker alive until the promise it's given settles, so a
// cache.put() left to run after that (a plain un-awaited .then()) can get
// killed mid-write and silently never land.
self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET" || !request.url.startsWith("http")) return;

  if (request.mode === "navigate") {
    event.respondWith(
      (async () => {
        try {
          const response = await fetch(request);
          const cache = await caches.open(CACHE_NAME);
          await cache.put(SCOPE, response.clone());
          return response;
        } catch {
          const cached = await caches.match(SCOPE);
          return cached || Response.error();
        }
      })(),
    );
    return;
  }

  // Everything else (JS/CSS/icons) is cache-first: Vite's build output is
  // content-hashed, so the same URL never needs re-fetching once cached.
  event.respondWith(
    (async () => {
      const cached = await caches.match(request);
      if (cached) return cached;
      const response = await fetch(request);
      if (response.ok) {
        const cache = await caches.open(CACHE_NAME);
        await cache.put(request, response.clone());
      }
      return response;
    })(),
  );
});
