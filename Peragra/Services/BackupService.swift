import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Exports/restores the whole app's data (trips, places, lists) as one
/// JSON file — the same schema the web app's own backup uses, so a file
/// exported from one can be restored on the other. Dates are epoch
/// milliseconds (matching how the web app already stores them) except
/// each trip's start/end date, which stay "yyyy-MM-dd" text like the web
/// app's own date inputs. Ids are preserved on restore, so re-importing
/// the same backup twice reconstructs the same graph rather than
/// duplicating it.
enum BackupService {
    struct BackupTrip: Codable {
        let id: UUID
        let name: String
        let destination: String
        let coverEmoji: String
        let startDate: String?
        let endDate: String?
        let createdAt: Double
    }

    struct BackupPlace: Codable {
        let id: UUID
        let tripId: UUID
        let name: String
        let category: String
        let address: String
        let phone: String?
        let notes: String
        let instagramUrl: String?
        let linkUrl: String?
        let lat: Double?
        let lng: Double?
        let geocodeStatus: String
        let visited: Bool
        let visitedAt: Double?
        let favorite: Bool
        let collectionIds: [UUID]
        let createdAt: Double
    }

    struct BackupCollection: Codable {
        let id: UUID
        let tripId: UUID
        let name: String
        let isVisitedList: Bool
        let isFavoritesList: Bool
        let isCountryList: Bool
        let countryName: String?
        let createdAt: Double

        init(
            id: UUID,
            tripId: UUID,
            name: String,
            isVisitedList: Bool,
            isFavoritesList: Bool,
            isCountryList: Bool,
            countryName: String?,
            createdAt: Double
        ) {
            self.id = id
            self.tripId = tripId
            self.name = name
            self.isVisitedList = isVisitedList
            self.isFavoritesList = isFavoritesList
            self.isCountryList = isCountryList
            self.countryName = countryName
            self.createdAt = createdAt
        }

