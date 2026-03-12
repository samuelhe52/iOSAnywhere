import AppKit
import CoreGraphics
import SwiftUI

struct InspectorPanelHeaderView: View {
    let selectedDeviceName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session")
                .font(.title3.weight(.semibold))

            if let selectedDeviceName {
                Text(selectedDeviceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a device to begin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InspectorDeviceSectionView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        InspectorPanelSection {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(deviceTint.opacity(0.16))
                        .frame(width: 42, height: 42)

                    Image(systemName: deviceIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(deviceTint)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let deviceName = viewModel.selectedDevice?.name {
                        Text(deviceName)
                            .font(.headline)
                    } else {
                        Text("No device selected")
                            .font(.headline)
                    }

                    Text(deviceSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let details = viewModel.selectedDevice?.details, !details.isEmpty {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var deviceSubtitle: String {
        guard let device = viewModel.selectedDevice else {
            return String(localized: TeleportStrings.chooseDeviceFromSidebar)
        }

        let kind: String
        switch device.kind {
        case .simulator:
            kind = String(localized: TeleportStrings.simulatorKind)
        case .physicalUSB:
            kind = String(localized: TeleportStrings.usbDeviceKind)
        case .physicalNetwork:
            kind = String(localized: TeleportStrings.wifiDeviceKind)
        }
        return String(localized: TeleportStrings.deviceSubtitle(kind: kind, osVersion: device.osVersion))
    }

    private var deviceIcon: String {
        switch viewModel.selectedDevice?.kind {
        case .simulator:
            return "iphone.gen3"
        case .physicalUSB:
            return "cable.connector"
        case .physicalNetwork:
            return "wifi"
        case nil:
            return "iphone.slash"
        }
    }

    private var deviceTint: Color {
        switch viewModel.selectedDevice?.kind {
        case .simulator:
            return .blue
        case .physicalUSB:
            return .green
        case .physicalNetwork:
            return .teal
        case nil:
            return .secondary
        }
    }
}

struct InspectorSessionStateSectionView: View {
    @Bindable var viewModel: AppViewModel
    @State private var isExpanded = true

    var body: some View {
        InspectorPanelSection("Status", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(
                    title: "Discovery",
                    value: viewModel.discoveryState.inspectorLabel,
                    tone: viewModel.discoveryState.inspectorTone
                )
                StatusRow(
                    title: "Connection",
                    value: viewModel.connectionState.inspectorLabel,
                    tone: viewModel.connectionState.inspectorTone
                )
                InspectorSimulationStatusRowView(viewModel: viewModel)
            }
        }
    }
}

fileprivate struct InspectorSimulationStatusRowView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showsCopiedCoordinatesPopup = false
    @State private var copiedCoordinatesTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Simulation")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if case .simulating(let coordinate) = viewModel.simulationState {
                Button {
                    copyCoordinates(coordinate.formatted)
                } label: {
                    HStack(spacing: 6) {
                        Text(coordinate.formatted)
                        Image(systemName: "doc.on.doc")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StatusTone.good.foregroundColor)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(StatusTone.good.backgroundColor)
                    )
                }
                .buttonStyle(.plain)
                .help("Copy coordinates")
                .overlay(alignment: .top) {
                    if showsCopiedCoordinatesPopup {
                        CopiedPopup()
                            .offset(y: -34)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            } else {
                StatusRowValue(
                    value: viewModel.simulationState.inspectorLabel, tone: viewModel.simulationState.inspectorTone)
            }
        }
    }

    private func copyCoordinates(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        copiedCoordinatesTask?.cancel()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            showsCopiedCoordinatesPopup = true
        }

        copiedCoordinatesTask = Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    showsCopiedCoordinatesPopup = false
                }
            }
        }
    }
}

struct InspectorUSBApprovalNoticeView: View {
    var body: some View {
        InspectorPanelSection {
            VStack(alignment: .leading, spacing: 8) {
                Label("Administrator approval is required for physical-device simulation.", systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))

                Text(
                    "Your password is requested in a separate macOS dialog. Teleport does not store, display, or reuse that password."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35))
        )
    }
}

struct InspectorAuthorizationProgressView: View {
    var body: some View {
        InspectorPanelSection {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Starting physical-device simulation")
                        .font(.footnote.weight(.semibold))
                    Text("Teleport is connecting to the device and preparing the helper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

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
                    .disabled(viewModel.connectionState == .disconnected)
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
                            || !isSimulating
                    )
                }

                Divider()

                InspectorInlineDisclosure(title: TeleportStrings.movementSectionTitle, isExpanded: $showsMovementControls) {
                    InspectorMovementControlsView(viewModel: viewModel, showsSectionTitle: false)
                }
            }
            .controlSize(.large)
        }
    }
}

struct InspectorRouteSectionView: View {
    @Bindable var viewModel: AppViewModel
    let importGPXAction: () -> Void
    @State private var isExpanded = false

