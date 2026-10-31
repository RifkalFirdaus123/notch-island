import SwiftUI

/// The single source of truth for what the island is showing.
enum IslandState: Equatable {
    /// Idle with no music: only the physical notch is visible.
    case collapsed
    /// Idle with music playing: artwork and an equalizer beside the notch.
    case playing
    /// Idle with pomodoro timer running.
    case pomodoro
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
    case pomodoro
    case camera
    case shelf
    case projects
    case storage

    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .pomodoro: "timer"
        case .camera: "camera.fill"
        case .shelf: "tray.full.fill"
        case .projects: "folder.fill"
        case .storage: "internaldrive.fill"
        }
    }

    /// The left ear fits up to three icons; remaining tabs sit in the right ear beside the title.
    var isInRightEar: Bool { self == .shelf || self == .projects || self == .storage }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .pomodoro: "Pomodoro"
        case .camera: "Camera"
        case .shelf: "File Shelf"
        case .projects: "Projects"
        case .storage: "Storage"
        }
    }
}
