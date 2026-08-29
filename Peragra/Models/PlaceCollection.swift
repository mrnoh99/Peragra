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

    var trip: Trip?
    var places: [Place] = []

    init(name: String, trip: Trip?) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.trip = trip
    }
}
