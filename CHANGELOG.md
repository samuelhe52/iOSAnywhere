<!-- markdownlint-disable MD024 -->

# Changelog

All notable changes to Teleport are documented in this file.

## v0.3.0 - 2026-03-14

### Added

- Added a full route-building workflow with multi-stop editing, playback controls, and an in-app saved-route library.
- Added Apple Maps navigation route building with transport selection and alternate route choices.
- Added GPX route import support and route editing tools for revisiting, renaming, duplicating, and refining saved routes.
- Added a return-to-current-location control to make it easier to jump the map back to the active simulated position.

### Changed

- Improved route playback pacing and smoothing so movement simulations follow routes more naturally.
- Reworked the inspector and app view model structure to better separate route building, playback, movement, and operation flows.
- Updated English and Simplified Chinese localization, README content, and screenshots to cover the expanded route tooling.

### Fixed

- Fixed physical-device USB simulation reset handling so stopping or resetting a session is more reliable.

## v0.2.2 - 2026-03-11

### Fixed

- Fixed the physical-device Python helper so it exits cleanly when the app disappears unexpectedly instead of looping forever on a closed stdin pipe.
- Fixed physical-device helper shutdown to escalate from cooperative stop to forceful termination when the backend process becomes stuck, preventing app quit from hanging indefinitely.

## v0.2.1 - 2026-03-11

### Added

- Added joystick movement controls for nudging the simulated location directly from the app on both simulators and real devices.
- Added variable-speed movement handling so joystick-driven movement responds to control intensity and configured speed presets.

### Changed

- Updated English and Simplified Chinese localization coverage for the new movement controls and related UI text.
- Refined the README device support and download guidance to match current simulator and physical-device capabilities.

## v0.2.0 - 2026-03-09

### Added

- Added Wi-Fi physical-device discovery and location simulation support.
- Added transport-aware physical device labeling for USB and Wi-Fi connections.
- Added Simplified Chinese translations for the new physical-device and Wi-Fi UI strings.

### Changed

- Switched physical-device discovery to CoreDevice via `devicectl` instead of relying on `xcdevice`.
- Updated the physical-device simulation startup state and messaging to reflect helper and connection startup rather than always implying administrator authorization.
- Refined the map pin model so picked and simulated locations are represented consistently.
- Generalized user-facing copy from USB-only wording to physical-device wording where appropriate.

### Fixed

- Fixed physical-device availability handling for Wi-Fi-connected devices.
- Fixed the Wi-Fi simulation path to use the correct network lockdown and tunnel flow.
- Fixed duplicate or stale map pin behavior when switching between picked and simulated locations.
- Fixed map pin deduplication to use approximate coordinate comparison instead of brittle exact equality.

## v0.1.1 - 2026-03-09

### Added

- Added a centralized localization setup for user-facing strings and shipped Simplified Chinese translations across the app.
- Added a Chinese README to make installation and usage clearer for Chinese-speaking users.

### Changed

- Improved the USB location workflow for physical devices, including clearer device availability handling and better state updates when a device is unplugged or becomes unavailable.
- Updated the physical-device authorization flow so an active `sudo` session can be reused instead of prompting for the administrator password again on every simulation attempt.
- Allowed switching directly from one simulated location to another without requiring a full stop first.

### Fixed

- Fixed stale USB device entries incorrectly appearing as still available or connected after disconnection.
- Fixed repeated or misleading administrator-password failures during physical-device simulation.
- Fixed the macOS administrator password prompt so Simplified Chinese text renders correctly instead of appearing as mojibake.
