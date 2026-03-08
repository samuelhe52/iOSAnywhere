import Foundation

enum TeleportStrings {
    static let readyToDiscoverDevices: LocalizedStringResource = "Ready to discover simulators and USB devices."
    static let scanningDevices: LocalizedStringResource = "Scanning for simulator and USB devices..."
    static let noDevicesFound: LocalizedStringResource = "No devices found."
    static let enterValidCoordinates: LocalizedStringResource = "Enter valid coordinates."
    static let reviewAdministratorApproval: LocalizedStringResource =
        "Review the administrator approval note to continue with USB location simulation."
    static let waitingForAdministratorApproval: LocalizedStringResource =
        "Waiting for macOS administrator approval. Your password is entered in a separate system dialog and is never stored by Teleport."
    static let approvalCanceledBeforePrompt: LocalizedStringResource =
        "Administrator approval was canceled before the macOS password prompt."
    static let disconnectedAndClearedLocations: LocalizedStringResource =
        "Disconnected and cleared simulated locations."
    static let missingPythonDependency: LocalizedStringResource = "Missing Python dependency"
    static let installPythonDependency: LocalizedStringResource =
        "Install pymobiledevice3 for the selected Python interpreter to continue USB location simulation."
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
    static let stateAuthorizing: LocalizedStringResource = "Authorizing"
    static let stateStopping: LocalizedStringResource = "Stopping"
    static let searchUnavailable: LocalizedStringResource = "Apple location search is temporarily unavailable."
    static let searchNoResult: LocalizedStringResource = "No map result was returned for that place."
    static let searchUnableToLoad: LocalizedStringResource = "Unable to load that location from Apple Maps right now."
    static let pickedLocation: LocalizedStringResource = "Picked Location"
    static let selectedPlace: LocalizedStringResource = "Selected Place"
    static let manualCoordinates: LocalizedStringResource = "Manual Coordinates"
    static let currentLocation: LocalizedStringResource = "Current Location"
    static let simulatedLocation: LocalizedStringResource = "Simulated Location"
    static let chooseDeviceFromSidebar: LocalizedStringResource = "Choose a USB device or simulator from the sidebar."
    static let selectDeviceToBegin: LocalizedStringResource = "Select a device to begin"
    static let noDeviceSelected: LocalizedStringResource = "No device selected"
    static let simulatorKind: LocalizedStringResource = "Simulator"
    static let usbDeviceKind: LocalizedStringResource = "USB Device"
    static let usbDeviceUnavailableDetails: LocalizedStringResource = "USB · unavailable"
    static let removeRecentSearchHelp: LocalizedStringResource = "Remove from recent searches"
    static let copyCoordinatesHelp: LocalizedStringResource = "Copy coordinates"
    static let selectedDeviceUnavailableOverUSB: LocalizedStringResource = "The selected device is not currently available over USB."
    static let failedToClearPhysicalDeviceLocation: LocalizedStringResource = "Failed to clear the physical-device simulated location."
    static let physicalHelperInvalidStartupState: LocalizedStringResource =
        "The physical-device helper reported an invalid startup state."
    static let physicalHelperExitedBeforeReady: LocalizedStringResource =
        "Physical-device location simulation exited before reporting ready."
    static let timedOutWaitingForAdministratorApproval: LocalizedStringResource =
        "Timed out waiting for administrator approval or helper startup while enabling physical-device location simulation."
    static let administratorApprovalCanceled: LocalizedStringResource =
        "Administrator approval was canceled. Physical-device location simulation did not start."
    static let administratorPasswordIncorrect: LocalizedStringResource =
        "The administrator password was incorrect. Check the password and try again."
    static let selectUSBDeviceToResolvePython: LocalizedStringResource =
        "Select a USB device to resolve the helper Python interpreter."
    static let pythonDependencyMissingIntro: LocalizedStringResource =
        "pymobiledevice3 is missing for the Python executable used by USB device simulation."
    static let retryUSBLocationAction: LocalizedStringResource = "Then retry the USB location action."
    static let usbSudoPrompt: LocalizedStringResource =
        "Teleport requires administrator privileges for physical-device location simulation."
    static let usbAuthorizePrompt: LocalizedStringResource =
        "Authorize USB location simulation for your physical device. Your password is handled by macOS and is not stored by Teleport."
    static let cancel: LocalizedStringResource = "Cancel"
    static let authorize: LocalizedStringResource = "Authorize"
    static let administratorPassword: LocalizedStringResource = "Administrator Password"

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

    static func clearedSimulatedLocation(on deviceName: String) -> LocalizedStringResource {
        "Cleared simulated location on \(deviceName)."
    }

    static func usbHelperPython(_ path: String) -> LocalizedStringResource {
        "USB helper Python: \(path)"
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