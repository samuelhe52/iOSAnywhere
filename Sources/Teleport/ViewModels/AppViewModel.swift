import Foundation
import OSLog
import Observation

enum RouteBuilderMode: String, CaseIterable, Sendable {
    case straightLine
    case navigation
}

enum RouteBuilderNavigationTransport: String, CaseIterable, Sendable {
    case driving
    case cycling
    case walking
}

struct RouteBuilderNavigationAlternative: Equatable, Sendable {
    var waypoints: [RouteWaypoint]
    var distanceMeters: Double
    var expectedTravelTime: TimeInterval?
}

@Observable
@MainActor
final class AppViewModel {
    private static let defaultMovementSpeedMetersPerSecond = 3.5
    private static let defaultMovementTickIntervalSeconds = 0.25
    private static let minimumMovementTickIntervalSeconds = 0.10
    private static let maximumMovementTickIntervalSeconds = 1.00
    private static let maximumRouteSegmentDelaySeconds = 1.00
    private static let routePlaybackSmoothingIntervalSeconds = 0.25
    private static let maximumRouteStepDistanceMeters = 25.0
    private static let defaultRoutePlaybackSpeedMultiplier = 8.0
    private static let routePlaybackSpeedMultipliers: [Double] = [1, 2, 4, 8, 16, 32]
    private static let routePlaybackFixedIntervalPresets: [Double] = [
        0.10, 0.15, 0.20, 0.25, 0.35, 0.50, 0.75, 1.00, 1.50, 2.00
    ]
    private static let defaultRoutePlaybackTravelSpeedMetersPerSecond = 5.0
    private static let movementSpeedPresets: [Double] = [
        1.5, 2.0, 2.5, 3.5, 5.0, 7.0, 9.5, 13.0, 17.5, 23.5, 31.0, 40.0
    ]

    let registry: DeviceRegistry
    var acknowledgedUSBPrivilegeDeviceID: String?
    let defaults: UserDefaults

    var discoveryState: DiscoveryState = .idle
    var connectionState: DeviceConnectionState = .disconnected
    var simulationState: SimulationRunState = .idle
    var devices: [Device] = []
    var selectedDeviceID: String? {
        didSet {
            Task { await updateSelectedPythonRuntimeNote() }
        }
    }
    var showsUSBPrivilegeNotice: Bool = false
    var showsPythonDependencyGuide: PythonDependencyInstallGuide?
    var latitudeText: String = "37.3346"
    var longitudeText: String = "-122.0090"
    var statusMessage: UserFacingText = .localized(TeleportStrings.readyToDiscoverDevices)
    var isSimulationActionInFlight: Bool = false
    var suppressUSBPrivilegeNotice: Bool
    var selectedUSBSetupGuide: USBSetupGuide?
    var selectedPythonRuntimeNote: UserFacingText?
    var movementControlVector: MovementControlVector = .zero
    var movementSpeedMetersPerSecond: Double = 4.0
    var movementTickIntervalSeconds: Double = 0.25
    var suppressPickedLocationPin: Bool = false
    var loadedRoute: SimulatedRoute?
    var draftRouteWaypoints: [RouteWaypoint] = []
    var routeBuilderStops: [LocationCoordinate] = []
    var routeBuilderNavigationTransport: RouteBuilderNavigationTransport = .driving
    var routeBuilderLatestSegmentAlternatives: [RouteBuilderNavigationAlternative] = []
    var routeBuilderSelectedAlternativeIndex: Int = 0
    var routeBuilderLatestSegmentPrefixWaypointCount: Int = 0
    var routeBuilderEditingSavedRouteID: UUID?
    var savedRoutes: [SimulatedRoute] = []
    var isRouteBuilderActive: Bool = false
    var routeBuilderMode: RouteBuilderMode = .straightLine
    var isRouteBuilderResolvingNavigation: Bool = false
    var routePlaybackState: RoutePlaybackState = .idle
    var routePlaybackTimingMode: RoutePlaybackTimingMode = .recorded
    var routePlaybackSpeedMultiplier: Double = 8.0
    var routePlaybackFixedIntervalSeconds: Double = 0.25
    var routePlaybackTravelSpeedMetersPerSecond: Double = 5.0

