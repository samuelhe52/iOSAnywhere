<!-- markdownlint-disable MD024 -->

# Changelog

All notable changes to Teleport are documented in this file.

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
