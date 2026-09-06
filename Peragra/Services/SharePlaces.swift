import Foundation

/// A place stripped down to what's worth handing to someone else — no
/// id, board, coordinates, visited/favorite status, or collections,
/// since those are either meaningless or private outside the sender's
/// own board. The recipient's copy gets its own id and is geocoded
/// fresh on import. Mirrors web/src/lib/sharePlaces.ts's SharedPlace so
/// a share copied on one platform pastes cleanly on the other.
struct SharedPlace: Codable {
    let name: String
    let category: String
    let address: String
    let phone: String?
    let notes: String
    let linkURL: String?

    enum CodingKeys: String, CodingKey {
        case name, category, address, phone, notes
        case linkURL = "linkUrl"
    }
}

struct SharedPlacesPayload: Codable {
    let app: String
    let kind: String
    let version: Int
    let places: [SharedPlace]
}

enum SharePlaces {
    static func buildPayload(from places: [Place]) -> SharedPlacesPayload {
        SharedPlacesPayload(
            app: "peragra",
            kind: "places",
            version: 1,
            places: places.map { place in
                SharedPlace(
                    name: place.name,
                    category: place.category.rawValue,
                    address: place.address,
                    phone: place.phone,
                    notes: place.notes,
                    linkURL: place.linkURLString
                )
            }
        )
    }

    static func toText(_ payload: SharedPlacesPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    static func filename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "peragra_places_\(formatter.string(from: date)).json"
    }

    /// Writes the payload to a fresh temp file for ShareLink/
    /// UIActivityViewController to hand to Messages, AirDrop, Files, etc.
    static func writeTempFile(_ payload: SharedPlacesPayload) -> URL? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename())
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    /// Parses text as a Peragra "shared places" payload — pasted from
    /// another person's "Copy as Text" share, or read from their "Share
    /// as File". Nil for anything that isn't recognizably that (not
    /// JSON, wrong shape, or a places array with nothing usable in it)
    /// rather than throwing, since the caller just needs a yes/no to
    /// decide how to handle the input.
    static func parse(_ text: String) -> [SharedPlace]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let payload = try? JSONDecoder().decode(SharedPlacesPayload.self, from: data) else { return nil }
        guard payload.app == "peragra", payload.kind == "places" else { return nil }
        let places = payload.places.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        return places.isEmpty ? nil : places
    }
}
