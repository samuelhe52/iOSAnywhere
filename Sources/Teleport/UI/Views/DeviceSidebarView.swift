import SwiftUI

struct DeviceSidebarView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showsSimulators = false

    var body: some View {
        List(selection: $viewModel.selectedDeviceID) {
            if !physicalDevices.isEmpty {
                Section("USB Devices") {
                    ForEach(physicalDevices) { device in
                        deviceRow(for: device)
                    }
                }
            }

            if !simulatorDevices.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsSimulators) {
                        ForEach(simulatorDevices) { device in
                            deviceRow(for: device)
                        }
                    } label: {
                        HStack {
                            Label("Simulators", systemImage: "desktopcomputer")
                            Spacer()
                            Text("\(simulatorDevices.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Devices")
    }

    private var physicalDevices: [Device] {
        viewModel.devices.filter { $0.kind == .physicalUSB }
    }

    private var simulatorDevices: [Device] {
        viewModel.devices.filter { $0.kind == .simulator }
    }

    @ViewBuilder
    private func deviceRow(for device: Device) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(device.name)
                    .font(.headline)

                if !device.isAvailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            if device.kind == .simulator {
                Text("Simulator")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("USB Device")
                    .font(.caption)
                    .foregroundStyle(device.isAvailable ? Color.secondary : Color.orange)
            }
            Text(device.details)
                .font(.caption2)
                .foregroundStyle(
                    device.isAvailable
                        ? AnyShapeStyle(.tertiary)
                        : AnyShapeStyle(.orange)
                )
                .lineLimit(2)
        }
        .opacity(device.isAvailable ? 1 : 0.78)
        .tag(device.id)
    }
}
