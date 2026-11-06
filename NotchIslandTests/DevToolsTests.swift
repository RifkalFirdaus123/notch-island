import AppKit
import Foundation
import Testing
@testable import NotchIsland

struct DevToolkitTests {
    @Test(arguments: [
        ("https://example.com/a?b=1", ClipKind.url),
        ("{\"a\": [1, 2]}", .json),
        ("[1, 2, 3]", .json),
        ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.sig", .jwt),
        ("3F2504E0-4F89-11D3-9A0C-0305E82C3301", .uuid),
        ("#ff8800", .color),
        ("#FFF", .color),
        ("1700000000", .timestamp),
        ("1700000000123", .timestamp),
        ("42", .number),
        ("aGVsbG8gd29ybGQgZnJvbSBub3RjaA==", .base64),
        ("just some words", .text),
        ("{ not json", .text),
    ])
    func detectsKind(text: String, expected: ClipKind) {
        #expect(DevToolkit.kind(of: text) == expected)
    }

    @Test func base64RoundTrip() {
        let encoded = DevToolkit.base64Encode("héllo wörld")
        #expect(DevToolkit.base64Decode(encoded) == "héllo wörld")
        // URL-safe without padding.
        #expect(DevToolkit.base64Decode("aGk") == "hi")
    }

    @Test func urlRoundTrip() {
        let encoded = DevToolkit.urlEncode("a b&c=d/é")
        #expect(encoded == "a%20b%26c%3Dd%2F%C3%A9")
        #expect(DevToolkit.urlDecode(encoded) == "a b&c=d/é")
        #expect(DevToolkit.urlDecode("a+b") == "a b")
    }

    @Test func jsonFormatAndMinify() {
        #expect(DevToolkit.minifyJSON("{ \"b\": 1,\n \"a\": \"x/y\" }") == "{\"a\":\"x/y\",\"b\":1}" ||
                DevToolkit.minifyJSON("{ \"b\": 1,\n \"a\": \"x/y\" }") == "{\"b\":1,\"a\":\"x/y\"}")
        #expect(DevToolkit.formatJSON("{\"b\":1,\"a\":2}") == "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
        #expect(DevToolkit.formatJSON("nope") == nil)
        #expect(DevToolkit.formatJSON("\"just a string\"") == nil)
    }

    @Test func decodesJWT() throws {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.sig"
        let decoded = try #require(DevToolkit.decodeJWT(token))
        #expect(decoded.contains("\"alg\" : \"HS256\""))
        #expect(decoded.contains("\"name\" : \"John\""))
        #expect(DevToolkit.decodeJWT("a.b.c") == nil)
    }

    @Test func timestamps() {
        #expect(DevToolkit.timestampDate("1700000000") == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(DevToolkit.timestampDate("1700000000500") == Date(timeIntervalSince1970: 1_700_000_000.5))
        #expect(DevToolkit.timestampDate("0000000001") == nil)
        #expect(DevToolkit.timestampDate("12345") == nil)
    }

    @Test func hexColors() throws {
        let orange = try #require(DevToolkit.rgba(fromHex: "#ff8800"))
        #expect(orange.r == 1 && orange.b == 0 && orange.a == 1)
        let short = try #require(DevToolkit.rgba(fromHex: "#0f08"))
        #expect(short.g == 1 && abs(short.a - 136.0 / 255) < 0.001)
        #expect(DevToolkit.rgba(fromHex: "#12345") == nil)
    }

    @Test func hashes() {
        #expect(DevToolkit.hash("abc", with: .md5) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(DevToolkit.hash("abc", with: .sha1) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(DevToolkit.hash("abc", with: .sha256) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(DevToolkit.hash("abc", with: .sha512).hasPrefix("ddaf35a193617aba"))
    }
}

struct PortsParsingTests {
    @Test func groupsSocketsByProcessAndPort() {
        let output = """
        p705
        crapportd
        f10
        n*:60866
        p749
        cControlCenter
        f10
        n*:7000
        f11
        n[::1]:7000
        f12
        n127.0.0.1:5000
        p1234
        cnode
        f20
        n127.0.0.1:3000
        """
        let ports = PortsService.parse(lsofOutput: output)
        #expect(ports.map(\.port) == [3000, 5000, 7000, 60866])
        let airplay = ports.first { $0.port == 7000 }
        #expect(airplay?.command == "ControlCenter")
        #expect(airplay?.addresses == ["*", "::1"])
        #expect(ports.first?.pid == 1234)
        #expect(ports.first?.command == "node")
    }

