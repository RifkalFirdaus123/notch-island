import Foundation

nonisolated enum ScriptError: Error, Equatable {
    /// The user denied Automation permission (-1743).
    case notAuthorized
    /// The target app quit while we were talking to it (-600).
    case appNotRunning
    /// A Chromium browser refused `execute javascript`.
    case javascriptDisabled
    case failed(String)
}

/// Runs AppleScript off the main thread on one serial queue, so a slow app
/// never stalls the island's animations. NSAppleScript instances are only
/// ever touched on that queue.
nonisolated final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "NotchIsland.applescript", qos: .userInitiated)
    /// Compiled scripts for sources that run repeatedly (polling, state reads).
    private var compiled: [String: NSAppleScript] = [:]

    /// Runs `source` and converts the result with `parse`, which also runs on
    /// the script queue because descriptors aren't Sendable.
    func run<T: Sendable>(
        _ source: String,
        cache: Bool = true,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> T
    ) async -> Result<T, ScriptError> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.execute(source, cache: cache).map(parse))
            }
        }
    }

    /// Fire-and-forget command such as "playpause".
    func send(_ source: String) async {
        _ = await run(source, cache: false) { _ in () }
    }

    private func execute(_ source: String, cache: Bool) -> Result<NSAppleEventDescriptor, ScriptError> {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { return .failure(.failed("invalid script")) }
            var error: NSDictionary?
            if !fresh.compileAndReturnError(&error) {
                return .failure(Self.scriptError(from: error))
            }
            if cache { compiled[source] = fresh }
            script = fresh
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { return .failure(Self.scriptError(from: error)) }
        return .success(result)
    }

    private static func scriptError(from info: NSDictionary?) -> ScriptError {
        let number = info?[NSAppleScript.errorNumber] as? Int ?? 0
        let message = info?[NSAppleScript.errorMessage] as? String ?? ""
        switch number {
        case -1743: return .notAuthorized
        case -600, -609: return .appNotRunning
        default:
            if message.localizedCaseInsensitiveContains("JavaScript") { return .javascriptDisabled }
            return .failed("\(number): \(message)")
        }
    }
}

nonisolated extension NSAppleEventDescriptor {
    /// 1-based list item, as AppleScript counts.
    func item(_ index: Int) -> NSAppleEventDescriptor? {
        index <= numberOfItems ? atIndex(index) : nil
    }

    /// Text of a list item, treating `missing value` as empty.
    func string(at index: Int) -> String {
        guard let item = item(index), item.descriptorType != typeType else { return "" }
        return item.stringValue ?? ""
    }

    func double(at index: Int) -> Double {
        item(index)?.doubleValue ?? 0
    }
}

nonisolated extension String {
    /// Escapes text for use inside an AppleScript string literal.
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