    @ObservationIgnored var movementLoopTask: Task<Void, Never>?
    @ObservationIgnored var routePlaybackTask: Task<Void, Never>?
    @ObservationIgnored var routeBuilderNavigationTask: Task<Void, Never>?

    init(registry: DeviceRegistry, defaults: UserDefaults = .standard) {
        self.registry = registry
        self.defaults = defaults
        self.suppressUSBPrivilegeNotice = defaults.bool(forKey: AppViewModelPreferences.suppressUSBPrivilegeNotice)
        self.movementSpeedMetersPerSecond = Self.defaultMovementSpeedMetersPerSecond
        self.movementTickIntervalSeconds = Self.defaultMovementTickIntervalSeconds
        self.routePlaybackSpeedMultiplier = Self.defaultRoutePlaybackSpeedMultiplier
        self.routePlaybackFixedIntervalSeconds = Self.defaultMovementTickIntervalSeconds
        self.routePlaybackTravelSpeedMetersPerSecond = Self.defaultRoutePlaybackTravelSpeedMetersPerSecond
        self.savedRoutes = Self.loadSavedRoutes(from: defaults)
    }

    var movementControlAvailable: Bool {
        guard connectionState == .connected, let selectedDevice else {
            return false
        }

        if selectedDevice.kind == .simulator {
            return true
        }

        guard selectedDevice.kind.isPhysicalDevice else {
            return false
        }

        if case .simulating = simulationState {
            return true
        }

        return false
    }

    var movementControlSupportedForSelection: Bool {
        guard let selectedDevice else {
            return false
        }

        return selectedDevice.kind == .simulator || selectedDevice.kind.isPhysicalDevice
    }

    var isMovementControlActive: Bool {
        !movementControlVector.isZero
    }

    var effectiveMovementSpeedMetersPerSecond: Double {
        movementSpeedMetersPerSecond * movementControlVector.magnitude
    }

    var showsPickedLocationPin: Bool {
        !suppressPickedLocationPin
    }

    var hasLoadedRoute: Bool {
        loadedRoute != nil
    }

    var hasSavedRoutes: Bool {
        !savedRoutes.isEmpty
    }

    var loadedSavedRouteIndex: Int? {
        guard let loadedRoute else {
            return nil
        }

        return savedRoutes.firstIndex { $0.id == loadedRoute.id }
    }

    var loadedRouteIsSavedInApp: Bool {
        loadedSavedRouteIndex != nil
    }

    var currentRouteCanBeSavedToApp: Bool {
        loadedRoute != nil
    }

    var currentRouteCanUpdateSavedRoute: Bool {
        loadedSavedRouteIndex != nil
    }

    var currentRouteCanSaveAsNew: Bool {
        loadedRoute != nil
    }

    var loadedRouteCanEnterEditPanel: Bool {
        guard let route = loadedRoute, loadedRouteIsSavedInApp else {
            return false
        }

        return canEditRouteInApp(route)
    }

    var currentRouteCanBeExportedAsGPX: Bool {
        guard let loadedRoute else {
            return false
        }

        return loadedRoute.source != .gpx
    }

    var hasDraftRoute: Bool {
        !draftRouteWaypoints.isEmpty
    }

    var routeBuilderCanUndo: Bool {
        !routeBuilderStops.isEmpty && !isRouteBuilderResolvingNavigation
    }

    var routeBuilderCanFinalize: Bool {
        draftRouteWaypoints.count > 1 && !isRouteBuilderResolvingNavigation
    }

    var routeBuilderWaypointCount: Int {
        draftRouteWaypoints.count
    }

    var routeBuilderStopCount: Int {
        routeBuilderStops.count
    }

    var routeBuilderDistanceMeters: Double {
        routeDistanceMeters(for: draftRouteWaypoints)
    }

    var routeBuilderHasMultipleAlternatives: Bool {
        routeBuilderLatestSegmentAlternatives.count > 1
    }

    var isRouteBuilderEditingSavedRoute: Bool {
        routeBuilderEditingSavedRouteID != nil
    }

    func canEditRouteInApp(_ route: SimulatedRoute) -> Bool {
        route.source != .gpx
    }

    var routePreviewPointCount: Int {
        if isRouteBuilderActive {
            return draftRouteWaypoints.count
        }

        return loadedRouteWaypointCount
    }

    var loadedRouteWaypointCount: Int {
        loadedRoute?.pointCount ?? 0
    }

