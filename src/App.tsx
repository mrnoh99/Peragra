import { Route, Routes } from "react-router-dom";
import { Layout } from "./components/Layout";
import { TripsPage } from "./pages/TripsPage";
import { TripDetailPage } from "./pages/TripDetailPage";

function App() {
  return (
    <Layout>
      <Routes>
        <Route path="/" element={<TripsPage />} />
        <Route path="/trips/:tripId" element={<TripDetailPage />} />
      </Routes>
    </Layout>
  );
}

export default App;
