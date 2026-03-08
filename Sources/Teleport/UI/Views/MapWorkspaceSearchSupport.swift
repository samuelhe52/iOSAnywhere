import Combine
import CoreLocation
import Foundation
import MapKit

struct LocationSearchCompletion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let rawValue: MKLocalSearchCompletion
}

struct LocationSearchHistoryEntry: Identifiable, Equatable, Codable {
    let title: String
    let subtitle: String
    let coordinate: LocationCoordinate

    var id: String {
        let latitude = String(format: "%.6f", coordinate.latitude)
        let longitude = String(format: "%.6f", coordinate.longitude)
        return [title, subtitle, latitude, longitude].joined(separator: "|")
    }
}

@MainActor
final class StartupLocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var startupCoordinate: CLLocationCoordinate2D?

    private let locationManager = CLLocationManager()
    private var hasRequestedLocation = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocationIfNeeded() {
        guard !hasRequestedLocation, CLLocationManager.locationServicesEnabled() else {
            return
        }

        hasRequestedLocation = true

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            startupCoordinate = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard startupCoordinate == nil, let location = locations.last else {
            return
        }

        startupCoordinate = location.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        startupCoordinate = nil
    }
}

@MainActor
final class LocationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    private enum Preferences {
        static let searchHistory = "locationSearchHistory"
    }

    private static let maxHistoryEntries = 10

    @Published var query: String = "" {
        didSet {
            errorMessage = nil
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completions = []
            }

            if suppressNextQueryFragmentUpdate {
                suppressNextQueryFragmentUpdate = false
                return
            }

            completer.queryFragment = query
        }
    }
    @Published var completions: [LocationSearchCompletion] = []
    @Published private(set) var history: [LocationSearchHistoryEntry] = []
    @Published var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private let defaults: UserDefaults
    private var suppressNextQueryFragmentUpdate = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        loadHistory()
    }

    func clear() {
        query = ""
        completions = []
        errorMessage = nil
    }

    func acceptSelection(named name: String?) {
        suppressNextQueryFragmentUpdate = true
        query = name ?? query
        completions = []
        errorMessage = nil
        completer.queryFragment = ""
    }

    func recordSelection(title: String, subtitle: String, coordinate: LocationCoordinate) {
        let entry = LocationSearchHistoryEntry(
            title: title,
            subtitle: subtitle,
            coordinate: coordinate
        )

        history.removeAll { $0.id == entry.id }
        history.insert(entry, at: 0)

        if history.count > Self.maxHistoryEntries {
            history = Array(history.prefix(Self.maxHistoryEntries))
        }

        saveHistory()
    }

    func removeHistoryEntry(_ entry: LocationSearchHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    func dismissOverlay() {
        completions = []
        errorMessage = nil
    }

    var showsOverlay: Bool {
        !completions.isEmpty || errorMessage != nil
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results.map {
            LocationSearchCompletion(
                id: $0.title + "|" + $0.subtitle,
                title: $0.title,
                subtitle: $0.subtitle,
                rawValue: $0
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
        errorMessage = "Apple location search is temporarily unavailable."
    }

    func resolve(_ completion: LocationSearchCompletion) async -> MKMapItem? {
        do {
            let request = MKLocalSearch.Request(completion: completion.rawValue)
            let response = try await MKLocalSearch(request: request).start()

            guard let first = response.mapItems.first else {
                errorMessage = "No map result was returned for that place."
                return nil
            }

            errorMessage = nil
            return first
        } catch {
            errorMessage = "Unable to load that location from Apple Maps right now."
            return nil
        }
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: Preferences.searchHistory) else {
            history = []
            return
        }

        do {
            history = try JSONDecoder().decode([LocationSearchHistoryEntry].self, from: data)
        } catch {
            history = []
        }
    }

    private func saveHistory() {
        if history.isEmpty {
            defaults.removeObject(forKey: Preferences.searchHistory)
            return
        }

        do {
            let data = try JSONEncoder().encode(history)
            defaults.set(data, forKey: Preferences.searchHistory)
        } catch {
            defaults.removeObject(forKey: Preferences.searchHistory)
        }
    }
}
