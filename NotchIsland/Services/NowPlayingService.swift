import AppKit
import Combine
import CoreImage
import SwiftUI

/// Picks the most relevant player among all sources and exposes its track,
/// artwork and controls to the UI. The UI never talks to a source directly,
/// so sources can be added without touching views.
final class NowPlayingService: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?
    /// Name of the player behind `info`, e.g. "Spotify" or "Chrome".
    @Published private(set) var sourceName: String?
    @Published private(set) var artwork: NSImage?
    /// Taken from the artwork; nil until it is known.
    @Published private(set) var accentColor: Color?
    /// Problems the user can fix, keyed by source name.
    @Published private(set) var issues: [String: MusicSourceIssue] = [:]

    private let sources: [MusicSource]
    private var active: MusicSource?
    /// When each source last started playing, to prefer the newest one.
    private var playingSince: [ObjectIdentifier: Date] = [:]
    private var artworkTrackID: String?
    private var artworkTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(sources: [MusicSource]? = nil) {
        self.sources = sources ?? Self.defaultSources()
    }

    static func defaultSources() -> [MusicSource] {
        [
            ScriptedPlayerSource(player: .spotify),
            ScriptedPlayerSource(player: .appleMusic),
        ] + BrowserSource.supported.map { BrowserSource(displayName: $0.name, bundleID: $0.bundleID) }
    }

    func start() {
        for source in sources {
            source.onUpdate = { [weak self, weak source] in
                guard let self, let source else { return }
                self.sourceDidUpdate(source)
            }
        }
        applyEnabledSources()

        // Sources can be switched on and off in Settings.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyEnabledSources() }
            .store(in: &cancellables)
    }

    func playPause() { active?.playPause() }
    func nextTrack() { active?.nextTrack() }
    func previousTrack() { active?.previousTrack() }

    // MARK: - Choosing a source

    private var enabledKinds = Set<MusicSourceKind>()

    private func applyEnabledSources() {
        let enabled = Set(MusicSourceKind.allCases.filter { UserDefaults.standard.bool(forKey: $0.settingsKey) })
        guard enabled != enabledKinds else { return }
        enabledKinds = enabled
        for source in sources {
            if enabled.contains(source.kind) { source.start() } else { source.stop() }
        }
        chooseActive()
    }

    private func sourceDidUpdate(_ source: MusicSource) {
        let id = ObjectIdentifier(source)
        if source.info?.isPlaying == true {
            if playingSince[id] == nil { playingSince[id] = Date() }
        } else {
            playingSince[id] = nil
        }

        var newIssues = issues
        newIssues[source.displayName] = source.issue
        if newIssues != issues { issues = newIssues }

        chooseActive()
    }

    /// Playing beats paused; among playing sources the one that started most
    /// recently wins; otherwise stick with the current one if it still has
    /// something to show.
    private func chooseActive() {
        let candidates = sources.filter { enabledKinds.contains($0.kind) && $0.info != nil }
        let playing = candidates.filter { $0.info?.isPlaying == true }
        let chosen: MusicSource?
        if !playing.isEmpty {
            chosen = playing.max { (playingSince[ObjectIdentifier($0)] ?? .distantPast) < (playingSince[ObjectIdentifier($1)] ?? .distantPast) }
        } else if let active, candidates.contains(where: { $0 === active }) {
            chosen = active
        } else {
            chosen = candidates.first
        }
        active = chosen
        publish(chosen?.info, from: chosen)
    }

    private func publish(_ newInfo: NowPlayingInfo?, from source: MusicSource?) {
        if source?.displayName != sourceName { sourceName = source?.displayName }

        // Skip updates that only differ by polling jitter.
        if let newInfo, let info, newInfo.isEquivalent(to: info) { return }
        if newInfo != info { info = newInfo }
        loadArtworkIfNeeded(for: newInfo, from: source)
    }

    // MARK: - Artwork

    private func loadArtworkIfNeeded(for info: NowPlayingInfo?, from source: MusicSource?) {
        guard let info else {
            artworkTask?.cancel()
            artworkTrackID = nil
            artwork = nil
            accentColor = nil
            return
        }
        let key = "\(source?.displayName ?? "")|\(info.trackID)|\(info.artworkURL?.absoluteString ?? "")"
        guard key != artworkTrackID else { return }
        artworkTrackID = key
        artworkTask?.cancel()

        let isAppleMusic = source?.kind == .appleMusic
        artworkTask = Task { [weak self] in
            let data: Data?
            if let url = info.artworkURL {
                data = try? await URLSession.shared.data(from: url).0
            } else if isAppleMusic {
                data = try? await AppleScriptRunner.shared.run(
                    ScriptedPlayer.appleMusicArtworkScript, parse: { $0.data }
                ).get()
            } else {
                data = nil
            }
            guard !Task.isCancelled, let self else { return }

            let image = data.flatMap(NSImage.init(data:))
            self.artwork = image
            self.accentColor = nil
            guard let data else { return }
            let color = await Task.detached { Self.accentColor(fromImageData: data) }.value
            guard !Task.isCancelled else { return }
            self.accentColor = color.map { Color(nsColor: $0) }
        }
    }

    /// Average color of the artwork, brightened so it reads on black.
    nonisolated static func accentColor(fromImageData data: Data) -> NSColor? {
        guard let image = CIImage(data: data),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: image,
                  kCIInputExtentKey: CIVector(cgRect: image.extent),
              ]),
              let output = filter.outputImage
        else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )
        let average = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(1, saturation * 1.2), brightness: max(0.75, brightness), alpha: 1)
    }
}
