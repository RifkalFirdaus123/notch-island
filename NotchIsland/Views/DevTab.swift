import AppKit
import SwiftUI

/// Coding utilities: terminal and agent activity, listening ports, clipboard
/// history, quick text tools and hashes.
struct DevTabView: View {
    @ObservedObject var activity: DevActivityService
    @ObservedObject var ports: PortsService
    @ObservedObject var clipboard: ClipboardService
    @Binding var wantsKeyboard: Bool
    /// Kept here so it survives switching sections while the panel is open.
    @State private var hashInput = ""
    @AppStorage("devTabSection") private var sectionRaw = DevSection.activity.rawValue

    private var section: DevSection { DevSection(rawValue: sectionRaw) ?? .activity }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(DevSection.allCases) { item in
                    SectionChip(section: item, isSelected: item == section, badge: badge(for: item)) {
                        sectionRaw = item.rawValue
                    }
                }
                Spacer(minLength: 0)
            }

            Group {
                switch section {
                case .activity: ActivityView(activity: activity)
                case .ports: PortsView(ports: ports)
                case .clipboard: ClipboardView(clipboard: clipboard, wantsKeyboard: $wantsKeyboard)
                case .tools: ToolsView(clipboard: clipboard)
                case .hash: HashView(input: $hashInput, wantsKeyboard: $wantsKeyboard)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            activity.startPollingAgents()
            ports.startPolling()
        }
        .onDisappear {
            activity.stopPollingAgents()
            ports.stopPolling()
        }
    }

    private func badge(for section: DevSection) -> Int? {
        switch section {
        case .ports: ports.ports.isEmpty ? nil : ports.ports.count
        case .activity: activity.agents.isEmpty ? nil : activity.agents.count
        default: nil
        }
    }
}

private enum DevSection: String, CaseIterable, Identifiable {
    case activity, ports, clipboard, tools, hash

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .activity: "bell.badge"
        case .ports: "network"
        case .clipboard: "doc.on.clipboard"
        case .tools: "wrench.and.screwdriver"
        case .hash: "number"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .activity: "Activity"
        case .ports: "Ports"
        case .clipboard: "Clipboard"
        case .tools: "Tools"
        case .hash: "Hash"
        }
    }
}

private struct SectionChip: View {
    let section: DevSection
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: section.symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(section.title)
                if let badge {
                    Text(verbatim: "\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(.white.opacity(0.2)))
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.55))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(.white.opacity(isSelected ? 0.16 : 0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity

private struct ActivityView: View {
    @ObservedObject var activity: DevActivityService

    var body: some View {
        if activity.agents.isEmpty && activity.events.isEmpty {
            EmptyNote(
                symbol: "terminal",
                text: DevHooks.isInstalled
                    ? "No activity yet. Long terminal commands and AI agent turns show up here."
                    : "Connect your terminal and AI agents in Settings › Dev Tools."
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    ForEach(activity.agents) { agent in
                        AgentRow(agent: agent, latest: activity.latestEvent(for: agent))
                    }
                    ForEach(activity.events) { event in
                        EventRow(event: event, activity: activity)
                    }
                }
            }
        }
    }
}

private struct AgentRow: View {
    let agent: AgentProcess
    let latest: DevEvent?
    @State private var isHovering = false

    private var status: DevEventStatus? {
        // A finished state from long ago isn't news.
        guard let latest, latest.status == .working || latest.status == .attention || Date.now.timeIntervalSince(latest.date) < 600 else {
            return nil
        }
        return latest.status
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 14)
            Text(verbatim: agent.name)
                .foregroundStyle(.white.opacity(0.9))
            if let project = agent.projectName {
                Text(verbatim: project)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let status {
                Label(statusText(status), systemImage: status.symbol)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
            } else {
                Text("Running")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Text(verbatim: agent.elapsed)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
        }
        .rowStyle(isHovering: isHovering)
        .onHover { isHovering = $0 }
        .help(Text(verbatim: "PID \(agent.pid)" + (agent.directory.map { "\n\($0)" } ?? "")))
        .contextMenu {
            if let directory = agent.directory {
                Button("Show in Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: directory, isDirectory: true))
                }
            }
        }
    }

    private func statusText(_ status: DevEventStatus) -> LocalizedStringKey {
        switch status {
        case .working: "Working"
        case .attention: "Needs you"
        case .success: "Done"
        case .failure: "Failed"
        case .info: "Running"
        }
    }
}

private struct EventRow: View {
    let event: DevEvent
    @ObservedObject var activity: DevActivityService
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: event.status.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(event.status.tint)
                .frame(width: 14)
            if event.isAgent {
                Text(verbatim: event.sourceName)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize()
            }
            Text(verbatim: event.title)
                .font(.system(size: 11, design: event.isAgent ? .default : .monospaced))
                .foregroundStyle(.white.opacity(event.isAgent ? 0.6 : 0.9))
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail = event.detail {
                Text(verbatim: detail)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 4)
            Text(event.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize()
        }
        .rowStyle(isHovering: isHovering)
        .onHover { isHovering = $0 }
        .help(Text(verbatim: [event.title, event.detail, event.directory].compactMap { $0 }.joined(separator: "\n")))
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(event.title, forType: .string)
            }
            if let directory = event.directory {
                Button("Show in Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: directory, isDirectory: true))
                }
            }
            Divider()
            Button("Remove") { activity.remove(event) }
            Button("Clear All") { activity.clearEvents() }
        }
    }
}

