import Foundation
import GRDB
import Testing
import ZIPFoundation
@testable import HorselyKit

/// Zależności zewnętrzne (GRDB, ZIPFoundation) rozwiązują się i działają na runnerze CI.
struct DependenciesSmokeTests {
    @Test func inMemoryDatabaseRunsSql() throws {
        let queue = try DatabaseQueue()
        let value = try queue.read { try Int.fetchOne($0, sql: "SELECT 1") }
        #expect(value == 1)
    }

    @Test func zipRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("a.txt")
        try "Horsely".write(to: source, atomically: true, encoding: .utf8)
        let archiveURL = directory.appendingPathComponent("kopia.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "a.txt", fileURL: source)

        let reopened = try Archive(url: archiveURL, accessMode: .read)
        #expect(reopened.contains { $0.path == "a.txt" })
    }

    @Test func kitReportsCoreVersion() {
        #expect(HorselyKit.appVersion == "2.0.1")
    }
}
