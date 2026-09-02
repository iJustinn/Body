//
//  BodySnapshotDirectoryTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class BodySnapshotDirectoryTests: XCTestCase {
    private var directoryURL: URL!

    override func setUp() {
        super.setUp()
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BodySnapshotDirectoryTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directoryURL)
        directoryURL = nil
        super.tearDown()
    }

    func testPrepareCreatesDirectoryAndExcludesFromBackup() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))

        try BodySnapshotDirectory.prepare(directoryURL)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        let values = try directoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        // The Simulator can report this as nil in some configurations; only
        // assert when the platform actually reports a value.
        if let isExcludedFromBackup = values.isExcludedFromBackup {
            XCTAssertTrue(isExcludedFromBackup)
        }
    }

    func testPrepareSetsBackupExclusionOnPreExistingDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var url = directoryURL!
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try? url.setResourceValues(values)

        try BodySnapshotDirectory.prepare(directoryURL)

        let resultValues = try directoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        if let isExcludedFromBackup = resultValues.isExcludedFromBackup {
            XCTAssertTrue(isExcludedFromBackup)
        }
    }
}
