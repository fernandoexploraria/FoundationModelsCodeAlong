import SwiftUI
import Combine
import MapKit
import FoundationModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Helper to decode the JSON we show on screen
private struct GeneratedInfo: Decodable {
    let name: String
    let continent: String
    let id: Int
    let placeID: String?
    let longitude: Double
    let latitude: Double
    let span: Double
    let description: String
    let shortDescription: String
}

@MainActor
final class LandmarkInfoViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var generatedDescription: String = ""
    @Published var generatedShortDescription: String = ""
    @Published var generatedID: Int = 9999
    @Published var generatedPlaceID: String? = nil
    @Published var city: String? = nil
    @Published var region: Locale.Region? = nil
    @Published var continent: String? = nil
    @Published var category: MKPointOfInterestCategory? = nil


    var currentJSON: String {
        let escapedName = Self.escapeJSONString(name)
        let lat = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let lon = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        let escapedDesc = Self.escapeJSONString(generatedDescription)
        let escapedShort = Self.escapeJSONString(generatedShortDescription)
        let escapedPlaceID = Self.escapeJSONString(generatedPlaceID ?? "")
        let span = category?.suggestedSpanDegrees ?? 0.10
        let spanStr = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), span)
        return """
        {
        \"name\": \"\(escapedName)\",\n        \"continent\": \"\(Self.escapeJSONString(continent ?? ""))\",\n        \"id\": \(generatedID),\n        \"placeID\": \"\(escapedPlaceID)\",\n        \"longitude\": \(lon),\n        \"latitude\": \(lat),\n        \"span\": \(spanStr),\n        \"description\": \"\(escapedDesc)\",\n        \"shortDescription\": \"\(escapedShort)\"\n        }
        """
    }

    private static func escapeJSONString(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.unicodeScalars {
            switch ch.value {
            case 0x22: out.append("\\\"")      // "
            case 0x5C: out.append("\\\\")      // \
            case 0x08: out.append("\\b")
            case 0x0C: out.append("\\f")
            case 0x0A: out.append("\\n")
            case 0x0D: out.append("\\r")
            case 0x09: out.append("\\t")
            case 0x00...0x1F:
                let hex = String(ch.value, radix: 16, uppercase: true)
                out.append("\\u" + String(repeating: "0", count: 4 - hex.count) + hex)
            default:
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }
}

/// A lightweight provider for MKLocalSearchCompleter suggestions scoped to POIs.
@MainActor
private final class SearchCompletionProvider: NSObject, ObservableObject {
    @Published var completions: [MKLocalSearchCompletion] = []
    private var completer: MKLocalSearchCompleter?

    func start() {
        completer = MKLocalSearchCompleter()
        completer?.delegate = self
        completer?.resultTypes = [.pointOfInterest, .query]
        completer?.regionPriority = .default
    }

    func stop() {
        completer = nil
        completions = []
    }

    func updateQuery(_ fragment: String, region: MKCoordinateRegion?, poiFilter: MKPointOfInterestFilter?) {
        guard let completer else { return }
        completer.resultTypes = [.pointOfInterest, .query]
        completer.regionPriority = .default
        completer.pointOfInterestFilter = poiFilter
        if let region { completer.region = region }
        completer.queryFragment = fragment
    }
}

extension SearchCompletionProvider: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.completions = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.completions = []
        }
    }
}

// Highlight helpers that mirror Apple's sample API but bridge to SwiftUI Text via AttributedString.
private extension MKLocalSearchCompletion {
    #if os(iOS)
    var highlightedTitleAttributed: AttributedString {
        AttributedString(Self.createHighlightedString(text: title, rangeValues: titleHighlightRanges))
    }
    var highlightedSubtitleAttributed: AttributedString {
        AttributedString(Self.createHighlightedString(text: subtitle, rangeValues: subtitleHighlightRanges))
    }

    private static func createHighlightedString(text: String, rangeValues: [NSValue]) -> NSAttributedString {
        let highlightedString = NSMutableAttributedString(string: text)
        let ranges = rangeValues.map { $0.rangeValue }
        let color = UIColor.systemYellow.withAlphaComponent(0.35)
        for range in ranges {
            highlightedString.addAttributes([.backgroundColor: color], range: range)
        }
        return highlightedString
    }
    #else
    var highlightedTitleAttributed: AttributedString { AttributedString(title) }
    var highlightedSubtitleAttributed: AttributedString { AttributedString(subtitle) }
    #endif
}

