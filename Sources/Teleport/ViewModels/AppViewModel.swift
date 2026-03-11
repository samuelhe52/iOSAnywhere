import Foundation
import Observation

@Observable
@MainActor
final class AppViewModel {
    private static let defaultMovementSpeedMetersPerSecond = 3.5
    private static let defaultMovementTickIntervalSeconds = 0.25
    private static let minimumMovementTickIntervalSeconds = 0.10
    private static let maximumMovementTickIntervalSeconds = 1.00
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
    var suppressUSBPrivilegeNotice: Bool
    var selectedUSBSetupGuide: USBSetupGuide?
    var selectedPythonRuntimeNote: UserFacingText?
    var movementControlVector: MovementControlVector = .zero
    var movementSpeedMetersPerSecond: Double = 4.0
    var movementTickIntervalSeconds: Double = 0.25
    var suppressPickedLocationPin: Bool = false

    @ObservationIgnored var movementLoopTask: Task<Void, Never>?

    init(registry: DeviceRegistry, defaults: UserDefaults = .standard) {
        self.registry = registry
        self.defaults = defaults
        self.suppressUSBPrivilegeNotice = defaults.bool(forKey: AppViewModelPreferences.suppressUSBPrivilegeNotice)
        self.movementSpeedMetersPerSecond = Self.defaultMovementSpeedMetersPerSecond
        self.movementTickIntervalSeconds = Self.defaultMovementTickIntervalSeconds
    }

    var movementControlAvailable: Bool {
        selectedDevice?.kind == .simulator && connectionState == .connected
    }

    var movementControlSupportedForSelection: Bool {
        selectedDevice?.kind == .simulator
    }

    var isMovementControlActive: Bool {
        !movementControlVector.isZero
    }

    var showsPickedLocationPin: Bool {
        !suppressPickedLocationPin
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
}
