import Foundation
import SwiftData

@Model
final class Place {
    var id: UUID
    var name: String
    var categoryRaw: String
    var address: String
    var phone: String?
    var notes: String
    var instagramURLString: String?
    var latitude: Double?
    var longitude: Double?
    var geocodeStatusRaw: String
    var visited: Bool
    var favorite: Bool
    var createdAt: Date

    var trip: Trip?

    @Relationship(inverse: \PlaceCollection.places)
    var collections: [PlaceCollection] = []

    init(
        name: String,
        category: PlaceCategory,
        address: String,
        phone: String? = nil,
        notes: String,
        instagramURLString: String?,
        trip: Trip?
    ) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.address = address
        self.phone = phone
        self.notes = notes
        self.instagramURLString = instagramURLString
        self.latitude = nil
        self.longitude = nil
        self.geocodeStatusRaw = GeocodeStatus.pending.rawValue
        self.visited = false
        self.favorite = false
        self.createdAt = .now
        self.trip = trip
    }

    var category: PlaceCategory {
        get { PlaceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var geocodeStatus: GeocodeStatus {
        get { GeocodeStatus(rawValue: geocodeStatusRaw) ?? .pending }
        set { geocodeStatusRaw = newValue.rawValue }
    }

    var instagramURL: URL? {
        instagramURLString.flatMap(URL.init(string:))
    }

    var coordinate2D: (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        return (latitude, longitude)
    }
}