// A simple row for displaying a completion with highlight.
private struct SearchCompletionRow: View {
    let completion: MKLocalSearchCompletion
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                Text(completion.highlightedTitleAttributed)
                    .font(.body)
                if !completion.subtitle.isEmpty {
                    Text(completion.highlightedSubtitleAttributed)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

private struct StaticItineraryHeader9999: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("9999")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
            Image("9999-thumb")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
                .blur(radius: 16, opaque: true)
                .saturation(1.3)
                .brightness(0.15)
                .mask {
                    Rectangle()
                        .fill(
                            Gradient(stops: [
                                .init(color: .clear, location: 0.5),
                                .init(color: .white, location: 0.6)
                            ])
                            .colorSpace(.perceptual)
                        )
                }
        }
        .frame(height: 420)
        .compositingGroup()
        .mask {
            Rectangle()
                .fill(
                    Gradient(stops: [
                        .init(color: .white, location: 0.3),
                        .init(color: .clear, location: 1.0)
                    ])
                    .colorSpace(.perceptual)
                )
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
#if os(iOS)
        .background(Color(uiColor: .systemGray6))
#endif
    }
}

// MARK: - Map Content Helpers (extracted to aid the type-checker)

@MapContentBuilder
private func RoutePolylineOverlay(_ polyline: MKPolyline?) -> some MapContent {
    if let polyline {
        MapPolyline(polyline)
            .stroke(.blue, lineWidth: 4)
    }
}

private struct PinIconView: View {
    let isHighlighted: Bool
    let isScaled: Bool

    var body: some View {
        Image(systemName: "mappin")
            .font(isScaled ? .title2 : .title3)
            .foregroundStyle(isHighlighted ? .blue : .red)
            .scaleEffect(isScaled ? 1.15 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0.1), value: isScaled)
            .animation(.spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0.1), value: isHighlighted)
    }
}

private struct DroppedPinsLayer: MapContent {
    let pins: [DroppedPin]
    let lastSelectedPinID: UUID?
    let latestPinScaledID: UUID?

    var body: some MapContent {
        ForEach(pins) { pin in
            let isHighlighted = (pin.id == lastSelectedPinID)
            let isScaled = (pin.id == latestPinScaledID)
            Annotation(pin.name, coordinate: pin.coordinate) {
                PinIconView(isHighlighted: isHighlighted, isScaled: isScaled)
            }
        }
    }
}

private struct PrimaryMarker: MapContent {
    let item: MKMapItem

    var body: some MapContent {
        Marker(item: item)
            .tag(MapSelection(item))
            .mapItemDetailSelectionAccessory(.automatic)
    }
}

// MARK: - Transport mode (UI-friendly wrapper)
private enum TransportMode: String, CaseIterable, Identifiable {
    case walking, automobile, cycling, transit
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .walking:    return "figure.walk"
        case .automobile: return "car.fill"
        case .cycling:    return "bicycle"
        case .transit:    return "tram.fill"
        }
    }
    var mkType: MKDirectionsTransportType {
        switch self {
        case .walking:    return .walking
        case .automobile: return .automobile
        case .cycling:    return .cycling
        case .transit:    return []
        }
    }
}

private struct PlaceMapView: View {
    var placeID: String
    var spanDegrees: Double = 0.10

    @State private var item: MKMapItem?
    @State private var selection: MapSelection<MKMapItem>?
    @State private var position: MapCameraPosition = .automatic
    @State private var didSetInitialCamera = false
    @State private var selectedFeatureCoordinate: CLLocationCoordinate2D? = nil
    @State private var showClearPinsConfirm = false
    @State private var lastSelectedPinID: UUID? = nil
    @State private var latestPinScaledID: UUID? = nil
    @State private var routePolyline: MKPolyline? = nil

    @State private var routeETA: TimeInterval? = nil
    @State private var routeDistance: CLLocationDistance? = nil

    @State private var isRouting = false

    // NEW: mode + dialog flag
    @State private var mode: TransportMode = .walking
    @State private var showTransportDialog = false

    private var lastSystemFeaturePin: DroppedPin? {
        droppedPins.last(where: { $0.source == .systemFeature })
    }

    @State private var droppedPins: [DroppedPin] = []

