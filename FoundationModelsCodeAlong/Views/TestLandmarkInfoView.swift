import SwiftUI
import Combine
import MapKit

private struct PlacePin: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
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

    var currentJSON: String {
        let escapedName = Self.escapeJSONString(name)
        let lat = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let lon = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        return """
        {
        \"name\": \"\(escapedName)\",\n        \"continent\": \"\",\n        \"id\": 0,\n        \"placeID\": \"\",\n        \"longitude\": \(lon),\n        \"latitude\": \(lat),\n        \"span\": 0,\n        \"description\": \"\",\n        \"shortDescription\": \"\"\n        }
        """
    }

    // MARK: - Persistence for landmarkData.json
    private func dataFileURL() throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return dir.appendingPathComponent("landmarkData.json")
    }

    private func ensureWritableCopy() throws {
        let url = try dataFileURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            if let bundled = Bundle.main.url(forResource: "landmarkData", withExtension: "json") {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: bundled, to: url)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "[]\n".data(using: .utf8)?.write(to: url, options: .atomic)
            }
        }
    }

    private struct IDOnly: Decodable { let id: Int }

    private func nextID() -> Int {
        do {
            try ensureWritableCopy()
            let url = try dataFileURL()
            let data = try Data(contentsOf: url)
            let ids = (try? JSONDecoder().decode([IDOnly].self, from: data))?.map { $0.id } ?? []
            return (ids.max() ?? 0) + 1
        } catch {
            return 1
        }
    }

    func saveCurrentToLandmarkData() {
        do {
            try ensureWritableCopy()
            let url = try dataFileURL()
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { return }
            let inner = trimmed.dropFirst().dropLast()
            let isEmpty = inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let escapedName = Self.escapeJSONString(name)
            let lat = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), latitude)
            let lon = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), longitude)
            let newID = nextID()

            let newObject = """
                {
                    \"name\": \"\(escapedName)\",
                    \"continent\": \"\",
                    \"id\": \(newID),
                    \"placeID\": \"\",
                    \"longitude\": \(lon),
                    \"latitude\": \(lat),
                    \"span\": 0.0,
                    \"description\": \"\",
                    \"shortDescription\": \"\"
                }
            """

            let newContent: String
            if isEmpty {
                newContent = "[\n\(newObject)\n]\n"
            } else {
                // remove the final ']' and append with a comma
                let withoutClosing = trimmed.dropLast()
                newContent = String(withoutClosing) + ",\n" + newObject + "\n]\n"
            }

            try newContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // For this baby step, silently ignore write errors
        }
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

struct TestLandmarkInfoView: View {
    @StateObject private var model = LandmarkInfoViewModel()
    @StateObject private var autocomplete = AutocompleteViewModel()
    @State private var pendingLandmark: Landmark? = nil

    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: .init(latitudeDelta: 2, longitudeDelta: 2)))

    private func updateRegion() {
        let coord = CLLocationCoordinate2D(latitude: model.latitude, longitude: model.longitude)
        guard CLLocationCoordinate2DIsValid(coord), coord.latitude != 0 || coord.longitude != 0 else { return }
        cameraPosition = .region(MKCoordinateRegion(center: coord, span: .init(latitudeDelta: 2, longitudeDelta: 2)))
    }

    var body: some View {
        VStack {
            Text("Landmark Info Lookup")
                .font(.title2).bold()

            HStack(spacing: 8) {
                TextField("Enter landmark name", text: $autocomplete.query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await model.lookupCoordinates() } }
                    .onChange(of: autocomplete.query) { _, newValue in
                        model.name = newValue
                    }
                Button("Search") { Task { await model.lookupCoordinates() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .onChange(of: model.latitude) { updateRegion() }
            .onChange(of: model.longitude) { updateRegion() }

            if !autocomplete.suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(autocomplete.suggestions.enumerated()), id: \.offset) { _, suggestion in
                            Button {
                                // Immediately reflect the selection in the input field
                                let chosen = suggestion.title
                                autocomplete.query = chosen
                                model.name = chosen
                                Task {
                                    if let item = await autocomplete.resolve(suggestion) {
                                        let coord = item.location.coordinate
                                        model.latitude = coord.latitude
                                        model.longitude = coord.longitude
                                        // Optionally refine with the resolved name if available
                                        if let resolved = item.name, !resolved.isEmpty {
                                            autocomplete.query = resolved
                                            model.name = resolved
                                        }
                                    } else {
                                        // Fallback: trigger a search using the chosen text
                                        await model.lookupCoordinates()
                                    }
                                    // Dismiss suggestions after selection
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
                .frame(height: 168) // ~3 rows tall; scroll for more
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .padding(.vertical, 4)
                .zIndex(1)
            }

            if model.latitude != 0 || model.longitude != 0 {
                let pins = [PlacePin(name: model.name.isEmpty ? "Selected Place" : model.name, coordinate: CLLocationCoordinate2D(latitude: model.latitude, longitude: model.longitude))]
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

            Text("Resulting JSON")
                .font(.headline)
            ScrollView {
                Text(model.currentJSON)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            Button("Open in Landmark Detail") {
                guard let data = model.currentJSON.data(using: .utf8) else { return }
                do {
                    let info = try JSONDecoder().decode(GeneratedInfo.self, from: data)
                    let cleanedPlaceID: String? = {
                        if let pid = info.placeID, !pid.isEmpty { return pid }
                        return nil
                    }()
                    // Provide sensible defaults for fields not set by the generator yet
                    let spanValue = info.span == 0 ? 10.0 : info.span
                    let lm = Landmark(
                        id: info.id == 0 ? -1 : info.id,
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
            .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Save to landmarkData") { model.saveCurrentToLandmarkData() }
                .buttonStyle(.bordered)
                .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            .navigationDestination(item: $pendingLandmark) { landmark in
                LandmarkDetailView(landmark: landmark)
            }
            // ... rest of the body content ...
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        TestLandmarkInfoView()
    }
}
