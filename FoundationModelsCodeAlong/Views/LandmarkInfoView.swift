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
    @State private var transportType: MKDirectionsTransportType = .walking

    private var lastSystemFeaturePin: DroppedPin? {
        droppedPins.last(where: { $0.source == .systemFeature })
    }

    @State private var droppedPins: [DroppedPin] = []

    @MainActor
    private func resetLatestPinAfterDelay() {
        let currentScaledID = latestPinScaledID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s
            // Only reset the scale if we are still highlighting the same pin
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
                // Selected our own marker backed by MKMapItem
                handleNewMapItem(mapItem, source: .ourItem)
            } else if let feature = newSelection?.feature {
                // Selected a system map feature; request an MKMapItem for it
                Task {
                    let request = MKMapItemRequest(feature: feature)
                    if let mapItem = try? await request.mapItem {
                        await MainActor.run {
                            handleNewMapItem(mapItem, source: .systemFeature)
                        }
                    }
                }
            } else {
                // Selection cleared; remove our transient pin
                selectedFeatureCoordinate = nil
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 8)
        .task {
            guard let identifier = MKMapItem.Identifier(rawValue: placeID) else { return }
            let request = MKMapItemRequest(mapItemIdentifier: identifier)
            item = try? await request.mapItem
            routePolyline = nil
            await setInitialCameraIfNeeded()
        }
        .onChange(of: item) { _, _ in
            routePolyline = nil
            Task { await setInitialCameraIfNeeded() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { @MainActor in
                        guard let sourceItem = item else { return }
                        guard let destPin = lastSystemFeaturePin else { return }
                        // Build destination MKMapItem from the dropped pin coordinate
                        let coord = destPin.coordinate
                        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        let destination = MKMapItem(location: loc, address: nil)
                        destination.name = destPin.name

                        let req = MKDirections.Request()
                        req.source = sourceItem
                        req.destination = destination
                        req.transportType = transportType
                        let directions = MKDirections(request: req)
                        do {
                            let response = try await directions.calculate()
                            if let route = response.routes.first {
                                routePolyline = route.polyline
                                // Fit camera to the route
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    position = .rect(route.polyline.boundingMapRect)
                                }
                            }
                        } catch {
                            // Silently ignore for now; could surface an alert if desired
                        }
                    }
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
        .confirmationDialog("Clear all dropped pins?", isPresented: $showClearPinsConfirm, titleVisibility: .visible) {
            Button("Clear Pins", role: .destructive) {
                droppedPins.removeAll()
                selectedFeatureCoordinate = nil
                routePolyline = nil
            }
            Button("Cancel", role: .cancel) { }
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
            .frame(height: 220)
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

struct LandmarkInfoView: View {
    @StateObject private var model = LandmarkInfoViewModel()
    @State private var queryText: String = ""

    @State private var pendingLandmark: Landmark? = nil

    @State private var descriptionGenerator: DescriptionGenerator? = nil
    @State private var isGeneratingDescription = false
    
    @State private var languageModelAvailability = SystemLanguageModel.default.availability
    
    @State private var canGenerate = false
    @State private var didPrewarm = false
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
        let includedCategories: [MKPointOfInterestCategory] = [
            .museum,
            .landmark,
            .park,
            .nationalPark,
            .beach,
            .marina,
            .aquarium,
            .amusementPark,
            .stadium,
            .theater,
            .movieTheater,
            .nightlife,
            .winery,
            .brewery,
            .library,
            .university,
            .campground
        ]
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: includedCategories)
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
        
        let baseName = item.name ?? queryText
        let cit = model.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let regionID = model.region?.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseAndCity = [baseName, cit]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let combined: String
        if let rid = regionID, !rid.isEmpty {
            combined = "\(baseAndCity) \(rid)"
        } else {
            combined = baseAndCity
        }
        model.name = combined

        queryText = baseName

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
        
        // Clear navigation state
        pendingLandmark = nil
        
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
                    Text("Landmark Info Lookup")
                        .font(.title2).bold()

                    HStack(spacing: 8) {
                        TextField("Enter landmark name", text: $queryText)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit { Task { await performSearch() } }

                        Button("Search") {
                            Task { await performSearch() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .onChange(of: searchResults) { _, _ in
                        rebuildAvailableFilters()
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
                            .frame(height: CGFloat(min(filteredResults().count, 5)) * 64)
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

                        Button("Explore") {
                            if let lm = landmarkFromCurrentJSON() {
                                pendingLandmark = lm
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasSelectedPlace || model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.generatedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                .padding(.top, 120)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await maybePrewarmIfAvailable()
        }
        .onAppear {
            resetState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await maybePrewarmIfAvailable() }
            }
        }
        .overlay(alignment: .topLeading) {
            if canGenerate && didPrewarm {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(isGeneratingDescription ? Color(hue: 0.28, saturation: 0.95, brightness: 0.95) : Color.accentColor)
                    .padding(.top, 120)
                    .padding(.leading, 16)
                    .accessibilityHidden(true)
            }
        }
        .toolbarBackground(.hidden, for: ToolbarPlacement.navigationBar)
        .navigationDestination(item: $pendingLandmark) { landmark in
            LandmarkDetailView(landmark: landmark)
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