    var loadedRouteDistanceMeters: Double {
        loadedRoute?.totalDistanceMeters ?? 0
    }

    var loadedRoutePreviewCoordinates: [LocationCoordinate] {
        let waypoints = isRouteBuilderActive ? draftRouteWaypoints : (loadedRoute?.waypoints ?? [])

        return waypoints.map {
            ChinaCoordinateTransform.displayCoordinate(for: $0.coordinate)
        }
    }

    var loadedRouteStartDisplayCoordinate: LocationCoordinate? {
        let coordinate = isRouteBuilderActive ? draftRouteWaypoints.first?.coordinate : loadedRoute?.startCoordinate
        return coordinate.map(ChinaCoordinateTransform.displayCoordinate(for:))
    }

    var loadedRouteEndDisplayCoordinate: LocationCoordinate? {
        let coordinate = isRouteBuilderActive ? draftRouteWaypoints.last?.coordinate : loadedRoute?.endCoordinate
        return coordinate.map(ChinaCoordinateTransform.displayCoordinate(for:))
    }

    var routePlaybackAvailable: Bool {
        guard hasLoadedRoute, connectionState == .connected else {
            return false
        }

        guard selectedDevice?.isAvailable != false else {
            return false
        }

        switch simulationState {
        case .starting, .stopping:
            return false
        case .idle, .simulating, .failed:
            return true
        }
    }

    var routePlaybackProgress: RoutePlaybackProgress? {
        switch routePlaybackState {
        case .playing(let progress), .paused(let progress), .completed(let progress):
            return progress
        case .idle, .ready, .failed:
            return nil
        }
    }

    var isRoutePlaybackActive: Bool {
        if case .playing = routePlaybackState {
            return true
        }

        return false
    }

    var routePlaybackSpeedPresetValues: [Double] {
        Self.routePlaybackSpeedMultipliers
    }

    var routePlaybackSpeedPresetRange: ClosedRange<Double> {
        0...Double(Self.routePlaybackSpeedMultipliers.count - 1)
    }

    var currentRoutePlaybackSpeedPresetIndex: Int {
        let nearest = Self.routePlaybackSpeedMultipliers.enumerated().min { lhs, rhs in
            abs(lhs.element - routePlaybackSpeedMultiplier) < abs(rhs.element - routePlaybackSpeedMultiplier)
        }

        return nearest?.offset ?? 0
    }

    func setRoutePlaybackSpeedPreset(index: Int) {
        let clampedIndex = min(max(index, 0), Self.routePlaybackSpeedMultipliers.count - 1)
        routePlaybackSpeedMultiplier = Self.routePlaybackSpeedMultipliers[clampedIndex]
    }

    var routePlaybackFixedIntervalPresetValues: [Double] {
        Self.routePlaybackFixedIntervalPresets
    }

    var routePlaybackFixedIntervalPresetRange: ClosedRange<Double> {
        0...Double(Self.routePlaybackFixedIntervalPresets.count - 1)
    }

    var currentRoutePlaybackFixedIntervalPresetIndex: Int {
        let nearest = Self.routePlaybackFixedIntervalPresets.enumerated().min { lhs, rhs in
            abs(lhs.element - routePlaybackFixedIntervalSeconds)
                < abs(rhs.element - routePlaybackFixedIntervalSeconds)
        }

        return nearest?.offset ?? 0
    }

    func setRoutePlaybackFixedIntervalPreset(index: Int) {
        let clampedIndex = min(max(index, 0), Self.routePlaybackFixedIntervalPresets.count - 1)
        routePlaybackFixedIntervalSeconds = Self.routePlaybackFixedIntervalPresets[clampedIndex]
    }

    var routePlaybackTravelSpeedPresetValues: [Double] {
        Self.movementSpeedPresets
    }

    var routePlaybackTravelSpeedPresetRange: ClosedRange<Double> {
        0...Double(Self.movementSpeedPresets.count - 1)
    }

    var currentRoutePlaybackTravelSpeedPresetIndex: Int {
        let nearest = Self.movementSpeedPresets.enumerated().min { lhs, rhs in
            abs(lhs.element - routePlaybackTravelSpeedMetersPerSecond)
                < abs(rhs.element - routePlaybackTravelSpeedMetersPerSecond)
        }

        return nearest?.offset ?? 0
    }

