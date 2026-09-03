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
