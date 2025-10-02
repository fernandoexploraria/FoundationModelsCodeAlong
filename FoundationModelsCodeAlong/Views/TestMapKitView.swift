import SwiftUI
import MapKit

struct TestMapKitView: View {
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""
    @State private var categoryText: String = ""
    @State private var results: [String] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Points of Interest Search (within 5km)")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latitude")
                    TextField("Latitude", text: $latitudeText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Longitude")
                    TextField("Longitude", text: $longitudeText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Category")
                TextField("e.g. hotel, cafe, museum", text: $categoryText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                Task { await performSearch() }
            } label: {
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Search")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSearch || isSearching)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if results.isEmpty && !isSearching {
                Text("No results")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results, id: \.self) { name in
                        Text("• \(name)")
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    private var canSearch: Bool {
        let hasCoords = Double(latitudeText) != nil && Double(longitudeText) != nil
        let hasCategory = !categoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasCoords && hasCategory
    }

    private func performSearch() async {
        guard let lat = Double(latitudeText), let lon = Double(longitudeText) else {
            errorMessage = "Please enter valid coordinates."
            results = []
            return
        }
        let category = categoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else {
            errorMessage = "Please enter a category."
            results = []
            return
        }
        errorMessage = nil
        isSearching = true
        defer { isSearching = false }
        let names = await getSuggestions(latitude: lat, longitude: lon, category: category)
        results = names
    }

    // Searches within a 5km radius (10km diameter) and returns up to 3 POI names for the given category.
    private func getSuggestions(latitude: Double, longitude: Double, category: String) async -> [String] {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 10_000, longitudinalMeters: 10_000)

        let request = MKLocalSearch.Request()
        request.region = region
        request.naturalLanguageQuery = category
        request.resultTypes = [.pointOfInterest]
        request.pointOfInterestFilter = .init(including: [.hotel, .restaurant])

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            let names = response.mapItems.prefix(3).compactMap { $0.name }
            return Array(names)
        } catch {
            // print("Search error: \(error)")
            return []
        }
    }
}

#Preview {
    TestMapKitView()
}
