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
                        Label("Administrator approval is required for USB device simulation.", systemImage: "lock.shield")
                            .font(.subheadline.weight(.semibold))
                        Text("Your password is requested in a separate macOS dialog. iOSAnywhere does not store, display, or reuse that password.")
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
        .alert("Administrator Approval", isPresented: $viewModel.showsUSBPrivilegeNotice) {
            Button("Continue") {
                Task { await viewModel.confirmUSBPrivilegeNotice() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.dismissUSBPrivilegeNotice()
            }
        } message: {
            Text(
                "USB device simulation needs administrator approval to create the device tunnel. Your password will be entered in a separate macOS dialog, and iOSAnywhere does not store it."
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
