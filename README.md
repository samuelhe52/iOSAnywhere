# Teleport

[English](README.md) | [简体中文](README.zh-CN.md)

Teleport is a native macOS app for simulating iOS device location on iOS Simulators and physical devices connected over USB or Wi-Fi.

Built with SwiftUI and MapKit, it gives you a desktop workflow for picking a point on a map, searching for a place, and pushing that location to your test target.

![Teleport app screenshot](Resources/screenshot-main.jpg)

## Disclaimer

Teleport is intended solely for developer testing, debugging, and other legitimate development workflows. Use outside of those purposes is not recommended.

By using this project for any non-development or otherwise unintended purpose, you do so at your own risk. The app and its developer do not accept responsibility for any consequences, liabilities, or damages arising from such use.

## Features

- Native macOS three-pane UI for device selection, map interaction, and session controls
- iOS Simulator support for set and clear location flows
- USB and Wi-Fi physical-device support for location simulation
- Stable simulator and physical-device simulation flows
- Map-based point selection with manual latitude/longitude entry
- Apple Maps search with recent-search history
- Clear session status and stop/reset controls

## Requirements

- macOS
- Xcode installed and opened once so `xcrun`, `simctl`, and `devicectl` are available
- For physical devices: a USB- or Wi-Fi-connected physical iOS device with Developer Mode enabled
- For physical devices: `python3` and `pymobiledevice3`
- For Wi-Fi physical devices: connect once over USB first to create a pairing record, then keep the device unlocked on the same local network

If macOS reports that developer tools are missing, install Apple's command line developer tools first:

```sh
xcode-select --install
```

If full Xcode is installed but `xcrun` is still pointing at the wrong developer directory, switch it explicitly:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Then launch Xcode once to finish first-run setup for simulator and device tooling.

Install the Python dependency into the same `python3` interpreter that Teleport resolves from your shell:

```sh
python3 -m pip install pymobiledevice3
```

## Quick Start

### Download a built app

If you do not want to build Teleport yourself, download the latest `.dmg` from the [Releases](https://github.com/samuelhe52/Teleport/releases) page.

Open the disk image, drag `Teleport.app` into `Applications`, and then launch it from there.

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
2. Select a simulator or physical iOS device.
3. Connect to the device.
4. Pick a location from the map, search, or manual coordinates.
5. Click `Simulate` to apply the location.
6. Click `Stop` to clear it.

For physical devices, Teleport may ask for administrator approval, guide you if a required Python dependency is missing, and require an initial USB pairing step before Wi-Fi discovery works.

## Status

Teleport already covers the core teleport workflow for simulators and physical devices over USB or Wi-Fi. Route playback, GPX import, and movement tooling are not part of the current app yet.

## Development

- `make format` runs `swift format -r -p -i .`
- `make lint` runs `swift format lint -r -p .`

## Notes

Teleport was originally developed under the name iOSAnywhere and later renamed.

If you are using Teleport from mainland China, Apple Maps search results may be limited to locations inside China or may fail for places outside China. In practice, searching for overseas places may require a VPN. You can still navigate the map directly to other regions and pick a location manually without search.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release notes, including [v0.2.0](CHANGELOG.md#v020---2026-03-09).
