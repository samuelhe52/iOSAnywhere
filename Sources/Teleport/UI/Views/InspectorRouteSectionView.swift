import Foundation
import SwiftUI

struct InspectorRouteSectionView: View {
    @Bindable var viewModel: AppViewModel
    let importGPXAction: () -> Void
    @State private var isExpanded = false

    private var routePlaybackSpeedPresetBinding: Binding<Double> {
        Binding(
            get: {
                Double(viewModel.currentRoutePlaybackSpeedPresetIndex)
            },
            set: { newValue in
                viewModel.setRoutePlaybackSpeedPreset(index: Int(newValue.rounded()))
            }
        )
    }

    private var routePlaybackTravelSpeedPresetBinding: Binding<Double> {
        Binding(
            get: {
                Double(viewModel.currentRoutePlaybackTravelSpeedPresetIndex)
            },
            set: { newValue in
                viewModel.setRoutePlaybackTravelSpeedPreset(index: Int(newValue.rounded()))
            }
        )
    }

    private var routePlaybackFixedIntervalPresetBinding: Binding<Double> {
        Binding(
            get: {
                Double(viewModel.currentRoutePlaybackFixedIntervalPresetIndex)
            },
            set: { newValue in
                viewModel.setRoutePlaybackFixedIntervalPreset(index: Int(newValue.rounded()))
            }
        )
    }

