import SwiftUI

/// Folders and workspaces in the projects folder; click one to open it in Antigravity.
struct ProjectsTabView: View {
    @ObservedObject var projects: ProjectsService

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if projects.folders.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(projects.folders) { folder in
                                FolderChip(
                                    name: folder.name,
                                    isSelected: folder == projects.selectedFolder
                                ) { projects.select(folder) }
                            }
                        }
                    }
                } else {
                    Text(verbatim: projects.selectedFolder?.name ?? projects.folder.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button { projects.promptNewProject() } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help("New Project Folder…")
                Menu {
                    Button("New Project Folder…") { projects.promptNewProject() }
                    Button("Refresh") { projects.refresh() }
                    Button("Show Folder in Finder") { projects.openFolderInFinder() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if let message = projects.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if projects.items.isEmpty {
                Text("No projects found")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(projects.items) { item in
                            ProjectRow(item: item, projects: projects)
                        }
                    }
                }
            }
        }
        .onAppear { projects.refresh() }
    }
}

private struct FolderChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: name)
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

private struct ProjectRow: View {
    let item: ProjectItem
    @ObservedObject var projects: ProjectsService
    @State private var isHovering = false

    var body: some View {
        Button { projects.open(item) } label: {
            HStack(spacing: 6) {
                Image(systemName: item.isWorkspace ? "square.stack.3d.up.fill" : "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(item.isWorkspace ? Color.accentColor : .white.opacity(0.7))
                    .frame(width: 14)
                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.16 : 0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open in \(projects.selectedEditor.displayName)") {
                projects.open(item)
            }
            Divider()
            Button("Open in Visual Studio Code") {
                projects.open(item, with: .vscode)
            }
            Button("Open in Antigravity") {
                projects.open(item, with: .antigravity)
            }
            Button("Open in Finder") {
                projects.open(item, with: .finder)
            }
            Divider()
            Button("Show in Finder") {
                projects.revealInFinder(item)
            }
        }
        .help(Text(verbatim: item.url.path))
    }
}