// MARK: - Ports

private struct PortsView: View {
    @ObservedObject var ports: PortsService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let message = ports.message {
                Text(verbatim: message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(5))
                        if ports.message == message { ports.dismissMessage() }
                    }
            }
            if ports.ports.isEmpty {
                if ports.isLoading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyNote(symbol: "network.slash", text: "No local ports are listening.")
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(ports.ports) { port in
                            PortRow(port: port, ports: ports)
                        }
                    }
                }
            }
        }
    }
}

private struct PortRow: View {
    let port: ListeningPort
    @ObservedObject var ports: PortsService
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: ":\(port.port)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 46, alignment: .leading)
            Text(verbatim: port.command)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            if let project = port.projectName {
                Text(verbatim: project)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(verbatim: "\(port.pid)")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.35))
            Button { ports.open(port) } label: {
                Image(systemName: "safari")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: "http://localhost:\(port.port)"))
            ConfirmButton(symbol: "xmark.circle", confirmTitle: "Kill?") { ports.kill(port) }
                .help(Text("Stop \(port.command) (PID \(String(port.pid)))"))
        }
        .rowStyle(isHovering: isHovering)
        .onHover { isHovering = $0 }
        .help(Text(verbatim: helpText))
        .contextMenu {
            Button("Open in Browser") { ports.open(port) }
            Button("Copy URL") { ports.copyURL(port) }
            if port.directory != nil {
                Button("Show Folder in Finder") { ports.revealDirectory(port) }
            }
            Divider()
            Button("Kill Process", role: .destructive) { ports.kill(port) }
        }
    }

    private var helpText: String {
        var lines = ["\(port.command) · PID \(port.pid)", port.addresses.joined(separator: ", ")]
        if let directory = port.directory { lines.append(directory) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Clipboard

private struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardService
    @Binding var wantsKeyboard: Bool
    @AppStorage(SettingsKeys.clipboardHistory) private var historyEnabled = true

    private var history: [ClipItem] { historyEnabled ? clipboard.items : [] }

    var body: some View {
        if clipboard.pinned.isEmpty && history.isEmpty {
            EmptyNote(
                symbol: "doc.on.clipboard",
                text: historyEnabled
                    ? "Copy some text. It stays in memory only and is never saved."
                    : "Clipboard history is off. Turn it on in Settings › Dev Tools."
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if !clipboard.pinned.isEmpty {
                        SectionHeader(symbol: "pin.fill", title: "Pinned", count: clipboard.pinned.count)
                        ForEach(clipboard.pinned) { item in
                            ClipRow(item: item, isPinned: true, clipboard: clipboard, wantsKeyboard: $wantsKeyboard)
                        }
                    }
                    if !history.isEmpty {
                        SectionHeader(symbol: "clock.arrow.circlepath", title: "Recent", count: history.count) {
                            ConfirmButton(title: "Clear All", confirmTitle: "Delete all?") { clipboard.clear() }
                                .help(Text("Pinned items stay."))
                        }
                        .padding(.top, clipboard.pinned.isEmpty ? 0 : 4)
                        ForEach(history) { item in
                            ClipRow(item: item, isPinned: false, clipboard: clipboard, wantsKeyboard: $wantsKeyboard)
                        }
                    }
                }
            }
        }
    }
}

