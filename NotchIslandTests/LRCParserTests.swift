import Testing
@testable import NotchIsland

struct LRCParserTests {
    @Test func parsesBasicLines() {
        let lines = LRCParser.parse("""
        [00:12.00]First line
        [00:17.20]Second line
        """)
        #expect(lines == [
            LyricLine(time: 12, text: "First line"),
            LyricLine(time: 17.2, text: "Second line"),
        ])
    }

    @Test func ignoresMetadataTags() {
        let lines = LRCParser.parse("""
        [ar:Artist]
        [ti:Title]
        [length:03:20]
        [00:01.00]Hello
        """)
        #expect(lines == [LyricLine(time: 1, text: "Hello")])
    }

    @Test func expandsMultipleTimestamps() {
        let lines = LRCParser.parse("[00:10.00][00:30.00]Chorus\n[00:20.00]Verse")
        #expect(lines.map(\.time) == [10, 20, 30])
        #expect(lines.map(\.text) == ["Chorus", "Verse", "Chorus"])
    }

    @Test func appliesOffsetFromAnywhereInFile() {
        // +500 ms shows lyrics half a second earlier.
        let lines = LRCParser.parse("[00:10.00]Line\n[offset:+500]")
        #expect(lines == [LyricLine(time: 9.5, text: "Line")])
    }

    @Test func clampsNegativeTimesToZero() {
        let lines = LRCParser.parse("[offset:1000]\n[00:00.50]Intro")
        #expect(lines.first?.time == 0)
    }

    @Test func keepsEmptyLinesAsGaps() {
        let lines = LRCParser.parse("[00:05.00]Sing\n[00:09.00]\n[00:12.00]Again")
        #expect(lines.map(\.text) == ["Sing", "", "Again"])
    }

    @Test(arguments: [
        ("01:02", 62.0),
        ("01:02.5", 62.5),
        ("01:02.50", 62.5),
        ("01:02.500", 62.5),
        ("01:02:50", 62.5),
        ("10:00.00", 600.0),
    ])
    func parsesTimestampFormats(tag: String, expected: Double) throws {
        let time = try #require(LRCParser.parseTimestamp(Substring(tag)))
        #expect(abs(time - expected) < 0.001)
    }

    @Test(arguments: ["ar:Someone", "by:me", "", "1a:00", ":12"])
    func rejectsNonTimestamps(tag: String) {
        #expect(LRCParser.parseTimestamp(Substring(tag)) == nil)
    }

    @Test func handlesWindowsLineEndings() {
        let lines = LRCParser.parse("[00:01.00]One\r\n[00:02.00]Two\r\n")
        #expect(lines.map(\.text) == ["One", "Two"])
    }

    @Test func findsLineAtTime() {
        let lines = [
            LyricLine(time: 5, text: "a"),
            LyricLine(time: 10, text: "b"),
            LyricLine(time: 15, text: "c"),
        ]
        #expect(LRCParser.lineIndex(at: 0, in: lines) == nil)
        #expect(LRCParser.lineIndex(at: 5, in: lines) == 0)
        #expect(LRCParser.lineIndex(at: 9.99, in: lines) == 0)
        #expect(LRCParser.lineIndex(at: 10, in: lines) == 1)
        #expect(LRCParser.lineIndex(at: 100, in: lines) == 2)
        #expect(LRCParser.lineIndex(at: 3, in: []) == nil)
    }
}
