import Foundation

/// Installs the `notchisland-notify` helper and zsh hook into ~/.notchisland,
/// and builds the snippets users paste into their shell and agent configs.
enum DevHooks {
    static var home: URL { DevActivityService.home }
    static var notifyScript: URL { home.appendingPathComponent("bin/notchisland-notify") }
    static var zshScript: URL { home.appendingPathComponent("notchisland.zsh") }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: notifyScript.path)
            && FileManager.default.fileExists(atPath: zshScript.path)
    }

    /// Copies the bundled scripts into ~/.notchisland, replacing older copies.
    static func install() throws {
        let fileManager = FileManager.default
        guard let notify = Bundle.main.url(forResource: "notchisland-notify", withExtension: "sh"),
              let zsh = Bundle.main.url(forResource: "notchisland", withExtension: "zsh")
        else { throw CocoaError(.fileNoSuchFile) }

        try fileManager.createDirectory(at: notifyScript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: DevActivityService.inbox, withIntermediateDirectories: true)
        for (source, destination) in [(notify, notifyScript), (zsh, zshScript)] {
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.copyItem(at: source, to: destination)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notifyScript.path)
    }

    static var zshSnippet: String {
        "source ~/.notchisland/notchisland.zsh"
    }

    /// Hooks for ~/.claude/settings.json.
    static var claudeSnippet: String {
        let command = "~/.notchisland/bin/notchisland-notify --claude"
        let hook = #"[{ "hooks": [{ "type": "command", "command": "\#(command)" }] }]"#
        return """
        "hooks": {
          "UserPromptSubmit": \(hook),
          "Stop": \(hook),
          "Notification": \(hook)
        }
        """
    }

    /// Line for ~/.codex/config.toml. Codex doesn't expand `~`.
    static var codexSnippet: String {
        #"notify = ["\#(notifyScript.path)", "--codex"]"#
    }
}
