import Foundation

enum AppViewModelPreferences {
    static let suppressUSBPrivilegeNotice = "suppressUSBPrivilegeNotice"
}

struct USBSetupGuide: Equatable {
    let resolvedPythonPath: String?

    var pythonInstallCommand: String {
        if let resolvedPythonPath {
            return Self.shellQuoted(resolvedPythonPath) + " -m pip install pymobiledevice3"
        }

        return "python3 -m pip install pymobiledevice3"
    }

    var pythonStatusText: String {
        if let resolvedPythonPath {
            return resolvedPythonPath
        }

        return String(localized: TeleportStrings.pythonUnavailableInShell)
    }

    private static func shellQuoted(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "'" }) else {
            return value
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct PythonDependencyInstallGuide: Identifiable, Equatable {
    let resolvedPythonPath: String
    let installCommand: String

    var id: String {
        resolvedPythonPath + "\n" + installCommand
    }

    static func parse(from message: String) -> PythonDependencyInstallGuide? {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.contains(where: { $0.localizedCaseInsensitiveContains("pymobiledevice3 is missing") }) else {
            return nil
        }

        guard
            let resolvedPythonPath = lines.first(where: { $0.hasPrefix("Resolved Python: ") })?
                .replacingOccurrences(of: "Resolved Python: ", with: ""),
            let installCommand = lines.first(where: { $0.hasPrefix("Run: ") })?
                .replacingOccurrences(of: "Run: ", with: "")
        else {
            return nil
        }

        return PythonDependencyInstallGuide(
            resolvedPythonPath: resolvedPythonPath,
            installCommand: installCommand
        )
    }
}
