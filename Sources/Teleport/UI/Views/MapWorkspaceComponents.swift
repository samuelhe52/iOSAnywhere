import CoreLocation
import MapKit
import SwiftUI

struct MapWorkspaceMapCanvasView: View {
    @Binding var cameraPosition: MapCameraPosition

    let simulationState: SimulationRunState
    let highlightedCoordinate: LocationCoordinate?
    let highlightedTitle: String?
    let onTapCoordinate: (CLLocationCoordinate2D) -> Void
    let onCameraChange: (MKCoordinateRegion) -> Void

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if case .simulating(let coordinate) = simulationState {
                    Marker(
                        "Simulated Location",
                        coordinate: CLLocationCoordinate2D(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        ))
                }

                if let highlightedCoordinate {
                    Group {
                        if let highlightedTitle {
                            Marker(
                                highlightedTitle,
                                coordinate: CLLocationCoordinate2D(
                                    latitude: highlightedCoordinate.latitude,
                                    longitude: highlightedCoordinate.longitude
                                )
                            )
                        } else {
                            Marker(
                                "Selected Place",
                                coordinate: CLLocationCoordinate2D(
                                    latitude: highlightedCoordinate.latitude,
                                    longitude: highlightedCoordinate.longitude
                                )
                            )
                        }
                    }
                    .tint(.blue)
                }
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else {
                            return
                        }

                        onTapCoordinate(coordinate)
                    }
            )
            .onMapCameraChange(frequency: .continuous) { context in
                onCameraChange(context.region)
            }
            .mapStyle(.standard(elevation: .realistic))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(minHeight: 420)
        }
    }
}

struct MapWorkspaceSearchOverlayView: View {
    @ObservedObject var searchModel: LocationSearchModel

    let isSearchFieldFocused: FocusState<Bool>.Binding
    let shouldShowHistoryOverlay: Bool
    let onSelectCompletion: (LocationSearchCompletion) -> Void
    let onSelectHistoryEntry: (LocationSearchHistoryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search for a place or address", text: $searchModel.query)
                    .textFieldStyle(.plain)
                    .focused(isSearchFieldFocused)

                if !searchModel.query.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            searchModel.clear()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(MapWorkspaceOverlayCardBackground(shadowOpacity: 0.16, shadowRadius: 12, shadowYOffset: 8))

            if let errorMessage = searchModel.errorMessage {
                Label {
                    Text(errorMessage)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        MapWorkspaceOverlayCardBackground(
                            cornerRadius: 14, shadowOpacity: 0.12, shadowRadius: 10, shadowYOffset: 6)
                    )
                    .transition(.opacity)
            } else if !searchModel.completions.isEmpty {
                MapWorkspaceOverlayCard {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(searchModel.completions) { completion in
                                Button {
                                    onSelectCompletion(completion)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(completion.title)
                                            .foregroundStyle(.primary)
                                        if !completion.subtitle.isEmpty {
                                            Text(completion.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if completion.id != searchModel.completions.last?.id {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
                .transition(.opacity)
            } else if shouldShowHistoryOverlay {
                MapWorkspaceOverlayCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Label("Recent Searches", systemImage: "clock.arrow.circlepath")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 12)

                            Button("Clear") {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    searchModel.clearHistory()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        Divider()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(searchModel.history) { entry in
                                    HStack(spacing: 10) {
                                        Button {
                                            onSelectHistoryEntry(entry)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.title)
                                                    .foregroundStyle(.primary)

                                                if !entry.subtitle.isEmpty {
                                                    Text(entry.subtitle)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }

                                                Text(entry.coordinate.formatted)
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 10)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                searchModel.removeHistoryEntry(entry)
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.tertiary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove from recent searches")
                                    }
                                    .padding(.horizontal, 14)

                                    if entry.id != searchModel.history.last?.id {
                                        Divider()
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

fileprivate struct MapWorkspaceOverlayCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(MapWorkspaceOverlayCardBackground(shadowOpacity: 0.18, shadowRadius: 16, shadowYOffset: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06))
            )
    }
}

fileprivate struct MapWorkspaceOverlayCardBackground: View {
    var cornerRadius: CGFloat = 16
    var shadowOpacity: Double
    var shadowRadius: CGFloat
    var shadowYOffset: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowYOffset)
    }
}
