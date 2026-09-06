import Foundation
import CoreLocation

/// Finds places on the same board that look like the same real-world spot
/// saved more than once — mirrors web/src/lib/duplicatePlaces.ts so both
/// platforms flag the same groups the same way.
enum DuplicatePlaces {
    /// Lowercases and strips everything but letters/digits, so "Blue Bottle
    /// Coffee", "blue-bottle coffee!", and "BlueBottleCoffee" all compare
    /// equal — the differences that actually show up between the same
    /// place typed twice (spacing, punctuation, case) rather than real
    /// distinctions.
    private static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Places within this distance of each other, with matching names, are
    /// treated as the same real-world place — loose enough to cover a
    /// geocoder snapping to a slightly different point on the same
    /// building or block, tight enough that two different branches of the
    /// same chain don't get merged.
    private static let duplicateDistanceMeters: CLLocationDistance = 150

    /// Whether two places look like the same real-world place saved
    /// twice: their names must match (after normalizing away
    /// case/spacing/punctuation), AND either their coordinates are close
    /// together, their addresses match/overlap, or — only when neither
    /// place has any coordinate or address to compare — the name match
    /// stands on its own, since there's nothing else available to check.
    static func likelyDuplicate(_ a: Place, _ b: Place) -> Bool {
        let trimmedA = a.name.trimmingCharacters(in: .whitespaces)
        let trimmedB = b.name.trimmingCharacters(in: .whitespaces)
        guard !trimmedA.isEmpty, !trimmedB.isEmpty else { return false }
        guard normalize(a.name) == normalize(b.name) else { return false }

        if let latA = a.latitude, let lngA = a.longitude, let latB = b.latitude, let lngB = b.longitude {
            let locationA = CLLocation(latitude: latA, longitude: lngA)
            let locationB = CLLocation(latitude: latB, longitude: lngB)
            return locationA.distance(from: locationB) <= duplicateDistanceMeters
        }

        let addrA = normalize(a.address)
        let addrB = normalize(b.address)
        if !addrA.isEmpty, !addrB.isEmpty {
            return addrA == addrB || addrA.contains(addrB) || addrB.contains(addrA)
        }

        // Neither has a coordinate, and at least one has no address
        // either — nothing left to compare but the name, which already
        // matched.
        return true
    }

    /// Groups a board's places into duplicate clusters — union-find over
    /// likelyDuplicate so A-matches-B and B-matches-C still group all
    /// three together even if A and C weren't compared as a close enough
    /// pair directly. Only groups of 2+ are returned; places with no
    /// duplicate are simply omitted rather than returned as singleton
    /// groups.
    static func findDuplicateGroups(_ places: [Place]) -> [[Place]] {
        var parent: [UUID: UUID] = [:]

        func find(_ id: UUID) -> UUID {
            var root = id
            while let next = parent[root], next != root {
                root = next
            }
            parent[id] = root
            return root
        }

        func union(_ a: UUID, _ b: UUID) {
            let rootA = find(a)
            let rootB = find(b)
            if rootA != rootB { parent[rootA] = rootB }
        }

        for place in places { parent[place.id] = place.id }

        for i in 0..<places.count {
            for j in (i + 1)..<places.count where j > i {
                if likelyDuplicate(places[i], places[j]) {
                    union(places[i].id, places[j].id)
                }
            }
        }

        var groups: [UUID: [Place]] = [:]
        for place in places {
            groups[find(place.id), default: []].append(place)
        }

        return groups.values.filter { $0.count > 1 }
    }
}
