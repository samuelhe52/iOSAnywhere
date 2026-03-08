import SwiftUI

struct InspectorPanelView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session")
                .font(.title3.weight(.semibold))

            LabeledContent("Discovery") {
                Text(label(for: viewModel.discoveryState))
            }
            LabeledContent("Connection") {
                Text(label(for: viewModel.connectionState))
            }
            LabeledContent("Simulation") {
                Text(label(for: viewModel.simulationState))
            }

            if viewModel.selectedDeviceRequiresAdministratorApproval {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Administrator approval is required for USB device simulation.", systemImage: "lock.shield"
                        )
                        .font(.subheadline.weight(.semibold))
                        Text(
                            "Your password is requested in a separate macOS dialog. iOSAnywhere does not store, display, or reuse that password."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if case .authorizing = viewModel.simulationState {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for administrator approval...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button("Refresh Devices") {
                    Task { await viewModel.refreshDevices() }
                }
                Button("Connect") {
                    Task { await viewModel.connectSelectedDevice() }
                }
                .disabled(viewModel.selectedDevice == nil)
                Button("Simulate Location") {
                    Task { await viewModel.simulateSelectedLocation() }
                }
                .disabled(viewModel.connectionState != .connected)
                Button("Stop Location") {
                    Task { await viewModel.clearSimulatedLocation() }
                }
                .disabled(viewModel.connectionState != .connected)
                Button("Disconnect") {
                    Task { await viewModel.disconnectSelectedDevice() }
                }
                .disabled(viewModel.connectionState == .disconnected)
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 260)
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

    private func label(for state: DiscoveryState) -> String {
        switch state {
        case .idle: return "Idle"
        case .discovering: return "Discovering"
        case .ready: return "Ready"
        case .failed(let message): return message
        }
    }

    private func label(for state: DeviceConnectionState) -> String {
        switch state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting"
        case .failed(let message): return message
        }
    }

    private func label(for state: SimulationRunState) -> String {
        switch state {
        case .idle: return "Idle"
        case .authorizing: return "Authorizing"
        case .simulating(let coordinate): return coordinate.formatted
        case .stopping: return "Stopping"
        case .failed(let message): return message
        }
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
