import Foundation
import Observation

@Observable
@MainActor
final class AppViewModel {
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
    var statusMessage: String = "Ready to discover simulators and USB devices."
    var suppressUSBPrivilegeNotice: Bool
    var selectedUSBSetupGuide: USBSetupGuide?
    var selectedPythonRuntimeNote: String?

    init(registry: DeviceRegistry, defaults: UserDefaults = .standard) {
        self.registry = registry
        self.defaults = defaults
        self.suppressUSBPrivilegeNotice = defaults.bool(forKey: AppViewModelPreferences.suppressUSBPrivilegeNotice)
    }
}