    @Test func parsesWorkingDirectories() {
        let output = "p1234\nfcwd\nn/Users/me/web app\np99\nfcwd\nn/\n"
        let dirs = PortsService.parseDirectories(lsofOutput: output)
        #expect(dirs[1234] == "/Users/me/web app")
        #expect(dirs[99] == "/")
    }
}

struct DevActivityParsingTests {
    @Test func terminalEvent() throws {
        let event = try #require(DevEvent.parse([
            "source": "terminal", "status": "fail", "title": "npm test", "detail": "exit 1 · 12s",
            "cwd": "/Users/me/app", "time": "1700000000",
        ]))
        #expect(event.status == .failure)
        #expect(event.title == "npm test")
        #expect(event.projectName == "app")
        #expect(event.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!event.isAgent)
    }

    @Test func claudeHooks() throws {
        func claude(_ json: String) -> DevEvent? {
            DevEvent.parse(["source": "claude", "payload": json, "cwd": "/tmp"])
        }
        let stop = try #require(claude(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/Users/me/api"}"#))
        #expect(stop.status == .success)
        #expect(stop.directory == "/Users/me/api")
        #expect(stop.sessionID == "s1")

        let ask = try #require(claude(#"{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}"#))
        #expect(ask.status == .attention)
        #expect(ask.title == "Claude needs your permission to use Bash")

        let working = try #require(claude(#"{"hook_event_name":"UserPromptSubmit","prompt":"fix\nthe bug"}"#))
        #expect(working.status == .working)
        #expect(working.detail == "fix the bug")

        #expect(claude(#"{"hook_event_name":"SubagentStop"}"#) == nil)
    }

    @Test func codexNotify() throws {
        let done = try #require(DevEvent.parse([
            "source": "codex",
            "payload": #"{"type":"agent-turn-complete","last-assistant-message":"All tests pass.","cwd":"/Users/me/x"}"#,
        ]))
        #expect(done.status == .success)
        #expect(done.detail == "All tests pass.")
        #expect(DevEvent.parse(["source": "codex", "payload": #"{"type":"other"}"#]) == nil)
    }

    @Test func ignoresEmptyEvents() {
        #expect(DevEvent.parse(["source": "terminal", "title": "  "]) == nil)
    }

    @Test func findsAgentProcesses() {
        let output = """
          6664 02-05:42:20 /Applications/Claude.app/Contents/MacOS/Claude
         48396 02-04:59:29 /Users/me/Library/Application Support/Claude/claude-code/2.1/claude.app/Contents/MacOS/claude
         55900       46:37 /Users/me/.vscode/extensions/openai.chatgpt/bin/codex
           123       00:09 /bin/zsh
        """
        let agents = DevActivityService.parseAgents(psOutput: output)
        #expect(agents.map(\.name) == ["Claude Code", "Codex"])
        #expect(agents.map(\.elapsed) == ["2d 4h", "46m"])
    }

    @Test func formatsElapsed() {
        #expect(DevActivityService.formatElapsed("01:02:03") == "1h 2m")
        #expect(DevActivityService.formatElapsed("00:09") == "9s")
    }
}

@MainActor
struct ClipboardPinTests {
    private func makeService(store: PinnedClipStore = MemoryPinnedClipStore()) -> ClipboardService {
        ClipboardService(pasteboard: NSPasteboard(name: .init("NotchIslandTests-\(UUID())")), pinnedStore: store)
    }

    @Test func pinMovesItemOutOfHistory() throws {
        let clipboard = makeService()
        clipboard.insert("one")
        clipboard.insert("two")
        let two = try #require(clipboard.items.first)
        clipboard.pin(two)
        #expect(clipboard.pinned.map(\.text) == ["two"])
        #expect(clipboard.items.map(\.text) == ["one"])
        // Copying it again doesn't list it twice.
        clipboard.insert("two")
        #expect(clipboard.items.map(\.text) == ["one"])
    }

