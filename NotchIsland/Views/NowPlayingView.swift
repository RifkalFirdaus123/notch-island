import SwiftUI

/// Left side of the Home tab: artwork, title, progress and controls.
struct NowPlayingView: View {
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        if let info = nowPlaying.info {
            HStack(spacing: 12) {
                ArtworkView(image: nowPlaying.artwork, cornerRadius: 12)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle(for: info))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                    PlaybackProgress(info: info, tint: nowPlaying.accentColor ?? .white)
                        .padding(.top, 3)
                    PlaybackControls(nowPlaying: nowPlaying, isPlaying: info.isPlaying)
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            NowPlayingEmptyView(hint: hint)
        }
    }

    private func subtitle(for info: NowPlayingInfo) -> String {
        [info.artist, nowPlaying.sourceName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Point the user at a fixable problem instead of an unexplained blank.
    private var hint: LocalizedStringKey? {
        if nowPlaying.issues.values.contains(.javascriptDisabled) {
            return "For YouTube, allow JavaScript from Apple Events in the browser"
        }
        if nowPlaying.issues.values.contains(.notAuthorized) {
            return "Allow NotchIsland under Privacy & Security › Automation"
        }
        return nil
    }
}

struct NowPlayingEmptyView: View {
    var hint: LocalizedStringKey?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(hint ?? "Play something in Spotify, Music or YouTube")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    var cornerRadius: CGFloat

    var body: some View {
        // The shape sets the size; the image fills it as an overlay, so a
        // wide image (e.g. a YouTube thumbnail) can't grow the view.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.white.opacity(0.08))
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Progress bar and times. The position is extrapolated locally, and the
/// timeline only ticks while this view is on screen.
private struct PlaybackProgress: View {
    let info: NowPlayingInfo
    let tint: Color

    var body: some View {
        if let duration = info.duration, duration > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let position = info.position(at: context.date)
                VStack(spacing: 2) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule()
                                .fill(tint)
                                .frame(width: proxy.size.width * min(1, position / duration))
                        }
                    }
                    .frame(height: 4)
                    HStack {
                        Text(Self.format(position))
                        Spacer()
                        Text(verbatim: "-" + Self.format(max(0, duration - position)))
                    }
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

private struct PlaybackControls: View {
    @ObservedObject var nowPlaying: NowPlayingService
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 18) {
            ControlButton(symbol: "backward.fill", size: 13, label: "Previous", action: nowPlaying.previousTrack)
            ControlButton(
                symbol: isPlaying ? "pause.fill" : "play.fill", size: 17,
                label: isPlaying ? "Pause" : "Play", action: nowPlaying.playPause
            )
            ControlButton(symbol: "forward.fill", size: 13, label: "Next", action: nowPlaying.nextTrack)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}
