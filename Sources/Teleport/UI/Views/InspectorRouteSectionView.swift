import Foundation
import SwiftUI

struct InspectorRouteSectionView: View {
    @Bindable var viewModel: AppViewModel
    let importGPXAction: () -> Void
    @State private var isExpanded = false
    @State private var showsAllSavedRoutes = false

    private let savedRoutesPreviewLimit = 3

    var body: some View {
        InspectorPanelSection(TeleportStrings.routeSectionTitle, isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isRouteBuilderActive {
                    RouteBuilderControlsView(viewModel: viewModel)
                } else {
                    RouteLibraryControlsView(viewModel: viewModel, importGPXAction: importGPXAction)
                }

                if viewModel.isRouteBuilderActive {
                    RouteBuilderContentView(viewModel: viewModel)
                } else if let route = viewModel.loadedRoute {
                    LoadedRouteDetailsView(viewModel: viewModel, route: route)

                    if viewModel.hasSavedRoutes {
                        SavedRoutesListView(
                            viewModel: viewModel,
                            showsAllSavedRoutes: $showsAllSavedRoutes,
                            previewLimit: savedRoutesPreviewLimit
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(TeleportStrings.routeEmptyHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if viewModel.hasSavedRoutes {
                            SavedRoutesListView(
                                viewModel: viewModel,
                                showsAllSavedRoutes: $showsAllSavedRoutes,
                                previewLimit: savedRoutesPreviewLimit
                            )
                        }
                    }
                }
            }
        }
    }
}
