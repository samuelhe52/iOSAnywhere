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
                MapWorkspaceMapCanvasView(
                    cameraPosition: $cameraPosition,
                    simulationState: viewModel.simulationState,
                    highlightedCoordinate: highlightedCoordinate,
                    highlightedTitle: highlightedTitle,
                    onTapCoordinate: { coordinate in
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
                    },
                    onCameraChange: { region in
                        currentCameraSpan = region.span

                        if searchModel.showsOverlay || shouldShowHistoryOverlay {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                searchModel.dismissOverlay()
                                isSearchFieldFocused = false
                            }
                        }
                    }
                )

                MapWorkspaceSearchOverlayView(
                    searchModel: searchModel,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    shouldShowHistoryOverlay: shouldShowHistoryOverlay,
                    onSelectCompletion: { completion in
                        Task {
                            await selectCompletion(completion)
                        }
                    },
                    onSelectHistoryEntry: selectHistoryEntry
                )
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
            (-90.0...90.0).contains(latitude),
            (-180.0...180.0).contains(longitude)
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
