import Foundation
import SwiftUI

struct RouteLibraryControlsView: View {
    @Bindable var viewModel: AppViewModel
    let importGPXAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: importGPXAction) {
                    Label(TeleportStrings.routeImportGPX, systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.startRouteBuilder()
                } label: {
                    Label(TeleportStrings.routeCreate, systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if viewModel.hasLoadedRoute {
                saveAndExportControls
                clearControls
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var saveAndExportControls: some View {
        if !viewModel.loadedRouteIsSavedInApp {
            HStack(spacing: 10) {
                Button {
                    viewModel.saveCurrentRouteToApp()
                } label: {
                    Label(TeleportStrings.routeSaveInApp, systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.currentRouteCanBeSavedToApp)

                Button {
                    viewModel.exportCurrentRouteAsGPX()
                } label: {
                    Label(TeleportStrings.routeExportGPX, systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.currentRouteCanBeExportedAsGPX)
            }
        }
    }

    private var clearControls: some View {
        HStack(spacing: 10) {
            if viewModel.loadedRouteIsSavedInApp {
                Button {
                    viewModel.exportCurrentRouteAsGPX()
                } label: {
                    Label(TeleportStrings.routeExportGPX, systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.currentRouteCanBeExportedAsGPX)
            }

            Button {
                viewModel.clearLoadedRoute()
            } label: {
                Label(TeleportStrings.routeClear, systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct RouteBuilderControlsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    viewModel.removeLastRouteBuilderWaypoint()
                } label: {
                    Label(TeleportStrings.routeBuilderUndo, systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.routeBuilderCanUndo)

                Button {
                    if viewModel.isRouteBuilderEditingSavedRoute {
                        viewModel.updateEditedSavedRouteInApp()
                    } else {
                        viewModel.finalizeRouteBuilder()
                    }
                } label: {
                    Label(
                        viewModel.isRouteBuilderEditingSavedRoute
                            ? TeleportStrings.routeUpdateSaved
                            : TeleportStrings.routeBuilderSave,
                        systemImage: viewModel.isRouteBuilderEditingSavedRoute
                            ? "arrow.triangle.2.circlepath"
                            : "checkmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.routeBuilderCanFinalize)
            }

            if viewModel.isRouteBuilderEditingSavedRoute {
                Button {
                    viewModel.saveEditedRouteAsNewInApp()
                } label: {
                    Label(TeleportStrings.routeSaveAsNew, systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.routeBuilderCanFinalize)
            }

            Button {
                viewModel.cancelRouteBuilder()
            } label: {
                Label(
                    viewModel.isRouteBuilderEditingSavedRoute
                        ? TeleportStrings.routeBuilderDiscardEdit
                        : TeleportStrings.routeBuilderCancel,
                    systemImage: "xmark"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }
}

struct RouteBuilderContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TeleportStrings.routeBuilderTitle)
                .font(.headline)

            Text(
                viewModel.isRouteBuilderEditingSavedRoute
                    ? TeleportStrings.routeBuilderEditHint : TeleportStrings.routeBuilderHint
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            LabeledContent {
                Picker(selection: routeBuilderModeBinding) {
                    Text(TeleportStrings.routeBuilderModeStraight)
                        .tag(RouteBuilderMode.straightLine)
                    Text(TeleportStrings.routeBuilderModeNavigation)
                        .tag(RouteBuilderMode.navigation)
                } label: {
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isRouteBuilderResolvingNavigation || viewModel.isRouteBuilderEditingSavedRoute)
            } label: {
                Text(TeleportStrings.routeBuilderModeLabel)
                    .font(.caption.weight(.medium))
            }

            if viewModel.routeBuilderMode == .navigation {
                Text(TeleportStrings.routeBuilderNavigationHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent {
                    Picker(selection: routeBuilderTransportBinding) {
                        Text(TeleportStrings.routeBuilderTransportDriving)
                            .tag(RouteBuilderNavigationTransport.driving)
                        Text(TeleportStrings.routeBuilderTransportCycling)
                            .tag(RouteBuilderNavigationTransport.cycling)
                        Text(TeleportStrings.routeBuilderTransportWalking)
                            .tag(RouteBuilderNavigationTransport.walking)
                    } label: {
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.isRouteBuilderResolvingNavigation)
                } label: {
                    Text(TeleportStrings.routeBuilderTransportLabel)
                        .font(.caption.weight(.medium))
                }
            }

            if viewModel.isRouteBuilderResolvingNavigation {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(TeleportStrings.routeBuilderRoutingSegment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.routeBuilderMode == .navigation {
                LabeledContent {
                    Text("\(viewModel.routeBuilderStopCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Text(TeleportStrings.routeBuilderStopsLabel)
                        .font(.caption.weight(.medium))
                }

                if viewModel.routeBuilderHasMultipleAlternatives {
                    LabeledContent {
                        Picker(selection: latestAlternativeBinding) {
                            ForEach(Array(viewModel.routeBuilderLatestSegmentAlternatives.enumerated()), id: \.offset) {
                                index, alternative in
                                Text(latestAlternativeLabel(for: alternative, index: index))
                                    .tag(index)
                            }
                        } label: {
                        }
                        .pickerStyle(.menu)
                        .disabled(viewModel.isRouteBuilderResolvingNavigation)
                    } label: {
                        Text(TeleportStrings.routeBuilderLatestLegLabel)
                            .font(.caption.weight(.medium))
                    }

                    Text(TeleportStrings.routeBuilderAlternativesHint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LabeledContent {
                Text("\(viewModel.routeBuilderWaypointCount)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Text(TeleportStrings.routePointsLabel)
                    .font(.caption.weight(.medium))
            }

            LabeledContent {
                Text(RouteInspectorFormatting.formattedDistance(viewModel.routeBuilderDistanceMeters))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Text(TeleportStrings.routeDistanceLabel)
                    .font(.caption.weight(.medium))
            }
        }
    }

    private var routeBuilderModeBinding: Binding<RouteBuilderMode> {
        Binding(
            get: { viewModel.routeBuilderMode },
            set: { viewModel.setRouteBuilderMode($0) }
        )
    }

    private var routeBuilderTransportBinding: Binding<RouteBuilderNavigationTransport> {
        Binding(
            get: { viewModel.routeBuilderNavigationTransport },
            set: { viewModel.setRouteBuilderNavigationTransport($0) }
        )
    }

    private var latestAlternativeBinding: Binding<Int> {
        Binding(
            get: { viewModel.routeBuilderSelectedAlternativeIndex },
            set: { viewModel.selectLatestRouteBuilderAlternative(index: $0) }
        )
    }

    private func latestAlternativeLabel(for alternative: RouteBuilderNavigationAlternative, index: Int) -> String {
        let distance = RouteInspectorFormatting.formattedDistance(alternative.distanceMeters)
        if let expectedTravelTime = alternative.expectedTravelTime {
            let duration = RouteInspectorFormatting.formattedDuration(expectedTravelTime)
            return "Option \(index + 1) · \(distance) · \(duration)"
        }

        return "Option \(index + 1) · \(distance)"
    }
}

enum RouteInspectorFormatting {
    static func formattedDistance(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.2f km", meters / 1_000)
        }

        return String(format: "%.0f m", meters)
    }

    static func formattedDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: duration) ?? String(format: "%.1fs", duration)
    }

    static func formattedSavedRouteAge(_ date: Date) -> String {
        let elapsedSeconds = max(0, Int(Date.now.timeIntervalSince(date)))

        if elapsedSeconds >= 14 * 24 * 60 * 60 {
            return "2 wk+"
        }

        if elapsedSeconds >= 7 * 24 * 60 * 60 {
            return "1 wk"
        }

        if elapsedSeconds >= 24 * 60 * 60 {
            let dayCount = elapsedSeconds / (24 * 60 * 60)
            return "\(dayCount) day" + (dayCount == 1 ? "" : "s")
        }

        if elapsedSeconds >= 60 * 60 {
            return "\(elapsedSeconds / (60 * 60)) hr"
        }

        if elapsedSeconds >= 60 {
            return "\(elapsedSeconds / 60) min"
        }

        if elapsedSeconds >= 5 {
            return "\(elapsedSeconds) sec"
        }

        return "now"
    }
}
