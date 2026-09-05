import Foundation
import SwiftData

@Model
final class Trip {
    /// Cover-icon choices shared by board creation and board editing.
    static let coverEmojiChoices = ["✈️", "🗺️", "🏖️", "🏙️", "⛰️", "🍜", "🎡", "🚆"]

    var id: UUID
    var name: String
    var destination: String
    var coverEmoji: String
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Place.trip)
    var places: [Place] = []

    @Relationship(deleteRule: .cascade, inverse: \PlaceCollection.trip)
    var collections: [PlaceCollection] = []

    init(
        name: String,
        destination: String,
        coverEmoji: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.destination = destination
        self.coverEmoji = coverEmoji
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = .now
    }
}