        // Backups made before the auto country-list feature existed won't
        // have isCountryList/countryName at all — default to "not a
        // country list" rather than failing to restore the whole file.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            tripId = try container.decode(UUID.self, forKey: .tripId)
            name = try container.decode(String.self, forKey: .name)
            isVisitedList = try container.decode(Bool.self, forKey: .isVisitedList)
            isFavoritesList = try container.decode(Bool.self, forKey: .isFavoritesList)
            isCountryList = try container.decodeIfPresent(Bool.self, forKey: .isCountryList) ?? false
            countryName = try container.decodeIfPresent(String.self, forKey: .countryName)
            createdAt = try container.decode(Double.self, forKey: .createdAt)
        }
    }

    struct BackupData: Codable {
        var app = "peragra"
        var version = 1
        var exportedAt: Double
        var trips: [BackupTrip]
        var places: [BackupPlace]
        var collections: [BackupCollection]
    }

    enum BackupError: LocalizedError {
        case invalidFile
        var errorDescription: String? {
            "That doesn't look like a Peragra backup file."
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }()

    static func filename(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "peragra_\(formatter.string(from: date))"
    }

    /// Filename (with .json extension, unlike filename(at:) above which
    /// is handed to .fileExporter and derives its own extension) for a
    /// single board's export — see exportBoard below.
    static func boardFilename(for trip: Trip, at date: Date = .now) -> String {
        let slug = trip.name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "peragra_board_\(slug.isEmpty ? "board" : slug)_\(formatter.string(from: date)).json"
    }

    static func exportData(context: ModelContext) throws -> Data {
        let trips = try context.fetch(FetchDescriptor<Trip>())
        let places = try context.fetch(FetchDescriptor<Place>())
        let collections = try context.fetch(FetchDescriptor<PlaceCollection>())

        let backup = BackupData(
            exportedAt: Date.now.timeIntervalSince1970 * 1000,
            trips: trips.map { trip in
                BackupTrip(
                    id: trip.id,
                    name: trip.name,
                    destination: trip.destination,
                    coverEmoji: trip.coverEmoji,
                    startDate: trip.startDate.map { dayFormatter.string(from: $0) },
                    endDate: trip.endDate.map { dayFormatter.string(from: $0) },
                    createdAt: trip.createdAt.timeIntervalSince1970 * 1000
                )
            },
            places: places.compactMap { place in
                guard let tripId = place.trip?.id else { return nil }
                return BackupPlace(
                    id: place.id,
                    tripId: tripId,
                    name: place.name,
                    category: place.categoryRaw,
                    address: place.address,
                    phone: place.phone,
                    notes: place.notes,
                    instagramUrl: place.instagramURLString,
                    linkUrl: place.linkURLString,
                    lat: place.latitude,
                    lng: place.longitude,
                    geocodeStatus: place.geocodeStatusRaw,
                    visited: place.visited,
                    visitedAt: place.visitedAt.map { $0.timeIntervalSince1970 * 1000 },
                    favorite: place.favorite,
                    collectionIds: place.collections.map(\.id),
                    createdAt: place.createdAt.timeIntervalSince1970 * 1000
                )
            },
            collections: collections.compactMap { collection in
                guard let tripId = collection.trip?.id else { return nil }
                return BackupCollection(
                    id: collection.id,
                    tripId: tripId,
                    name: collection.name,
                    isVisitedList: collection.isVisitedList,
                    isFavoritesList: collection.isFavoritesList,
                    isCountryList: collection.isCountryList,
                    countryName: collection.countryName,
                    createdAt: collection.createdAt.timeIntervalSince1970 * 1000
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// Same BackupData shape as exportData, scoped to just one board —
    /// its own places and lists, with real coordinates and visited/
    /// favorite status intact (unlike sharing a handful of place cards,
    /// which strips all of that as sender-board-specific). See
    /// importBoard below for the receiving end.
    static func exportBoard(_ trip: Trip) throws -> Data {
        let backup = BackupData(
            exportedAt: Date.now.timeIntervalSince1970 * 1000,
            trips: [
                BackupTrip(
                    id: trip.id,
                    name: trip.name,
                    destination: trip.destination,
                    coverEmoji: trip.coverEmoji,
                    startDate: trip.startDate.map { dayFormatter.string(from: $0) },
                    endDate: trip.endDate.map { dayFormatter.string(from: $0) },
                    createdAt: trip.createdAt.timeIntervalSince1970 * 1000
                ),
            ],
            places: trip.places.map { place in
                BackupPlace(
                    id: place.id,
                    tripId: trip.id,
                    name: place.name,
                    category: place.categoryRaw,
                    address: place.address,
                    phone: place.phone,
                    notes: place.notes,
                    instagramUrl: place.instagramURLString,
                    linkUrl: place.linkURLString,
                    lat: place.latitude,
                    lng: place.longitude,
                    geocodeStatus: place.geocodeStatusRaw,
                    visited: place.visited,
                    visitedAt: place.visitedAt.map { $0.timeIntervalSince1970 * 1000 },
                    favorite: place.favorite,
                    collectionIds: place.collections.map(\.id),
                    createdAt: place.createdAt.timeIntervalSince1970 * 1000
                )
            },
            collections: trip.collections.map { collection in
                BackupCollection(
                    id: collection.id,
                    tripId: trip.id,
                    name: collection.name,
                    isVisitedList: collection.isVisitedList,
                    isFavoritesList: collection.isFavoritesList,
                    isCountryList: collection.isCountryList,
                    countryName: collection.countryName,
                    createdAt: collection.createdAt.timeIntervalSince1970 * 1000
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// Adds board(s) from an already-parsed board/backup export as new
    /// boards alongside whatever's already here — unlike restore, which
    /// replaces everything and reuses the backup's own ids, this
    /// generates a fresh id for every trip/place/list so it can't
    /// collide with existing data (including re-importing the same
    /// shared board twice). Takes the parsed struct rather than raw Data
    /// since the caller (see ImportBoardSheet) already decoded it once
    /// to show a preview before the person confirms. Returns the newly
    /// created trips.
    @discardableResult
    static func importBoard(_ backup: BackupData, context: ModelContext) throws -> [Trip] {
        guard backup.app == "peragra" else { throw BackupError.invalidFile }

        var tripsByOldID: [UUID: Trip] = [:]
        var newTrips: [Trip] = []
        for backupTrip in backup.trips {
            let trip = Trip(
                name: backupTrip.name,
                destination: backupTrip.destination,
                coverEmoji: backupTrip.coverEmoji,
                startDate: backupTrip.startDate.flatMap(dayFormatter.date(from:)),
                endDate: backupTrip.endDate.flatMap(dayFormatter.date(from:))
            )
            trip.createdAt = Date(timeIntervalSince1970: backupTrip.createdAt / 1000)
            context.insert(trip)
            tripsByOldID[backupTrip.id] = trip
            newTrips.append(trip)
        }

        var collectionsByOldID: [UUID: PlaceCollection] = [:]
        for backupCollection in backup.collections {
            guard let trip = tripsByOldID[backupCollection.tripId] else { continue }
            let collection = PlaceCollection(
                name: backupCollection.name,
                trip: trip,
                isVisitedList: backupCollection.isVisitedList,
                isFavoritesList: backupCollection.isFavoritesList,
                isCountryList: backupCollection.isCountryList,
                countryName: backupCollection.countryName
            )
            collection.createdAt = Date(timeIntervalSince1970: backupCollection.createdAt / 1000)
            context.insert(collection)
            collectionsByOldID[backupCollection.id] = collection
        }

        for backupPlace in backup.places {
            guard let trip = tripsByOldID[backupPlace.tripId] else { continue }
            let place = Place(
                name: backupPlace.name,
                category: PlaceCategory(rawValue: backupPlace.category) ?? .other,
                address: backupPlace.address,
                phone: backupPlace.phone,
                notes: backupPlace.notes,
                instagramURLString: backupPlace.instagramUrl,
                linkURLString: backupPlace.linkUrl,
                trip: trip
            )
            place.latitude = backupPlace.lat
            place.longitude = backupPlace.lng
            place.geocodeStatusRaw = backupPlace.geocodeStatus
            place.visited = backupPlace.visited
            place.visitedAt = backupPlace.visitedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            place.favorite = backupPlace.favorite
            place.createdAt = Date(timeIntervalSince1970: backupPlace.createdAt / 1000)
            place.collections = backupPlace.collectionIds.compactMap { collectionsByOldID[$0] }
            context.insert(place)
        }

        try context.save()
        return newTrips
    }

    /// Replaces every current trip/place/list with the backup's contents
    /// — matches "restore" (return to that snapshot) rather than merging
    /// it into what's already here.
    static func restore(from data: Data, context: ModelContext) throws {
        let backup: BackupData
        do {
            backup = try JSONDecoder().decode(BackupData.self, from: data)
        } catch {
            throw BackupError.invalidFile
        }
        guard backup.app == "peragra" else { throw BackupError.invalidFile }

        for trip in try context.fetch(FetchDescriptor<Trip>()) { context.delete(trip) }
        for place in try context.fetch(FetchDescriptor<Place>()) { context.delete(place) }
        for collection in try context.fetch(FetchDescriptor<PlaceCollection>()) { context.delete(collection) }

        var tripsByID: [UUID: Trip] = [:]
        for backupTrip in backup.trips {
            let trip = Trip(
                name: backupTrip.name,
                destination: backupTrip.destination,
                coverEmoji: backupTrip.coverEmoji,
                startDate: backupTrip.startDate.flatMap(dayFormatter.date(from:)),
                endDate: backupTrip.endDate.flatMap(dayFormatter.date(from:))
            )
            trip.id = backupTrip.id
            trip.createdAt = Date(timeIntervalSince1970: backupTrip.createdAt / 1000)
            context.insert(trip)
            tripsByID[trip.id] = trip
        }

        var collectionsByID: [UUID: PlaceCollection] = [:]
        for backupCollection in backup.collections {
            guard let trip = tripsByID[backupCollection.tripId] else { continue }
            let collection = PlaceCollection(
                name: backupCollection.name,
                trip: trip,
                isVisitedList: backupCollection.isVisitedList,
                isFavoritesList: backupCollection.isFavoritesList,
                isCountryList: backupCollection.isCountryList,
                countryName: backupCollection.countryName
            )
            collection.id = backupCollection.id
            collection.createdAt = Date(timeIntervalSince1970: backupCollection.createdAt / 1000)
            context.insert(collection)
            collectionsByID[collection.id] = collection
        }

        for backupPlace in backup.places {
            guard let trip = tripsByID[backupPlace.tripId] else { continue }
            let place = Place(
                name: backupPlace.name,
                category: PlaceCategory(rawValue: backupPlace.category) ?? .other,
                address: backupPlace.address,
                phone: backupPlace.phone,
                notes: backupPlace.notes,
                instagramURLString: backupPlace.instagramUrl,
                linkURLString: backupPlace.linkUrl,
                trip: trip
            )
            place.id = backupPlace.id
            place.latitude = backupPlace.lat
            place.longitude = backupPlace.lng
            place.geocodeStatusRaw = backupPlace.geocodeStatus
            place.visited = backupPlace.visited
            place.visitedAt = backupPlace.visitedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            place.favorite = backupPlace.favorite
            place.createdAt = Date(timeIntervalSince1970: backupPlace.createdAt / 1000)
            place.collections = backupPlace.collectionIds.compactMap { collectionsByID[$0] }
            context.insert(place)
        }

        try context.save()
    }
}

/// Minimal `FileDocument` wrapper so `.fileExporter` can hand the already-
/// built backup JSON to the system's save-location picker (Files app,
/// iCloud Drive, On My iPhone, ...) instead of writing to a fixed path.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
