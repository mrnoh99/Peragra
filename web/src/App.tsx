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
