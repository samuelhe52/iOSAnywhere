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
    @State private var pickedCoordinate: LocationCoordinate?

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
                    pickedCoordinate: pickedCoordinate,
                    showsPickedCoordinate: viewModel.showsPickedLocationPin,
                    routePreviewCoordinates: viewModel.loadedRoutePreviewCoordinates,
                    routeStartCoordinate: viewModel.loadedRouteStartDisplayCoordinate,
                    routeEndCoordinate: viewModel.loadedRouteEndDisplayCoordinate,
                    onTapCoordinate: { coordinate in
                        setPickedLocation(
                            LocationCoordinate(
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude
                            ),
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
        .onChange(of: viewModel.loadedRoute?.id) { _, _ in
            focusLoadedRoutePreviewIfNeeded()
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
                viewModel.suppressPickedLocationPin = false
                syncPickedCoordinate(to: coordinate)
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

    private func syncPickedCoordinate(to coordinate: LocationCoordinate, recenterMap: Bool = true) {
        pickedCoordinate = coordinate
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
        source: CoordinateSource,
        recenterMap: Bool,
        debounceNanoseconds: UInt64,
        preferredSpan: MKCoordinateSpan
    ) {
        let displayedCoordinate = displayCoordinate(for: coordinate, source: source)

        pendingCoordinateSyncTask?.cancel()
        viewModel.suppressPickedLocationPin = false
        suppressedManualCoordinateSyncCallbacks = 2
        viewModel.latitudeText = String(format: "%.6f", displayedCoordinate.latitude)
        viewModel.longitudeText = String(format: "%.6f", displayedCoordinate.longitude)
        syncPickedCoordinate(to: displayedCoordinate, recenterMap: false)

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

        guard pickedCoordinate == nil, lastSyncedManualCoordinate == nil else {
            hasAppliedStartupLocation = true
            return
        }

        hasAppliedStartupLocation = true
        setPickedLocation(
            LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
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

    private func focusLoadedRoutePreviewIfNeeded() {
        let coordinates = viewModel.loadedRoutePreviewCoordinates
        guard let region = routeBoundingRegion(for: coordinates) else {
            return
        }

        currentCameraSpan = region.span
        updateCameraPosition(region, debounceNanoseconds: 0)
    }

    private func routeBoundingRegion(for coordinates: [LocationCoordinate]) -> MKCoordinateRegion? {
        guard let firstCoordinate = coordinates.first else {
            return nil
        }

        var minimumLatitude = firstCoordinate.latitude
        var maximumLatitude = firstCoordinate.latitude
        var minimumLongitude = firstCoordinate.longitude
        var maximumLongitude = firstCoordinate.longitude

        for coordinate in coordinates.dropFirst() {
            minimumLatitude = min(minimumLatitude, coordinate.latitude)
            maximumLatitude = max(maximumLatitude, coordinate.latitude)
            minimumLongitude = min(minimumLongitude, coordinate.longitude)
            maximumLongitude = max(maximumLongitude, coordinate.longitude)
        }

        let latitudePadding = max((maximumLatitude - minimumLatitude) * 0.2, 0.01)
        let longitudePadding = max((maximumLongitude - minimumLongitude) * 0.2, 0.01)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maximumLatitude - minimumLatitude) + latitudePadding, 0.02),
                longitudeDelta: max((maximumLongitude - minimumLongitude) + longitudePadding, 0.02)
            )
        )
    }

}
