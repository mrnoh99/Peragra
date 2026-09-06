import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { HashRouter } from "react-router-dom";
import "./index.css";
import App from "./App.tsx";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    {/* HashRouter, not BrowserRouter: this app is deployed to GitHub
        Pages (static file hosting, no server-side rewrites), where a
        direct/refreshed load of a path like /trips/abc 404s under
        BrowserRouter. Hash routes (/#/trips/abc) always resolve to
        index.html since the server never sees anything past the #. */}
    <HashRouter>
      <App />
    </HashRouter>
  </StrictMode>,
);

// Registering a service worker (alongside the manifest link in index.html)
// is what makes Chrome/Android offer "Install app" / "Add to Home
// screen" as a real standalone PWA instead of a plain browser shortcut.
// Skipped in dev so the Vite dev server's own reloading isn't shadowed by
// a stale cached response.
if ("serviceWorker" in navigator && import.meta.env.PROD) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`).catch(() => {});
  });
}
