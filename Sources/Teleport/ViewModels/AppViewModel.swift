import Foundation
import Observation

struct USBSetupGuide: Equatable {
    let resolvedPythonPath: String?

    var pythonInstallCommand: String {
        if let resolvedPythonPath {
            return Self.shellQuoted(resolvedPythonPath) + " -m pip install pymobiledevice3"
        }

        return "python3 -m pip install pymobiledevice3"
    }

    var pythonStatusText: String {
        if let resolvedPythonPath {
            return resolvedPythonPath
        }

        return "python3 is not currently resolving from your shell. Install Python 3 first, then refresh devices."
    }

    private static func shellQuoted(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "'" }) else {
            return value
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct PythonDependencyInstallGuide: Identifiable, Equatable {
    let resolvedPythonPath: String
    let installCommand: String

    var id: String {
        resolvedPythonPath + "\n" + installCommand
    }

    static func parse(from message: String) -> PythonDependencyInstallGuide? {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.contains(where: { $0.localizedCaseInsensitiveContains("pymobiledevice3 is missing") }) else {
            return nil
        }

        guard
            let resolvedPythonPath = lines.first(where: { $0.hasPrefix("Resolved Python: ") })?
                .replacingOccurrences(of: "Resolved Python: ", with: ""),
            let installCommand = lines.first(where: { $0.hasPrefix("Run: ") })?
                .replacingOccurrences(of: "Run: ", with: "")
        else {
            return nil
        }

        return PythonDependencyInstallGuide(
            resolvedPythonPath: resolvedPythonPath,
            installCommand: installCommand
        )
    }
}

@Observable
@MainActor
final class AppViewModel {
    private enum Preferences {
        static let suppressUSBPrivilegeNotice = "suppressUSBPrivilegeNotice"
    }

    private let registry: DeviceRegistry
    private var acknowledgedUSBPrivilegeDeviceID: String?
    private let defaults: UserDefaults

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
        self.suppressUSBPrivilegeNotice = defaults.bool(forKey: Preferences.suppressUSBPrivilegeNotice)
    }

    var selectedDevice: Device? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    var selectedDeviceRequiresAdministratorApproval: Bool {
        selectedDevice?.kind == .physicalUSB
    }

    var showsUSBApprovalReminder: Bool {
        guard selectedDeviceRequiresAdministratorApproval else {
            return false
        }

        if suppressUSBPrivilegeNotice {
            return false
        }

        return acknowledgedUSBPrivilegeDeviceID != selectedDeviceID
    }

    func refreshDevices() async {
        discoveryState = .discovering
        statusMessage = "Scanning for simulator and USB devices..."

        do {
            async let simulatorDevices = registry.service(for: .simulator)?.discoverDevices() ?? []
            async let physicalDevices = registry.service(for: .physicalUSB)?.discoverDevices() ?? []
            let discovered = try await simulatorDevices + physicalDevices
            devices = discovered.sorted { $0.name < $1.name }
            selectedDeviceID = devices.first?.id
            await updateSelectedPythonRuntimeNote()
            discoveryState = .ready
            statusMessage = devices.isEmpty ? "No devices found." : "Found \(devices.count) device(s)."
        } catch {
            discoveryState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func connectSelectedDevice() async {
        guard let device = selectedDevice else {
            connectionState = .failed(ServiceError.invalidSelection.localizedDescription)
            return
        }
        guard let service = registry.service(for: device.kind) else {
            connectionState = .failed(
                ServiceError.unsupported("No service available for \(device.kind.rawValue).").localizedDescription)
            return
        }

        connectionState = .connecting
        statusMessage = "Connecting to \(device.name)..."

        do {
            try await service.connect(to: device)
            connectionState = .connected
            statusMessage = "Connected to \(device.name)."
        } catch {
            connectionState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func disconnectSelectedDevice() async {
        guard let device = selectedDevice, let service = registry.service(for: device.kind) else {
            connectionState = .disconnected
            return
        }

        connectionState = .disconnecting
        await service.disconnect()
        connectionState = .disconnected
        simulationState = .idle
        showsPythonDependencyGuide = nil
        statusMessage = "Disconnected from \(device.name)."
    }

    func simulateSelectedLocation() async {
        guard let device = selectedDevice else {
            simulationState = .failed(ServiceError.invalidSelection.localizedDescription)
            return
        }
        guard let service = registry.service(for: device.kind) else {
            simulationState = .failed(
                ServiceError.unsupported("No service available for \(device.kind.rawValue).").localizedDescription)
            return
        }
        guard let latitude = Double(latitudeText), let longitude = Double(longitudeText) else {
            simulationState = .failed("Enter valid coordinates.")
            statusMessage = "Enter valid coordinates."
            return
        }

        if device.kind == .physicalUSB && showsUSBApprovalReminder {
            showsUSBPrivilegeNotice = true
            statusMessage = "Review the administrator approval note to continue with USB location simulation."
            return
        }

        let coordinate = LocationCoordinate(latitude: latitude, longitude: longitude)
        let simulationCoordinate = ChinaCoordinateTransform.simulationCoordinate(fromDisplayed: coordinate)
        do {
            if device.kind == .physicalUSB {
                simulationState = .authorizing
                statusMessage =
                    "Waiting for macOS administrator approval. Your password is entered in a separate system dialog and is never stored by Teleport."
            }
            try await service.setLocation(simulationCoordinate)
            simulationState = .simulating(coordinate)
            showsPythonDependencyGuide = nil
            statusMessage = "Simulating \(coordinate.formatted) on \(device.name)."
        } catch {
            handleSimulationError(error)
        }
    }

    func confirmUSBPrivilegeNotice(suppressFuturePrompts: Bool) async {
        if suppressFuturePrompts {
            suppressUSBPrivilegeNotice = true
            defaults.set(true, forKey: Preferences.suppressUSBPrivilegeNotice)
        }
        acknowledgedUSBPrivilegeDeviceID = selectedDeviceID
        showsUSBPrivilegeNotice = false
        await simulateSelectedLocation()
    }

    func dismissUSBPrivilegeNotice() {
        showsUSBPrivilegeNotice = false
        simulationState = .failed("Administrator approval was canceled before the macOS password prompt.")
        statusMessage = "Administrator approval was canceled before the macOS password prompt."
    }

    func clearSimulatedLocation() async {
        guard let device = selectedDevice, let service = registry.service(for: device.kind) else {
            simulationState = .failed(ServiceError.invalidSelection.localizedDescription)
            return
        }

        simulationState = .stopping
        do {
            try await service.clearLocation()
            simulationState = .idle
            showsPythonDependencyGuide = nil
            statusMessage = "Cleared simulated location on \(device.name)."
        } catch {
            handleSimulationError(error)
        }
    }

    func prepareForTermination() async {
        await registry.shutdownAll()
        connectionState = .disconnected
        simulationState = .idle
        statusMessage = "Disconnected and cleared simulated locations."
    }

    func dismissPythonDependencyGuide() {
        showsPythonDependencyGuide = nil
    }

    private func handleSimulationError(_ error: Error) {
        let message = error.localizedDescription

        if let guide = PythonDependencyInstallGuide.parse(from: message) {
            showsPythonDependencyGuide = guide
            simulationState = .failed("Missing Python dependency")
            statusMessage =
                "Install pymobiledevice3 for the selected Python interpreter to continue USB location simulation."
            return
        }

        simulationState = .failed(message)
        statusMessage = message
    }

    private func updateSelectedPythonRuntimeNote() async {
        guard selectedDevice?.kind == .physicalUSB,
            let usbService = registry.service(for: .physicalUSB) as? USBDeviceLocationService,
            let path = await usbService.resolvedPythonExecutablePathForDisplay()
        else {
            selectedUSBSetupGuide = selectedDevice?.kind == .physicalUSB ? USBSetupGuide(resolvedPythonPath: nil) : nil
            selectedPythonRuntimeNote = nil
            return
        }

        selectedUSBSetupGuide = USBSetupGuide(resolvedPythonPath: path)
        selectedPythonRuntimeNote = "USB helper Python: \(path)"
    }
}
