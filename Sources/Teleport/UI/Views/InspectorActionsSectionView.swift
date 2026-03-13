import AppKit
import CoreGraphics
import SwiftUI

struct InspectorMovementControlsView: View {
    @Bindable var viewModel: AppViewModel
    let showsSectionTitle: Bool

    init(viewModel: AppViewModel, showsSectionTitle: Bool = true) {
        self.viewModel = viewModel
        self.showsSectionTitle = showsSectionTitle
    }

    private var movementSpeedPresetBinding: Binding<Double> {
        Binding(
            get: {
                Double(viewModel.currentMovementSpeedPresetIndex)
            },
            set: { newValue in
                viewModel.setMovementSpeedPreset(index: Int(newValue.rounded()))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsSectionTitle {
                Text(TeleportStrings.movementSectionTitle)
                    .font(.subheadline.weight(.semibold))
            }

            MovementWheelView(
                isEnabled: viewModel.movementControlAvailable,
                isActive: viewModel.isMovementControlActive,
                onChange: { vector in
                    viewModel.updateMovementControl(vector)
                },
                onEnd: {
                    viewModel.stopMovementControl()
                }
            )
            .frame(maxWidth: .infinity)

            Text(TeleportStrings.movementWheelHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Label(
                    viewModel.isMovementControlActive
                        ? TeleportStrings.movementActive
                        : TeleportStrings.movementIdle,
                    systemImage: viewModel.isMovementControlActive ? "location.north.line.fill" : "pause.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(viewModel.isMovementControlActive ? .blue : .secondary)

                Spacer(minLength: 8)

                Text(
                    String(
                        format: "%.1f / %.1f m/s · %.2fs", viewModel.effectiveMovementSpeedMetersPerSecond,
                        viewModel.movementSpeedMetersPerSecond,
                        viewModel.movementTickIntervalSeconds)
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                LabeledContent {
                    Text(String(format: "%.1f m/s", viewModel.movementSpeedMetersPerSecond))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } label: {
                    Text(TeleportStrings.movementSpeedLabel)
                        .font(.caption.weight(.medium))
                }

                Slider(
                    value: movementSpeedPresetBinding,
                    in: viewModel.movementSpeedPresetRange,
                    step: 1
                )
                .disabled(!viewModel.movementControlSupportedForSelection)

                HStack {
                    Text(String(format: "1.5 m/s · %@", String(localized: TeleportStrings.movementWalkingSpeed)))
                    Spacer(minLength: 12)
                    Text(String(format: "40.0 m/s · %@", String(localized: TeleportStrings.movementHighwaySpeed)))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                LabeledContent {
                    Text(String(format: "%.2fs", viewModel.movementTickIntervalSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } label: {
                    Text(TeleportStrings.movementUpdateIntervalLabel)
                        .font(.caption.weight(.medium))
                }

                Slider(
                    value: $viewModel.movementTickIntervalSeconds,
                    in: viewModel.movementTickIntervalRange,
                    step: 0.05
                )
                .disabled(!viewModel.movementControlSupportedForSelection)
            }

            if let availabilityMessage {
                Text(availabilityMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availabilityMessage: LocalizedStringResource? {
        guard !viewModel.movementControlAvailable else {
            return nil
        }

        if !viewModel.movementControlSupportedForSelection {
            return TeleportStrings.movementAvailableForSimulatorOnly
        }

        if viewModel.selectedDevice?.kind.isPhysicalDevice == true,
            viewModel.connectionState == .connected
        {
            return TeleportStrings.movementRequiresActivePhysicalSimulation
        }

        return TeleportStrings.movementRequiresConnection
    }
}

fileprivate struct MovementWheelView: View {
    let isEnabled: Bool
    let isActive: Bool
    let onChange: (MovementControlVector) -> Void
    let onEnd: () -> Void

    @State private var knobOffset: CGSize = .zero

    private let wheelDiameter: CGFloat = 132
    private let knobDiameter: CGFloat = 46

    var body: some View {
        let radius = wheelDiameter / 2
        let knobTravel = radius - knobDiameter / 2 - 6

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(isEnabled ? 0.22 : 0.08),
                            Color(NSColor.controlColor).opacity(isEnabled ? 0.92 : 0.7)
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: radius
                    )
                )

            Circle()
                .strokeBorder(Color.primary.opacity(isEnabled ? 0.16 : 0.08), lineWidth: 1)

            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                .foregroundStyle(Color.primary.opacity(0.08))
                .padding(22)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: wheelDiameter - 24)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: wheelDiameter - 24, height: 1)

            Circle()
                .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.45))
                .frame(width: knobDiameter, height: knobDiameter)
                .overlay {
                    Image(systemName: isActive ? "location.north.fill" : "circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(isEnabled ? 0.18 : 0.08), radius: 8, y: 5)
                .offset(knobOffset)
        }
        .frame(width: wheelDiameter, height: wheelDiameter)
        .contentShape(Circle())
        .opacity(isEnabled ? 1 : 0.65)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isEnabled else {
                        return
                    }

                    let clampedOffset = clampedOffset(for: value.translation, maxDistance: knobTravel)
                    knobOffset = clampedOffset
                    onChange(
                        MovementControlVector(
                            x: clampedOffset.width / knobTravel,
                            y: clampedOffset.height / knobTravel
                        )
                    )
                }
                .onEnded { _ in
                    knobOffset = .zero
                    onEnd()
                }
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.82), value: knobOffset)
    }

    private func clampedOffset(for translation: CGSize, maxDistance: CGFloat) -> CGSize {
        let distance = sqrt((translation.width * translation.width) + (translation.height * translation.height))

        guard distance > maxDistance, distance > 0 else {
            return translation
        }

        let scale = maxDistance / distance
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }
}

struct InspectorActionsSectionView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showsMovementControls = false

    private var isSimulating: Bool {
        if case .simulating = viewModel.simulationState {
            return true
        }

        return false
    }

    var body: some View {
        InspectorPanelSection("Actions") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await viewModel.refreshDevices() }
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.connectSelectedDevice() }
                    } label: {
                        Label("Connect", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        viewModel.selectedDevice == nil
                            || viewModel.selectedDevice?.isAvailable == false
                            || viewModel.connectionState == .connecting
                            || viewModel.connectionState == .connected
                    )

                    Button {
                        Task { await viewModel.disconnectSelectedDevice() }
                    } label: {
                        Label("Disconnect", image: "link.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        viewModel.connectionState == .disconnected
                            || viewModel.isSimulationActionInFlight
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.simulateSelectedLocation() }
                    } label: {
                        Label("Simulate", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        viewModel.connectionState != .connected
                            || viewModel.selectedDevice?.isAvailable == false
                            || viewModel.isSimulationActionInFlight
                            || viewModel.simulationState == .starting
                            || viewModel.simulationState == .stopping
                    )

                    Button {
                        Task { await viewModel.clearSimulatedLocation() }
                    } label: {
                        Label("Stop", systemImage: "location.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        viewModel.connectionState != .connected
                            || viewModel.selectedDevice?.isAvailable == false
                            || viewModel.isSimulationActionInFlight
                            || !isSimulating
                    )
                }

                Divider()

                InspectorInlineDisclosure(
                    title: TeleportStrings.movementSectionTitle, isExpanded: $showsMovementControls
                ) {
                    InspectorMovementControlsView(viewModel: viewModel, showsSectionTitle: false)
                }
            }
            .controlSize(.large)
        }
    }
}