    @MainActor
    private func resetLatestPinAfterDelay() {
        let currentScaledID = latestPinScaledID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s
            if currentScaledID == latestPinScaledID {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.1)) {
                    latestPinScaledID = nil
                }
            }
        }
    }

    private func handleNewMapItem(_ mapItem: MKMapItem, source: DroppedPin.Source) {
        selectedFeatureCoordinate = mapItem.location.coordinate
        let newPin = MapInteractionModel.makeDroppedPin(from: mapItem, source: source)
        let isDuplicate: Bool = MapInteractionModel.isDuplicate(newPin, existing: droppedPins)
        if !isDuplicate {
            droppedPins.append(newPin)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0.1)) {
                lastSelectedPinID = newPin.id
            }
            latestPinScaledID = newPin.id
            resetLatestPinAfterDelay()
            routePolyline = nil
            routeETA = nil
            routeDistance = nil
        }
    }

    // NEW: central routing function (uses selected mode)
    @MainActor
    private func makeRoute() async {
        guard let sourceItem = item,
              let destPin = lastSystemFeaturePin else { return }

        isRouting = true

        let coord = destPin.coordinate
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let destination = MKMapItem(location: loc, address: nil)
        destination.name = destPin.name

        let req = MKDirections.Request()
        req.source = sourceItem
        req.destination = destination
        req.transportType = mode.mkType

        let directions = MKDirections(request: req)
        do {
            let response = try await directions.calculate()
            if let route = response.routes.first {
                routeETA = route.expectedTravelTime
                routeDistance = route.distance
                routePolyline = route.polyline
                withAnimation(.easeInOut(duration: 0.3)) {
                    position = .rect(route.polyline.boundingMapRect)
                }
                isRouting = false
            } else {
                routePolyline = nil
                isRouting = false
                routeETA = nil
                routeDistance = nil
            }
        } catch {
            routePolyline = nil
            routeETA = nil
            routeDistance = nil
            isRouting = false
        }
    }

    var body: some View {
        Map(position: $position, selection: $selection) {
            if let item {
                PrimaryMarker(item: item)
            }
            DroppedPinsLayer(
                pins: droppedPins,
                lastSelectedPinID: lastSelectedPinID,
                latestPinScaledID: latestPinScaledID
            )
            RoutePolylineOverlay(routePolyline)
        }
        .mapFeatureSelectionAccessory(.callout)
        .onChange(of: selection) { _, newSelection in
            if let mapItem = newSelection?.value {
                handleNewMapItem(mapItem, source: .ourItem)
            } else if let feature = newSelection?.feature {
                Task {
                    let request = MKMapItemRequest(feature: feature)
                    if let mapItem = try? await request.mapItem {
                        await MainActor.run {
                            handleNewMapItem(mapItem, source: .systemFeature)
                        }
                    }
                }
            } else {
                selectedFeatureCoordinate = nil
            }
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 8)
        .task {
            guard let identifier = MKMapItem.Identifier(rawValue: placeID) else { return }
            let request = MKMapItemRequest(mapItemIdentifier: identifier)
            item = try? await request.mapItem
            routePolyline = nil
            routeETA = nil
            routeDistance = nil
            await setInitialCameraIfNeeded()
        }
        .onChange(of: item) { _, _ in
            routePolyline = nil
            routeETA = nil
            routeDistance = nil
            Task { await setInitialCameraIfNeeded() }
        }
        .toolbar {
            // Route button: now opens a mode chooser
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTransportDialog = true
                } label: {
                    Label("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .disabled(!(item != nil && droppedPins.contains(where: { $0.source == .systemFeature })))
                .accessibilityLabel("Create Route")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showClearPinsConfirm = true
                } label: {
                    Label("Clear Pins", systemImage: "eraser.fill")
                }
                .disabled(droppedPins.isEmpty && selectedFeatureCoordinate == nil)
                .accessibilityLabel("Clear Pins")
            }
        }
        // NEW: transport mode picker dialog
        .confirmationDialog("Choose transport", isPresented: $showTransportDialog, titleVisibility: .visible) {
            ForEach(TransportMode.allCases) { choice in
                Button {
                    guard !isRouting else { return }
                    if choice == .transit {
                        guard let sourceItem = item, let destPin = lastSystemFeaturePin else { return }
                        let coord = destPin.coordinate
                        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        let destination = MKMapItem(location: loc, address: nil)
                        destination.name = destPin.name
                        MKMapItem.openMaps(
                            with: [sourceItem, destination],
                            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit]
                        )
                    } else {
                        mode = choice
                        Task { await makeRoute() }
                    }
                } label: {
                    Label(choice.rawValue.capitalized, systemImage: choice.icon)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear all dropped pins?", isPresented: $showClearPinsConfirm, titleVisibility: .visible) {
            Button("Clear Pins", role: .destructive) {
                droppedPins.removeAll()
                selectedFeatureCoordinate = nil
                routePolyline = nil
                routeETA = nil
                routeDistance = nil
                isRouting = false
            }
            Button("Cancel", role: .cancel) { }
        }
        .overlay(alignment: .bottomLeading) {
            if isRouting {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.9)
                    Text("Routing…")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(10)
                .accessibilityLabel("Calculating route")
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let eta = routeETA, let dist = routeDistance, !isRouting {
                HStack(spacing: 8) {
                    Image(systemName: mode.icon)
                        .imageScale(.medium)
                        .foregroundStyle(Color(hue: 0.28, saturation: 0.95, brightness: 0.95))
                        .shadow(color: Color(hue: 0.28, saturation: 0.95, brightness: 0.95).opacity(0.55), radius: 6)
                    Text("\(formattedETA(eta)) • \(formattedDistance(dist))")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(10)
                .accessibilityLabel("\(mode.rawValue.capitalized) route, \(formattedETA(eta)), distance \(formattedDistance(dist))")
            }
        }
    }

    @MainActor
    private func setInitialCameraIfNeeded() async {
        guard !didSetInitialCamera, let coord = item?.location.coordinate else { return }
        let region = MKCoordinateRegion(
            center: coord,
            span: .init(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            position = .region(region)
            didSetInitialCamera = true
        }
    }

    private func formattedETA(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "ETA \(hours) hr \(minutes) min"
        } else {
            return "ETA \(minutes) min"
        }
    }

    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .short
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return formatter.string(from: measurement)
    }
}
private struct DescriptionSectionView: View {
    let generator: DescriptionGenerator?
    let isGenerating: Bool

