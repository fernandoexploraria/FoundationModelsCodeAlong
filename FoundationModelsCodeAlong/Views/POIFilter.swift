import Foundation
import MapKit

enum POIFilter: Hashable, Identifiable {
    case all
    case category(MKPointOfInterestCategory)
    case uncategorized

    var id: String {
        switch self {
        case .all: return "all"
        case .uncategorized: return "uncategorized"
        case .category(let c): return c.rawValue
        }
    }

    var title: String {
        switch self {
        case .all: return "All"
        case .uncategorized: return "Uncategorized"
        case .category(let c): return c.displayName
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .uncategorized:
            return "mappin"
        case .category(let c):
            return c.symbolName
        }
    }
}
