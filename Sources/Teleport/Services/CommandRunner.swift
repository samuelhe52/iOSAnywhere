import Foundation

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
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ServiceError.unavailable(
                "Failed to launch \(executableURL.lastPathComponent): \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let output = Output(
            stdout: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            terminationStatus: process.terminationStatus
        )

        guard output.terminationStatus == 0 else {
            let message =
                [output.stderrString, output.stdoutString]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "Command failed with exit code \(output.terminationStatus)."
            throw ServiceError.unavailable(message)
        }

        return output
    }
}
