import SwiftUI

/// Full panel: tab icons in the left ear, tab content below the notch.
struct ExpandedIslandView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(viewModel.enabledTabs.filter { !$0.isInRightEar }) { tab in
                        TabButton(tab: tab, isSelected: tab == viewModel.selectedTab) {
                            viewModel.select(tab)
                        }
                    }
                }
                Spacer(minLength: viewModel.notchSize.width + 8)
                Text(viewModel.selectedTab.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                HStack(spacing: 2) {
                    ForEach(viewModel.enabledTabs.filter(\.isInRightEar)) { tab in
                        TabButton(tab: tab, isSelected: tab == viewModel.selectedTab) {
                            viewModel.select(tab)
                        }
                    }
                }
                .padding(.leading, 6)
            }
            .padding(.horizontal, 14)
            .frame(height: viewModel.notchSize.height)

            ZStack {
                tabContent(viewModel.selectedTab)
                    .id(viewModel.selectedTab)
                    .transition(.push(from: viewModel.tabTransitionEdge))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding([.horizontal, .bottom], 16)
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: IslandTab) -> some View {
        switch tab {
        case .home:
            HomeTabView(
                clock: viewModel.clock,
                battery: viewModel.battery,
                systemStats: viewModel.systemStats,
                nowPlaying: viewModel.nowPlaying
            )
        case .camera:
            CameraTabView(camera: viewModel.camera)
        case .shelf:
            ShelfTabView(shelf: viewModel.shelf)
        case .projects:
            ProjectsTabView(projects: viewModel.projects)
        }
    }
}

private struct TabButton: View {
    let tab: IslandTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 22)
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.45))
                .background(
                    Capsule().fill(.white.opacity(isSelected ? 0.16 : 0))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(tab.title))
    }
}
