import { useEffect } from "react";
import { Route, Routes } from "react-router-dom";
import { Layout } from "./components/Layout";
import { TripsPage } from "./pages/TripsPage";
import { TripDetailPage } from "./pages/TripDetailPage";
import { AllPlacesPage } from "./pages/AllPlacesPage";
import { runAutoBackupIfDue } from "./lib/autoBackup";
import { useStore } from "./store/useStore";

function App() {
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
