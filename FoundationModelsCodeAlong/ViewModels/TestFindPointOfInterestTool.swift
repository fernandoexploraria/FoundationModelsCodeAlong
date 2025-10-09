import SwiftUI
import MapKit

struct TestFindPointOfInterestTool: View {
    @State private var selectedCategory: Category = .hotel
    @State private var latitudeText: String = "23.90013" // Example: Sahara
    @State private var longitudeText: String = "10.33569"
    @State private var isSearching: Bool = false
    @State private var results: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(Category.allCases, id: \.self) { cat in
                            Text(cat.rawValue.capitalized).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Coordinates") {
                    TextField("Latitude", text: $latitudeText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Longitude", text: $longitudeText)
                        .keyboardType(.numbersAndPunctuation)
                }

                Section {
                    Button(action: search) {
                        HStack {
                            if isSearching { ProgressView() }
                            Text("Search")
                        }
                    }
                    .disabled(isSearching)
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Results") {
                    if results.isEmpty {
                        Text("No results yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(results, id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }
            .navigationTitle("POI Playground")
        }
    }

    private func search() {
        errorMessage = nil
        results = []
        guard let lat = Double(latitudeText), let lon = Double(longitudeText) else {
            errorMessage = "Please enter valid numeric coordinates."
            return
        }
        isSearching = true
        Task {
            let names = await localGetSuggestions(category: selectedCategory, latitude: lat, longitude: lon)
            await MainActor.run {
                self.results = names
                self.isSearching = false
            }
        }
    }
}

private func localGetSuggestions(category: Category, latitude: Double, longitude: Double) async -> [String] {
    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)

    let request = MKLocalSearch.Request()
    request.region = region
    if let mk = category.mkCategory {
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [mk])
    }
    request.naturalLanguageQuery = category.rawValue
    request.resultTypes = [.pointOfInterest]

    let search = MKLocalSearch(request: request)
    do {
        let response = try await search.start()
        let names = response.mapItems.compactMap { $0.name }
        return Array(names.prefix(3))
    } catch {
        return []
    }
}

extension Category {
    var mkCategory: MKPointOfInterestCategory? {
        switch self {
        case .hotel: return .hotel
        case .restaurant: return .restaurant
        }
    }
}

#Preview {
    TestFindPointOfInterestTool()
}
