import Foundation

enum TeleportStrings {
    static let readyToDiscoverDevices: LocalizedStringResource = "Ready to discover simulators and physical devices."
    static let scanningDevices: LocalizedStringResource = "Scanning for simulator and physical devices..."
    static let noDevicesFound: LocalizedStringResource = "No devices found."
    static let enterValidCoordinates: LocalizedStringResource = "Enter valid coordinates."
    static let reviewAdministratorApproval: LocalizedStringResource =
        "Review the administrator approval note to continue with physical-device location simulation."
    static let startingPhysicalDeviceSimulation: LocalizedStringResource =
        "Starting physical-device location simulation. This can take a moment while Teleport connects to the device and prepares the helper."
    static let approvalCanceledBeforePrompt: LocalizedStringResource =
        "Administrator approval was canceled before the macOS password prompt."
    static let disconnectedAndClearedLocations: LocalizedStringResource =
        "Disconnected and cleared simulated locations."
    static let missingPythonDependency: LocalizedStringResource = "Missing Python dependency"
    static let installPythonDependency: LocalizedStringResource =
        "Install pymobiledevice3 for the selected Python interpreter to continue physical-device location simulation."
    static let selectDeviceFirst: LocalizedStringResource = "Select a device first."
    static let pythonUnavailableInShell: LocalizedStringResource =
        "python3 is not currently resolving from your shell. Install Python 3 first, then refresh devices."
    static let stateIdle: LocalizedStringResource = "Idle"
    static let stateDiscovering: LocalizedStringResource = "Discovering"
    static let stateReady: LocalizedStringResource = "Ready"
    static let stateFailed: LocalizedStringResource = "Failed"
    static let stateDisconnected: LocalizedStringResource = "Disconnected"
    static let stateConnecting: LocalizedStringResource = "Connecting"
    static let stateConnected: LocalizedStringResource = "Connected"
    static let stateDisconnecting: LocalizedStringResource = "Disconnecting"
    static let stateStarting: LocalizedStringResource = "Starting"
    static let stateStopping: LocalizedStringResource = "Stopping"
    static let routeSectionTitle: LocalizedStringResource = "Route"
    static let routeImportGPX: LocalizedStringResource = "Import GPX"
    static let routeCreate: LocalizedStringResource = "Create Route"
    static let routeSaveInApp: LocalizedStringResource = "Save in App"
    static let routeUpdateSaved: LocalizedStringResource = "Update Saved"
    static let routeSaveAsNew: LocalizedStringResource = "Save As New"
    static let routeExportGPX: LocalizedStringResource = "Export GPX"
    static let routeClear: LocalizedStringResource = "Clear Route"
    static let savedRoutesTitle: LocalizedStringResource = "Saved Routes"
    static let savedRouteLoad: LocalizedStringResource = "Load"
    static let savedRouteRename: LocalizedStringResource = "Rename"
    static let savedRouteDelete: LocalizedStringResource = "Delete"
    static let savedRoutesShowAll: LocalizedStringResource = "Show All"
    static let savedRoutesShowLess: LocalizedStringResource = "Show Less"
    static let routePlaybackLabel: LocalizedStringResource = "Playback"
    static let routePointsLabel: LocalizedStringResource = "Points"
    static let routeDistanceLabel: LocalizedStringResource = "Distance"
    static let routeSourceLabel: LocalizedStringResource = "Source"
    static let routeEmptyHint: LocalizedStringResource =
        "Import a GPX route or create one by adding waypoints on the map."
    static let routeBuilderTitle: LocalizedStringResource = "Waypoint Route"
    static let routeBuilderHint: LocalizedStringResource =
        "Tap the map to add waypoints. Then replay the route with a fixed interval or travel speed."
    static let routeBuilderUndo: LocalizedStringResource = "Undo"
    static let routeBuilderSave: LocalizedStringResource = "Save"
    static let routeBuilderCancel: LocalizedStringResource = "Cancel"
    static let routeBuilderDefaultName: LocalizedStringResource = "Waypoint Route"
    static let routeSourceGPX: LocalizedStringResource = "GPX"
    static let routeSourceDrawn: LocalizedStringResource = "Drawn"
    static let routeSourceNavigation: LocalizedStringResource = "Navigation"
    static let routePlaybackReady: LocalizedStringResource = "Ready"
    static let routePlaybackPlaying: LocalizedStringResource = "Playing"
    static let routePlaybackPaused: LocalizedStringResource = "Paused"
    static let routePlaybackCompleted: LocalizedStringResource = "Completed"
    static let routePlaybackPlay: LocalizedStringResource = "Play"
    static let routePlaybackPause: LocalizedStringResource = "Pause"
    static let routePlaybackStop: LocalizedStringResource = "Stop"
    static let routePlaybackResume: LocalizedStringResource = "Resume"
    static let routePlaybackReplay: LocalizedStringResource = "Replay"
    static let routePlaybackProgressLabel: LocalizedStringResource = "Progress"
    static let routePlaybackCurrentPointLabel: LocalizedStringResource = "Current Point"
    static let routeRecordedTimeLabel: LocalizedStringResource = "Recorded Time"
    static let routeTotalTimeLabel: LocalizedStringResource = "Replay Time"
    static let routeTimingModeLabel: LocalizedStringResource = "Timing"
    static let routeTimingRecorded: LocalizedStringResource = "Recorded"
    static let routeTimingFixed: LocalizedStringResource = "Fixed"
    static let routeTimingSpeed: LocalizedStringResource = "Speed"
    static let routeReplaySpeedLabel: LocalizedStringResource = "Replay Speed"
    static let routeFixedIntervalLabel: LocalizedStringResource = "Fixed Interval"
    static let routeTravelSpeedLabel: LocalizedStringResource = "Travel Speed"
    static let routePacingHintRecorded: LocalizedStringResource =
        "Use GPX timing when present, but compress long pauses for practical replay."
    static let routePacingHintFixed: LocalizedStringResource =
        "Advance every waypoint on a fixed clock regardless of GPX timestamps."
    static let routePacingHintSpeed: LocalizedStringResource =
        "Convert segment distance into delay using a target speed. Best for planned routes with no timing data."
    static let routePreviewStart: LocalizedStringResource = "Route Start"
    static let routePreviewEnd: LocalizedStringResource = "Route End"
    static let movementSectionTitle: LocalizedStringResource = "Movement"
    static let movementWheelHint: LocalizedStringResource =
        "Drag the control wheel to move the simulated point. Push farther to move faster, up to the configured speed. Release to stop."
    static let movementAvailableForSimulatorOnly: LocalizedStringResource =
        "The movement wheel is available for connected simulators and for physical devices after simulation has started."
    static let movementRequiresConnection: LocalizedStringResource =
        "Connect to a device before using the movement wheel."
    static let movementRequiresValidCoordinates: LocalizedStringResource =
        "Enter valid coordinates before starting movement."
    static let movementRequiresActivePhysicalSimulation: LocalizedStringResource =
        "Start simulation on the physical device before using the movement wheel."
    static let movementSpeedLabel: LocalizedStringResource = "Speed"
    static let movementUpdateIntervalLabel: LocalizedStringResource = "Update Interval"
    static let movementWalkingSpeed: LocalizedStringResource = "Walking"
    static let movementHighwaySpeed: LocalizedStringResource = "Highway"
    static let movementActive: LocalizedStringResource = "Moving"
    static let movementIdle: LocalizedStringResource = "Ready"
    static let searchUnavailable: LocalizedStringResource = "Apple location search is temporarily unavailable."
    static let searchNoResult: LocalizedStringResource = "No map result was returned for that place."
    static let searchUnableToLoad: LocalizedStringResource = "Unable to load that location from Apple Maps right now."
    static let pickedLocation: LocalizedStringResource = "Candidate Location"
    static let selectedPlace: LocalizedStringResource = "Selected Place"
    static let manualCoordinates: LocalizedStringResource = "Manual Coordinates"
    static let currentLocation: LocalizedStringResource = "Current Location"
    static let simulatedLocation: LocalizedStringResource = "Simulated Location"
    static let chooseDeviceFromSidebar: LocalizedStringResource =
        "Choose a physical device or simulator from the sidebar."
    static let selectDeviceToBegin: LocalizedStringResource = "Select a device to begin"
    static let noDeviceSelected: LocalizedStringResource = "No device selected"
    static let simulatorKind: LocalizedStringResource = "Simulator"
    static let usbDeviceKind: LocalizedStringResource = "USB Device"
    static let wifiDeviceKind: LocalizedStringResource = "Wi-Fi Device"
    static let usbDeviceUnavailableDetails: LocalizedStringResource = "USB · unavailable"
    static let wifiDeviceUnavailableDetails: LocalizedStringResource = "Wi-Fi · unavailable"
    static let removeRecentSearchHelp: LocalizedStringResource = "Remove from recent searches"
    static let copyCoordinatesHelp: LocalizedStringResource = "Copy coordinates"
    static let selectedDeviceUnavailableOverUSB: LocalizedStringResource =
        "The selected physical device is not currently reachable."
    static let selectedPhysicalDeviceUnavailable: LocalizedStringResource =
        "The selected physical device is not currently reachable."
    static let failedToClearPhysicalDeviceLocation: LocalizedStringResource =
        "Failed to clear the physical-device simulated location."
    static let physicalHelperInvalidStartupState: LocalizedStringResource =
        "The physical-device helper reported an invalid startup state."
    static let physicalHelperExitedBeforeReady: LocalizedStringResource =
        "Physical-device location simulation exited before reporting ready."
    static let timedOutWaitingForPhysicalDeviceStartup: LocalizedStringResource =
        "Timed out while waiting for the physical-device helper to start location simulation."
    static let administratorApprovalCanceled: LocalizedStringResource =
        "Administrator approval was canceled. Physical-device location simulation did not start."
    static let administratorPasswordIncorrect: LocalizedStringResource =
        "The administrator password was incorrect. Check the password and try again."
    static let selectUSBDeviceToResolvePython: LocalizedStringResource =
        "Select a physical device to resolve the helper Python interpreter."
    static let pythonDependencyMissingIntro: LocalizedStringResource =
        "pymobiledevice3 is missing for the Python executable used by physical-device simulation."
    static let retryUSBLocationAction: LocalizedStringResource = "Then retry the physical-device location action."
    static let usbSudoPrompt: LocalizedStringResource =
        "Teleport requires administrator privileges for physical-device location simulation."
    static let usbAuthorizePrompt: LocalizedStringResource =
        "Authorize physical-device location simulation. Your password is handled by macOS and is not stored by Teleport."
    static let cancel: LocalizedStringResource = "Cancel"
    static let authorize: LocalizedStringResource = "Authorize"
    static let administratorPassword: LocalizedStringResource = "Administrator Password"
    static let noRouteLoaded: LocalizedStringResource = "Load a route before starting playback."
    static let routeRequiresAtLeastTwoPoints: LocalizedStringResource =
        "The loaded route needs at least two points for playback."
    static let routePlaybackRequiresConnection: LocalizedStringResource =
        "Connect to an available device before starting route playback."
    static let routeBuilderStarted: LocalizedStringResource = "Route builder is active. Tap the map to add waypoints."
    static let routeBuilderCanceled: LocalizedStringResource = "Canceled route builder."
    static let routeBuilderNeedsTwoPoints: LocalizedStringResource =
        "Add at least two waypoints before saving the route."
    static let routeBuilderEmpty: LocalizedStringResource = "The route builder is empty."
    static let saveRoutePromptTitle: LocalizedStringResource = "Save Route in App"
    static let saveRoutePromptMessage: LocalizedStringResource = "Choose a name for the saved route."
    static let renameRoutePromptTitle: LocalizedStringResource = "Rename Saved Route"
    static let renameRoutePromptMessage: LocalizedStringResource = "Enter a new name for this saved route."

