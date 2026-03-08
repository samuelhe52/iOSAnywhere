import Foundation

struct DeviceRegistry: Sendable {
    let services: [any LocationSimulationService]

    func service(for kind: DeviceKind) -> (any LocationSimulationService)? {
        services.first(where: { $0.kind == kind })
    }

    func shutdownAll() async {
        for service in services {
            try? await service.clearLocation()
            await service.disconnect()
        }
    }
}
