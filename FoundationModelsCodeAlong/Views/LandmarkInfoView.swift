import SwiftUI
import Combine
import MapKit
import FoundationModels

private struct PlacePin: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

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

    var currentJSON: String {
        let escapedName = Self.escapeJSONString(name)
        let lat = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let lon = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        let escapedDesc = Self.escapeJSONString(generatedDescription)
        let escapedShort = Self.escapeJSONString(generatedShortDescription)
        let escapedPlaceID = Self.escapeJSONString(generatedPlaceID ?? "")
        return """
        {
        \"name\": \"\(escapedName)\",\n        \"continent\": \"\",\n        \"id\": \(generatedID),\n        \"placeID\": \"\(escapedPlaceID)\",\n        \"longitude\": \(lon),\n        \"latitude\": \(lat),\n        \"span\": 1,\n        \"description\": \"\(escapedDesc)\",\n        \"shortDescription\": \"\(escapedShort)\"\n        }
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

private struct MapPreviewView: View {
    var name: String
    var latitude: Double
    var longitude: Double
    @Binding var cameraPosition: MapCameraPosition

    var body: some View {
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let pins = [PlacePin(name: name.isEmpty ? "Selected Place" : name, coordinate: coord)]
        Map(position: $cameraPosition) {
            ForEach(pins) { pin in
                Marker(pin.name.isEmpty ? "Selected Place" : pin.name, coordinate: pin.coordinate)
                    .tint(.red)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 8)
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

struct LandmarkInfoView: View {
    @StateObject private var model = LandmarkInfoViewModel()
    
    @State private var pendingLandmark: Landmark? = nil

    @State private var descriptionGenerator: DescriptionGenerator? = nil
    @State private var isGeneratingDescription = false
    
    @State private var languageModelAvailability = SystemLanguageModel.default.availability
    
    @State private var canGenerate = false
    @State private var didPrewarm = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: .init(latitudeDelta: 2, longitudeDelta: 2)))

    // Removed the following line as per instructions:
    // @State private var biasRegion: MKCoordinateRegion? = nil
    
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchMessage: String? = nil

    private func updateRegion() {
        let coord = CLLocationCoordinate2D(latitude: model.latitude, longitude: model.longitude)
        guard CLLocationCoordinate2DIsValid(coord), coord.latitude != 0 || coord.longitude != 0 else { return }
        // Map preview region (wider span)
        let mapRegion = MKCoordinateRegion(center: coord, span: .init(latitudeDelta: 2, longitudeDelta: 2))
        cameraPosition = .region(mapRegion)
        // Removed these lines as per instructions:
        // // Bias region (city scale)
        // let citySpan = MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
        // let newBias = MKCoordinateRegion(center: coord, span: citySpan)
        // biasRegion = newBias
    }

    @MainActor
    private func performSearch() async {
        let q = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Apply a POI category exclude filter to remove everyday/utilitarian places
        let excludedCategories: [MKPointOfInterestCategory] = [
            .atm,
            .bank,
            .gasStation,
            .pharmacy,
            .hospital,
            .police,
            .postOffice,
            .school,
            .store,
            .restaurant,
            .cafe,
            .bakery,
            .parking,
            .carRental,
            .evCharger,
            .laundry,
            .hotel
        ]
        request.pointOfInterestFilter = MKPointOfInterestFilter(excluding: excludedCategories)
        do {
            let response = try await MKLocalSearch(request: request).start()
            let filtered = response.mapItems.compactMap { item -> MKMapItem? in
                guard item.identifier != nil else { return nil }
                return item
            }
            let topFive = Array(filtered.prefix(5))
            searchResults = topFive
            if topFive.isEmpty {
                searchMessage = "No results with a verified Apple Place ID. Try a more specific query."
            }
        } catch {
            searchMessage = "Search failed. Please try again."
        }
    }

    @MainActor
    private func select(_ item: MKMapItem) {
        model.name = item.name ?? model.name

        let coord = item.location.coordinate

        model.latitude = coord.latitude
        model.longitude = coord.longitude
        model.generatedPlaceID = item.identifier?.rawValue

        // Clear the results list and message
        searchResults = []
        searchMessage = nil

        // Update the map region and bias
        updateRegion()

        // Keep existing behavior: generate description from the name
        Task {
            if canGenerate {
                await startDescriptionGeneration()
            }
        }
    }

    private func subtitle(for item: MKMapItem) -> String {
        let c = item.location.coordinate
        return String(format: "%.4f, %.4f", c.latitude, c.longitude)
    }

    @MainActor
    private func startDescriptionGeneration() async {
        let trimmed = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let generator = DescriptionGenerator(name: model.generatedPlaceID ?? "")
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
                let warmup = DescriptionGenerator(name: model.generatedPlaceID ?? "warmup-placeholder")
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
        
        // Clear generation state
        descriptionGenerator = nil
        isGeneratingDescription = false
        
        // Clear navigation state
        pendingLandmark = nil
        
        // Reset camera
        cameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: .init(latitudeDelta: 2, longitudeDelta: 2)))
        
        // Reset UI measurements and search state
        // Removed the following line as per instructions:
        // biasRegion = nil
        searchResults = []
        isSearching = false
        searchMessage = nil
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

    var body: some View {
        ZStack(alignment: .top) {
            StaticItineraryHeader9999()
            ScrollView {
                VStack {
                    Text("Landmark Info Lookup")
                        .font(.title2).bold()

                    HStack(spacing: 8) {
                        TextField("Enter landmark name", text: $model.name)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit { Task { await performSearch() } }

                        Button("Search") {
                            Task { await performSearch() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .onChange(of: model.latitude) { updateRegion() }
                    .onChange(of: model.longitude) { updateRegion() }

                    if isSearching {
                        ProgressView("Searching…")
                            .padding(.vertical, 4)
                    } else if !searchResults.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Select a Place").bold().padding(.bottom, 6)
                            ForEach(Array(searchResults.enumerated()), id: \.offset) { _, item in
                                Button {
                                    select(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "Unknown place")
                                            .font(.body)
                                        Text(subtitle(for: item))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    } else if let message = searchMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                    
                    // Show the JSON we are producing
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Generated JSON").bold()
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
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    
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

                    if model.latitude != 0 || model.longitude != 0 {
                        MapPreviewView(name: model.name, latitude: model.latitude, longitude: model.longitude, cameraPosition: $cameraPosition)
                    }

                    DescriptionSectionView(generator: descriptionGenerator, isGenerating: isGeneratingDescription)

                    Button("Explore") {
                        if let lm = landmarkFromCurrentJSON() {
                            pendingLandmark = lm
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.generatedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
    }
}

#Preview {
    NavigationStack {
        LandmarkInfoView()
    }
}

