import SwiftUI
import UniformTypeIdentifiers

struct InspectorPanelView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showsGPXImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                InspectorPanelHeaderView(selectedDeviceName: viewModel.selectedDevice?.name)
                InspectorDeviceSectionView(viewModel: viewModel)
                InspectorSessionStateSectionView(viewModel: viewModel)

                if viewModel.showsUSBApprovalReminder {
                    InspectorUSBApprovalNoticeView()
                }

                if case .starting = viewModel.simulationState {
                    InspectorAuthorizationProgressView()
                }

                InspectorActionsSectionView(viewModel: viewModel)
                InspectorRouteSectionView(
                    viewModel: viewModel,
                    importGPXAction: {
                        showsGPXImporter = true
                    }
                )
                InspectorStatusSectionView(viewModel: viewModel)
            }
            .padding(20)
        }
        .frame(minWidth: 280, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $viewModel.showsUSBPrivilegeNotice) {
            USBOnboardingSheet(
                guide: viewModel.selectedUSBSetupGuide,
                continueAction: { suppressFuturePrompts in
                    Task { await viewModel.confirmUSBPrivilegeNotice(suppressFuturePrompts: suppressFuturePrompts) }
                },
                cancelAction: {
                    viewModel.dismissUSBPrivilegeNotice()
                }
            )
        }
        .sheet(item: $viewModel.showsPythonDependencyGuide) { guide in
            PythonDependencyInstallSheet(
                guide: guide,
                dismissAction: {
                    viewModel.dismissPythonDependencyGuide()
                }
            )
        }
        .fileImporter(
            isPresented: $showsGPXImporter,
            allowedContentTypes: [.gpx, .xml],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }

                Task {
                    await viewModel.importGPXRoute(from: url)
                }
            case .failure(let error):
                let message = UserFacingText.localized(
                    TeleportStrings.failedToImportGPX(error.localizedDescription)
                )
                viewModel.routePlaybackState = .failed(message)
                viewModel.statusMessage = message
            }
        }
    }
}

extension UTType {
    fileprivate static let gpx = UTType(filenameExtension: "gpx") ?? .xml
}
