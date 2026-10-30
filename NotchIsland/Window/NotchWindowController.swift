import AppKit
import Combine
import SwiftUI

/// Owns the notch panel: positions it over the notch, detects hover, and
/// drives `IslandViewModel.state`.
///
/// Hover is detected with global/local mouse monitors rather than an
/// NSTrackingArea, because the panel ignores mouse events while collapsed
/// (so clicks reach the menu bar) and tracking areas need the window to
/// receive events. Mouse-moved monitoring needs no extra permission.
@MainActor
final class NotchWindowController {
    private static let expandDelay: Duration = .milliseconds(500)
    private static let collapseDelay: Duration = .milliseconds(400)
    private static let fullscreenCheckDelay: RunLoop.SchedulerTimeType.Stride = .milliseconds(600)
    /// Extra room around the expanded shape for the top flares and shadow.
    private static let windowMargin = CGSize(width: 80, height: 40)
    /// Tolerance around the shape so the edge doesn't flicker.
    private static let hitSlop: CGFloat = 6
    /// How far around the notch a dragged file opens the shelf.
    private static let dropApproachSlop = CGSize(width: 60, height: 40)
    /// Pointer polling interval while the mouse button is held.
    private static let dragPollInterval: Duration = .milliseconds(50)

    private let viewModel: IslandViewModel
    private let panel: NotchPanel
    private var eventMonitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var expandTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    /// Watches the pointer while the mouse button is held, see `watchForDrag`.
    private var dragWatchTask: Task<Void, Never>?
    /// Drag pasteboard change count at the last mouse down; a change while
    /// dragging means a real drag-and-drop session (not a window drag).
    private var dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    /// The last mouse down was inside the open panel, e.g. to drag a shelf
    /// item out, so the panel must stay put until the button is released.
    private var mouseDownInPanel = false

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        panel = NotchPanel(contentRect: .zero)
        panel.acceptsMouseMovedEvents = true

