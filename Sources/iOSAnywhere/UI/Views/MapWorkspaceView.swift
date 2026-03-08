import Combine
import MapKit
import SwiftUI

struct MapWorkspaceView: View {
    @Bindable var viewModel: AppViewModel
    @StateObject private var searchModel = LocationSearchModel()
    @State private var pendingCoordinateSyncTask: Task<Void, Never>?
    @State private var pendingCameraUpdateTask: Task<Void, Never>?
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
                                    recenterMap: true,
                                    debounceNanoseconds: 140_000_000,
                                    preferredSpan: currentCameraSpan
                                )
                            }
                    )
                    .onMapCameraChange(frequency: .continuous) { context in
                        currentCameraSpan = context.region.span

                        if searchModel.showsOverlay {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                searchModel.dismissOverlay()
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
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .animation(.easeInOut(duration: 0.2), value: searchModel.completions)
            .animation(.easeInOut(duration: 0.2), value: searchModel.errorMessage)

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
    }

    private func selectCompletion(_ completion: LocationSearchCompletion) async {
        guard let result = await searchModel.resolve(completion) else {
            return
        }

        let coordinate = result.placemark.coordinate
        setPickedLocation(
            LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            title: result.name ?? "Selected Place",
            recenterMap: true,
            debounceNanoseconds: 0,
            preferredSpan: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
        searchModel.acceptSelection(named: result.name)
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
        recenterMap: Bool,
        debounceNanoseconds: UInt64,
        preferredSpan: MKCoordinateSpan
    ) {
        pendingCoordinateSyncTask?.cancel()
        suppressedManualCoordinateSyncCallbacks = 2
        viewModel.latitudeText = String(format: "%.6f", coordinate.latitude)
        viewModel.longitudeText = String(format: "%.6f", coordinate.longitude)
        syncMap(to: coordinate, title: title, recenterMap: false)

        if recenterMap {
            updateCameraPosition(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ),
                    span: preferredSpan
                ),
                debounceNanoseconds: debounceNanoseconds
            )
        }

        if searchModel.showsOverlay {
            withAnimation(.easeInOut(duration: 0.18)) {
                searchModel.dismissOverlay()
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

}

fileprivate struct LocationSearchCompletion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let rawValue: MKLocalSearchCompletion
}

@MainActor
fileprivate final class LocationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
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
    @Published var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var suppressNextQueryFragmentUpdate = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
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
}