private struct SectionHeader<Trailing: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let count: Int
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(title)
            Text(verbatim: "\(count)")
                .monospacedDigit()
                .opacity(0.7)
            Spacer()
            trailing()
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.45))
        .frame(minHeight: 18)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(symbol: String, title: LocalizedStringKey, count: Int) {
        self.init(symbol: symbol, title: title, count: count) { EmptyView() }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let isPinned: Bool
    @ObservedObject var clipboard: ClipboardService
    @Binding var wantsKeyboard: Bool
    @State private var isHovering = false
    @State private var copied = false
    @State private var revealed = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                labelEditor
            } else {
                content
            }
        }
        .rowStyle(isHovering: isHovering || isEditing)
        .onHover { isHovering = $0 }
        .onDisappear { if isEditing { endEditing() } }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }

    // MARK: Normal row

    private var content: some View {
        HStack(spacing: 6) {
            Button(action: copyItem) {
                HStack(spacing: 6) {
                    if let label = item.label {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30)
                        Text(verbatim: label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Text(verbatim: revealed ? item.preview : "••••••••")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        KindBadge(kind: item.kind, text: item.text)
                        Text(verbatim: item.preview)
                            .font(.system(size: 11, design: item.kind == .text ? .default : .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    if copied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    } else if !item.isLabeled, let note = inlineNote {
                        Text(verbatim: note)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.isLabeled {
                IconButton(symbol: revealed ? "eye.slash" : "eye", isVisible: isHovering) { revealed.toggle() }
                    .help(revealed ? Text("Hide value") : Text("Show value"))
            } else if let action = smartAction {
                Button(action.title) { action.run() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .opacity(isHovering ? 1 : 0.6)
            }

            IconButton(symbol: item.isLabeled ? "tag.fill" : "tag", isVisible: isHovering, action: startEditing)
                .help(item.isLabeled ? Text("Rename label") : Text("Add label"))

            Button { clipboard.togglePin(item) } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isPinned ? 0 : 45))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPinned ? Color.accentColor : .white.opacity(isHovering ? 0.8 : 0.25))
            .help(isPinned ? Text("Unpin") : Text("Pin"))

            IconButton(symbol: "xmark", isVisible: isHovering) { clipboard.remove(item) }
                .help(isPinned ? Text("Remove pinned item") : Text("Remove from history"))
        }
        // Don't show a labeled secret in the tooltip.
        .help(item.isLabeled ? Text(verbatim: item.label ?? "") : Text(verbatim: String(item.text.prefix(600))))
        .contextMenu {
            Button("Copy", action: copyItem)
            Button(item.isLabeled ? "Rename Label…" : "Add Label…", action: startEditing)
            if item.isLabeled {
                Button("Remove Label") { clipboard.setLabel("", for: item) }
            }
            Button(isPinned ? "Unpin" : "Pin") { clipboard.togglePin(item) }
            Button("Remove") { clipboard.remove(item) }
            Divider()
            Button("Clear History") { clipboard.clear() }
        }
    }

    // MARK: Label editor

    private var labelEditor: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            TextField("Label, e.g. Database password", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .onSubmit(saveLabel)
                .onExitCommand(perform: endEditing)
            Button(action: saveLabel) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Save"))
            Button(action: endEditing) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Cancel"))
        }
    }

    private func startEditing() {
        draft = item.label ?? ""
        isEditing = true
        wantsKeyboard = true
        // The click was on a button, so the panel isn't key yet.
        DispatchQueue.main.async {
            NotchPanel.focusForTyping()
            fieldFocused = true
        }
    }

    private func saveLabel() {
        clipboard.setLabel(draft, for: item)
        endEditing()
    }

    private func endEditing() {
        isEditing = false
        fieldFocused = false
        wantsKeyboard = false
    }

    private func copyItem() {
        clipboard.copy(item)
        copied = true
    }

    private func copy(_ text: String) {
        clipboard.copy(text)
        copied = true
    }

    private var inlineNote: String? {
        switch item.kind {
        case .timestamp:
            DevToolkit.timestampDate(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .map { $0.formatted(date: .abbreviated, time: .shortened) }
        default:
            nil
        }
    }

    private struct SmartAction {
        let title: LocalizedStringKey
        let run: () -> Void
    }

    /// The most useful one-click action for what was copied.
    private var smartAction: SmartAction? {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.kind {
        case .url:
            guard let url = URL(string: text) else { return nil }
            return SmartAction(title: "Open") { NSWorkspace.shared.open(url) }
        case .json:
            return transform("Format") { DevToolkit.formatJSON(text) }
        case .jwt:
            return transform("Decode") { DevToolkit.decodeJWT(text) }
        case .base64:
            return transform("Decode") { DevToolkit.base64Decode(text) }
        case .timestamp:
            return transform("ISO") {
                DevToolkit.timestampDate(text).map { $0.formatted(.iso8601) }
            }
        default:
            return nil
        }
    }

    private func transform(_ title: LocalizedStringKey, _ make: @escaping () -> String?) -> SmartAction {
        SmartAction(title: title) {
            if let output = make() { copy(output) }
        }
    }
}

/// Small row icon that fades in on hover.
private struct IconButton: View {
    let symbol: String
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(isVisible ? 0.8 : 0.25))
    }
}

