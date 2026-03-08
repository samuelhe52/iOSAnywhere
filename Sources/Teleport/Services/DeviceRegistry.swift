import Foundation
import OSLog

struct DeviceRegistry: Sendable {
    let services: [any LocationSimulationService]

    func service(for kind: DeviceKind) -> (any LocationSimulationService)? {
        let service = services.first(where: { $0.kind == kind })

        if service == nil {
            TeleportLog.devices.error("No registered service found for device kind \(kind.rawValue, privacy: .public)")
        }

        return service
    }

    func shutdownAll() async {
        TeleportLog.devices.info("Shutting down \(services.count) location simulation service(s)")
        for service in services {
            do {
                try await service.clearLocation()
            } catch {
                TeleportLog.simulation.warning(
                    "Failed to clear location while shutting down \(service.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            await service.disconnect()
            TeleportLog.devices.debug("Disconnected service for \(service.kind.rawValue, privacy: .public)")
        }
    }
}
