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
    // Set when `visited` is turned on (by whichever control does it — the
    // checkmark button or adding to the Visited list), cleared when
    // turned back off. Same default-value requirement as `favorite`
    // above, for lightweight migration on existing rows.
    var visitedAt: Date? = nil
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
        self.visitedAt = nil
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
        visitedAt = willBeVisited ? .now : nil
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

    /// Marks this place visited at a specific moment, rather than
    /// toggleVisited's always-`.now` — for a place whose visit
    /// demonstrably already happened, like one logged from an on-site
    /// photo taken at a known time. Keeps the trip's default "Visited"
    /// list in sync the same way toggleVisited does.
    func markVisited(at date: Date, context: ModelContext) {
        visited = true
        visitedAt = date
        guard let trip else { return }
        let visitedList = PlaceCollection.ensureVisitedList(for: trip, context: context)
        if !collections.contains(where: { $0.id == visitedList.id }) {
            collections.append(visitedList)
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

    /// Recomputes which auto-created "country" list (if any) this place
    /// belongs to, from its current name/address text and geocoded
    /// coordinates — mirrors MapProviderPolicy's Korea/non-Korea signal
    /// but resolves an actual country name rather than just yes/no.
    /// Call after anything that could change either (added, edited,
    /// geocoded, or moved to a different board). Creates the country's
    /// list the first time a place needs it, and prunes any auto country
    /// list left with no members (on any trip, since a board move can
    /// orphan one).
    func syncCountryList(context: ModelContext) {
        guard let trip else { return }

        var countryName = CountryNames.detectCountryFromText(address)
        if countryName == nil { countryName = CountryNames.detectCountryFromText(name) }
        if countryName == nil, let latitude, let longitude, KoreaRegion.contains(latitude: latitude, longitude: longitude) {
            countryName = "South Korea"
        }

        let countryCollections = trip.collections.filter(\.isCountryList)
        var target: PlaceCollection?
        if let countryName {
            target = countryCollections.first { $0.countryName == countryName }
            if target == nil {
                let collection = PlaceCollection(name: countryName, trip: trip, isCountryList: true, countryName: countryName)
                context.insert(collection)
                target = collection
            }
        }

        for collection in countryCollections where collection.id != target?.id {
            collections.removeAll { $0.id == collection.id }
        }
        if let target, !collections.contains(where: { $0.id == target.id }) {
            collections.append(target)
        }

        Self.pruneEmptyCountryLists(context: context)
    }

    /// Auto country lists are fully derived from place data, so any that
    /// lost its last member (e.g. after a board move away from it) is
    /// deleted rather than left behind as clutter.
    private static func pruneEmptyCountryLists(context: ModelContext) {
        let descriptor = FetchDescriptor<PlaceCollection>(predicate: #Predicate<PlaceCollection> { $0.isCountryList })
        guard let countryLists = try? context.fetch(descriptor) else { return }
        for list in countryLists where list.places.isEmpty {
            context.delete(list)
        }
    }
}