    func setRoutePlaybackTravelSpeedPreset(index: Int) {
        let clampedIndex = min(max(index, 0), Self.movementSpeedPresets.count - 1)
        routePlaybackTravelSpeedMetersPerSecond = Self.movementSpeedPresets[clampedIndex]
    }

    var loadedRouteRecordedDurationSeconds: TimeInterval? {
        loadedRoute?.recordedDurationSeconds
    }

    var loadedRouteReplayDurationSeconds: TimeInterval? {
        guard let route = loadedRoute, route.waypoints.count > 1 else {
            return nil
        }

        return zip(route.waypoints, route.waypoints.dropFirst()).reduce(0) { total, pair in
            total + playbackSegmentDelay(from: pair.0, to: pair.1)
        }
    }

    var movementSpeedPresetValues: [Double] {
        Self.movementSpeedPresets
    }

    var movementSpeedPresetRange: ClosedRange<Double> {
        0...Double(Self.movementSpeedPresets.count - 1)
    }

    var currentMovementSpeedPresetIndex: Int {
        let nearest = Self.movementSpeedPresets.enumerated().min { lhs, rhs in
            abs(lhs.element - movementSpeedMetersPerSecond) < abs(rhs.element - movementSpeedMetersPerSecond)
        }

        return nearest?.offset ?? 0
    }

    func setMovementSpeedPreset(index: Int) {
        let clampedIndex = min(max(index, 0), Self.movementSpeedPresets.count - 1)
        movementSpeedMetersPerSecond = Self.movementSpeedPresets[clampedIndex]
    }

    var movementTickIntervalRange: ClosedRange<Double> {
        Self.minimumMovementTickIntervalSeconds...Self.maximumMovementTickIntervalSeconds
    }

    var maximumRouteSegmentDelaySeconds: Double {
        Self.maximumRouteSegmentDelaySeconds
    }

    var routePlaybackSmoothingIntervalSeconds: Double {
        Self.routePlaybackSmoothingIntervalSeconds
    }

    var maximumRouteStepDistanceMeters: Double {
        Self.maximumRouteStepDistanceMeters
    }

    func playbackSegmentDelay(from start: RouteWaypoint, to end: RouteWaypoint) -> TimeInterval {
        switch routePlaybackTimingMode {
        case .fixedInterval:
            return routePlaybackFixedIntervalSeconds
        case .recorded:
            if let startTimestamp = start.timestamp,
                let endTimestamp = end.timestamp
            {
                let timestampDelay = endTimestamp.timeIntervalSince(startTimestamp)
                if timestampDelay > 0 {
                    return min(
                        timestampDelay / routePlaybackSpeedMultiplier,
                        maximumRouteSegmentDelaySeconds
                    )
                }
            }

            if let expectedTravelTime = end.expectedTravelTime,
                expectedTravelTime > 0
            {
                return min(
                    expectedTravelTime / routePlaybackSpeedMultiplier,
                    maximumRouteSegmentDelaySeconds
                )
            }

            return movementTickIntervalSeconds
        case .fixedSpeed:
            let distanceMeters = start.coordinate.distance(to: end.coordinate)
            guard distanceMeters > 0 else {
                return 0
            }

            return distanceMeters / routePlaybackTravelSpeedMetersPerSecond
        }
    }

    private func routeDistanceMeters(for waypoints: [RouteWaypoint]) -> Double {
        guard waypoints.count > 1 else {
            return 0
        }

        return zip(waypoints, waypoints.dropFirst()).reduce(0) { total, pair in
            total + pair.0.coordinate.distance(to: pair.1.coordinate)
        }
    }

    private static func loadSavedRoutes(from defaults: UserDefaults) -> [SimulatedRoute] {
        guard let data = defaults.data(forKey: AppViewModelPreferences.savedRoutes) else {
            return []
        }

        do {
            return try JSONDecoder().decode([SimulatedRoute].self, from: data)
        } catch {
            return []
        }
    }

    func persistSavedRoutes() {
        do {
            let data = try JSONEncoder().encode(savedRoutes)
            defaults.set(data, forKey: AppViewModelPreferences.savedRoutes)
        } catch {
            TeleportLog.simulation.error(
                "Failed to persist saved routes: \(error.localizedDescription, privacy: .public)")
        }
    }
}
