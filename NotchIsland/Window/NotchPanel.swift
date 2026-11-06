import AppKit

/// Borderless, non-activating panel that sits above the menu bar.
/// It only becomes key while a text field needs typing (the Hash input), so
/// the frontmost app otherwise keeps focus.
final class NotchPanel: NSPanel {
    /// Set while a view that takes keyboard input is on screen.
    var allowsKeyboard = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the menu bar (.mainMenu) so the island can cover the notch area.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true
        // Clicking buttons doesn't take focus; only text fields do.
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { allowsKeyboard }

    /// Makes the island panel key so a text field shown after a button
    /// click (e.g. the clipboard label editor) can take typing.
    static func focusForTyping() {
        guard let panel = NSApp.windows.first(where: { $0 is NotchPanel }) as? NotchPanel,
              panel.allowsKeyboard
        else { return }
        panel.makeKey()
    }

    /// The app never activates, so the Edit menu's shortcuts don't reach
    /// text fields here; route the common ones directly.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command || flags == [.command, .shift] {
            let action: Selector? = switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": #selector(NSText.paste(_:))
            case "c": #selector(NSText.copy(_:))
            case "x": #selector(NSText.cut(_:))
            case "a": #selector(NSText.selectAll(_:))
            case "z": flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
            default: nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
    override var canBecomeMain: Bool { false }

    // AppKit would otherwise push the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