    var body: some View {
        if let gen = generator {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description").bold()

                if let text = gen.description {
                    ScrollView {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                } else if isGenerating {
                    VStack {
                        Spacer()
                        ProgressView("Generating…")
                        Spacer()
                    }
                } else if let error = gen.error {
                    ScrollView {
                        Text("Error: \(error.localizedDescription)")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(12)
            .frame(height: 270)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct OrderedSet<Element: Hashable> {
    private var array: [Element] = []
    private var set: Set<Element> = []
    var isEmpty: Bool { array.isEmpty }
    mutating func insert(_ element: Element) {
        if set.insert(element).inserted {
            array.append(element)
        }
    }
    func contains(_ element: Element) -> Bool { set.contains(element) }
}

// Shared curated list of tourist-relevant POI categories used by completer and full search
private let touristPOICategories: [MKPointOfInterestCategory] = [
    .museum, .landmark, .park, .nationalPark, .beach, .marina, .aquarium,
    .amusementPark, .stadium, .theater, .movieTheater, .nightlife, .winery,
    .brewery, .library, .university, .campground
]

private func currentPOIFilter() -> MKPointOfInterestFilter? {
    return MKPointOfInterestFilter(including: touristPOICategories)
}

struct LandmarkInfoView: View {
    @StateObject private var model = LandmarkInfoViewModel()
    @State private var queryText: String = ""

    @State private var descriptionGenerator: DescriptionGenerator? = nil
    @State private var isGeneratingDescription = false
    
    @State private var languageModelAvailability = SystemLanguageModel.default.availability
    
    @State private var canGenerate = false
    @State private var didPrewarm = false
    @State private var didPrewarmItinerary = false
    @State private var itineraryPrewarmCount: Int = 0

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchMessage: String? = nil
    
    // Filter state
    @State private var selectedFilter: POIFilter = .all
    @State private var availableFilters: [POIFilter] = [.all]
    
    @State private var hasSelectedPlace = false
    
    @State private var selectedItemForDetails: MKMapItem? = nil

    // Direct itinerary generation (Option B)
    @State private var directItineraryGenerator: ItineraryGenerator? = nil
    @State private var directItineraryLandmark: Landmark? = nil
    @State private var showDirectItinerary: Bool = false
    @State private var isGeneratingDirect: Bool = false
    @State private var directGenerationError: Error? = nil

    // Search completion state
    @StateObject private var completionProvider = SearchCompletionProvider()
    @State private var searchCompletions: [MKLocalSearchCompletion] = []
    
    // Added: debounce task reference for completions update cancel
    @State private var completionUpdateTask: Task<Void, Never>? = nil

    // Added toast state
    @State private var toastMessage: String? = nil

    private func currentCompleterRegion() -> MKCoordinateRegion? {
        if model.latitude != 0 || model.longitude != 0 {
            let span = max(0.75, model.category?.suggestedSpanDegrees ?? 0.25)
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: model.latitude, longitude: model.longitude),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
        }
        return nil
    }

    private func applyCompletion(_ completion: MKLocalSearchCompletion) {
        // Hide suggestions immediately and cancel any in-flight debounce
        completionUpdateTask?.cancel()
        searchCompletions = []

        // Build a strong initial query from the completion
        let combined = [completion.title, completion.subtitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Set the query, perform the search, then reset the input to avoid re-triggering the completer
        queryText = combined
        Task { @MainActor in
            await performSearch()
            // Reset input so the completer does not repopulate new suggestions for the selected text
            queryText = ""
        }
    }

    @MainActor
    private func performSearch() async {
        withAnimation { hasSelectedPlace = false }
        descriptionGenerator = nil
        isGeneratingDescription = false
        let q = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = []
            searchMessage = "Please enter a place name to search."
            return
        }
        isSearching = true
        searchMessage = nil
        searchResults = []
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.pointOfInterest, .physicalFeature]
        // Apply a POI category include filter to focus on tourist-relevant places
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: touristPOICategories)
        do {
            let response = try await MKLocalSearch(request: request).start()
            let filtered = response.mapItems.compactMap { item -> MKMapItem? in
                guard item.identifier != nil else { return nil }
                return item
            }
            // Sort results by tourist relevance: category priority, then name relevance, then alphabetical

            func nameMatchScore(name: String, query: String) -> Int {
                let n = name.lowercased()
                let ql = query.lowercased()
                if n == ql { return 0 }
                if n.hasPrefix(ql) { return 1 }
                if n.contains(ql) { return 2 }
                return 3
            }

            let sorted = filtered.sorted { a, b in
                let p0 = a.pointOfInterestCategory?.touristPriority ?? 100
                let p1 = b.pointOfInterestCategory?.touristPriority ?? 100
                if p0 != p1 { return p0 < p1 }

                let s0 = nameMatchScore(name: a.name ?? "", query: q)
                let s1 = nameMatchScore(name: b.name ?? "", query: q)
                if s0 != s1 { return s0 < s1 }

                return (a.name ?? "") < (b.name ?? "")
            }

            let topTwenty = Array(sorted.prefix(20))
            searchResults = topTwenty
            rebuildAvailableFilters()
            // Reset selection to All on new result set
            selectedFilter = .all
            if topTwenty.isEmpty {
                searchMessage = "No results with a verified Apple Place ID. Try a more specific query."
            }
        } catch {
            searchMessage = "Search failed. Please try again."
        }
    }

    @MainActor
    private func select(_ item: MKMapItem) {
        model.latitude = item.location.coordinate.latitude
        model.longitude = item.location.coordinate.longitude
        model.generatedPlaceID = item.identifier?.rawValue
        model.city = item.addressRepresentations?.cityWithContext
        model.region = item.addressRepresentations?.region
        model.continent = ContinentLookup.continentName(for: model.region)
        model.category = item.pointOfInterestCategory
        
        // Replace legacy combined name building with helper
        let baseName = (item.name ?? queryText).trimmingCharacters(in: .whitespacesAndNewlines)
        let standardized = standardizedName(baseName: baseName, region: model.region)
        let safe = standardized.transliteratedLatinSafe
        model.name = safe.isEmpty ? standardized : safe

        // Reset the input field and suggestions to avoid re-triggering the completer
        completionUpdateTask?.cancel()
        queryText = ""
        searchCompletions = []

        // Clear the results list and message
        searchResults = []
        searchMessage = nil
        
        withAnimation { hasSelectedPlace = true }

        // Keep existing behavior: generate description from the name
        Task {
            if canGenerate {
                await startDescriptionGeneration()
            }
        }
        // Prewarm itinerary once we can construct a valid Landmark
        maybePrewarmItineraryIfPossible()
    }

    private func subtitleParts(for item: MKMapItem) -> (symbolName: String?, city: String?, regionID: String?) {
        let symbol = item.pointOfInterestCategory?.symbolName
        let city = item.addressRepresentations?.cityWithContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let regionIDRaw = item.addressRepresentations?.region?.identifier
        let regionID = regionIDRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (symbol, city, regionID)
    }

    private func subtitle(for item: MKMapItem) -> String {
        let category = item.pointOfInterestCategory?.displayName
        let city = item.addressRepresentations?.cityWithContext?.trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = [category, city].compactMap { $0 }.filter { !$0.isEmpty }
        if parts.isEmpty {
            // Fallback: coordinates if neither category nor city is available
            let c = item.location.coordinate
            return String(format: "%.4f, %.4f", c.latitude, c.longitude)
        }
        // Use a single space between Category and City
        return parts.joined(separator: " ")
    }
    
    // Helper: Build a standardized name as "BaseName, CC" (or just BaseName if no region)
    private func standardizedName(baseName: String, region: Locale.Region?) -> String {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return "" }
        // Prefer 2-letter country code if possible. Locale.Region.identifier may be like "US" or "US-CA".
        let code: String? = {
            guard let region else { return nil }
            let id = region.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            // Use the first component before '-' as the country code (e.g., "US" from "US-CA").
            if let dash = id.firstIndex(of: "-") {
                return String(id[..<dash])
            }
            return id
        }()
        if let cc = code, !cc.isEmpty {
            return "\(trimmedBase), \(cc)"
        } else {
            return trimmedBase
        }
    }
    
    private var suggestionContextLabel: String? {
        if hasSelectedPlace {
            let combinedName = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !combinedName.isEmpty { return combinedName }
            let city = model.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rid = model.region?.identifier.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !city.isEmpty && !rid.isEmpty { return "\(city), \(rid)" }
            if !city.isEmpty { return city }
            if !rid.isEmpty { return rid }
        }
        return nil
    }
    
    private func rebuildAvailableFilters() {
        // Build a set of categories present in current searchResults
        var set = OrderedSet<String>()
        var categories: [MKPointOfInterestCategory] = []
        var hasUncategorized = false
        for item in searchResults {
            if let cat = item.pointOfInterestCategory {
                // Avoid duplicates using rawValue as key
                if !set.contains(cat.rawValue) {
                    set.insert(cat.rawValue)
                    categories.append(cat)
                }
            } else {
                hasUncategorized = true
            }
        }
        // Sort categories by the same priority used in search, then by name
        categories.sort { lhs, rhs in
            let p0 = lhs.touristPriority
            let p1 = rhs.touristPriority
            if p0 != p1 { return p0 < p1 }
            return lhs.displayName < rhs.displayName
        }
        var filters: [POIFilter] = [.all]
        filters.append(contentsOf: categories.map { .category($0) })
        if hasUncategorized { filters.append(.uncategorized) }
        availableFilters = filters

        // If current selection disappeared, fallback to .all
        if !availableFilters.contains(selectedFilter) {
            selectedFilter = .all
        }
    }
    
    private func filteredResults() -> [MKMapItem] {
        switch selectedFilter {
        case .all:
            return searchResults
        case .uncategorized:
            return searchResults.filter { $0.pointOfInterestCategory == nil }
        case .category(let c):
            return searchResults.filter { $0.pointOfInterestCategory == c }
        }
    }

    @MainActor
    private func startDescriptionGeneration() async {
        let trimmed = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let generator = DescriptionGenerator(name: trimmed)
        descriptionGenerator = generator
        isGeneratingDescription = true
        await generator.generateDescription()
        model.generatedDescription = generator.description ?? ""
        let full = model.generatedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let short: String = {
            if let dot = full.firstIndex(of: ".") {
                let sentence = full[...dot] // include the period
                return String(sentence).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return full
        }()
        model.generatedShortDescription = short
        isGeneratingDescription = false
    }

    @MainActor
    private func refreshModelAvailability() {
        languageModelAvailability = SystemLanguageModel.default.availability
    }

    @MainActor
    private func maybePrewarmIfAvailable() async {
        refreshModelAvailability()
        switch languageModelAvailability {
        case .available:
            canGenerate = true
            if !didPrewarm {
                // Create a temporary generator solely to warm up the model.
                let warmup = DescriptionGenerator(name: model.name.isEmpty ? "warmup-placeholder" : model.name)
                // If prewarmModel is async in your implementation, prefer: `await warmup.prewarmModel()`
                warmup.prewarmModel()
                didPrewarm = true
            }
        default:
            canGenerate = false
        }
    }

    // Inserted helper function to compare two landmarks by placeID
    private func isSameLandmarkByPlaceID(_ a: Landmark, _ b: Landmark) -> Bool {
        guard let pa = a.placeID, !pa.isEmpty, let pb = b.placeID, !pb.isEmpty else { return false }
        return pa == pb
    }

    @MainActor
    private func maybePrewarmItineraryIfPossible() {
        // Only prewarm if Apple Intelligence is available
        guard canGenerate else { return }
        // Build a Landmark from the current JSON
        guard let lm = landmarkFromCurrentJSON() else { return }

        // If we already have a prewarmed landmark with the same placeID, skip
        if let existing = directItineraryLandmark, isSameLandmarkByPlaceID(existing, lm) {
            return
        }

        // Create and store a generator tied to this landmark, then prewarm it
        let gen = ItineraryGenerator(landmark: lm)
        directItineraryLandmark = lm
        directItineraryGenerator = gen
        gen.prewarmModel()

        didPrewarmItinerary = true
        itineraryPrewarmCount += 1
    }
    
    @MainActor
    private func resetState() {
        // Clear view model state
        model.name = ""
        model.latitude = 0
        model.longitude = 0
        model.generatedDescription = ""
        model.generatedShortDescription = ""
        model.generatedID = 9999
        model.generatedPlaceID = nil
        model.city = nil
        model.region = nil
        model.continent = nil
        queryText = ""
        model.category = nil
        
        // Clear generation state
        descriptionGenerator = nil
        isGeneratingDescription = false
        
        // Reset UI measurements and search state
        searchResults = []
        isSearching = false
        searchMessage = nil
        
        hasSelectedPlace = false
    }
    
    private func landmarkFromCurrentJSON() -> Landmark? {
        guard let data = model.currentJSON.data(using: .utf8) else { return nil }
        do {
            let info = try JSONDecoder().decode(GeneratedInfo.self, from: data)
            let cleanedPlaceID: String? = {
                if let pid = info.placeID, !pid.isEmpty { return pid }
                return nil
            }()
            return Landmark(
                id: info.id,
                name: info.name,
                continent: info.continent,
                description: info.description,
                shortDescription: info.shortDescription,
                latitude: info.latitude,
                longitude: info.longitude,
                span: info.span,
                placeID: cleanedPlaceID
            )
        } catch {
            return nil
        }
    }

    private func copyToClipboard(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
#elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
#else
        _ = text
#endif
    }

    var body: some View {
        ZStack(alignment: .top) {
            StaticItineraryHeader9999()
            ScrollView {
                VStack {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Landmark Info Lookup")
                            .font(.title).bold()
                        if canGenerate && didPrewarm {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(isGeneratingDescription ? Color(hue: 0.28, saturation: 0.95, brightness: 0.95) : Color.accentColor)
                                .scaleEffect(isGeneratingDescription ? 1.08 : 1.0)
                                .opacity(isGeneratingDescription ? 0.9 : 1.0)
                                .animation(isGeneratingDescription ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: isGeneratingDescription)
                                .accessibilityHidden(true)
                        }
                        if canGenerate && didPrewarmItinerary {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "sparkles")
                                    .font(.title3)
                                    .foregroundStyle(isGeneratingDirect ? Color(hue: 0.28, saturation: 0.95, brightness: 0.95) : Color.accentColor)
                                    .scaleEffect(isGeneratingDirect ? 1.08 : 1.0)
                                    .opacity(isGeneratingDirect ? 0.9 : 1.0)
                                    .animation(isGeneratingDirect ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: isGeneratingDirect)
                                    .accessibilityHidden(true)

                                if itineraryPrewarmCount > 0 {
                                    Text("\u{00D7}\(itineraryPrewarmCount)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .offset(x: 10, y: -8)
                                        .accessibilityLabel("Itinerary model prewarmed \(itineraryPrewarmCount) times")
                                }
                            }
                        }
                    }
                    
                    if !canGenerate {
                        Text("Apple Intelligence not available on this device.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 4)
                    }

                    HStack(spacing: 8) {
                        TextField("Enter landmark name", text: $queryText)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit {
                                searchCompletions = []
                                Task { await performSearch() }
                            }

                        Button("Search") {
                            searchCompletions = []
                            Task { await performSearch() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .onChange(of: queryText) { _, newValue in
                        completionProvider.updateQuery(newValue, region: currentCompleterRegion(), poiFilter: currentPOIFilter())
                        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            searchCompletions = []
                        }
                    }
                    .onChange(of: searchResults) { _, _ in
                        rebuildAvailableFilters()
                    }
                    .onReceive(completionProvider.$completions) { comps in
                        self.searchCompletions = comps
                    }

                    if !searchCompletions.isEmpty && !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            // Updated header with dynamic label
                            let suggestionsHeader: String = {
                                if let label = suggestionContextLabel {
                                    return "Suggestions near \(label)"
                                } else {
                                    return "Suggestions"
                                }
                            }()
                            Text(suggestionsHeader)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 6)
                                .padding(.top, 2)

                            Divider().opacity(0.25)

                            ScrollView {
                                ForEach(Array(searchCompletions.enumerated()), id: \.offset) { _, completion in
                                    SearchCompletionRow(completion: completion) {
                                        applyCompletion(completion)
                                    }
                                    Divider()
                                }
                            }
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if isSearching {
                        ProgressView("Searching…")
                            .padding(.vertical, 4)
                    } else if !searchResults.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Select a Place").bold().padding(.bottom, 6)
                            if availableFilters.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(availableFilters) { filter in
                                            FilterToken(filter: filter, isSelected: filter == selectedFilter) {
                                                withAnimation(.snappy) { selectedFilter = filter }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .padding(.bottom, 6)
                            }
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(filteredResults().enumerated()), id: \.offset) { _, item in
                                        Button {
                                            select(item)
                                        } label: {
                                            HStack(alignment: .top) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.name ?? "Unknown place")
                                                        .font(.body)
                                                    let parts = subtitleParts(for: item)
                                                    if let sym = parts.symbolName, (parts.city?.isEmpty == false || parts.regionID?.isEmpty == false) {
                                                        HStack(spacing: 6) {
                                                            Image(systemName: sym)
                                                                .font(.footnote)
                                                                .foregroundStyle(.secondary)
                                                            if let city = parts.city, !city.isEmpty {
                                                                Text(city)
                                                                    .font(.footnote)
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                            if let rid = parts.regionID, !rid.isEmpty {
                                                                Text("**\(rid)**")
                                                                    .font(.footnote)
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                        }
                                                    } else if (parts.city?.isEmpty == false) || (parts.regionID?.isEmpty == false) {
                                                        HStack(spacing: 6) {
                                                            if let city = parts.city, !city.isEmpty {
                                                                Text(city)
                                                                    .font(.footnote)
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                            if let rid = parts.regionID, !rid.isEmpty {
                                                                Text("**\(rid)**")
                                                                    .font(.footnote)
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                        }
                                                    } else if let sym = parts.symbolName {
                                                        Image(systemName: sym)
                                                            .font(.footnote)
                                                            .foregroundStyle(.secondary)
                                                    } else {
                                                        Text(subtitle(for: item))
                                                            .font(.footnote)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                Spacer(minLength: 8)
                                                Button {
                                                    selectedItemForDetails = item
                                                } label: {
                                                    Label("Details", systemImage: "info.circle")
                                                        .labelStyle(.iconOnly)
                                                        .imageScale(.medium)
                                                        .foregroundStyle(.secondary)
                                                        .padding(6)
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Show details for \(item.name ?? "Unknown place")")
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        Divider()
                                    }
                                }
                            }
                            .frame(height: CGFloat(min(filteredResults().count, 7)) * 64)
                        }
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    } else if let message = searchMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }

                    Group {
                        if hasSelectedPlace {
                            if let pid = model.generatedPlaceID {
                                PlaceMapView(placeID: pid, spanDegrees: model.category?.suggestedSpanDegrees ?? 0.10)
                            }

                            DescriptionSectionView(generator: descriptionGenerator, isGenerating: isGeneratingDescription)
                        }
                    }

#if DEBUG
                    // Show the JSON we are producing
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Generated JSON").bold()
                            Spacer()
                            Button {
                                copyToClipboard(model.currentJSON)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        ScrollView {
                            Text(model.currentJSON)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .frame(height: 180)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
#endif

#if DEBUG
                    // Parsed Landmark preview from the JSON above
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Landmark Preview").bold()
                        if let lm = landmarkFromCurrentJSON() {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ID: \(lm.id)")
                                Text("Name: \(lm.name)")
                                Text("Continent: \(lm.continent.isEmpty ? "N/A" : lm.continent)")
                                Text("Description: \(lm.description.isEmpty ? "N/A" : lm.description)")
                                Text("Short Description: \(lm.shortDescription.isEmpty ? "N/A" : lm.shortDescription)")
                                Text(String(format: "Latitude: %.5f", lm.latitude))
                                Text(String(format: "Longitude: %.5f", lm.longitude))
                                Text(String(format: "Span: %.3f", lm.span))
                                Text("Place ID: \(lm.placeID ?? "N/A")")
                            }
                        } else {
                            Text("Landmark preview will appear here once the JSON is valid.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
#endif

                }
                .padding(.horizontal)
                .padding(.top, 25)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let msg = toastMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isGeneratingDirect {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.9)
                    Text("Generating itinerary…")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(10)
                .accessibilityLabel("Generating itinerary")
            }
        }
        .task {
            await maybePrewarmIfAvailable()
        }
        .onAppear {
            resetState()
            completionProvider.start()
        }
        .onDisappear {
            completionProvider.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await maybePrewarmIfAvailable()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard !isGeneratingDirect, let lm = landmarkFromCurrentJSON() else { return }

                    // Prefer reusing the prewarmed generator if it matches the current place by placeID
                    let isReusingPrewarmed: Bool = {
                        if let existingLM = directItineraryLandmark,
                           let _ = directItineraryGenerator,
                           let a = existingLM.placeID, let b = lm.placeID, a == b {
                            return true
                        }
                        return false
                    }()

                    toastMessage = isReusingPrewarmed ? "prewarmed" : "new"

                    // Clear toast after a short delay
                    Task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        if toastMessage == (isReusingPrewarmed ? "prewarmed" : "new") {
                            withAnimation {
                                toastMessage = nil
                            }
                        }
                    }

                    let generatorToUse: ItineraryGenerator = {
                        if isReusingPrewarmed {
                            return directItineraryGenerator!
                        } else {
                            let newGen = ItineraryGenerator(landmark: lm)
                            directItineraryLandmark = lm
                            directItineraryGenerator = newGen
                            return newGen
                        }
                    }()

                    isGeneratingDirect = true
                    Task {
                        await generatorToUse.generateItinerary()
                        isGeneratingDirect = false
                        if generatorToUse.itinerary != nil {
                            showDirectItinerary = true
                        }
                    }
                } label: {
                    Label("Generate Itinerary", systemImage: "sparkles")
                }
                .disabled(!hasSelectedPlace
                          || model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || isGeneratingDirect
                          || !canGenerate)
                .help(!canGenerate ? "Apple Intelligence is not available." : "Generate a trip itinerary for the selected place.")
                .accessibilityHint(!canGenerate ? "Apple Intelligence is not available" : "Generates a trip itinerary for the selected place")
                .accessibilityLabel("Generate itinerary directly")
            }
        }
        .toolbarBackground(.hidden, for: ToolbarPlacement.navigationBar)
        .sheet(isPresented: $showDirectItinerary) {
            if let lm = directItineraryLandmark, let itin = directItineraryGenerator?.itinerary {
                ScrollView {
                    ItineraryView(landmark: lm, itinerary: itin)
                        .padding()
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView("Generating…")
                    if let _ = directGenerationError {
                        Text("Generation failed. Please try again.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .mapItemDetailSheet(item: $selectedItemForDetails)
    }
}

#Preview {
    NavigationStack {
        LandmarkInfoView()
    }
}

