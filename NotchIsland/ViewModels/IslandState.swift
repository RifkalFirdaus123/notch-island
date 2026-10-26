import SwiftUI

/// The single source of truth for what the island is showing.
enum IslandState: Equatable {
    /// Idle with no music: only the physical notch is visible.
    case collapsed
    /// Idle with music playing: artwork and an equalizer beside the notch.
    case playing
    /// Like `playing`, plus a thin lyric strip under the notch.
    case lyric
    /// Cursor over the notch: medium width summary.
    case hover
    /// Full panel with tabs.
    case expanded

    var isOpen: Bool { self == .hover || self == .expanded }
}

enum IslandTab: Int, CaseIterable, Identifiable {
    case home
    case camera
    case shelf
    case projects

    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .camera: "camera.fill"
        case .shelf: "tray.full.fill"
        case .projects: "folder.fill"
        }
    }

    /// The left ear only fits three icons; the rest sit beside the title.
    var isInRightEar: Bool { self == .projects }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .camera: "Camera"
        case .shelf: "File Shelf"
        case .projects: "Projects"
        }
    }
}
