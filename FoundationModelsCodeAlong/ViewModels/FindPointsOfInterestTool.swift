import FoundationModels
import SwiftUI
import MapKit

@Observable
final class FindPointsOfInterestTool: Tool {
    
    let name = "findPointsOfInterest"
    let description = "Finds points of interest for a landmark."
    
    let landmark: Landmark
    init(landmark: Landmark) {
        self.landmark = landmark
    }

    @Generable
    struct Arguments {
        @Guide(description: "This is the type of business to look up for.")
        let pointOfInterest: Category
    }
    
    func call(arguments: Arguments) async throws -> String {
        let results = try await getSuggestions(
            category: arguments.pointOfInterest,
            latitude: landmark.latitude,
            longitude: landmark.longitude
        )
        return """
        There are these \(arguments.pointOfInterest) in \(landmark.name): 
        \(results.joined(separator: ", "))
        """
    }
}

@Generable
enum Category: String, CaseIterable {
    case hotel
    case restaurant
}

func getSuggestions(
    category: Category,
    latitude: Double,
    longitude: Double
) async throws -> [String] {
    
    // define region
    let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let meters: CLLocationDistance = 10_000
    let region = MKCoordinateRegion(center: center, latitudinalMeters: meters, longitudinalMeters: meters)
    //
    
    // define request
    let request = MKLocalSearch.Request()
    request.region = region
    request.naturalLanguageQuery = category.rawValue
    request.resultTypes = [.pointOfInterest]
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category.poiCategory])
    //
    
    // perform search
    let search = MKLocalSearch(request: request)
    //
    
    // get response
    let response = try await search.start()
    //
    
    // Sort by distance from center, then tie-break alphabetically by name
    let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
    let sortedItems = response.mapItems.sorted { a, b in
        let da = CLLocation(latitude: a.location.coordinate.latitude,
                            longitude: a.location.coordinate.longitude).distance(from: centerLoc)
        let db = CLLocation(latitude: b.location.coordinate.latitude,
                            longitude: b.location.coordinate.longitude).distance(from: centerLoc)
        if da == db {
            let an = a.name ?? ""
            let bn = b.name ?? ""
            return an.localizedCaseInsensitiveCompare(bn) == .orderedAscending
        }
        return da < db
    }

    // De-duplicate by same name within ~75 meters, keeping the closest (already sorted)
    var seen: [(name: String, coord: CLLocationCoordinate2D)] = []
    let dedupedItems = sortedItems.filter { item in
        guard let rawName = item.name else { return false }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDuplicate = seen.contains { s in
            s.name.caseInsensitiveCompare(name) == .orderedSame &&
            CLLocation(latitude: s.coord.latitude, longitude: s.coord.longitude)
                .distance(from: CLLocation(latitude: item.location.coordinate.latitude,
                                           longitude: item.location.coordinate.longitude)) < 75
        }
        if !isDuplicate {
            seen.append((name: name, coord: item.location.coordinate))
        }
        return !isDuplicate
    }

    // Map to transliterated names, prefix with "TG ", and return up to three
    let names = dedupedItems.compactMap { item -> String? in
        guard let raw = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let transliterated = raw.transliteratedLatinSafe
        let finalName = transliterated.isEmpty ? raw : transliterated
        return "TG " + finalName
    }
    return Array(names.prefix(3))
    //
    
}

extension Category {
    var poiCategory: MKPointOfInterestCategory {
        switch self {
        case .hotel:
            return .hotel
        case .restaurant:
            return .restaurant
        }
    }
}
