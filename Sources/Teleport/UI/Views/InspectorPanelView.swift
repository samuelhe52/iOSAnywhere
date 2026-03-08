import SwiftUI

struct InspectorPanelView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                InspectorPanelHeaderView(selectedDeviceName: viewModel.selectedDevice?.name)
                InspectorDeviceSectionView(viewModel: viewModel)
                InspectorSessionStateSectionView(viewModel: viewModel)

                if viewModel.showsUSBApprovalReminder {
                    InspectorUSBApprovalNoticeView()
                }

                if case .authorizing = viewModel.simulationState {
                    InspectorAuthorizationProgressView()
                }

                InspectorActionsSectionView(viewModel: viewModel)
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
    }
}
