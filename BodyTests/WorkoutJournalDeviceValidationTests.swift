import HealthKit
import XCTest
@testable import Body

/// Explicitly opted in on a physical device only. Never part of ordinary gates.
/// Keeps the exact workout archive before saving; retries refuse a second workout.
final class WorkoutJournalDeviceValidationTests: XCTestCase {
    func testApprovedHistoricalAdditionAndDeletion() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires an explicitly approved physical device run")
        #else
        guard ProcessInfo.processInfo.environment["BODY_APPROVED_WORKOUT_MUTATION"] == "RP03_ONE_WORKOUT" else {
            throw XCTSkip("Requires explicit approval for one temporary workout")
        }
        let store = HKHealthStore()
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [HKObjectType.workoutType()])
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw ValidationError.writePermissionRequired
        }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RP03DeviceValidation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excludedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
        let marker = directory.appendingPathComponent("approved-workout.archive")
        guard !FileManager.default.fileExists(atPath: marker.path) else {
            // Retain this receipt even after success. Never silently repeat a mutation.
            throw ValidationError.existingReceiptRequiresReview
        }
        let start = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -30, to: Date()))
        // The legacy initializer deliberately allows archiving the exact UUID BEFORE
        // HealthKit receives a write. No energy, distance, route, or samples are added.
        let workout = HKWorkout(activityType: .other, start: start, end: start.addingTimeInterval(60),
            workoutEvents: nil, totalEnergyBurned: nil, totalDistance: nil,
            metadata: [HKMetadataKeyWorkoutBrandName: "Body RP03 validation",
                       "BodyRP03Validation": "one approved temporary workout"])
        let engine = HealthKitFetchEngine(permission: .init(enabledPermissions: [.workouts]),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: store, effortLedgerDirectoryURL: nil)
        let file = directory.appendingPathComponent("journal.json")
        let owner = WorkoutJournalReconciler(engine: engine, file: file)
        try await drain(owner)
        let baseline = await owner.snapshot()
        let archive = try NSKeyedArchiver.archivedData(withRootObject: workout, requiringSecureCoding: true)
        try archive.write(to: marker, options: .atomic)
        var deleted = false
        do {
            try await store.save(workout)
            try await drain(owner)
            let added = await owner.snapshot()
            guard added.entries[workout.uuid.uuidString]?.start == start else {
                throw ValidationError.additionNotObserved
            }
            // Reconstruct the actor from disk, including its real archived HK anchor.
            // This is disk restoration, not a claim of process termination coverage.
            let restored = WorkoutJournalReconciler(engine: engine, file: file)
            let restoredState = await restored.snapshot()
            XCTAssertEqual(restoredState, added)
            try await store.delete(workout)
            deleted = true
            try await drain(restored)
            let removed = await restored.snapshot()
            guard removed.entries[workout.uuid.uuidString] == nil,
                  removed.dirtyIntervals[workout.uuid.uuidString] != nil else {
                throw ValidationError.deletionNotObserved
            }
            XCTAssertTrue(Set(baseline.entries.keys).isSubset(of: Set(removed.entries.keys)),
                "Existing membership changed during this controlled run; investigate concurrent HealthKit changes")
            let receipt = "Addition observed; disk restoration matched; exact workout deleted; deletion observed. UUID: \(workout.uuid)"
            try Data(receipt.utf8).write(to: directory.appendingPathComponent("result.txt"), options: .atomic)
            let attachment = XCTAttachment(string: receipt)
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            if !deleted {
                // Only the archived, newly constructed object can be deleted here.
                // A failed cleanup leaves the identity receipt for explicit recovery.
                do { try await store.delete(workout) }
                catch { XCTFail("Exact test workout cleanup requires review: \(workout.uuid); \(error)") }
            }
            throw error
        }
        #endif
    }

    /// Reads only the previously deleted validation workout's association predicate.
    /// No authorization changes, sample creation, deletion, or production cache writes.
    func testNativeWorkoutCumulativeNoDataErrorCode() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical HealthKit no-data probe only")
        #else
        guard ProcessInfo.processInfo.environment["BODY_APPROVED_WORKOUT_NODATA_PROBE"] == "1" else {
            throw XCTSkip("Requires an explicitly approved read-only device probe")
        }
        let directory = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask).first).appendingPathComponent("RP03DeviceValidation")
        let bytes = try Data(contentsOf: directory.appendingPathComponent("approved-workout.archive"))
        let workout = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: HKWorkout.self, from: bytes))
        let store = HKHealthStore()
        for identifier: HKQuantityTypeIdentifier in [.stepCount, .distanceWalkingRunning, .distanceCycling] {
            let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: identifier))
            let task = Task { await store.cumulativeQuantity(.init(quantityType: type,
                predicate: HKQuery.predicateForObjects(from: workout), options: .cumulativeSum)) }
            let result = await OneShotDeadlineRace.run(deadline: .seconds(20)) { await task.value }
            task.cancel()
            guard case .finished(.failure(let error)) = result, let error else {
                XCTFail("Expected native no-data error for \(identifier.rawValue)")
                continue
            }
            let native = error as NSError
            XCTAssertEqual(native.domain, HKErrorDomain)
            XCTAssertEqual(native.code, HKError.errorNoData.rawValue)
            let attachment = XCTAttachment(string: "\(identifier.rawValue): \(native.domain) code \(native.code)")
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        #endif
    }

    private enum ValidationError: Error {
        case writePermissionRequired, existingReceiptRequiresReview
        case additionNotObserved, deletionNotObserved, scanFailed
    }

    private func drain(_ owner: WorkoutJournalReconciler) async throws {
        // One bounded scan covers up to 8,000 deltas, ample for this reference device.
        guard await owner.scan(maxPages: 16, deadline: .seconds(120)) == .caughtUp else {
            throw ValidationError.scanFailed
        }
    }
}
