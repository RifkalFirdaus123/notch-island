import Foundation

/// Runs a command-line tool off the main thread and returns its output.
nonisolated enum ShellCommand {
    static func run(_ path: String, _ arguments: [String]) async -> String? {
        await Task.detached(priority: .utility) {
            runSync(path, arguments)
        }.value
    }

    static func runSync(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting so a full pipe can't block the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
