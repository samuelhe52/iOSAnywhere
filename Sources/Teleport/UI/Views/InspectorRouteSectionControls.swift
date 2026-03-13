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
        if viewModel.loadedRouteIsSavedInApp {
            HStack(spacing: 10) {
                Button {
                    viewModel.updateCurrentSavedRouteInApp()
                } label: {
                    Label(TeleportStrings.routeUpdateSaved, systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.currentRouteCanUpdateSavedRoute)

                Button {
                    viewModel.saveCurrentRouteToAppAsNew()
                } label: {
                    Label(TeleportStrings.routeSaveAsNew, systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.currentRouteCanSaveAsNew)
            }
        } else {
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
                    viewModel.finalizeRouteBuilder()
                } label: {
                    Label(TeleportStrings.routeBuilderSave, systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.routeBuilderCanFinalize)
            }

            Button {
                viewModel.cancelRouteBuilder()
            } label: {
                Label(TeleportStrings.routeBuilderCancel, systemImage: "xmark")
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

            Text(TeleportStrings.routeBuilderHint)
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
                .disabled(viewModel.isRouteBuilderResolvingNavigation)
            } label: {
                Text(TeleportStrings.routeBuilderModeLabel)
                    .font(.caption.weight(.medium))
            }

            if viewModel.routeBuilderMode == .navigation {
                Text(TeleportStrings.routeBuilderNavigationHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
