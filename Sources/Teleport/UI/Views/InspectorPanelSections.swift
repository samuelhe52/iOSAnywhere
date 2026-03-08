import AppKit
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

        let kind = String(
            localized: device.kind == .simulator ? TeleportStrings.simulatorKind : TeleportStrings.usbDeviceKind
        )
        return String(localized: TeleportStrings.deviceSubtitle(kind: kind, osVersion: device.osVersion))
    }

    private var deviceIcon: String {
        switch viewModel.selectedDevice?.kind {
        case .simulator:
            return "iphone.gen3"
        case .physicalUSB:
            return "cable.connector"
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
        case nil:
            return .secondary
        }
    }
}

struct InspectorSessionStateSectionView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        InspectorPanelSection("Status") {
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
                Label("Administrator approval is required for USB device simulation.", systemImage: "lock.shield")
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
                    Text("Waiting for administrator approval")
                        .font(.footnote.weight(.semibold))
                    Text("Complete the separate macOS password dialog to continue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InspectorActionsSectionView: View {
    @Bindable var viewModel: AppViewModel

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
                    .disabled(viewModel.selectedDevice == nil)

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
                    .disabled(viewModel.connectionState != .connected)

                    Button {
                        Task { await viewModel.clearSimulatedLocation() }
                    } label: {
                        Label("Stop", systemImage: "location.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.connectionState != .connected)
                }
            }
            .controlSize(.large)
        }
    }
}

struct InspectorStatusSectionView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        InspectorPanelSection("Session Log") {
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
        case .authorizing: return .localized(TeleportStrings.stateAuthorizing)
        case .simulating(let coordinate): return .verbatim(coordinate.formatted)
        case .stopping: return .localized(TeleportStrings.stateStopping)
        case .failed: return .localized(TeleportStrings.stateFailed)
        }
    }

    fileprivate var inspectorTone: StatusTone {
        switch self {
        case .idle:
            return .neutral
        case .authorizing, .stopping:
            return .active
        case .simulating:
            return .good
        case .failed:
            return .error
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
        case .authorizing, .stopping:
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
