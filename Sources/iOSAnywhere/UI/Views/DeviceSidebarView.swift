import SwiftUI

struct DeviceSidebarView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        List(selection: $viewModel.selectedDeviceID) {
            ForEach(viewModel.devices) { device in
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                    Text(device.kind == .simulator ? "Simulator" : "USB Device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(device.details)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                .tag(device.id)
            }
        }
        .navigationTitle("Devices")
    }
}
