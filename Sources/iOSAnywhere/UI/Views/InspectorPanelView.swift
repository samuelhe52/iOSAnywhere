import AppKit
import SwiftUI

struct InspectorPanelView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showsCopiedCoordinatesPopup = false
    @State private var copiedCoordinatesTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                deviceSection
                sessionStateSection

                if viewModel.showsUSBApprovalReminder {
                    usbApprovalNotice
                }

                if case .authorizing = viewModel.simulationState {
                    authorizationProgress
                }

                actionsSection
                statusSection
            }
            .padding(20)
        }
        .frame(minWidth: 300, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $viewModel.showsUSBPrivilegeNotice) {
            USBAuthorizationSheet(
                continueAction: {
                    Task { await viewModel.confirmUSBPrivilegeNotice() }
                },
                cancelAction: {
                    viewModel.dismissUSBPrivilegeNotice()
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session")
                .font(.title3.weight(.semibold))

            Text(viewModel.selectedDevice?.name ?? "Select a device to begin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var deviceSection: some View {
        panelSection {
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
                    Text(viewModel.selectedDevice?.name ?? "No device selected")
                        .font(.headline)

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

    private var sessionStateSection: some View {
        panelSection("Status") {
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(title: "Discovery", value: label(for: viewModel.discoveryState), tone: tone(for: viewModel.discoveryState))
                StatusRow(title: "Connection", value: label(for: viewModel.connectionState), tone: tone(for: viewModel.connectionState))
                simulationStatusRow
            }
        }
    }

    private var simulationStatusRow: some View {
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
                StatusRowValue(value: label(for: viewModel.simulationState), tone: tone(for: viewModel.simulationState))
            }
        }
    }

    private var usbApprovalNotice: some View {
        panelSection {
            VStack(alignment: .leading, spacing: 8) {
                Label("Administrator approval is required for USB device simulation.", systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))

                Text(
                    "Your password is requested in a separate macOS dialog. iOSAnywhere does not store, display, or reuse that password."
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

    private var authorizationProgress: some View {
        panelSection {
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

    private var actionsSection: some View {
        panelSection("Actions") {
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
                        Label("Disconnect", systemImage: "link.badge.minus")
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

    private var statusSection: some View {
        panelSection("Session Log") {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusTint)
                    .frame(width: 18)

                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deviceSubtitle: String {
        guard let device = viewModel.selectedDevice else {
            return "Choose a USB device or simulator from the sidebar."
        }

        let kind = device.kind == .simulator ? "Simulator" : "USB Device"
        return "\(kind) · iOS \(device.osVersion)"
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

    private var statusSymbol: String {
        switch viewModel.connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting, .disconnecting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            break
        }

        switch viewModel.simulationState {
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

    private var statusTint: Color {
        if case .failed = viewModel.connectionState {
            return .red
        }
        if case .failed = viewModel.simulationState {
            return .red
        }
        if case .connected = viewModel.connectionState {
            return .green
        }
        if case .simulating = viewModel.simulationState {
            return .blue
        }
        return .secondary
    }

    private func label(for state: DiscoveryState) -> String {
        switch state {
        case .idle: return "Idle"
        case .discovering: return "Discovering"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }

    private func label(for state: DeviceConnectionState) -> String {
        switch state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting"
        case .failed: return "Failed"
        }
    }

    private func label(for state: SimulationRunState) -> String {
        switch state {
        case .idle: return "Idle"
        case .authorizing: return "Authorizing"
        case .simulating(let coordinate): return coordinate.formatted
        case .stopping: return "Stopping"
        case .failed: return "Failed"
        }
    }

    private func tone(for state: DiscoveryState) -> StatusTone {
        switch state {
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

    private func tone(for state: DeviceConnectionState) -> StatusTone {
        switch state {
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

    private func tone(for state: SimulationRunState) -> StatusTone {
        switch state {
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

    @ViewBuilder
    private func panelSection<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06))
        )
    }
}

fileprivate enum StatusTone {
    case neutral
    case active
    case good
    case error

    var foregroundColor: Color {
        switch self {
        case .neutral:
            return .secondary
        case .active:
            return .blue
        case .good:
            return .green
        case .error:
            return .red
        }
    }

    var backgroundColor: Color {
        switch self {
        case .neutral:
            return Color.secondary.opacity(0.12)
        case .active:
            return Color.blue.opacity(0.14)
        case .good:
            return Color.green.opacity(0.14)
        case .error:
            return Color.red.opacity(0.14)
        }
    }
}

fileprivate struct StatusRow: View {
    let title: String
    let value: String
    let tone: StatusTone

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            StatusRowValue(value: value, tone: tone)
        }
    }
}

fileprivate struct StatusRowValue: View {
    let value: String
    let tone: StatusTone

    var body: some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.backgroundColor)
            )
    }
}

fileprivate struct CopiedPopup: View {
    var body: some View {
        Text("Copied")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.96))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

fileprivate struct USBAuthorizationSheet: View {
    let continueAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Administrator Approval Required")
                        .font(.title3.weight(.semibold))
                    Text(
                        "To simulate location on a USB device, macOS will ask for your administrator password in a separate system dialog."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SimpleSecurityRow(
                    icon: "checkmark.shield",
                    text: "iOSAnywhere does not capture or store your password."
                )
                SimpleSecurityRow(
                    icon: "cable.connector",
                    text: "The approval is used only to create the USB device tunnel."
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            HStack {
                Button("Cancel", role: .cancel) {
                    cancelAction()
                }

                Spacer()

                Button("Continue") {
                    continueAction()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

fileprivate struct SimpleSecurityRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 18)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