    static func foundDevices(_ count: Int) -> LocalizedStringResource {
        "Found \(count) device(s)."
    }

    static func connectingToDevice(_ name: String) -> LocalizedStringResource {
        "Connecting to \(name)..."
    }

    static func connectedToDevice(_ name: String) -> LocalizedStringResource {
        "Connected to \(name)."
    }

    static func disconnectedFromDevice(_ name: String) -> LocalizedStringResource {
        "Disconnected from \(name)."
    }

    static func simulatingCoordinate(_ coordinate: String, on deviceName: String) -> LocalizedStringResource {
        "Simulating \(coordinate) on \(deviceName)."
    }

    static func movingCoordinate(_ coordinate: String, on deviceName: String) -> LocalizedStringResource {
        "Moving through \(coordinate) on \(deviceName)."
    }

    static func loadedRoute(_ name: String, pointCount: Int) -> LocalizedStringResource {
        "Loaded route \(name) with \(pointCount) point(s)."
    }

    static func failedToImportGPX(_ details: String) -> LocalizedStringResource {
        "Failed to import GPX: \(details)"
    }

    static func playingRoute(_ name: String, pointNumber: Int, totalPoints: Int) -> LocalizedStringResource {
        "Playing route \(name) · point \(pointNumber) of \(totalPoints)."
    }

