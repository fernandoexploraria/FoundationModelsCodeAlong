import Foundation
import MapKit

extension MKPointOfInterestCategory {
    var displayName: String {
        switch self {
        case .museum: return "Museum"
        case .landmark: return "Landmark"
        case .park: return "Park"
        case .nationalPark: return "National Park"
        case .beach: return "Beach"
        case .marina: return "Marina"
        case .aquarium: return "Aquarium"
        case .amusementPark: return "Amusement Park"
        case .stadium: return "Stadium"
        case .theater: return "Theater"
        case .movieTheater: return "Movie Theater"
        case .nightlife: return "Nightlife"
        case .winery: return "Winery"
        case .brewery: return "Brewery"
        case .library: return "Library"
        case .university: return "University"
        case .campground: return "Campground"
        default:
            let raw = self.rawValue
            let prefix = "MKPOICategory"
            var name = raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
            name = name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            return name
        }
    }
    var touristPriority: Int {
        switch self {
        case .landmark: return 0
        case .museum: return 1
        case .nationalPark: return 2
        case .park: return 3
        case .beach: return 4
        case .aquarium: return 5
        case .amusementPark: return 6
        case .stadium: return 7
        case .theater: return 8
        case .movieTheater: return 9
        case .marina: return 10
        case .winery: return 11
        case .brewery: return 12
        case .library: return 13
        case .university: return 14
        case .campground: return 15
        case .nightlife: return 16
        default: return 50
        }
    }
    var suggestedSpanDegrees: Double {
        switch self {
        case .landmark: return 0.03
        case .museum: return 0.03
        case .theater: return 0.03
        case .movieTheater: return 0.03
        case .library: return 0.03
        case .aquarium: return 0.04
        case .brewery: return 0.04
        case .stadium: return 0.05
        case .nightlife: return 0.05
        case .marina: return 0.06
        case .winery: return 0.06
        case .park: return 0.10
        case .amusementPark: return 0.12
        case .university: return 0.12
        case .campground: return 0.12
        case .beach: return 0.15
        case .nationalPark: return 0.50
        default:
            return 0.08
        }
    }
    var symbolName: String {
        switch self {
        case .landmark:
            return "star.circle.fill"
        case .museum:
            return "building.columns"
        case .nationalPark:
            if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
                return "mountain.2.fill"
            } else {
                return "leaf.fill"
            }
        case .park:
            return "tree.fill"
        case .beach:
            if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
                return "beach.umbrella.fill"
            } else {
                return "sun.max"
            }
        case .marina:
            return "sailboat.fill"
        case .aquarium:
            return "fish"
        case .amusementPark:
            return "sparkles"
        case .stadium:
            return "sportscourt.fill"
        case .theater:
            return "theatermasks.fill"
        case .movieTheater:
            return "film.fill"
        case .nightlife:
            return "moon.stars.fill"
        case .winery:
            return "wineglass"
        case .brewery:
            return "wineglass"
        case .library:
            return "books.vertical"
        case .university:
            return "graduationcap.fill"
        case .campground:
            return "tent.fill"
        default:
            return "mappin"
        }
    }
}