    var body: some View {
        InspectorPanelSection(TeleportStrings.routeSectionTitle, isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isRouteBuilderActive {
                    routeBuilderControls
                } else {
                    routeLibraryControls
                }

                if viewModel.isRouteBuilderActive {
                    routeBuilderContent
                } else if let route = viewModel.loadedRoute {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(route.name)
                            .font(.headline)

                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await viewModel.startRoutePlayback()
                                }
                            } label: {
                                Label(primaryRoutePlaybackActionTitle, systemImage: primaryRoutePlaybackActionSymbol)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.routePlaybackAvailable || viewModel.isRoutePlaybackActive)

                            Button {
                                if viewModel.isRoutePlaybackActive {
                                    viewModel.pauseRoutePlayback()
                                } else {
                                    viewModel.stopRoutePlayback()
                                }
                            } label: {
                                Label(
                                    secondaryRoutePlaybackActionTitle, systemImage: secondaryRoutePlaybackActionSymbol
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!secondaryRoutePlaybackEnabled)
                        }
                        .controlSize(.large)

                        StatusRow(
                            title: TeleportStrings.routePlaybackLabel,
                            value: viewModel.routePlaybackState.inspectorLabel,
                            tone: viewModel.routePlaybackState.inspectorTone
                        )

                        routeTimingControls

                        if let progress = viewModel.routePlaybackProgress {
                            LabeledContent {
                                Text(String(format: "%.0f%%", progress.fractionCompleted * 100))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } label: {
                                Text(TeleportStrings.routePlaybackProgressLabel)
                                    .font(.caption.weight(.medium))
                            }

                            LabeledContent {
                                Text("\(progress.waypointIndex + 1) / \(progress.waypointCount)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } label: {
                                Text(TeleportStrings.routePlaybackCurrentPointLabel)
                                    .font(.caption.weight(.medium))
                            }
                        }

                        LabeledContent {
                            Text(route.source.inspectorName)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(TeleportStrings.routeSourceLabel)
                                .font(.caption.weight(.medium))
                        }

                        LabeledContent {
                            Text("\(viewModel.loadedRouteWaypointCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(TeleportStrings.routePointsLabel)
                                .font(.caption.weight(.medium))
                        }

                        LabeledContent {
                            Text(formattedDistance(viewModel.loadedRouteDistanceMeters))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(TeleportStrings.routeDistanceLabel)
                                .font(.caption.weight(.medium))
                        }

                        if let recordedDurationSeconds = viewModel.loadedRouteRecordedDurationSeconds {
                            LabeledContent {
                                Text(formattedDuration(recordedDurationSeconds))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } label: {
                                Text(TeleportStrings.routeRecordedTimeLabel)
                                    .font(.caption.weight(.medium))
                            }
                        }

                        if let replayDurationSeconds = viewModel.loadedRouteReplayDurationSeconds {
                            LabeledContent {
                                Text(formattedDuration(replayDurationSeconds))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } label: {
                                Text(TeleportStrings.routeTotalTimeLabel)
                                    .font(.caption.weight(.medium))
                            }
                        }
                    }

                    if viewModel.hasSavedRoutes {
                        savedRoutesContent
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(TeleportStrings.routeEmptyHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if viewModel.hasSavedRoutes {
                            savedRoutesContent
                        }
                    }
                }
            }
        }
    }

    private var routeLibraryControls: some View {
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
        .controlSize(.large)
    }

    private var routeBuilderControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    viewModel.removeLastRouteBuilderWaypoint()
                } label: {
                    Label(TeleportStrings.routeBuilderUndo, systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasDraftRoute)

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

    private var routeBuilderContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TeleportStrings.routeBuilderTitle)
                .font(.headline)

            Text(TeleportStrings.routeBuilderHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent {
                Text("\(viewModel.routeBuilderWaypointCount)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Text(TeleportStrings.routePointsLabel)
                    .font(.caption.weight(.medium))
            }

            LabeledContent {
                Text(formattedDistance(viewModel.routeBuilderDistanceMeters))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Text(TeleportStrings.routeDistanceLabel)
                    .font(.caption.weight(.medium))
            }
        }
    }

    private var savedRoutesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TeleportStrings.savedRoutesTitle)
                .font(.subheadline.weight(.semibold))

            ForEach(viewModel.savedRoutes) { route in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(route.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(route.source.inspectorName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 12) {
                        Text("\(route.pointCount) pts")
                        Text(formattedDistance(route.totalDistanceMeters))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            viewModel.loadSavedRoute(route)
                        } label: {
                            Label(TeleportStrings.savedRouteLoad, systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.renameSavedRoute(route)
                        } label: {
                            Label(TeleportStrings.savedRouteRename, systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        viewModel.deleteSavedRoute(route)
                    } label: {
                        Label(TeleportStrings.savedRouteDelete, systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
            }
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.2f km", meters / 1_000)
        }

        return String(format: "%.0f m", meters)
    }

    @ViewBuilder
    private var routeTimingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TeleportStrings.routeTimingModeLabel)
                .font(.caption.weight(.medium))

            Picker("", selection: $viewModel.routePlaybackTimingMode) {
                Text(TeleportStrings.routeTimingRecorded).tag(RoutePlaybackTimingMode.recorded)
                Text(TeleportStrings.routeTimingFixed).tag(RoutePlaybackTimingMode.fixedInterval)
                Text(TeleportStrings.routeTimingSpeed).tag(RoutePlaybackTimingMode.fixedSpeed)
            }
            .pickerStyle(.segmented)

            switch viewModel.routePlaybackTimingMode {
            case .recorded:
                LabeledContent {
                    Text(String(format: "%.0fx", viewModel.routePlaybackSpeedMultiplier))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } label: {
                    Text(TeleportStrings.routeReplaySpeedLabel)
                        .font(.caption.weight(.medium))
                }

                Slider(
                    value: routePlaybackSpeedPresetBinding,
                    in: viewModel.routePlaybackSpeedPresetRange,
                    step: 1
                )

                HStack {
                    Text("1x")
                    Spacer(minLength: 12)
                    Text("32x")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                Text(TeleportStrings.routePacingHintRecorded)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

            case .fixedInterval:
                LabeledContent {
                    Text(String(format: "%.2fs", viewModel.routePlaybackFixedIntervalSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } label: {
                    Text(TeleportStrings.routeFixedIntervalLabel)
                        .font(.caption.weight(.medium))
                }

                Slider(
                    value: routePlaybackFixedIntervalPresetBinding,
                    in: viewModel.routePlaybackFixedIntervalPresetRange,
                    step: 1
                )

                HStack {
                    Text("0.10s")
                    Spacer(minLength: 12)
                    Text("2.00s")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                Text(TeleportStrings.routePacingHintFixed)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

            case .fixedSpeed:
                LabeledContent {
                    Text(String(format: "%.1f m/s", viewModel.routePlaybackTravelSpeedMetersPerSecond))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } label: {
                    Text(TeleportStrings.routeTravelSpeedLabel)
                        .font(.caption.weight(.medium))
                }

                Slider(
                    value: routePlaybackTravelSpeedPresetBinding,
                    in: viewModel.routePlaybackTravelSpeedPresetRange,
                    step: 1
                )

                HStack {
                    Text(String(format: "1.5 m/s · %@", String(localized: TeleportStrings.movementWalkingSpeed)))
                    Spacer(minLength: 12)
                    Text(String(format: "40.0 m/s · %@", String(localized: TeleportStrings.movementHighwaySpeed)))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                Text(TeleportStrings.routePacingHintSpeed)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: duration) ?? String(format: "%.1fs", duration)
    }

    private var primaryRoutePlaybackActionTitle: LocalizedStringResource {
        switch viewModel.routePlaybackState {
        case .completed:
            return TeleportStrings.routePlaybackReplay
        case .paused:
            return TeleportStrings.routePlaybackResume
        case .idle, .ready, .failed, .playing:
            return TeleportStrings.routePlaybackPlay
        }
    }

    private var primaryRoutePlaybackActionSymbol: String {
        switch viewModel.routePlaybackState {
        case .completed:
            return "arrow.clockwise"
        case .paused:
            return "play.fill"
        case .idle, .ready, .failed, .playing:
            return "play.fill"
        }
    }

    private var secondaryRoutePlaybackActionTitle: LocalizedStringResource {
        switch viewModel.routePlaybackState {
        case .playing:
            return TeleportStrings.routePlaybackPause
        case .idle, .ready, .paused, .completed, .failed:
            return TeleportStrings.routePlaybackStop
        }
    }

    private var secondaryRoutePlaybackActionSymbol: String {
        switch viewModel.routePlaybackState {
        case .playing:
            return "pause.fill"
        case .idle, .ready, .paused, .completed, .failed:
            return "stop.fill"
        }
    }

    private var secondaryRoutePlaybackEnabled: Bool {
        switch viewModel.routePlaybackState {
        case .playing, .paused, .failed:
            return true
        case .idle, .ready, .completed:
            return false
        }
    }
}
