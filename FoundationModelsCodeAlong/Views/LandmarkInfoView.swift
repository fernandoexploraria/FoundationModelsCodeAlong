import SwiftUI
import Combine
import MapKit
import FoundationModels

private struct PlacePin: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

private struct TextFieldHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Autocomplete support using MKLocalSearchCompleter
@MainActor
final class AutocompleteViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" { didSet { completer.queryFragment = query } }
    @Published var suggestions: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = [.address, .pointOfInterest] // locations only (addresses & POIs); exclude generic queries
        return c
    }()

    override init() {
        super.init()
        completer.delegate = self
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        self.suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        self.suggestions = []
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: completion)
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.first
        } catch {
            return nil
        }
    }
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

struct ExampleDoc: Codable {
    let name: String
    let continent: String
    let id: Int
    let placeID: String
    let longitude: Double
    let latitude: Double
    let span: Double
    let description: String
    let shortdescription: String

    private enum CodingKeys: String, CodingKey {
        case name
        case continent
        case id
        case placeID
        case longitude
        case latitude
        case span
        case description
        case shortdescription
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(continent, forKey: .continent)
        try container.encode(id, forKey: .id)
        try container.encode(placeID, forKey: .placeID)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(span, forKey: .span)
        try container.encode(description, forKey: .description)
        try container.encode(shortdescription, forKey: .shortdescription)
    }
}

@MainActor
final class LandmarkInfoViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var generatedDescription: String = ""
    @Published var generatedShortDescription: String = ""

    var currentJSON: String {
        let escapedName = Self.escapeJSONString(name)
        let lat = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let lon = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        let escapedDesc = Self.escapeJSONString(generatedDescription)
        let escapedShort = Self.escapeJSONString(generatedShortDescription)
        return """
        {
        \"name\": \"\(escapedName)\",\n        \"continent\": \"\",\n        \"id\": 0,\n        \"placeID\": \"\",\n        \"longitude\": \(lon),\n        \"latitude\": \(lat),\n        \"span\": 0,\n        \"description\": \"\(escapedDesc)\",\n        \"shortDescription\": \"\(escapedShort)\"\n        }
        """
    }

    func lookupCoordinates() async {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            if let item = response.mapItems.first {
                let coord = item.location.coordinate
                self.latitude = coord.latitude
                self.longitude = coord.longitude
            }
        } catch {
            // Ignore errors for this baby step; leave lat/long as-is
        }
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

private struct SearchFieldWithSuggestions: View {
    @ObservedObject var model: LandmarkInfoViewModel
    @ObservedObject var autocomplete: AutocompleteViewModel
    @Binding var textFieldHeight: CGFloat

    var body: some View {
        TextField("Enter landmark name", text: $autocomplete.query)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.search)
            .onSubmit { Task { await model.lookupCoordinates() } }
            .onChange(of: autocomplete.query) { _, newValue in
                model.name = newValue
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: TextFieldHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(TextFieldHeightKey.self) { height in
                textFieldHeight = height
            }
            .overlay(alignment: .topLeading) {
                AutocompleteOverlayList(autocomplete: autocomplete, model: model, textFieldHeight: textFieldHeight)
            }
    }
}

private struct AutocompleteOverlayList: View {
    @ObservedObject var autocomplete: AutocompleteViewModel
    @ObservedObject var model: LandmarkInfoViewModel
    var textFieldHeight: CGFloat

    var body: some View {
        if !autocomplete.suggestions.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(autocomplete.suggestions.enumerated()), id: \.offset) { _, suggestion in
                        Button {
                            let chosen = suggestion.title
                            autocomplete.query = chosen
                            model.name = chosen
                            Task {
                                if let item = await autocomplete.resolve(suggestion) {
                                    let coord = item.location.coordinate
                                    model.latitude = coord.latitude
                                    model.longitude = coord.longitude
                                    if let resolved = item.name, !resolved.isEmpty {
                                        autocomplete.query = resolved
                                        model.name = resolved
                                    }
                                } else {
                                    await model.lookupCoordinates()
                                }
                                autocomplete.suggestions = []
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.body)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .frame(height: 216)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            .offset(y: textFieldHeight + 36)
            .zIndex(10)
        }
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
    @StateObject private var autocomplete = AutocompleteViewModel()
    @State private var pendingLandmark: Landmark? = nil

    @State private var descriptionGenerator: DescriptionGenerator? = nil
    @State private var isGeneratingDescription = false
    
    @State private var languageModelAvailability = SystemLanguageModel.default.availability
    
    @State private var canGenerate = false
    @State private var didPrewarm = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: .init(latitudeDelta: 2, longitudeDelta: 2)))

    @State private var textFieldHeight: CGFloat = 0

    private func updateRegion() {
        let coord = CLLocationCoordinate2D(latitude: model.latitude, longitude: model.longitude)
        guard CLLocationCoordinate2DIsValid(coord), coord.latitude != 0 || coord.longitude != 0 else { return }
        cameraPosition = .region(MKCoordinateRegion(center: coord, span: .init(latitudeDelta: 2, longitudeDelta: 2)))
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
                let warmup = DescriptionGenerator(name: "Warmup")
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
        
        // Clear autocomplete
        autocomplete.query = ""
        autocomplete.suggestions = []
        
        // Clear generation state
        descriptionGenerator = nil
        isGeneratingDescription = false
        
        // Clear navigation state
        pendingLandmark = nil
        
        // Reset camera
        cameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: .init(latitudeDelta: 2, longitudeDelta: 2)))
        
        // Reset UI measurements
        textFieldHeight = 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            StaticItineraryHeader9999()
            ScrollView {
                VStack {
                    Text("Landmark Info Lookup")
                        .font(.title2).bold()

                    HStack(spacing: 8) {
                        SearchFieldWithSuggestions(model: model, autocomplete: autocomplete, textFieldHeight: $textFieldHeight)
                        Button("Search") {
                            Task {
                                await model.lookupCoordinates()
                                if canGenerate {
                                    await startDescriptionGeneration()
                                }
                            }
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .onChange(of: model.latitude) { updateRegion() }
                    .onChange(of: model.longitude) { updateRegion() }
                    .zIndex(autocomplete.suggestions.isEmpty ? 0 : 1000)

                    if model.latitude != 0 || model.longitude != 0 {
                        MapPreviewView(name: model.name, latitude: model.latitude, longitude: model.longitude, cameraPosition: $cameraPosition)
                    }

                    DescriptionSectionView(generator: descriptionGenerator, isGenerating: isGeneratingDescription)

                    Button("Explore") {
                        guard let data = model.currentJSON.data(using: .utf8) else { return }
                        do {
                            let info = try JSONDecoder().decode(GeneratedInfo.self, from: data)
                            let cleanedPlaceID: String? = {
                                if let pid = info.placeID, !pid.isEmpty { return pid }
                                return nil
                            }()
                            // Provide sensible defaults for fields not set by the generator yet
                            let spanValue = info.span == 0 ? 10.0 : info.span
                            let displayID = (info.id <= 0) ? 9999 : info.id
                            let lm = Landmark(
                                id: displayID,
                                name: info.name,
                                continent: info.continent,
                                description: info.description,
                                shortDescription: info.shortDescription,
                                latitude: info.latitude,
                                longitude: info.longitude,
                                span: spanValue,
                                placeID: cleanedPlaceID
                            )
                            pendingLandmark = lm
                        } catch {
                            // Ignore decode errors in this step
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

