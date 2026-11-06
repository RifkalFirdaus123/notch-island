import AppKit
import SwiftUI

/// The signed-in user's unfinished cards on Resam Kanban. Click one to open it
/// on kanban.resam.id.
struct KanbanTabView: View {
    @ObservedObject var kanban: KanbanService

    /// The board's unfinished columns, left to right.
    static let columns = KanbanStatus.allCases.filter { !$0.isFinished }

    var body: some View {
        Group {
            if kanban.isSignedIn {
                signedIn
            } else {
                signedOut
            }
        }
        .onAppear { kanban.refresh() }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(KanbanScope.allCases) { scope in
                    ScopeChip(label: scope.label, isSelected: scope == kanban.scope) {
                        kanban.scope = scope
                    }
                }
                if !kanban.unfinishedTasks.isEmpty {
                    Text(verbatim: "\(kanban.unfinishedTasks.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.leading, 2)
                }
                Spacer()
                if kanban.isLoading {
                    ProgressView().controlSize(.mini)
                }
                Button { kanban.refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .disabled(kanban.isLoading)
                .help("Refresh")
                Button { openBoard() } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help("Open Resam Kanban")
            }

            if let message = kanban.errorMessage, kanban.tasks.isEmpty {
                placeholder(message)
            } else if kanban.unfinishedTasks.isEmpty {
                placeholder(kanban.lastUpdated == nil ? String(localized: "Loading…") : String(localized: "No unfinished cards 🎉"))
            } else {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Self.columns, id: \.self) { status in
                        KanbanColumn(status: status, tasks: kanban.unfinishedTasks.filter { $0.status == status })
                    }
                }
            }
        }
    }

    private var signedOut: some View {
        VStack(spacing: 8) {
            if let message = kanban.errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            Text("Sign in to Resam Kanban in Settings to see your cards.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Open Settings…") { kanban.onRequestSignIn?() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openBoard() {
        if let url = URL(string: "\(KanbanBrowser.host)/sla/board") { KanbanBrowser.open(url) }
    }
}

private struct ScopeChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.5))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(.white.opacity(isSelected ? 0.18 : 0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One board column: a header with its count, then its cards.
private struct KanbanColumn: View {
    let status: KanbanStatus
    let tasks: [KanbanTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(status.tint).frame(width: 5, height: 5)
                Text(verbatim: status.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(verbatim: "\(tasks.count)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 4)

            if tasks.isEmpty {
                Text("—")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(tasks) { task in
                            KanbanCard(task: task)
                        }
                    }
                }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.04))
        )
    }
}

private struct KanbanCard: View {
    let task: KanbanTask
    @State private var isHovering = false

    var body: some View {
        Button { if let url = task.webURL { KanbanBrowser.open(url) } } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: task.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Circle()
                        .fill(slaColor)
                        .frame(width: 5, height: 5)
                    if let due = task.dueDate {
                        Text(due, format: .dateTime.day().month(.abbreviated))
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(task.isOverdue ? Color.red : .white.opacity(0.5))
                    }
                    if let product = task.product, !product.isEmpty {
                        Text(verbatim: product)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.18 : 0.09))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(task.status.tint.opacity(0.8))
                    .frame(width: 2)
                    .padding(.vertical, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(Text(verbatim: helpText))
    }

    private var helpText: String {
        var parts = [task.title]
        if let due = task.dueDate {
            parts.append(due.formatted(date: .abbreviated, time: .shortened))
        }
        if let percentage = task.slaPercentage { parts.append("SLA \(Int(percentage))%") }
        return parts.joined(separator: " · ")
    }

    /// The board's SLA traffic light (hijau / kuning / merah).
    private var slaColor: Color {
        switch task.slaColor {
        case "hijau": .green
        case "kuning": .yellow
        case "merah": .red
        default: .white.opacity(0.25)
        }
    }
}

private extension KanbanStatus {
    var tint: Color {
        switch self {
        case .requested: .purple
        case .todo: .white
        case .inProgress: .blue
        case .review: .orange
        case .completed: .green
        case .rejected, .cancelled: .gray
        }
    }
}
