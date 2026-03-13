import Foundation
import SwiftUI

struct LoadedRouteDetailsView: View {
    @Bindable var viewModel: AppViewModel
    let route: SimulatedRoute

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
        VStack(alignment: .leading, spacing: 10) {
            Text(route.name)
                .font(.headline)

            playbackControls

            StatusRow(
                title: TeleportStrings.routePlaybackLabel,
                value: viewModel.routePlaybackState.inspectorLabel,
                tone: viewModel.routePlaybackState.inspectorTone
            )

            routeTimingControls

            if let progress = viewModel.routePlaybackProgress {
                playbackProgress(progress)
            }

            routeMetadata
        }
    }

    private var playbackControls: some View {
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
                Label(secondaryRoutePlaybackActionTitle, systemImage: secondaryRoutePlaybackActionSymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!secondaryRoutePlaybackEnabled)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private func playbackProgress(_ progress: RoutePlaybackProgress) -> some View {
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

    private var routeMetadata: some View {
        Group {
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
                Text(RouteInspectorFormatting.formattedDistance(viewModel.loadedRouteDistanceMeters))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Text(TeleportStrings.routeDistanceLabel)
                    .font(.caption.weight(.medium))
            }

            if let recordedDurationSeconds = viewModel.loadedRouteRecordedDurationSeconds {
                LabeledContent {
                    Text(RouteInspectorFormatting.formattedDuration(recordedDurationSeconds))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Text(TeleportStrings.routeRecordedTimeLabel)
                        .font(.caption.weight(.medium))
                }
            }

            if let replayDurationSeconds = viewModel.loadedRouteReplayDurationSeconds {
                LabeledContent {
                    Text(RouteInspectorFormatting.formattedDuration(replayDurationSeconds))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Text(TeleportStrings.routeTotalTimeLabel)
                        .font(.caption.weight(.medium))
                }
            }
        }
    }

    @ViewBuilder
    private var routeTimingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TeleportStrings.routeTimingModeLabel)
                .font(.caption.weight(.medium))

            Picker(selection: $viewModel.routePlaybackTimingMode) {
                Text(TeleportStrings.routeTimingRecorded).tag(RoutePlaybackTimingMode.recorded)
                Text(TeleportStrings.routeTimingFixed).tag(RoutePlaybackTimingMode.fixedInterval)
                Text(TeleportStrings.routeTimingSpeed).tag(RoutePlaybackTimingMode.fixedSpeed)
            } label: {
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

struct SavedRoutesListView: View {
    @Bindable var viewModel: AppViewModel
    @Binding var showsAllSavedRoutes: Bool
    let previewLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TeleportStrings.savedRoutesTitle)
                .font(.subheadline.weight(.semibold))

            ForEach(visibleSavedRoutes) { route in
                SavedRouteCardView(viewModel: viewModel, route: route)
            }

            if savedRoutesOverflowCount > 0 || showsAllSavedRoutes {
                Button {
                    showsAllSavedRoutes.toggle()
                } label: {
                    Label(
                        showsAllSavedRoutes
                            ? TeleportStrings.savedRoutesShowLess
                            : TeleportStrings.savedRoutesShowAll,
                        systemImage: showsAllSavedRoutes ? "chevron.up" : "chevron.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var visibleSavedRoutes: [SimulatedRoute] {
        if showsAllSavedRoutes {
            return viewModel.savedRoutes
        }

        return Array(viewModel.savedRoutes.prefix(previewLimit))
    }

    private var savedRoutesOverflowCount: Int {
        max(0, viewModel.savedRoutes.count - previewLimit)
    }
}

fileprivate struct SavedRouteCardView: View {
    @Bindable var viewModel: AppViewModel
    let route: SimulatedRoute

    var body: some View {
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
                Text(RouteInspectorFormatting.formattedDistance(route.totalDistanceMeters))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(RouteInspectorFormatting.formattedSavedRouteAge(route.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)

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
