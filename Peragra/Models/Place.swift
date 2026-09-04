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
    // A default value here (not just in init()) is required for SwiftData's
    // automatic lightweight migration to backfill this attribute on
    // existing rows — favorite was added to this model after some users
    // already had a persisted store without it, and without a default,
    // migration fails outright with "missing attribute values on
    // mandatory destination attribute" (a real reported crash, not
    // theoretical).
    var favorite: Bool = false
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

    /// Toggles `visited` and keeps membership in the trip's default
    /// "Visited" list in sync in both directions — this is the other
    /// control (besides adding/removing that list directly) that marks a
    /// place visited.
    func toggleVisited(context: ModelContext) {
        let willBeVisited = !visited
        visited = willBeVisited
        guard let trip else { return }
        let visitedList = PlaceCollection.ensureVisitedList(for: trip, context: context)
        if willBeVisited {
            if !collections.contains(where: { $0.id == visitedList.id }) {
                collections.append(visitedList)
            }
        } else {
            collections.removeAll { $0.id == visitedList.id }
        }
    }

    /// Same as toggleVisited, for `favorite` and the default "Favorites" list.
    func toggleFavorite(context: ModelContext) {
        let willBeFavorite = !favorite
        favorite = willBeFavorite
        guard let trip else { return }
        let favoritesList = PlaceCollection.ensureFavoritesList(for: trip, context: context)
        if willBeFavorite {
            if !collections.contains(where: { $0.id == favoritesList.id }) {
                collections.append(favoritesList)
            }
        } else {
            collections.removeAll { $0.id == favoritesList.id }
        }
    }
}
