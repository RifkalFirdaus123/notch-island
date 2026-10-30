import SwiftUI

struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel
    // Re-render when the strip height changes in Settings.
    @AppStorage(SettingsKeys.lyricStripHeight) private var lyricStripHeight = SettingsKeys.defaultLyricStripHeight
    // …and when the idle size changes.
    @AppStorage(SettingsKeys.idleExtraWidth) private var idleExtraWidth = 0.0
    @AppStorage(SettingsKeys.idleExtraHeight) private var idleExtraHeight = 0.0

    static let animation = Animation.spring(response: 0.3, dampingFraction: 0.8)

    private var state: IslandState { viewModel.state }
    private var size: CGSize { viewModel.size(for: state) }

    private var topRadius: CGFloat { state == .collapsed ? 0 : 8 }

    private var bottomRadius: CGFloat {
        switch state {
        case .collapsed: 8
        case .playing: 10
        case .lyric: 12
        case .hover: 14
        case .expanded: 28
        }
    }

    /// Off-notch screens have nothing to blend into, so stay hidden when idle.
    private var isVisible: Bool {
        guard !viewModel.isSuppressed else { return false }
        return viewModel.geometry?.hasNotch == true || state != .collapsed
    }

    var body: some View {
        content
            .frame(width: size.width, height: size.height, alignment: .top)
            .padding(.horizontal, topRadius)
            .background(Color.black)
            .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
            .shadow(color: .black.opacity(state == .expanded ? 0.4 : 0), radius: 14, y: 6)
            .opacity(isVisible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .animation(Self.animation, value: state)
            .animation(Self.animation, value: viewModel.selectedTab)
            .animation(Self.animation, value: viewModel.lyricLine)
            .animation(Self.animation, value: idleExtraWidth)
            .animation(Self.animation, value: idleExtraHeight)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .collapsed:
            Color.clear
        case .playing:
            CompactNowPlayingRow(notchSize: viewModel.idleNotchSize, nowPlaying: viewModel.nowPlaying)
                .transition(.opacity)
        case .lyric:
            ZStack(alignment: .top) {
                LyricStripView(
                    line: viewModel.lyricLine ?? "",
                    notchHeight: viewModel.idleNotchSize.height,
                    stripHeight: lyricStripHeight,
                    mood: viewModel.lyricMood
                )
                CompactNowPlayingRow(notchSize: viewModel.idleNotchSize, nowPlaying: viewModel.nowPlaying)
            }
            .transition(.opacity)
        case .hover:
            HoverSummaryView(
                // Physical notch width to clear, idle height to fill.
                notchSize: CGSize(width: viewModel.notchSize.width, height: viewModel.idleNotchSize.height),
                clock: viewModel.clock,
                battery: viewModel.battery,
                nowPlaying: viewModel.nowPlaying
            )
                .contentShape(Rectangle())
                .onTapGesture { viewModel.state = .expanded }
                .transition(.opacity)
        case .expanded:
            ExpandedIslandView(viewModel: viewModel)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        }
    }
}

/// Medium-width summary shown in the "ears" next to the notch.
private struct HoverSummaryView: View {
    let notchSize: CGSize
    @ObservedObject var clock: ClockService
    @ObservedObject var battery: BatteryService
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        HStack(spacing: 6) {
            if let info = nowPlaying.info {
                ArtworkView(image: nowPlaying.artwork, cornerRadius: 5)
                    .frame(width: 20, height: 20)
                if info.isPlaying {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .foregroundStyle(nowPlaying.accentColor ?? .white)
                }
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: notchSize.width)
            // Icon only: the ear is too narrow for the percentage too.
            if let status = battery.status {
                Image(systemName: status.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(status.isCharging ? .green : status.isLow ? .red : .white)
            }
            Text(clock.now, format: .dateTime.hour().minute())
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: notchSize.height)
    }
}

/// Idle row while music plays: artwork left of the notch, equalizer right.
private struct CompactNowPlayingRow: View {
    let notchSize: CGSize
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: nowPlaying.artwork, cornerRadius: 5)
                .frame(width: 22, height: 22)
            Spacer(minLength: notchSize.width)
            EqualizerView(
                isAnimating: nowPlaying.info?.isPlaying == true,
                color: nowPlaying.accentColor ?? .white
            )
            .frame(width: 18, height: 14)
        }
        .padding(.horizontal, 10)
        // Fixed width, centered: under a wide lyric strip it stays beside
        // the notch instead of drifting to the strip's edges.
        .frame(width: notchSize.width + IslandViewModel.idleEarWidth * 2, height: notchSize.height)
    }
}

/// A few bouncing bars. Driven by a slow timeline so it stays cheap; the
/// bars aren't tied to the real audio, which no public API exposes.
private struct EqualizerView: View {
    let isAnimating: Bool
    let color: Color

    private static let phases: [Double] = [0, 1.7, 0.9, 2.6]
    private static let speeds: [Double] = [7.1, 9.3, 6.2, 8.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Self.phases.indices, id: \.self) { i in
                        let level = isAnimating
                            ? 0.3 + 0.7 * abs(sin(t * Self.speeds[i] / 2 + Self.phases[i]))
                            : 0.25
                        Capsule()
                            .fill(color)
                            .frame(height: max(3, proxy.size.height * level))
                    }
                }
                .frame(maxHeight: .infinity)
                .animation(.linear(duration: 1 / 12), value: t)
            }
        }
    }
}
