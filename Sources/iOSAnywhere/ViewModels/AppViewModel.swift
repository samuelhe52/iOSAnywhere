import Foundation
import Observation

@Observable
@MainActor
final class AppViewModel {
    private let registry: DeviceRegistry
    private var hasAcknowledgedUSBPrivilegeNotice = false

    var discoveryState: DiscoveryState = .idle
    var connectionState: DeviceConnectionState = .disconnected
    var simulationState: SimulationRunState = .idle
    var devices: [Device] = []
    var selectedDeviceID: String?
    var showsUSBPrivilegeNotice: Bool = false
    var latitudeText: String = "37.3346"
    var longitudeText: String = "-122.0090"
    var statusMessage: String = "Ready to discover simulators and USB devices."

    init(registry: DeviceRegistry) {
        self.registry = registry
    }

    var selectedDevice: Device? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    var selectedDeviceRequiresAdministratorApproval: Bool {
        selectedDevice?.kind == .physicalUSB
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

        if device.kind == .physicalUSB && !hasAcknowledgedUSBPrivilegeNotice {
            showsUSBPrivilegeNotice = true
            statusMessage = "Review the administrator approval note to continue with USB location simulation."
            return
        }

        let coordinate = LocationCoordinate(latitude: latitude, longitude: longitude)
        do {
            if device.kind == .physicalUSB {
                simulationState = .authorizing
                statusMessage = "Waiting for macOS administrator approval. Your password is entered in a separate system dialog and is never stored by iOSAnywhere."
            }
            try await service.setLocation(coordinate)
            simulationState = .simulating(coordinate)
            statusMessage = "Simulating \(coordinate.formatted) on \(device.name)."
        } catch {
            simulationState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func confirmUSBPrivilegeNotice() async {
        hasAcknowledgedUSBPrivilegeNotice = true
        showsUSBPrivilegeNotice = false
        await simulateSelectedLocation()
    }

    func dismissUSBPrivilegeNotice() {
        showsUSBPrivilegeNotice = false
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
            statusMessage = "Cleared simulated location on \(device.name)."
        } catch {
            simulationState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func prepareForTermination() async {
        await registry.shutdownAll()
        connectionState = .disconnected
        simulationState = .idle
        statusMessage = "Disconnected and cleared simulated locations."
    }
}
