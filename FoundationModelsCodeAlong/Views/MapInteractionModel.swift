import Foundation
import MapKit
import SwiftUI

struct DroppedPin: Identifiable, Hashable {
    static func == (lhs: DroppedPin, rhs: DroppedPin) -> Bool {
        // If both have a placeID, compare by placeID
        if let lp = lhs.placeID, let rp = rhs.placeID {
            return lp == rp
        }
        // Otherwise, compare by stable UUID identity
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        if let pid = placeID {
            hasher.combine(pid)
        } else {
            hasher.combine(id)
        }
    }
    
    let id: UUID = UUID()
    let coordinate: CLLocationCoordinate2D
    let name: String
    let placeID: String?
    let category: MKPointOfInterestCategory?
    let address: MKAddressRepresentations?
    let shortAddress: String?
    let source: Source

    enum Source: String, Hashable { case ourItem, systemFeature }
}

// Helpers for map interactions
enum MapInteractionModel {
    static let pinDedupThresholdMeters: CLLocationDistance = 20

    static func distanceInMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        let ca = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let cb = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return ca.distance(from: cb)
    }

    @MainActor
    static func makeDroppedPin(from mapItem: MKMapItem, source: DroppedPin.Source) -> DroppedPin {
        let coord: CLLocationCoordinate2D = mapItem.location.coordinate
        let addr: MKAddressRepresentations? = mapItem.addressRepresentations
        let cityWithContext: String? = addr?.cityWithContext
        let short: String? = cityWithContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DroppedPin(
            coordinate: coord,
            name: mapItem.name ?? "Selected Place",
            placeID: mapItem.identifier?.rawValue,
            category: mapItem.pointOfInterestCategory,
            address: addr,
            shortAddress: short,
            source: source
        )
    }

    static func isDuplicate(_ newPin: DroppedPin, existing: [DroppedPin]) -> Bool {
        if let pid = newPin.placeID {
            return existing.contains(where: { $0.placeID == pid })
        } else {
            return existing.contains(where: { distanceInMeters($0.coordinate, newPin.coordinate) <= pinDedupThresholdMeters })
        }
    }
}

