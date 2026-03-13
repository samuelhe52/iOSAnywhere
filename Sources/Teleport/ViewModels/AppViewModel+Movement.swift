import Foundation
import OSLog

extension AppViewModel {
    func updateMovementControl(_ vector: MovementControlVector) {
        guard movementControlSupportedForSelection else {
            movementControlVector = .zero
            statusMessage = .localized(TeleportStrings.movementAvailableForSimulatorOnly)
            return
        }

        guard movementControlAvailable else {
            movementControlVector = .zero
            statusMessage = .localized(TeleportStrings.movementRequiresConnection)
            return
        }

        guard !vector.isZero else {
            stopMovementControl()
            return
        }

        guard currentMovementAnchorCoordinate != nil else {
            movementControlVector = .zero
            statusMessage = .localized(TeleportStrings.movementRequiresValidCoordinates)
            return
        }

        suppressPickedLocationPin = true
        movementControlVector = vector

        guard movementLoopTask == nil else {
            return
        }

        movementLoopTask = Task {
            await runMovementLoop()
        }
    }

    func stopMovementControl(commitCurrentCoordinateToTextFields: Bool = true) {
        movementControlVector = .zero
        movementLoopTask?.cancel()
        movementLoopTask = nil

        guard commitCurrentCoordinateToTextFields,
            case .simulating(let coordinate) = simulationState
        else {
            return
        }

        latitudeText = String(format: "%.6f", coordinate.latitude)
        longitudeText = String(format: "%.6f", coordinate.longitude)
    }

    private var currentMovementAnchorCoordinate: LocationCoordinate? {
        if case .simulating(let coordinate) = simulationState {
            return coordinate
        }

        guard let latitude = Double(latitudeText),
            let longitude = Double(longitudeText),
            (-90.0...90.0).contains(latitude),
            (-180.0...180.0).contains(longitude)
        else {
            return nil
        }

        return LocationCoordinate(latitude: latitude, longitude: longitude)
    }

    private func runMovementLoop() async {
        guard let device = selectedDevice,
            let service = registry.service(for: device.kind),
            movementControlAvailable,
            movementControlSupportedForSelection,
            var coordinate = currentMovementAnchorCoordinate
        else {
            movementLoopTask = nil
            movementControlVector = .zero
            return
        }

        TeleportLog.simulation.info(
            "Starting movement loop on \(device.logLabel, privacy: .public) at \(coordinate.formatted, privacy: .private)"
        )

        defer {
            movementLoopTask = nil
            movementControlVector = .zero
        }

        do {
            if case .simulating = simulationState {
                // Keep the active simulated location as the movement origin.
            } else {
                try await applyDisplayedSimulationCoordinate(coordinate, on: device, using: service)
            }

            var lastStepStartedAt = Date()

            while !Task.isCancelled {
                let vector = movementControlVector
                guard !vector.isZero else {
                    break
                }

                let stepStartedAt = Date()
                let direction = vector.normalized
                let elapsedSinceLastStep = max(
                    stepStartedAt.timeIntervalSince(lastStepStartedAt),
                    movementTickIntervalSeconds
                )
                lastStepStartedAt = stepStartedAt
                let effectiveSpeed = movementSpeedMetersPerSecond * vector.magnitude
                let stepDistance = effectiveSpeed * elapsedSinceLastStep
                coordinate = coordinate.offsetBy(
                    northMeters: -direction.y * stepDistance,
                    eastMeters: direction.x * stepDistance
                )

                try await applyDisplayedSimulationCoordinate(
                    coordinate,
                    on: device,
                    using: service,
                    moving: true
                )

                let remainingDelay = movementTickIntervalSeconds - Date().timeIntervalSince(stepStartedAt)
                if remainingDelay > 0 {
                    try await Task.sleep(
                        nanoseconds: UInt64(remainingDelay * 1_000_000_000)
                    )
                }
            }

            TeleportLog.simulation.info(
                "Stopped movement loop on \(device.logLabel, privacy: .public) at \(coordinate.formatted, privacy: .private)"
            )
        } catch is CancellationError {
            TeleportLog.simulation.debug("Movement loop cancelled")
        } catch {
            handleSimulationError(error)
        }
    }
}