    static func pausedRoute(_ name: String) -> LocalizedStringResource {
        "Paused route \(name)."
    }

    static func stoppedRoute(_ name: String) -> LocalizedStringResource {
        "Stopped route \(name)."
    }

    static func completedRoute(_ name: String) -> LocalizedStringResource {
        "Completed route \(name)."
    }

    static func savedRouteInApp(_ name: String) -> LocalizedStringResource {
        "Saved \(name) in the app."
    }

    static func updatedSavedRouteInApp(_ name: String) -> LocalizedStringResource {
        "Updated saved route \(name)."
    }

    static func savedRouteAsNewCopy(_ name: String) -> LocalizedStringResource {
        "Saved \(name) as a new route."
    }

    static func loadedSavedRoute(_ name: String) -> LocalizedStringResource {
        "Loaded saved route \(name)."
    }

    static func renamedSavedRoute(_ name: String) -> LocalizedStringResource {
        "Renamed saved route to \(name)."
    }

    static func deletedSavedRoute(_ name: String) -> LocalizedStringResource {
        "Deleted saved route \(name)."
    }

    static func exportedRouteAsGPX(_ name: String) -> LocalizedStringResource {
        "Exported \(name) as GPX."
    }

    static func failedToExportGPX(_ details: String) -> LocalizedStringResource {
        "Failed to export GPX: \(details)"
    }

