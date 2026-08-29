import SwiftUI
import SwiftData

@main
struct PeragraApp: App {
    var body: some Scene {
        WindowGroup {
            TripsListView()
        }
        .modelContainer(for: [Trip.self, Place.self, PlaceCollection.self])
    }
}