private struct KindBadge: View {
    let kind: ClipKind
    let text: String

    var body: some View {
        Group {
            if kind == .color, let rgba = DevToolkit.rgba(fromHex: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.3), lineWidth: 0.5))
                    .frame(width: 12, height: 12)
                    .frame(width: 30)
            } else {
                Text(verbatim: kind.label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(kind == .text ? .white.opacity(0.45) : Color.accentColor)
                    .frame(width: 30, height: 14)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08)))
            }
        }
    }
}

// MARK: - Tools

/// Transforms the clipboard text and copies the result back.
private struct ToolsView: View {
    @ObservedObject var clipboard: ClipboardService
    @State private var output: String?
    @State private var failed: LocalizedStringKey?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ClipboardSource(text: clipboard.current)

            LazyVGrid(columns: columns, spacing: 4) {
                tool("Base64 ↑") { DevToolkit.base64Encode($0) }
                tool("Base64 ↓") { DevToolkit.base64Decode($0) }
                tool("URL ↑") { DevToolkit.urlEncode($0) }
                tool("URL ↓") { DevToolkit.urlDecode($0) }
                tool("JSON {…}") { DevToolkit.formatJSON($0) }
                tool("JSON min") { DevToolkit.minifyJSON($0) }
                tool("JWT") { DevToolkit.decodeJWT($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                tool("Epoch → Date") { text in
                    DevToolkit.timestampDate(text.trimmingCharacters(in: .whitespacesAndNewlines)).map(DevToolkit.timestampDescription)
                }
                generator("UUID") { UUID().uuidString }
                generator("uuid") { UUID().uuidString.lowercased() }
                generator("Now (epoch)") { String(Int(Date.now.timeIntervalSince1970)) }
                generator("Now (ISO)") { Date.now.formatted(.iso8601) }
            }

            if let failed {
                Text(failed)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let output {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(verbatim: output.split(whereSeparator: \.isNewline).joined(separator: " "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 10))
                .help(Text(verbatim: String(output.prefix(1000))))
            }
        }
        .task(id: output) {
            guard output != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            output = nil
        }
        .task(id: failed.map { "\($0)" }) {
            guard failed != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            failed = nil
        }
    }

    private func tool(_ title: LocalizedStringKey, _ transform: @escaping (String) -> String?) -> some View {
        ToolButton(title: title, isEnabled: clipboard.current != nil) {
            guard let input = clipboard.current else { return }
            if let result = transform(input) {
                clipboard.copy(result)
                output = result
                failed = nil
            } else {
                failed = "That clipboard text can't be converted this way."
                output = nil
            }
        }
    }

    private func generator(_ title: LocalizedStringKey, _ make: @escaping () -> String) -> some View {
        ToolButton(title: title, isEnabled: true) {
            let result = make()
            clipboard.copy(result)
            output = result
            failed = nil
        }
    }
}

private struct ToolButton: View {
    let title: LocalizedStringKey
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.35))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(isHovering && isEnabled ? 0.18 : 0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
    }
}

