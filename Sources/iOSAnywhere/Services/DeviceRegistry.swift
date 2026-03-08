import Foundation

struct DeviceRegistry: Sendable {
    let services: [any LocationSimulationService]

    func service(for kind: DeviceKind) -> (any LocationSimulationService)? {
        services.first(where: { $0.kind == kind })
    }
}
