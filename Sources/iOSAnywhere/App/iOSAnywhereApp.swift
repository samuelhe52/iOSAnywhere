import SwiftUI

@main
struct iOSAnywhereApp: App {
    @State private var viewModel = AppViewModel(
        registry: DeviceRegistry(
            services: [
                SimulatorLocationService(),
                USBDeviceLocationService()
            ]
        )
    )

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                DeviceSidebarView(viewModel: viewModel)
            } content: {
                MapWorkspaceView(viewModel: viewModel)
            } detail: {
                InspectorPanelView(viewModel: viewModel)
            }
            .task {
                await viewModel.refreshDevices()
            }
            .frame(minWidth: 1080, minHeight: 720)
        }
        .windowResizability(.contentSize)
    }
}
