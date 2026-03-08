# Changelog

All notable changes to Teleport are documented in this file.

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