    var body: some View {
        InspectorPanelSection(TeleportStrings.routeSectionTitle, isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button(action: importGPXAction) {
                        Label(TeleportStrings.routeImportGPX, systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        viewModel.clearLoadedRoute()
                    } label: {
                        Label(TeleportStrings.routeClear, systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasLoadedRoute)
                }
                .controlSize(.large)

                if let route = viewModel.loadedRoute {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(route.name)
                            .font(.headline)

                        StatusRow(
                            title: TeleportStrings.routePlaybackLabel,
                            value: viewModel.routePlaybackState.inspectorLabel,
                            tone: viewModel.routePlaybackState.inspectorTone
                        )

                        LabeledContent {
                            Text(route.source.inspectorName)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(TeleportStrings.routeSourceLabel)
                                .font(.caption.weight(.medium))
                        }

                        LabeledContent {
                            Text("\(viewModel.loadedRouteWaypointCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(TeleportStrings.routePointsLabel)
                                .font(.caption.weight(.medium))
                        }

                        LabeledContent {
                            Text(formattedDistance(viewModel.loadedRouteDistanceMeters))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(TeleportStrings.routeDistanceLabel)
                                .font(.caption.weight(.medium))
                        }
                    }
                } else {
                    Text(TeleportStrings.routeEmptyHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.2f km", meters / 1_000)
        }

        return String(format: "%.0f m", meters)
    }
}

struct InspectorStatusSectionView: View {
    @Bindable var viewModel: AppViewModel
    @State private var isExpanded = true

    var body: some View {
        InspectorPanelSection("Session Log", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: viewModel.inspectorStatusSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(viewModel.inspectorStatusTint)
                        .frame(width: 18)

                    Text(viewModel.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let pythonNote = viewModel.selectedPythonRuntimeNote {
                    Text(pythonNote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 28)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension DiscoveryState {
    fileprivate var inspectorLabel: UserFacingText {
        switch self {
        case .idle: return .localized(TeleportStrings.stateIdle)
        case .discovering: return .localized(TeleportStrings.stateDiscovering)
        case .ready: return .localized(TeleportStrings.stateReady)
        case .failed: return .localized(TeleportStrings.stateFailed)
        }
    }

    fileprivate var inspectorTone: StatusTone {
        switch self {
        case .idle:
            return .neutral
        case .discovering:
            return .active
        case .ready:
            return .good
        case .failed:
            return .error
        }
    }
}

extension DeviceConnectionState {
    fileprivate var inspectorLabel: UserFacingText {
        switch self {
        case .disconnected: return .localized(TeleportStrings.stateDisconnected)
        case .connecting: return .localized(TeleportStrings.stateConnecting)
        case .connected: return .localized(TeleportStrings.stateConnected)
        case .disconnecting: return .localized(TeleportStrings.stateDisconnecting)
        case .failed: return .localized(TeleportStrings.stateFailed)
        }
    }

    fileprivate var inspectorTone: StatusTone {
        switch self {
        case .disconnected:
            return .neutral
        case .connecting, .disconnecting:
            return .active
        case .connected:
            return .good
        case .failed:
            return .error
        }
    }
}

extension SimulationRunState {
    fileprivate var inspectorLabel: UserFacingText {
        switch self {
        case .idle: return .localized(TeleportStrings.stateIdle)
        case .starting: return .localized(TeleportStrings.stateStarting)
        case .simulating(let coordinate): return .verbatim(coordinate.formatted)
        case .stopping: return .localized(TeleportStrings.stateStopping)
        case .failed: return .localized(TeleportStrings.stateFailed)
        }
    }

    fileprivate var inspectorTone: StatusTone {
        switch self {
        case .idle:
            return .neutral
        case .starting, .stopping:
            return .active
        case .simulating:
            return .good
        case .failed:
            return .error
        }
    }
}

extension RoutePlaybackState {
    fileprivate var inspectorLabel: UserFacingText {
        switch self {
        case .idle:
            return .localized(TeleportStrings.stateIdle)
        case .ready:
            return .localized(TeleportStrings.routePlaybackReady)
        case .playing:
            return .localized(TeleportStrings.routePlaybackPlaying)
        case .paused:
            return .localized(TeleportStrings.routePlaybackPaused)
        case .completed:
            return .localized(TeleportStrings.routePlaybackCompleted)
        case .failed:
            return .localized(TeleportStrings.stateFailed)
        }
    }

    fileprivate var inspectorTone: StatusTone {
        switch self {
        case .idle:
            return .neutral
        case .ready, .paused:
            return .active
        case .playing, .completed:
            return .good
        case .failed:
            return .error
        }
    }
}

extension RouteSource {
    fileprivate var inspectorName: String {
        switch self {
        case .gpx:
            return String(localized: TeleportStrings.routeSourceGPX)
        case .drawn:
            return String(localized: TeleportStrings.routeSourceDrawn)
        case .navigation:
            return String(localized: TeleportStrings.routeSourceNavigation)
        }
    }
}

extension AppViewModel {
    fileprivate var inspectorStatusSymbol: String {
        if case .failed = simulationState {
            return "exclamationmark.triangle.fill"
        }
        if case .failed = connectionState {
            return "exclamationmark.triangle.fill"
        }

        switch connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting, .disconnecting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            break
        }

        switch simulationState {
        case .simulating:
            return "location.fill"
        case .starting, .stopping:
            return "clock.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "info.circle.fill"
        }
    }

    fileprivate var inspectorStatusTint: Color {
        if case .failed = connectionState {
            return .red
        }
        if case .failed = simulationState {
            return .red
        }
        if case .connected = connectionState {
            return .green
        }
        if case .simulating = simulationState {
            return .blue
        }
        return .secondary
    }
}
