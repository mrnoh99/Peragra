import SwiftUI
import SwiftData

@main
struct PeragraApp: App {
    // Built explicitly (schema + an explicit ModelConfiguration), rather
    // than the `.modelContainer(for:)` Scene-level convenience modifier,
    // after that convenience form was found — via
    // container.configurations.first?.url — to be silently backing every
    // board with a store at "/dev/null" (CoreData/SwiftData's internal
    // signature for an in-memory-only store) on a real device, with no
    // explicit inMemory flag anywhere in this app to explain it and no
    // crash to reveal it: every insert/save silently no-oped, which is
    // exactly how "board가 안 만들어짐" kept reproducing on a completely
    // clean install. Being explicit about isStoredInMemoryOnly: false, and
    // constructing the container ourselves, either fixes that or — if the
    // real container creation is genuinely failing for some other reason —
    // surfaces the actual underlying error instead of a silent fallback.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Trip.self, Place.self, PlaceCollection.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create Peragra's persistent store: \(error)")
        }
    }

    let container = Self.makeContainer()

    var body: some Scene {
        WindowGroup {
            TripsListView()
        }
        .modelContainer(container)
    }
}
