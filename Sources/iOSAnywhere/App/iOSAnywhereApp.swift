import AppKit
import SwiftUI

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    var shutdownHandler: (() async -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let shutdownHandler else {
            return .terminateNow
        }

        Task {
            await shutdownHandler()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}

@main
struct iOSAnywhereApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
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
                    .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
            }
            .task {
                appDelegate.shutdownHandler = {
                    await viewModel.prepareForTermination()
                }
                await viewModel.refreshDevices()
            }
            .frame(minWidth: 1200, minHeight: 720)
        }
        .windowResizability(.contentSize)
    }
}
