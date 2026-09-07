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
    // clean install.
    //
    // The actual root cause, once this stopped swallowing the real error:
    // ModelConfiguration's cloudKitDatabase parameter defaults to
    // `.automatic`, which turns on CloudKit-backed sync as soon as the
    // app's entitlements declare an iCloud container — which
    // Peragra.entitlements does, for CloudBackupService's own manual JSON
    // export/import to iCloud Drive (nothing to do with SwiftData's native
    // CloudKit sync). CloudKit-backed persistence requires every
    // non-optional attribute to carry an inline default value, not just
    // one assigned in init() — Trip/Place/PlaceCollection's original
    // properties (id, name, destination, ...) only ever got theirs from
    // init(), so CloudKit's schema validation rejected the container on
    // every attempt, on every device, since long before this session's
    // changes — it just always failed silently until this explicit
    // construction removed the convenience modifier's fallback and
    // surfaced it. `.none` here is the actual fix: this app was never
    // meant to use SwiftData's own CloudKit sync at all.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Trip.self, Place.self, PlaceCollection.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
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
