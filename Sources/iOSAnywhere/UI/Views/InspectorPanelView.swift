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
        case .simulating(let coordinate): return coordinate.formatted
        case .stopping: return "Stopping"
        case .failed(let message): return message
        }
    }
}