        let hostingView = IslandHostingView(rootView: IslandView(viewModel: viewModel))
        // The panel has a fixed size; SwiftUI animates the shape inside it.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
    }

    func start() {
        viewModel.$state
            .sink { [weak self] state in
                // Only intercept clicks while open; otherwise the menu bar
                // under the panel keeps working.
                self?.panel.ignoresMouseEvents = !state.isOpen
            }
            .store(in: &cancellables)

        // Show or hide the lyric strip and now-playing row while idle.
        viewModel.$lyricLine
            .map { $0 != nil }
            .removeDuplicates()
            .combineLatest(viewModel.nowPlaying.$info.map { $0?.isPlaying == true }.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.viewModel.state.isOpen else { return }
                self.viewModel.state = self.viewModel.idleState
            }
            .store(in: &cancellables)

        reposition()
        observeSystemChanges()
        installMouseMonitors()
    }

    // MARK: - Positioning

    private func reposition() {
        guard let screen = NotchGeometry.preferredScreen() else {
            panel.orderOut(nil)
            return
        }
        let geometry = NotchGeometry(screen: screen)
        viewModel.geometry = geometry

        // Big enough for the expanded panel and the widest lyric strip. The
        // transparent parts let clicks through.
        let expanded = viewModel.size(for: .expanded)
        let windowSize = CGSize(
            width: max(expanded.width, viewModel.maxLyricWidth) + Self.windowMargin.width,
            height: expanded.height + Self.windowMargin.height
        )
        panel.setFrame(geometry.topCenteredRect(size: windowSize), display: true)
        updateFullscreenSuppression()
    }

    private func observeSystemChanges() {
        let workspace = NSWorkspace.shared.notificationCenter

        // Displays plugged/unplugged, resolution changes, and wake from sleep.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didWakeNotification))
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        // Entering/leaving fullscreen changes the active space; wait for the
        // transition animation before checking window sizes.
        workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didActivateApplicationNotification))
            .debounce(for: Self.fullscreenCheckDelay, scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateFullscreenSuppression() }
            .store(in: &cancellables)

        // Settings changed: fullscreen option, enabled tabs, strip height.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.viewModel.validateSelectedTab()
                self.viewModel.objectWillChange.send()
                self.updateFullscreenSuppression()
            }
            .store(in: &cancellables)
    }

    // MARK: - Fullscreen

    private func updateFullscreenSuppression() {
        let showInFullscreen = UserDefaults.standard.bool(forKey: SettingsKeys.showInFullscreen)
        let suppressed = !showInFullscreen && isFrontmostAppFullscreen()
        viewModel.isSuppressed = suppressed
        if suppressed {
            collapseNow()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// True when the frontmost app has a normal-level window covering the
    /// whole screen. Window bounds don't require screen recording permission.
    private func isFrontmostAppFullscreen() -> Bool {
        guard let geometry = viewModel.geometry,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]]
        else { return false }

        return windows.contains { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return false }
            return bounds.size == geometry.screenFrame.size
        }
    }

    // MARK: - Hover

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            eventMonitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        guard !viewModel.isSuppressed, viewModel.geometry != nil else { return }
        let point = NSEvent.mouseLocation
        let inside = activeRegion().contains(point)

        switch event.type {
        case .leftMouseDown:
            dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            mouseDownInPanel = inside && viewModel.state.isOpen
            // Clicking elsewhere closes the panel immediately.
            if !inside && viewModel.state.isOpen { collapseNow() }
            watchForDrag()
        default:
            if inside { pointerEntered() } else { pointerExited() }
        }
    }

    /// While another app runs a drag-and-drop session (e.g. a file dragged
    /// from Finder), the system drag loop swallows the drag events, so global
    /// monitors never see them. Poll the pointer instead, only while the
    /// button is held.
    private func watchForDrag() {
        dragWatchTask?.cancel()
        dragWatchTask = Task { @MainActor [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0, !Task.isCancelled {
                self?.dragMoved(to: NSEvent.mouseLocation)
                try? await Task.sleep(for: Self.dragPollInterval)
            }
        }
    }

    private func dragMoved(to point: CGPoint) {
        guard !viewModel.isSuppressed, viewModel.geometry != nil else { return }
        // Ignore window moves and text selection: only real drag-and-drop
        // sessions write to the drag pasteboard.
        guard NSPasteboard(name: .drag).changeCount != dragChangeCountAtMouseDown else { return }
        guard UserDefaults.standard.bool(forKey: SettingsKeys.featureShelf) || viewModel.state.isOpen else { return }
        if dropRegion().contains(point) { openForDrop() } else { pointerExited() }
    }

    /// Like `activeRegion`, but more generous around the idle notch so a file
    /// dragged *toward* it opens the shelf.
    private func dropRegion() -> CGRect {
        guard let geometry = viewModel.geometry, !viewModel.state.isOpen else { return activeRegion() }
        return geometry.notchRect.insetBy(dx: -Self.dropApproachSlop.width, dy: -Self.dropApproachSlop.height)
    }

    private func openForDrop() {
        collapseTask?.cancel()
        collapseTask = nil
        expandTask?.cancel()
        // Our own shelf items dragged around inside the panel shouldn't
        // switch tabs.
        if !mouseDownInPanel, viewModel.enabledTabs.contains(.shelf) { viewModel.select(.shelf) }
        if viewModel.state != .expanded { viewModel.state = .expanded }
    }

    /// Region that counts as "on the island": the notch (plus the now-playing
    /// row beside it) while idle, the visible shape while open.
    private func activeRegion() -> CGRect {
        guard let geometry = viewModel.geometry else { return .zero }
        let rect: CGRect
        switch viewModel.state {
        case .hover, .expanded: rect = viewModel.screenRect(for: viewModel.state)
        // Not the lyric strip itself, so it doesn't open while reading.
        case .playing, .lyric: rect = viewModel.screenRect(for: .playing)
        case .collapsed: rect = geometry.notchRect
        }
        // Negative inset also extends past the top edge, so the topmost
        // pixel row is inside.
        return rect.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop)
    }

    private func pointerEntered() {
        collapseTask?.cancel()
        collapseTask = nil
        guard !viewModel.state.isOpen else { return }

        viewModel.state = .hover
        expandTask?.cancel()
        expandTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.expandDelay)
            guard !Task.isCancelled, let self, self.viewModel.state == .hover else { return }
            self.viewModel.state = .expanded
        }
    }

    private func pointerExited() {
        guard viewModel.state.isOpen, collapseTask == nil else { return }
        expandTask?.cancel()
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.collapseDelay)
            // Closing mid-drag would tear down the item being dragged out.
            while let self, self.mouseDownInPanel, NSEvent.pressedMouseButtons & 1 != 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            self?.collapseNow()
        }
    }

    private func collapseNow() {
        expandTask?.cancel()
        collapseTask?.cancel()
        collapseTask = nil
        let idle = viewModel.idleState
        if viewModel.state != idle {
            viewModel.state = idle
        }
    }
}

/// Lets the first click on the (never key) panel hit SwiftUI controls.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
