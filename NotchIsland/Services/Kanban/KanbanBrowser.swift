import AppKit

/// Opens kanban.resam.id links in a tab that already shows the board, so
/// clicking cards doesn't pile up new tabs. Falls back to a new tab in the
/// default browser when none is open or the browser can't be scripted.
enum KanbanBrowser {
    static let host = "https://kanban.resam.id"

    private enum Family { case chromium, arc, safari }

    private static let browsers: [(bundleID: String, family: Family)] = [
        ("com.apple.Safari", .safari),
        ("com.google.Chrome", .chromium),
        ("company.thebrowser.Browser", .arc),
        ("com.brave.Browser", .chromium),
        ("com.microsoft.edgemac", .chromium),
    ]

    @MainActor
    static func open(_ url: URL) {
        let candidates = runningBrowsers()
        guard !candidates.isEmpty else {
            NSWorkspace.shared.open(url)
            return
        }
        Task {
            for browser in candidates {
                let result = await AppleScriptRunner.shared.run(
                    script(for: browser.family, bundleID: browser.bundleID, target: url.absoluteString),
                    cache: false
                ) { $0.booleanValue }
                if case .success(true) = result { return }
            }
            NSWorkspace.shared.open(url)
        }
    }

    /// Running supported browsers, the default browser first. Browsers that
    /// aren't running are skipped so scripting never launches one.
    private static func runningBrowsers() -> [(bundleID: String, family: Family)] {
        let running = browsers.filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty
        }
        let defaultID = NSWorkspace.shared.urlForApplication(toOpen: URL(string: host)!)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        return running.sorted { a, _ in a.bundleID == defaultID }
    }

    /// Returns true when it found a board tab, pointed it at `target` and
    /// brought it to the front.
    private static func script(for family: Family, bundleID: String, target: String) -> String {
        let host = host.appleScriptEscaped
        let target = target.appleScriptEscaped
        // Only navigate when the tab isn't already there, so it doesn't reload.
        let navigate = """
                        if (URL of t as text) is not "\(target)" then set URL of t to "\(target)"
        """
        switch family {
        case .chromium:
            return """
            tell application id "\(bundleID)"
                repeat with w in windows
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if (URL of t as text) starts with "\(host)" then
            \(navigate)
                            set active tab index of w to i
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case .arc:
            return """
            tell application id "\(bundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t as text) starts with "\(host)" then
            \(navigate)
                            tell t to select
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case .safari:
            return """
            tell application id "\(bundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t as text) starts with "\(host)" then
            \(navigate)
                            set current tab of w to t
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        }
    }
}
