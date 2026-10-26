import SwiftUI

@main
struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The island lives in an NSPanel owned by AppDelegate; the settings
        // window is filled in during phase 7.
        Settings {
            EmptyView()
        }
    }
}