/// Shows which text the tools and hashes are working on.
private struct ClipboardSource: View {
    let text: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 9, weight: .semibold))
            if let text {
                Text(verbatim: text.split(whereSeparator: \.isNewline).joined(separator: " ⏎ "))
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(verbatim: "\(text.count)")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .opacity(0.7)
            } else {
                Text("Copy some text to use the tools.")
                    .font(.system(size: 10))
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white.opacity(0.5))
        .help(text.map { Text(verbatim: String($0.prefix(600))) } ?? Text(verbatim: ""))
    }
}

// MARK: - Hash

/// Type or paste text and get its hashes. Independent of the clipboard.
private struct HashView: View {
    @Binding var input: String
    @Binding var wantsKeyboard: Bool
    @State private var copied: HashAlgorithm?
    @FocusState private var isFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Text to hash", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .focused($isFocused)
                    .onSubmit { isFocused = false }
                if !input.isEmpty {
                    Text(verbatim: "\(input.utf8.count) B")
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                    Button { input = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help(Text("Clear"))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(isFocused ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.accentColor.opacity(isFocused ? 0.8 : 0), lineWidth: 1)
            )

            if input.isEmpty {
                Text("Click the field and type, or paste with ⌘V. Click a hash to copy it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(HashAlgorithm.allCases) { algorithm in
                        HashRow(
                            algorithm: algorithm,
                            value: DevToolkit.hash(input, with: algorithm),
                            isCopied: copied == algorithm
                        ) { value in
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(value, forType: .string)
                            copied = algorithm
                        }
                    }
                }
            }
        }
        .onAppear { wantsKeyboard = true }
        .onDisappear { wantsKeyboard = false }
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            copied = nil
        }
    }
}

private struct HashRow: View {
    let algorithm: HashAlgorithm
    let value: String
    let isCopied: Bool
    let copy: (String) -> Void
    @State private var isHovering = false

    var body: some View {
        Button { copy(value) } label: {
            HStack(spacing: 6) {
                Text(verbatim: algorithm.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, alignment: .leading)
                Text(verbatim: value)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isCopied ? .green : .white.opacity(isHovering ? 0.8 : 0.3))
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.16 : 0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(Text(verbatim: value))
    }
}

// MARK: - Shared

private struct EmptyNote: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.35))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }
}
