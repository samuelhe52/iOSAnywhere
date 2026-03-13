# Project Guidelines

## Project Nature

- Teleport is a native macOS SwiftUI app for simulating iOS device location on simulators and physical devices over USB or Wi-Fi.
- Keep this file preference-oriented and concise; use the README for broader project details.

## Build And Validation

- Before commit, run `make format`.
- Validate changes with the VS Code `Build Teleport` task.
- When using Copilot tooling to inspect large task output, check the temporary `content.txt` artifact that `get_task_output` may create in VS Code workspace storage.
