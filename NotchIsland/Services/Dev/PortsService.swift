import AppKit
import Combine

nonisolated struct ListeningPort: Identifiable, Equatable, Sendable {
    let port: Int
    let pid: Int32
    let command: String
    /// Every address the process listens on for this port, e.g. "*" or "127.0.0.1".
    let addresses: [String]
    /// Working directory of the process, when readable.
    var directory: String?

    var id: String { "\(pid):\(port)" }

    var projectName: String? {
        guard let directory, directory != "/", directory != NSHomeDirectory() else { return nil }
        return (directory as NSString).lastPathComponent
    }
}

/// TCP ports your processes are listening on, from `lsof`. Only processes you
/// own are listed, which are also the only ones you can stop.
final class PortsService: ObservableObject {
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    private var pollTask: Task<Void, Never>?
    private static let lsof = "/usr/sbin/lsof"

    /// Polls every few seconds while the Ports view is on screen.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        if ports.isEmpty { isLoading = true }
        defer { isLoading = false }
        guard let output = await ShellCommand.run(Self.lsof, ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]) else { return }
        var found = Self.parse(lsofOutput: output)
        let pids = Set(found.map(\.pid)).map(String.init).sorted()
        if !pids.isEmpty,
           let cwdOutput = await ShellCommand.run(Self.lsof, ["-a", "-d", "cwd", "-p", pids.joined(separator: ","), "-Fpn"]) {
            let directories = Self.parseDirectories(lsofOutput: cwdOutput)
            for index in found.indices { found[index].directory = directories[found[index].pid] }
        }
        if found != ports { ports = found }
    }

    func open(_ port: ListeningPort) {
        guard let url = URL(string: "http://localhost:\(port.port)") else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(_ port: ListeningPort) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
    }

    func revealDirectory(_ port: ListeningPort) {
        guard let directory = port.directory else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: directory, isDirectory: true))
    }

    /// Asks the process to quit (SIGTERM); forces it (SIGKILL) if it's still
    /// there two seconds later.
    func kill(_ port: ListeningPort) {
        let pid = port.pid
        guard Darwin.kill(pid, SIGTERM) == 0 else {
            message = String(localized: "Can't stop \(port.command) (PID \(String(pid))): \(String(cString: strerror(errno)))")
            return
        }
        message = nil
        ports.removeAll { $0.pid == pid }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if Darwin.kill(pid, 0) == 0 { _ = Darwin.kill(pid, SIGKILL) }
            await self?.refresh()
        }
    }

    func dismissMessage() { message = nil }

    // MARK: Parsing

    /// Parses `lsof -F pcn` output: `p<pid>`, `c<command>`, then one
    /// `n<address>:<port>` per socket.
    nonisolated static func parse(lsofOutput: String) -> [ListeningPort] {
        var pid: Int32 = 0
        var command = ""
        var addressesByKey: [String: (port: Int, pid: Int32, command: String, addresses: [String])] = [:]
        var order: [String] = []

        for line in lsofOutput.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value) ?? 0
                command = ""
            case "c":
                command = value
            case "n":
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                var address = String(value[..<colon])
                if address.hasPrefix("["), address.hasSuffix("]") { address = String(address.dropFirst().dropLast()) }
                let key = "\(pid):\(port)"
                if addressesByKey[key] == nil {
                    addressesByKey[key] = (port, pid, command, [])
                    order.append(key)
                }
                if addressesByKey[key]?.addresses.contains(address) == false {
                    addressesByKey[key]?.addresses.append(address)
                }
            default:
                continue
            }
        }
        return order.compactMap { addressesByKey[$0] }
            .map { ListeningPort(port: $0.port, pid: $0.pid, command: $0.command, addresses: $0.addresses) }
            .sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Parses `lsof -d cwd -F pn` output into PID → working directory.
    nonisolated static func parseDirectories(lsofOutput: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var pid: Int32?
        for line in lsofOutput.split(separator: "\n") {
            if line.hasPrefix("p") {
                pid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let current = pid {
                result[current] = String(line.dropFirst())
            }
        }
        return result
    }
}
