/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A tool to use alongside the models to find points of interest for a landmark.
*/

import FoundationModels
import MapKit
import SwiftUI
import Foundation

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
        let results = await getSuggestions(category: arguments.pointOfInterest, latitude: landmark.latitude, longitude: landmark.longitude)
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

extension Category {
    var mkCategory: MKPointOfInterestCategory? {
        switch self {
        case .hotel: return .hotel
        case .restaurant: return .restaurant
        }
    }
}

extension String {
    /// Returns a Latin transliteration of the string. If transliteration fails, returns `self`.
    /// When `stripDiacritics` is true, removes combining marks to improve readability (ASCII-ish).
    func latinTransliteration(stripDiacritics: Bool = true) -> String {
        // Convert to Latin script (e.g., Arabic → Latin)
        let latin = self.applyingTransform(.toLatin, reverse: false) ?? self
        guard stripDiacritics else { return latin }
        // Remove combining marks to approximate ASCII when possible
        return latin.applyingTransform(.stripCombiningMarks, reverse: false) ?? latin
    }
}

func getSuggestions(category: Category, latitude: Double, longitude: Double) async -> [String] {
    return await MapKitSearch(latitude: latitude, longitude: longitude, category: category)
}

private func MapKitSearch(latitude: Double, longitude: Double, category: Category) async -> [String] {
    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
    let request = MKLocalSearch.Request()
    request.region = region
    request.naturalLanguageQuery = category.rawValue
    request.resultTypes = [.pointOfInterest]
    if let mk = category.mkCategory {
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [mk])
    } else {
        request.pointOfInterestFilter = nil
    }
    let search = MKLocalSearch(request: request)
    do {
        let response = try await search.start()
        let names = response.mapItems
            .prefix(3)
            .compactMap { $0.name }
            .map { name in
                let latin = name.latinTransliteration()
                return name == latin ? name : "\(name) (\(latin))"
            }
        return Array(names)
    } catch {
        // print("Search error: \(error)")
        return []
    }
}
