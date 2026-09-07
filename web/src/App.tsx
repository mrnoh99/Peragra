import { useEffect } from "react";
import { Route, Routes, useNavigate } from "react-router-dom";
import { Layout } from "./components/Layout";
import { TripsPage } from "./pages/TripsPage";
import { TripDetailPage } from "./pages/TripDetailPage";
import { AllPlacesPage } from "./pages/AllPlacesPage";
import { runAutoBackupIfDue } from "./lib/autoBackup";
import { setPendingSharedPlace } from "./lib/pendingSharedPlace";
import { parseSharedPlace } from "./lib/sharedPlaceImport";
import { useStore } from "./store/useStore";

// The board every OS-shared place (see share_target in
// manifest.webmanifest) lands in — created lazily the first time
// something's actually shared, not up front for every install.
const SHARED_PLACES_BOARD_NAME = "From Google";

function App() {
  const navigate = useNavigate();

  useEffect(() => {
    // The PWA's share_target navigates here with the shared content as
    // query params (method GET, so it's a plain page load, not a
    // fetch/service-worker interception) — present only when the app was
    // just opened via "Share" from another app (typically Google Maps).
    const params = new URLSearchParams(window.location.search);
    if (!params.has("title") && !params.has("text") && !params.has("url")) return;

    // Drop the query string either way, so refreshing or navigating back
    // to this URL later doesn't re-trigger the import.
    window.history.replaceState({}, "", window.location.pathname + window.location.hash);

    const shared = parseSharedPlace({
      title: params.get("title"),
      text: params.get("text"),
      url: params.get("url"),
    });
    if (!shared) return;

    const { trips, addTrip } = useStore.getState();
    const board =
      trips.find((t) => t.name === SHARED_PLACES_BOARD_NAME) ??
      addTrip({ name: SHARED_PLACES_BOARD_NAME, destination: "", coverEmoji: "🗺️", startDate: null, endDate: null });
    setPendingSharedPlace(shared);
    navigate(`/trips/${board.id}`);
  }, [navigate]);

  useEffect(() => {
    // Backfills country-list membership for every place, not just ones
    // that go through an add/edit/geocode/board-move from here on —
    // syncPlaceCountry only ever ran on those events, so a place that
    // was already geocoded before country lists existed (or before its
    // own last edit) was never going to get classified on its own.
    useStore.getState().syncAllPlaceCountries();

    // Checked once per app open (a web page has no true background
    // schedule) — writes a fresh backup to the chosen folder if
    // automatic backups are on and the configured interval has elapsed.
    const { trips, places, collections } = useStore.getState();
    void runAutoBackupIfDue(trips, places, collections);
  }, []);

  return (
    <Layout>
      <Routes>
        <Route path="/" element={<TripsPage />} />
        <Route path="/all-places" element={<AllPlacesPage />} />
        <Route path="/trips/:tripId" element={<TripDetailPage />} />
      </Routes>
    </Layout>
  );
}

export default App;
