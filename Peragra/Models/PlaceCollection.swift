import Foundation
import SwiftData

/// A user-defined list within a trip (e.g. "Must eat", "If we have time")
/// used to group and filter saved places. Named `PlaceCollection` to avoid
/// clashing with Swift's `Collection` protocol.
@Model
final class PlaceCollection {
    var id: UUID
    var name: String
    var createdAt: Date
    // Marks the one auto-created, undeletable "Visited" list every trip
    // gets — kept in sync with each place's `visited` flag in both
    // directions, rather than a regular user-managed list. Defaulted (not
    // just set in init()) so SwiftData's lightweight migration can
    // backfill it on existing rows — same reason Place.favorite has one.
    var isVisitedList: Bool = false

    var trip: Trip?
    var places: [Place] = []

    init(name: String, trip: Trip?, isVisitedList: Bool = false) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.trip = trip
        self.isVisitedList = isVisitedList
    }

    /// Finds the trip's auto-created "Visited" list, creating (and
    /// inserting) it if this trip predates the feature.
    static func ensureVisitedList(for trip: Trip, context: ModelContext) -> PlaceCollection {
        if let existing = trip.collections.first(where: { $0.isVisitedList }) {
            return existing
        }
        let collection = PlaceCollection(name: "Visited", trip: trip, isVisitedList: true)
        context.insert(collection)
        return collection
    }
}
