import AppKit
import Combine

nonisolated enum DevEventStatus: String, Equatable, Sendable {
    case success = "ok"
    case failure = "fail"
    case attention
    case working
    case info

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.octagon.fill"
        case .attention: "exclamationmark.bubble.fill"
        case .working: "ellipsis.circle.fill"
        case .info: "bell.fill"
        }
    }

    /// Worth popping up on the island.
    var alerts: Bool { self != .working }
}

nonisolated struct DevEvent: Identifiable, Equatable, Sendable {
    var id = UUID()
    /// "terminal", "claude", "codex", or whatever `-t` was given.
    let source: String
    let status: DevEventStatus
    let title: String
    let detail: String?
    let directory: String?
    let date: Date
    /// Claude Code session, so a later "finished" replaces "working".
    var sessionID: String?

    var projectName: String? {
        guard let directory, directory != "/", directory != NSHomeDirectory() else { return nil }
        return (directory as NSString).lastPathComponent
    }

    var sourceName: String {
        switch source {
        case "terminal", "shell": String(localized: "Terminal")
        case "claude": "Claude Code"
        case "codex": "Codex"
        default: source
        }
    }

    var isAgent: Bool { source == "claude" || source == "codex" }

    /// Builds an event from a file written by `notchisland-notify`. Returns
    /// nil for hook calls that aren't worth showing.
    static func parse(_ dict: [String: Any], now: Date = .now) -> DevEvent? {
        let source = (dict["source"] as? String) ?? "shell"
        let directory = (dict["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let date = (dict["time"] as? String).flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) ?? now

        if let payload = dict["payload"] as? String,
           let data = payload.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            switch source {
            case "claude": return claudeEvent(json, fallbackDirectory: directory, date: date)
            case "codex": return codexEvent(json, fallbackDirectory: directory, date: date)
            default: break
            }
        }

        guard let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return DevEvent(
            source: source,
            status: DevEventStatus(rawValue: (dict["status"] as? String) ?? "") ?? .info,
            title: title,
            detail: (dict["detail"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            directory: directory,
            date: date
        )
    }

    /// Claude Code hook input: https://docs.claude.com/en/docs/claude-code/hooks
    private static func claudeEvent(_ json: [String: Any], fallbackDirectory: String?, date: Date) -> DevEvent? {
        let directory = (json["cwd"] as? String) ?? fallbackDirectory
        let session = json["session_id"] as? String
        let status: DevEventStatus
        let title: String
        var detail: String?
        switch json["hook_event_name"] as? String {
        case "UserPromptSubmit":
            status = .working
            title = String(localized: "Working…")
            detail = (json["prompt"] as? String).map(Self.oneLine)
        case "Stop":
            status = .success
            title = String(localized: "Finished")
        case "Notification":
            status = .attention
            title = (json["message"] as? String).map(Self.oneLine) ?? String(localized: "Needs your input")
        case "SubagentStop", "PreCompact", "SessionStart", "SessionEnd":
            return nil
        default:
            return nil
        }
        if detail == nil, let directory { detail = (directory as NSString).lastPathComponent }
        return DevEvent(source: "claude", status: status, title: title, detail: detail, directory: directory, date: date, sessionID: session)
    }

    /// Codex `notify` payload: {"type": "agent-turn-complete", "last-assistant-message": …}
    private static func codexEvent(_ json: [String: Any], fallbackDirectory: String?, date: Date) -> DevEvent? {
        guard json["type"] as? String == "agent-turn-complete" else { return nil }
        let directory = (json["cwd"] as? String) ?? fallbackDirectory
        return DevEvent(
            source: "codex",
            status: .success,
            title: String(localized: "Finished"),
            detail: (json["last-assistant-message"] as? String).map(Self.oneLine)
                ?? directory.map { ($0 as NSString).lastPathComponent },
            directory: directory,
            date: date,
            sessionID: json["thread-id"] as? String
        )
    }

    private static func oneLine(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return String(collapsed.prefix(160))
    }
}

/// An AI coding agent process (Claude Code, Codex, Gemini CLI…) running on this Mac.
nonisolated struct AgentProcess: Identifiable, Equatable, Sendable {
    let pid: Int32
    let name: String
    let elapsed: String
    var directory: String?

    var id: Int32 { pid }

    var projectName: String? {
        guard let directory, directory != "/", directory != NSHomeDirectory() else { return nil }
        return (directory as NSString).lastPathComponent
    }

    /// `source` value used by hook events from this agent.
    var source: String? {
        switch name {
        case "Claude Code": "claude"
        case "Codex": "codex"
        default: nil
        }
    }
}

/// Terminal and AI agent activity: events from `notchisland-notify` (dropped
/// in ~/.notchisland/inbox) plus a list of running agent processes.
final class DevActivityService: ObservableObject {
    @Published private(set) var events: [DevEvent] = []
    @Published private(set) var agents: [AgentProcess] = []
    /// The event currently popped up on the island.
    @Published private(set) var alert: DevEvent?

    static let home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".notchisland", isDirectory: true)
    static let inbox = home.appendingPathComponent("inbox", isDirectory: true)
    static let maxEvents = 40

    private var source: DispatchSourceFileSystemObject?
    private var alertTask: Task<Void, Never>?
    private var agentPollTask: Task<Void, Never>?

    func start() {
        try? FileManager.default.createDirectory(at: Self.inbox, withIntermediateDirectories: true)
        drainInbox()
        let descriptor = open(Self.inbox.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drainInbox() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    // MARK: Inbox

    private func drainInbox() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        let newEvents = files
            .filter { $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> DevEvent? in
                defer { try? FileManager.default.removeItem(at: url) }
                guard let data = try? Data(contentsOf: url),
                      let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { return nil }
                return DevEvent.parse(dict)
            }
        for event in newEvents { receive(event) }
    }

    func receive(_ event: DevEvent) {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.featureDev) else { return }
        // A session's newest state replaces its "working" row.
        if let session = event.sessionID {
            events.removeAll { $0.sessionID == session && $0.status == .working }
        }
        events.insert(event, at: 0)
        if events.count > Self.maxEvents { events.removeLast(events.count - Self.maxEvents) }
        if event.status.alerts { showAlert(event) }
    }

    func clearEvents() {
        events.removeAll()
    }

    func remove(_ event: DevEvent) {
        events.removeAll { $0.id == event.id }
    }

    /// Latest hook state for an agent process, matched by agent and folder.
    func latestEvent(for agent: AgentProcess) -> DevEvent? {
        guard let source = agent.source else { return nil }
        return events.first { $0.source == source && $0.directory == agent.directory }
    }

    // MARK: Alert

    private func showAlert(_ event: DevEvent) {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.devAlerts) else { return }
        alert = event
        alertTask?.cancel()
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(event.status == .attention ? 8 : 5))
            guard !Task.isCancelled else { return }
            self?.alert = nil
        }
    }

    func dismissAlert() {
        alertTask?.cancel()
        alert = nil
    }

    // MARK: Agents

    func startPollingAgents() {
        guard agentPollTask == nil else { return }
        agentPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAgents()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func stopPollingAgents() {
        agentPollTask?.cancel()
        agentPollTask = nil
    }

    func refreshAgents() async {
        guard let output = await ShellCommand.run("/bin/ps", ["-axo", "pid=,etime=,comm="]) else { return }
        var found = Self.parseAgents(psOutput: output)
        if !found.isEmpty,
           let cwd = await ShellCommand.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", found.map { String($0.pid) }.joined(separator: ","), "-Fpn"]) {
            let directories = PortsService.parseDirectories(lsofOutput: cwd)
            for index in found.indices { found[index].directory = directories[found[index].pid] }
        }
        if found != agents { agents = found }
    }

    /// Executable names of agent CLIs. Matched case-sensitively so the
    /// Claude desktop app ("Claude") isn't listed as Claude Code.
    nonisolated static let agentNames: [String: String] = [
        "claude": "Claude Code",
        "codex": "Codex",
        "gemini": "Gemini CLI",
        "aider": "Aider",
        "opencode": "OpenCode",
        "cursor-agent": "Cursor Agent",
        "amp": "Amp",
        "copilot": "Copilot CLI",
        "qwen": "Qwen Code",
        "crush": "Crush",
    ]

    /// Parses `ps -axo pid=,etime=,comm=` output.
    nonisolated static func parseAgents(psOutput: String) -> [AgentProcess] {
        psOutput.split(separator: "\n").compactMap { line -> AgentProcess? in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]) else { return nil }
            let executable = (String(fields[2]) as NSString).lastPathComponent
            guard let name = agentNames[executable] else { return nil }
            return AgentProcess(pid: pid, name: name, elapsed: formatElapsed(String(fields[1])))
        }
    }

    /// "02-04:59:29" → "2d 4h", "46:37" → "46m", "00:12" → "12s".
    nonisolated static func formatElapsed(_ etime: String) -> String {
        var days = 0
        var rest = Substring(etime)
        if let dash = rest.firstIndex(of: "-") {
            days = Int(rest[..<dash]) ?? 0
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":").compactMap { Int($0) }
        let (hours, minutes, seconds): (Int, Int, Int) = switch parts.count {
        case 3: (parts[0], parts[1], parts[2])
        case 2: (0, parts[0], parts[1])
        default: (0, 0, parts.first ?? 0)
        }
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}