    @Test func clearKeepsPinned() throws {
        let clipboard = makeService()
        clipboard.insert("keep")
        clipboard.pin(try #require(clipboard.items.first))
        clipboard.insert("drop")
        clipboard.clear()
        #expect(clipboard.items.isEmpty)
        #expect(clipboard.pinned.map(\.text) == ["keep"])
    }

    @Test func pinnedSurviveHistoryLimit() throws {
        let clipboard = makeService()
        clipboard.insert("pinned")
        clipboard.pin(try #require(clipboard.items.first))
        for i in 0..<(ClipboardService.maxItems + 5) { clipboard.insert("item \(i)") }
        #expect(clipboard.items.count == ClipboardService.maxItems)
        #expect(clipboard.pinned.map(\.text) == ["pinned"])
    }

    @Test func unpinReturnsToTopOfHistory() throws {
        let clipboard = makeService()
        clipboard.insert("a")
        let a = try #require(clipboard.items.first)
        clipboard.pin(a)
        clipboard.insert("b")
        clipboard.unpin(a)
        #expect(clipboard.pinned.isEmpty)
        #expect(clipboard.items.map(\.text) == ["a", "b"])
    }

    @Test func pinnedArePersisted() throws {
        let store = MemoryPinnedClipStore()
        let first = makeService(store: store)
        first.insert("{\"a\":1}")
        first.pin(try #require(first.items.first))

        let second = makeService(store: store)
        #expect(second.pinned.map(\.text) == ["{\"a\":1}"])
        #expect(second.pinned.first?.kind == .json)
        #expect(second.items.isEmpty)
    }

    @Test func labelingPinsAndPersists() throws {
        let store = MemoryPinnedClipStore()
        let clipboard = makeService(store: store)
        clipboard.insert("s3cr3t-pa55")
        clipboard.setLabel("  Database password ", for: try #require(clipboard.items.first))
        #expect(clipboard.items.isEmpty)
        #expect(clipboard.pinned.first?.label == "Database password")
        #expect(clipboard.pinned.first?.text == "s3cr3t-pa55")

        let reloaded = makeService(store: store)
        #expect(reloaded.pinned.first?.label == "Database password")
    }

    @Test func renameAndRemoveLabel() throws {
        let clipboard = makeService()
        clipboard.insert("token")
        clipboard.setLabel("API token", for: try #require(clipboard.items.first))
        let item = try #require(clipboard.pinned.first)
        clipboard.setLabel("Staging token", for: item)
        #expect(clipboard.pinned.map(\.label) == ["Staging token"])
        clipboard.setLabel("", for: try #require(clipboard.pinned.first))
        // Still pinned, just unnamed.
        #expect(clipboard.pinned.count == 1)
        #expect(clipboard.pinned.first?.label == nil)
    }

    @Test func unpinKeepsLabel() throws {
        let clipboard = makeService()
        clipboard.insert("value")
        clipboard.setLabel("Name", for: try #require(clipboard.items.first))
        clipboard.unpin(try #require(clipboard.pinned.first))
        #expect(clipboard.pinned.isEmpty)
        #expect(clipboard.items.first?.label == "Name")
        #expect(clipboard.items.first?.text == "value")

        // Renaming in the history doesn't pin it again.
        clipboard.setLabel("Renamed", for: try #require(clipboard.items.first))
        #expect(clipboard.pinned.isEmpty)
        #expect(clipboard.items.first?.label == "Renamed")

        // Pinning again keeps the label.
        clipboard.pin(try #require(clipboard.items.first))
        #expect(clipboard.pinned.first?.label == "Renamed")
    }

    @Test func copyingAgainKeepsLabel() throws {
        let clipboard = makeService()
        clipboard.insert("secret")
        clipboard.setLabel("DB", for: try #require(clipboard.items.first))
        clipboard.unpin(try #require(clipboard.pinned.first))
        clipboard.insert("other")
        clipboard.insert("secret")
        #expect(clipboard.items.map(\.text) == ["secret", "other"])
        #expect(clipboard.items.first?.label == "DB")
    }

    @Test func labeledCopyIsConcealed() throws {
        let board = NSPasteboard(name: .init("NotchIslandTests-\(UUID())"))
        let clipboard = ClipboardService(pasteboard: board, pinnedStore: MemoryPinnedClipStore())
        clipboard.insert("hunter2")
        clipboard.setLabel("DB", for: try #require(clipboard.items.first))
        clipboard.copy(try #require(clipboard.pinned.first))
        #expect(board.string(forType: .string) == "hunter2")
        #expect(board.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
    }
}
