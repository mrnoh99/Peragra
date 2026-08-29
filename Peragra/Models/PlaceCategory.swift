import SwiftUI

enum PlaceCategory: String, Codable, CaseIterable, Identifiable {
    case restaurant
    case cafe
    case attraction
    case shopping
    case hotel
    case nightlife
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .restaurant: return "Restaurant"
        case .cafe: return "Cafe"
        case .attraction: return "Attraction"
        case .shopping: return "Shopping"
        case .hotel: return "Hotel"
        case .nightlife: return "Nightlife"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .attraction: return "camera.fill"
        case .shopping: return "bag.fill"
        case .hotel: return "bed.double.fill"
        case .nightlife: return "moon.stars.fill"
        case .other: return "mappin"
        }
    }

    var tint: Color {
        switch self {
        case .restaurant: return .orange
        case .cafe: return .brown
        case .attraction: return .purple
        case .shopping: return .pink
        case .hotel: return .blue
        case .nightlife: return .indigo
        case .other: return .gray
        }
    }
}

enum GeocodeStatus: String, Codable {
    case pending
    case located
    case failed
}
