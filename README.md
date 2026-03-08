# Teleport

Teleport is a native macOS app for simulating iPhone location on iOS Simulators and USB-connected physical devices.

Built with SwiftUI and MapKit, it gives you a desktop workflow for picking a point on a map, searching for a place, and pushing that location to your test target.

![Teleport app screenshot](Resources/screenshot-main.jpg)

## Features

- Native macOS three-pane UI for device selection, map interaction, and session controls
- iOS Simulator support for set and clear location flows
- USB iPhone support for physical-device location simulation
- Map-based point selection with manual latitude/longitude entry
- Apple Maps search with recent-search history
- Clear session status and stop/reset controls

## Requirements

- macOS
- Xcode with simulator tooling installed
- For physical devices: a USB-connected iPhone with Developer Mode enabled
- For physical devices: `python3` and `pymobiledevice3`

Install the Python dependency with:

```sh
python3 -m pip install pymobiledevice3
```

## Quick Start

### Run in Xcode

1. Open `Teleport.xcodeproj`.
2. Select the `Teleport` scheme.
3. Build and run the app.

### Build from the command line

```sh
xcodebuild -project Teleport.xcodeproj -scheme Teleport -destination 'platform=macOS' build
```

## How It Works

1. Launch Teleport.
2. Select a simulator or USB-connected iPhone.
3. Connect to the device.
4. Pick a location from the map, search, or manual coordinates.
5. Click `Simulate` to apply the location.
6. Click `Stop` to clear it.

For physical devices, Teleport may ask for administrator approval and will guide you if a required Python dependency is missing.

## Status

Teleport already covers the core teleport workflow for simulators and USB devices. Route playback, GPX import, and movement tooling are not part of the current app yet.

## Development

- `make format` runs `swift format -r -p -i .`
- `make lint` runs `swift format lint -r -p .`

## Notes

Teleport was originally developed under the name iOSAnywhere and later renamed.

If you are using Teleport from mainland China, Apple Maps search results may be limited to locations inside China or may fail for places outside China. In practice, searching for overseas places may require a VPN. You can still navigate the map directly to other regions and pick a location manually without search.
