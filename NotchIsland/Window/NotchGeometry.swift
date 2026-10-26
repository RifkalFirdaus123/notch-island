import AppKit

/// Size and position of the physical notch on a screen, in screen coordinates
/// (origin bottom-left, as AppKit uses).
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchSize: CGSize
    var hasNotch: Bool

    /// Used on screens without a notch (external monitors).
    static let fallbackNotchWidth: CGFloat = 180

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: topInset)
        } else {
            hasNotch = false
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: Self.fallbackNotchWidth, height: max(menuBarHeight, 24))
        }
    }

    /// Rect of a shape of `size` hanging from the top center of the screen.
    func topCenteredRect(size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The physical notch rect.
    var notchRect: CGRect { topCenteredRect(size: notchSize) }

    /// The screen whose notch we should use: the built-in display if present.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
