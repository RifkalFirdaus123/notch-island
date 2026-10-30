import Foundation
import Testing
@testable import NotchIsland

struct StorageTests {
    private let caches = URL(fileURLWithPath: "/Users/me/Library/Caches", isDirectory: true)

    @Test func itemsBelowTheFolderAreInside() {
        #expect(StorageService.isInside(caches.appendingPathComponent("com.app"), caches))
        #expect(StorageService.isInside(caches.appendingPathComponent("a/b/c"), caches))
    }

    @Test func theFolderItselfIsNotInside() {
        #expect(!StorageService.isInside(caches, caches))
        #expect(!StorageService.isInside(URL(fileURLWithPath: "/Users/me/Library/Caches/"), caches))
    }

    @Test func siblingsAndParentsAreNotInside() {
        #expect(!StorageService.isInside(URL(fileURLWithPath: "/Users/me/Library/CachesOld/x"), caches))
        #expect(!StorageService.isInside(URL(fileURLWithPath: "/Users/me/Library"), caches))
        #expect(!StorageService.isInside(caches.appendingPathComponent("../Preferences"), caches))
    }

    @Test func measuresFilesAndFolders() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageTests-\(UUID().uuidString)", isDirectory: true)
        let sub = folder.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appendingPathComponent("a.bin")
        try Data(count: 100_000).write(to: file)
        try Data(count: 50_000).write(to: sub.appendingPathComponent("b.bin"))

        let fileSize = try #require(FolderSizer.allocatedSize(of: file))
        let total = try #require(FolderSizer.allocatedSize(of: folder))
        #expect(fileSize >= 100_000)
        #expect(total >= 150_000)
        #expect(total > fileSize)

        let children = try #require(FolderSizer.children(of: folder))
        #expect(Set(children.map(\.name)) == ["a.bin", "sub"])
        #expect(children.first { $0.name == "sub" }?.isFolder == true)
        #expect(children.first { $0.name == "a.bin" }?.isFolder == false)
    }

    @Test func missingFolderHasNoSize() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(FolderSizer.allocatedSize(of: missing) == nil)
        #expect(FolderSizer.children(of: missing) == nil)
    }
}
