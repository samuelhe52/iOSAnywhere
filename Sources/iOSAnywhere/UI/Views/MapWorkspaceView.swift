import MapKit
import SwiftUI

struct MapWorkspaceView: View {
    @Bindable var viewModel: AppViewModel

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Map(position: $cameraPosition) {
                if case .simulating(let coordinate) = viewModel.simulationState {
                    Marker(
                        "Simulated Location",
                        coordinate: CLLocationCoordinate2D(
                            latitude: coordinate.latitude, longitude: coordinate.longitude))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(minHeight: 320)

            HStack(spacing: 12) {
                TextField("Latitude", text: $viewModel.latitudeText)
                TextField("Longitude", text: $viewModel.longitudeText)
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding(20)
    }
}
