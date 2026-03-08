import Foundation
import OSLog

struct CommandRunner {
    struct Output: Sendable {
        let stdout: Data
        let stderr: Data
        let terminationStatus: Int32

        var stdoutString: String {
            String(decoding: stdout, as: UTF8.self)
        }

        var stderrString: String {
            String(decoding: stderr, as: UTF8.self)
        }
    }

    static func run(_ executableURL: URL, arguments: [String]) throws -> Output {
        let commandDescription = summarizedCommand(executableURL: executableURL, arguments: arguments)
        let startTime = DispatchTime.now().uptimeNanoseconds
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        TeleportLog.commands.debug("Running command: \(commandDescription, privacy: .public)")

        do {
            try process.run()
        } catch {
            TeleportLog.commands.error(
                "Failed to launch command \(commandDescription, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw ServiceError.unavailable(
                String(
                    localized: TeleportStrings.failedToLaunchExecutable(
                        executableURL.lastPathComponent,
                        details: error.localizedDescription
                    )
                ))
        }

        process.waitUntilExit()

        let output = Output(
            stdout: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            terminationStatus: process.terminationStatus
        )

        let durationMilliseconds = elapsedMilliseconds(since: startTime)

        guard output.terminationStatus == 0 else {
            let message =
                [output.stderrString, output.stdoutString]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
                ?? String(localized: TeleportStrings.commandFailed(exitCode: output.terminationStatus))
            TeleportLog.commands.error(
                "Command failed: \(commandDescription, privacy: .public) in \(durationMilliseconds) ms with exit code \(output.terminationStatus): \(message, privacy: .public)"
            )
            throw ServiceError.unavailable(message)
        }

        TeleportLog.commands.info(
            "Command succeeded: \(commandDescription, privacy: .public) in \(durationMilliseconds) ms"
        )

        return output
    }

    private static func summarizedCommand(executableURL: URL, arguments: [String]) -> String {
        let summarizedArguments = arguments.enumerated().map { index, argument in
            if index > 0, arguments[index - 1] == "-c" {
                return "<inline-script>"
            }

            return argument.count > 160 ? String(argument.prefix(157)) + "..." : argument
        }

        return ([executableURL.path] + summarizedArguments).joined(separator: " ")
    }

    private static func elapsedMilliseconds(since startTime: UInt64) -> UInt64 {
        (DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000
    }
}