    static func routeBuilderAddedPoint(_ pointCount: Int) -> LocalizedStringResource {
        "Added waypoint \(pointCount)."
    }

    static func routeBuilderUpdated(_ pointCount: Int) -> LocalizedStringResource {
        "Route builder now has \(pointCount) waypoint(s)."
    }

    static let clearedLoadedRoute: LocalizedStringResource = "Cleared the loaded route preview."

    static func clearedSimulatedLocation(on deviceName: String) -> LocalizedStringResource {
        "Cleared simulated location on \(deviceName)."
    }

    static func usbHelperPython(_ path: String) -> LocalizedStringResource {
        "Device helper Python: \(path)"
    }

    static func deviceSubtitle(kind: String, osVersion: String) -> LocalizedStringResource {
        "\(kind) · iOS \(osVersion)"
    }

    static func noServiceAvailable(for kind: String) -> LocalizedStringResource {
        "No service available for \(kind)."
    }

    static func failedToLaunchExecutable(_ executableName: String, details: String) -> LocalizedStringResource {
        "Failed to launch \(executableName): \(details)"
    }

    static func commandFailed(exitCode: Int32) -> LocalizedStringResource {
        "Command failed with exit code \(exitCode)."
    }

    static func failedToLaunchPhysicalDeviceHelper(_ details: String) -> LocalizedStringResource {
        "Failed to launch the physical-device helper: \(details)"
    }

    static func unableToResolvePython3(from shellName: String) -> LocalizedStringResource {
        "Unable to resolve python3 from \(shellName)."
    }

    static func pythonPathNotExecutable(_ path: String) -> LocalizedStringResource {
        "Resolved python3 to \(path), but that file is not executable."
    }

    static func resolvedPythonLine(_ path: String) -> LocalizedStringResource {
        "Resolved Python: \(path)"
    }

    static func runCommandLine(_ command: String) -> LocalizedStringResource {
        "Run: \(command)"
    }
}
