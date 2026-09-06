import HealthKit
import XCTest
@testable import Body

final class WorkoutAnchoredQueryTests: XCTestCase {
    private func engine(_ fake: FakeHealthStore) -> HealthKitFetchEngine {
        .init(permission: .init(enabledPermissions: [.workouts]), healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .defaultValue, combinesHealthDataSourcesByName: false,
            healthStore: fake, effortLedgerDirectoryURL: nil)
    }

    func testScriptedAdditionDeletionEmptyFailureAndCancellationAreDistinct() async throws {
        let fake = FakeHealthStore(), date = Date(timeIntervalSince1970: 1000)
        let workout = HKWorkout(activityType: .running, start: date, end: date.addingTimeInterval(60))
        let bytes = try NSKeyedArchiver.archivedData(withRootObject: HKQueryAnchor(fromValue: 1), requiringSecureCoding: true)
        let deleted = UUID()
        fake.scriptWorkoutChanges([
            .success(.init(workouts: [workout], deletedIDs: [deleted], anchor: bytes)),
            .success(.init(workouts: [], deletedIDs: [], anchor: bytes)), .failure(nil), .cancelled
        ])
        let engine = engine(fake)
        let request = BodyWorkoutChangesRequest(lowerBound: date, anchor: nil, limit: 100)
        guard case .success(let batch) = await engine.fetchWorkoutChanges(request) else { return XCTFail() }
        XCTAssertEqual(batch.workouts.map(\.uuid), [workout.uuid])
        XCTAssertEqual(batch.deletedIDs, [deleted])
        XCTAssertNotNil(try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: batch.anchor))
        guard case .success(let empty) = await engine.fetchWorkoutChanges(request) else { return XCTFail() }
        XCTAssertTrue(empty.workouts.isEmpty && empty.deletedIDs.isEmpty)
        guard case .failure = await engine.fetchWorkoutChanges(request) else { return XCTFail() }
        guard case .cancelled = await engine.fetchWorkoutChanges(request) else { return XCTFail() }
        XCTAssertEqual(fake.workoutChangeRequests, Array(repeating: request, count: 4))
    }

    func testSuspendedAnchoredReadCancels() async throws {
        let fake = FakeHealthStore()
        let observedEngine = self.engine(fake)
        let task = Task { await observedEngine.fetchWorkoutChanges(.init(lowerBound: .distantPast, anchor: nil, limit: 100)) }
        for _ in 0..<100 where fake.workoutChangeRequests.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertEqual(fake.workoutChangeRequests.count, 1)
        task.cancel()
        guard case .cancelled = await task.value else { return XCTFail() }
    }

    func testNativeSeamRejectsMalformedAnchorAndUnboundedRequestBeforeExecuting() async {
        let store = HKHealthStore()
        let invalid = await store.workoutChanges(.init(lowerBound: .distantPast, anchor: Data([1, 2, 3]), limit: 100))
        guard case .failure(let error) = invalid,
              case .invalidArchive = error as? BodyWorkoutAnchorError else { return XCTFail() }
        let unbounded = await store.workoutChanges(.init(lowerBound: .distantPast, anchor: nil, limit: 0))
        guard case .failure(let error) = unbounded,
              case .invalidRequest = error as? BodyWorkoutAnchorError else { return XCTFail() }
    }
}
