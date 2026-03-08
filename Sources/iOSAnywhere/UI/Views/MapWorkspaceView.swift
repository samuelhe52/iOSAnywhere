import Combine
import CoreLocation
import MapKit
import SwiftUI

struct MapWorkspaceView: View {
    @Bindable var viewModel: AppViewModel
    @StateObject private var searchModel = LocationSearchModel()
    @StateObject private var startupLocationModel = StartupLocationModel()
    @FocusState private var isSearchFieldFocused: Bool
    @State private var pendingCoordinateSyncTask: Task<Void, Never>?
    @State private var pendingCameraUpdateTask: Task<Void, Never>?
    @State private var hasAppliedStartupLocation = false
    @State private var lastSyncedManualCoordinate: LocationCoordinate?
    @State private var suppressedManualCoordinateSyncCallbacks = 0
    @State private var currentCameraSpan = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    )
    @State private var highlightedCoordinate: LocationCoordinate?
    @State private var highlightedTitle: String?

    private enum CoordinateSource {
        case appleMapDisplay
        case coreLocation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .top) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if case .simulating(let coordinate) = viewModel.simulationState {
                            Marker(
                                "Simulated Location",
                                coordinate: CLLocationCoordinate2D(
                                    latitude: coordinate.latitude,
                                    longitude: coordinate.longitude
                                ))
                        }

                        if let highlightedCoordinate {
                            Marker(
                                highlightedTitle ?? "Selected Place",
                                coordinate: CLLocationCoordinate2D(
                                    latitude: highlightedCoordinate.latitude,
                                    longitude: highlightedCoordinate.longitude
                                )
                            )
                            .tint(.blue)
                        }
                    }
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard let coordinate = proxy.convert(value.location, from: .local) else {
                                    return
                                }

                                setPickedLocation(
                                    LocationCoordinate(
                                        latitude: coordinate.latitude,
                                        longitude: coordinate.longitude
                                    ),
                                    title: "Picked Location",
                                    source: .appleMapDisplay,
                                    recenterMap: true,
                                    debounceNanoseconds: 140_000_000,
                                    preferredSpan: currentCameraSpan
                                )
                            }
                    )
                    .onMapCameraChange(frequency: .continuous) { context in
                        currentCameraSpan = context.region.span

                        if searchModel.showsOverlay || shouldShowHistoryOverlay {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                searchModel.dismissOverlay()
                                isSearchFieldFocused = false
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .frame(minHeight: 420)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField("Search for a place or address", text: $searchModel.query)
                            .textFieldStyle(.plain)
                            .focused($isSearchFieldFocused)

                        if !searchModel.query.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    searchModel.clear()
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(color: .black.opacity(0.16), radius: 12, y: 8)
                    )

                    if let errorMessage = searchModel.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                            )
                            .transition(.opacity)
                    } else if !searchModel.completions.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(searchModel.completions) { completion in
                                    Button {
                                        Task {
                                            await selectCompletion(completion)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(completion.title)
                                                .foregroundStyle(.primary)
                                            if !completion.subtitle.isEmpty {
                                                Text(completion.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if completion.id != searchModel.completions.last?.id {
                                        Divider()
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06))
                        )
                        .transition(.opacity)
                    } else if shouldShowHistoryOverlay {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Label("Recent Searches", systemImage: "clock.arrow.circlepath")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 12)

                                Button("Clear") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        searchModel.clearHistory()
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            Divider()

                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(searchModel.history) { entry in
                                        HStack(spacing: 10) {
                                            Button {
                                                selectHistoryEntry(entry)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(entry.title)
                                                        .foregroundStyle(.primary)

                                                    if !entry.subtitle.isEmpty {
                                                        Text(entry.subtitle)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }

                                                    Text(entry.coordinate.formatted)
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 10)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                withAnimation(.easeInOut(duration: 0.18)) {
                                                    searchModel.removeHistoryEntry(entry)
                                                }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Remove from recent searches")
                                        }
                                        .padding(.horizontal, 14)

                                        if entry.id != searchModel.history.last?.id {
                                            Divider()
                                                .padding(.leading, 14)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 280)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06))
                        )
                        .transition(.opacity)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .animation(.easeInOut(duration: 0.2), value: searchModel.completions)
            .animation(.easeInOut(duration: 0.2), value: searchModel.errorMessage)
            .animation(.easeInOut(duration: 0.2), value: searchModel.history)

            HStack(spacing: 12) {
                TextField("Latitude", text: $viewModel.latitudeText)
                TextField("Longitude", text: $viewModel.longitudeText)
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding(20)
        .onChange(of: viewModel.latitudeText) { _, _ in
            scheduleManualCoordinateSync()
        }
        .onChange(of: viewModel.longitudeText) { _, _ in
            scheduleManualCoordinateSync()
        }
        .task {
            startupLocationModel.requestLocationIfNeeded()
        }
        .onReceive(startupLocationModel.$startupCoordinate.compactMap { $0 }) { coordinate in
            applyStartupLocationIfNeeded(coordinate)
        }
    }

    private func selectCompletion(_ completion: LocationSearchCompletion) async {
        guard let result = await searchModel.resolve(completion) else {
            return
        }

        let coordinate = result.placemark.coordinate
        let selectedCoordinate = LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        setPickedLocation(
            selectedCoordinate,
            title: result.name ?? "Selected Place",
            source: .appleMapDisplay,
            recenterMap: true,
            debounceNanoseconds: 0,
            preferredSpan: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
        searchModel.recordSelection(
            title: result.name ?? completion.title,
            subtitle: completion.subtitle,
            coordinate: selectedCoordinate
        )
        searchModel.acceptSelection(named: result.name)
        isSearchFieldFocused = false
    }

    private func selectHistoryEntry(_ entry: LocationSearchHistoryEntry) {
        setPickedLocation(
            entry.coordinate,
            title: entry.title,
            source: .appleMapDisplay,
            recenterMap: true,
            debounceNanoseconds: 0,
            preferredSpan: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
        searchModel.acceptSelection(named: entry.title)
        searchModel.recordSelection(
            title: entry.title,
            subtitle: entry.subtitle,
            coordinate: entry.coordinate
        )
        isSearchFieldFocused = false
    }

    private func scheduleManualCoordinateSync() {
        pendingCoordinateSyncTask?.cancel()

        guard let coordinate = parsedManualCoordinate else {
            return
        }

        if suppressedManualCoordinateSyncCallbacks > 0 {
            suppressedManualCoordinateSyncCallbacks -= 1
            return
        }

        if lastSyncedManualCoordinate == coordinate {
            return
        }

        pendingCoordinateSyncTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                syncMap(to: coordinate, title: "Manual Coordinates")
            }
        }
    }

    private var parsedManualCoordinate: LocationCoordinate? {
        guard
            let latitude = Double(viewModel.latitudeText),
            let longitude = Double(viewModel.longitudeText),
            (-90.0 ... 90.0).contains(latitude),
            (-180.0 ... 180.0).contains(longitude)
        else {
            return nil
        }

        return LocationCoordinate(latitude: latitude, longitude: longitude)
    }

    private var shouldShowHistoryOverlay: Bool {
        isSearchFieldFocused
            && searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !searchModel.history.isEmpty
    }

    private func syncMap(to coordinate: LocationCoordinate, title: String, recenterMap: Bool = true) {
        highlightedCoordinate = coordinate
        highlightedTitle = title
        lastSyncedManualCoordinate = coordinate
        if recenterMap {
            updateCameraPosition(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ),
                    span: currentCameraSpan
                ),
                debounceNanoseconds: 0
            )
        }
    }

    private func setPickedLocation(
        _ coordinate: LocationCoordinate,
        title: String,
        source: CoordinateSource,
        recenterMap: Bool,
        debounceNanoseconds: UInt64,
        preferredSpan: MKCoordinateSpan
    ) {
        let displayedCoordinate = displayCoordinate(for: coordinate, source: source)

        pendingCoordinateSyncTask?.cancel()
        suppressedManualCoordinateSyncCallbacks = 2
        viewModel.latitudeText = String(format: "%.6f", displayedCoordinate.latitude)
        viewModel.longitudeText = String(format: "%.6f", displayedCoordinate.longitude)
        syncMap(to: displayedCoordinate, title: title, recenterMap: false)

        if recenterMap {
            updateCameraPosition(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: displayedCoordinate.latitude,
                        longitude: displayedCoordinate.longitude
                    ),
                    span: preferredSpan
                ),
                debounceNanoseconds: debounceNanoseconds
            )
        }

        if searchModel.showsOverlay || shouldShowHistoryOverlay {
            withAnimation(.easeInOut(duration: 0.18)) {
                searchModel.dismissOverlay()
                isSearchFieldFocused = false
            }
        }
    }

    private func updateCameraPosition(_ region: MKCoordinateRegion, debounceNanoseconds: UInt64) {
        pendingCameraUpdateTask?.cancel()

        let applyUpdate = {
            withAnimation(.easeInOut(duration: 0.26)) {
                cameraPosition = .region(region)
            }
        }

        guard debounceNanoseconds > 0 else {
            applyUpdate()
            return
        }

        pendingCameraUpdateTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                applyUpdate()
            }
        }
    }

    private func applyStartupLocationIfNeeded(_ coordinate: CLLocationCoordinate2D) {
        guard !hasAppliedStartupLocation else {
            return
        }

        guard highlightedCoordinate == nil, lastSyncedManualCoordinate == nil else {
            hasAppliedStartupLocation = true
            return
        }

        hasAppliedStartupLocation = true
        setPickedLocation(
            LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            title: "Current Location",
            source: .coreLocation,
            recenterMap: true,
            debounceNanoseconds: 0,
            preferredSpan: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    }

    private func displayCoordinate(for coordinate: LocationCoordinate, source: CoordinateSource) -> LocationCoordinate {
        switch source {
        case .appleMapDisplay:
            return coordinate
        case .coreLocation:
            return ChinaCoordinateTransform.displayCoordinate(for: coordinate)
        }
    }

}

fileprivate struct LocationSearchCompletion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let rawValue: MKLocalSearchCompletion
}

fileprivate struct LocationSearchHistoryEntry: Identifiable, Equatable, Codable {
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
fileprivate final class StartupLocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
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
fileprivate final class LocationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
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
