//
//  BodyMetricWarningFetchTests.swift
//  BodyTests
//
//  The HealthKit read behind today's threshold warnings, shared by the
//  iPhone's `HealthKitFetchEngine` and the watch's own check
//  (`BodyMetricWarningFetch.todaysReadings`), driven against
//  `FakeHealthStore`. The engine tests pin the headless warning read end to
//  end, so the engine reads the same episode through the shared read as it
//  did through its own query; the descriptor rows the read takes its type,
//  unit and transform from are pinned to that former query. Also pinned: the
//  one day key both devices fold and notify under, and the max heart rate
//  the watch payload resolves High Heart Rate's default threshold from.
//

import XCTest
import HealthKit
@testable import Body

final class BodyMetricWarningFetchTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    private let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    // MARK: - Engine

    /// Low Heart Rate reads no workouts, so the whole read runs through the
    /// fake's scriptable leaves.
    func testEngineReadsTodaysLowHeartRateEpisode() async throws {
        let heartRate = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let fake = FakeHealthStore()
        fake.scriptSources(for: heartRate, .sources([]))
        fake.scriptSamples(for: heartRate, .samples([
            sample(heartRate, 52, endingAt: date(3)),
            sample(heartRate, 38, endingAt: date(3, 10)),
            sample(heartRate, 36, endingAt: date(3, 20)),
            sample(heartRate, 39, endingAt: date(3, 35)),
            sample(heartRate, 45, endingAt: date(3, 50)),
            // Over 30 minutes after the last low reading: a later episode.
            sample(heartRate, 35, endingAt: date(5))
        ]))
        let now = date(14)

        let results = await engine(fake).fetchCurrentMetricWarnings(kinds: [.lowHeartRate], calendar: calendar, now: now)

        guard case .success(let event?)? = results[.lowHeartRate] else {
            return XCTFail("readings under 40 bpm today are a warning")
        }
        XCTAssertEqual(event.kind, .lowHeartRate)
        XCTAssertEqual(event.startDate, date(3, 10))
        XCTAssertEqual(event.endDate, date(3, 35))
        XCTAssertEqual(event.extremeValue, 36)
        XCTAssertEqual(event.threshold, 40)
        XCTAssertEqual(event.sampleCount, 3)

        // Today's readings under the limit only, every one of them, by end date.
        let request = try XCTUnwrap(fake.sampleRequests.last)
        XCTAssertEqual(request.predicate, NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: calendar.startOfDay(for: now), end: now),
            HKQuery.predicateForQuantitySamples(
                with: .lessThan,
                quantity: HKQuantity(unit: beatsPerMinute, doubleValue: 40)
            )
        ]))
        XCTAssertEqual(request.limit, HKObjectQueryNoLimit)
        XCTAssertEqual(request.sortDescriptors.map(\.key), [HKSampleSortIdentifierEndDate])
        XCTAssertEqual(request.sortDescriptors.map(\.ascending), [true])
        XCTAssertEqual(fake.leafRequests, [.sources(heartRate.identifier), .samples(heartRate.identifier)])
        XCTAssertTrue(fake.executedQueries.isEmpty, "no raw query: Low Heart Rate reads no workouts")
    }

    func testEngineConfirmsNoLowHeartRateWhenNothingIsUnderTheLimit() async throws {
        let heartRate = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let fake = FakeHealthStore()
        fake.scriptSources(for: heartRate, .sources([]))
        fake.scriptSamples(for: heartRate, .samples([
            // A reading exactly at the limit never warns.
            sample(heartRate, 40, endingAt: date(3)),
            sample(heartRate, 58, endingAt: date(9))
        ]))

        let results = await engine(fake).fetchCurrentMetricWarnings(kinds: [.lowHeartRate], calendar: calendar, now: date(14))

        guard case .success(nil)? = results[.lowHeartRate] else {
            return XCTFail("a read with nothing under the limit confirms there is no warning")
        }
    }

    // MARK: - Shared read

    func testHeartRateAsksHealthKitForPastThresholdReadingsOnly() async throws {
        let heartRate = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let now = date(14)
        let sources = NSPredicate(format: "bundleIdentifier == %@", "com.example.ring")
        let cases: [(MetricWarningKind, NSComparisonPredicate.Operator, Double, [Double])] = [
            (.lowHeartRate, .lessThan, 40, [38, 36]),
            (.highHeartRate, .greaterThan, 120, [131, 128])
        ]

        for (kind, comparison, threshold, values) in cases {
            let fake = FakeHealthStore()
            // Any other predicate fails the read.
            fake.scriptSamples(for: heartRate, .failure(nil))
            fake.scriptSamples(for: heartRate, matching: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    HKQuery.predicateForSamples(withStart: calendar.startOfDay(for: now), end: now),
                    sources
                ]),
                HKQuery.predicateForQuantitySamples(
                    with: comparison,
                    quantity: HKQuantity(unit: beatsPerMinute, doubleValue: threshold)
                )
            ]), .samples([
                sample(heartRate, values[0], endingAt: date(9, 5)),
                sample(heartRate, values[1], endingAt: date(9, 10))
            ]))

            let outcome = await BodyMetricWarningFetch.todaysReadings(
                for: kind, store: fake, sourcePredicate: sources, threshold: threshold, now: now, calendar: calendar
            )

            guard case .success(let points) = outcome else {
                XCTFail("\(kind): today's past threshold readings under the selected sources")
                continue
            }
            XCTAssertEqual(points, [
                HealthTrendDataPoint(date: date(9, 5), value: values[0]),
                HealthTrendDataPoint(date: date(9, 10), value: values[1])
            ], "\(kind): dated at each sample's end")
            let request = try XCTUnwrap(fake.sampleRequests.last)
            XCTAssertEqual(request.limit, HKObjectQueryNoLimit, "\(kind)")
            XCTAssertEqual(request.sortDescriptors.map(\.key), [HKSampleSortIdentifierEndDate], "\(kind)")
            XCTAssertEqual(request.sortDescriptors.map(\.ascending), [true], "\(kind)")
        }
    }

    func testBloodOxygenComesBackAsAPercentFromTheWholeDay() async throws {
        let oxygen = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .oxygenSaturation))
        let fake = FakeHealthStore()
        fake.scriptSamples(for: oxygen, .samples([
            // Most sources write a fraction, some write 0 to 100.
            sample(oxygen, 0.88, unit: .percent(), endingAt: date(2)),
            sample(oxygen, 97, unit: .percent(), endingAt: date(3))
        ]))
        let now = date(14)

        let outcome = await BodyMetricWarningFetch.todaysReadings(
            for: .lowBloodOxygen, store: fake, sourcePredicate: nil, threshold: 90, now: now, calendar: calendar
        )

        guard case .success(let points) = outcome else {
            return XCTFail("a scripted day is a success")
        }
        XCTAssertEqual(points.map(\.date), [date(2), date(3)])
        for (value, expected) in zip(points.map(\.value), [88.0, 97]) {
            XCTAssertEqual(value, expected, accuracy: 1e-9)
        }
        // No threshold filter: a 0 to 100 source would never match one in the native unit.
        let window = HKQuery.predicateForSamples(withStart: calendar.startOfDay(for: now), end: now)
        XCTAssertEqual(fake.sampleRequests.last?.predicate, window)
    }

    func testWristTemperatureComesBackInCelsiusFromTheWholeDay() async throws {
        let temperature = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature))
        let fake = FakeHealthStore()
        fake.scriptSamples(for: temperature, .samples([
            sample(temperature, 100.4, unit: .degreeFahrenheit(), endingAt: date(4)),
            sample(temperature, 36.5, unit: .degreeCelsius(), endingAt: date(5))
        ]))
        let now = date(14)

        let outcome = await BodyMetricWarningFetch.todaysReadings(
            for: .highWristTemperature, store: fake, sourcePredicate: nil, threshold: 38, now: now, calendar: calendar
        )

        guard case .success(let points) = outcome else {
            return XCTFail("a scripted day is a success")
        }
        XCTAssertEqual(points.map(\.date), [date(4), date(5)])
        for (value, expected) in zip(points.map(\.value), [38.0, 36.5]) {
            XCTAssertEqual(value, expected, accuracy: 1e-9)
        }
        let window = HKQuery.predicateForSamples(withStart: calendar.startOfDay(for: now), end: now)
        XCTAssertEqual(fake.sampleRequests.last?.predicate, window)
    }

    func testAFailedReadIsAFailure() async throws {
        let heartRate = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let fake = FakeHealthStore()
        // HealthKit's "neither samples nor an error": a locked device.
        fake.scriptSamples(for: heartRate, .failure(nil))
        let recorder = FailureRecorder()

        let outcome = await BodyMetricWarningFetch.todaysReadings(
            for: .highHeartRate, store: fake, sourcePredicate: nil, threshold: 120, now: date(14), calendar: calendar,
            onFailure: { recorder.record($0) }
        )

        XCTAssertFalse(outcome.isSuccess, "a failed read must not read as a day without readings")
        XCTAssertEqual(recorder.count, 1)
    }

    func testNonFiniteReadingsAreDropped() async throws {
        let heartRate = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let fake = FakeHealthStore()
        fake.scriptSamples(for: heartRate, .samples([
            sample(heartRate, .nan, endingAt: date(9)),
            sample(heartRate, 131, endingAt: date(9, 5))
        ]))

        let outcome = await BodyMetricWarningFetch.todaysReadings(
            for: .highHeartRate, store: fake, sourcePredicate: nil, threshold: 120, now: date(14), calendar: calendar
        )

        guard case .success(let points) = outcome else {
            return XCTFail("a scripted day is a success")
        }
        XCTAssertEqual(points, [HealthTrendDataPoint(date: date(9, 5), value: 131)])
    }

    // MARK: - Descriptor parity

    /// The type, unit and transform each kind's read takes from
    /// `HealthMetricQueryDescriptor` are the ones the engine's own warning
    /// query used before it moved onto the shared read.
    func testEachKindReadsTheEnginesFormerTypeUnitAndTransform() throws {
        let expected: [MetricWarningKind: (HKQuantityTypeIdentifier, HKUnit)] = [
            .lowHeartRate: (.heartRate, beatsPerMinute),
            .highHeartRate: (.heartRate, beatsPerMinute),
            .lowBloodOxygen: (.oxygenSaturation, .percent()),
            .highRespiratoryRate: (.respiratoryRate, beatsPerMinute),
            .highWristTemperature: (.appleSleepingWristTemperature, .degreeCelsius())
        ]
        XCTAssertEqual(Set(expected.keys), Set(MetricWarningKind.allCases))

        for kind in MetricWarningKind.allCases {
            let descriptor = try XCTUnwrap(HealthMetricQueryDescriptor.descriptor(for: kind.metric), "\(kind)")
            let (identifier, unit) = try XCTUnwrap(expected[kind])
            XCTAssertEqual(descriptor.quantityType, identifier, "\(kind)")
            XCTAssertEqual(descriptor.unit, unit, "\(kind)")
            for value in [0.5, 0.88, 1, 36.6, 97, 131] {
                // Blood oxygen normalizes a fraction to a percentage; the rest read as is.
                let transformed = kind == .lowBloodOxygen ? BodyHealthQuantityFetch.normalizedPercent(value) : value
                XCTAssertEqual(descriptor.valueTransform(value), transformed, "\(kind) \(value)")
            }
        }
    }

    // MARK: - Day key

    /// The fold key, the notification identifier and the notification ledger
    /// all name a warning's day through `MetricWarningDayKey`, in the
    /// calendar's own time zone.
    func testFoldKeyNotificationIdentifierAndLedgerShareOneLocalDay() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let tenPastMidnight = try XCTUnwrap(tokyo.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 0, minute: 10)))
        let lateThatDay = try XCTUnwrap(tokyo.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 23, minute: 50)))
        let nextMorning = try XCTUnwrap(tokyo.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 0, minute: 5)))
        XCTAssertEqual(MetricWarningDayKey.dayText(for: tenPastMidnight, calendar: utc), "2026-10-04",
                       "still the day before in UTC, so the calendar's own zone decides")

        let event = warningEvent(.highHeartRate, startingAt: tenPastMidnight)
        XCTAssertEqual(MetricWarningDayKey.dayText(for: tenPastMidnight, calendar: tokyo), "2026-10-05")
        XCTAssertEqual(MetricWarningDayKey.foldKey(kind: .highHeartRate, startDate: tenPastMidnight, calendar: tokyo),
                       "highHeartRate@2026-10-05")
        XCTAssertEqual(BodyDismissedMetricWarnings.entryKey(for: event, calendar: tokyo), "highHeartRate@2026-10-05")
        XCTAssertEqual(MetricWarningDayKey.notificationIdentifier(kind: .highHeartRate, date: tenPastMidnight, calendar: tokyo),
                       "warning.highHeartRate.2026-10-05")
        XCTAssertEqual(MetricWarningBackgroundEvaluator.notificationIdentifier(for: .highHeartRate, date: tenPastMidnight, calendar: tokyo),
                       "warning.highHeartRate.2026-10-05")

        var ledger = MetricWarningNotificationLedger.defaultValue
        ledger.markNotified(kind: .highHeartRate, on: tenPastMidnight, calendar: tokyo)
        // The stored day is the same text the watch compares its own days with.
        XCTAssertEqual(ledger.lastNotifiedDayKeys[.highHeartRate], MetricWarningDayKey.dayText(for: tenPastMidnight, calendar: tokyo))
        XCTAssertEqual(MetricWarningNotificationLedger.storedValue(from: ledger.rawValue).lastNotifiedDayKeys[.highHeartRate],
                       "2026-10-05")
        XCTAssertFalse(ledger.shouldNotify(kind: .highHeartRate, event: warningEvent(.highHeartRate, startingAt: lateThatDay), calendar: tokyo))
        XCTAssertTrue(ledger.shouldNotify(kind: .highHeartRate, event: warningEvent(.highHeartRate, startingAt: nextMorning), calendar: tokyo))
    }

    // MARK: - Max heart rate

    func testMaxHeartRateIsStoredAsTwoHundredTwentyMinusAge() async throws {
        let defaults = try scratchDefaults()
        let engine = maxHeartRateEngine(BirthDateHealthStore(birthDate: birthDate), defaults: defaults)
        let now = try ageThirtySix()

        let maxHeartRate = await engine.userMaxHeartRate(asOf: now)

        XCTAssertEqual(maxHeartRate, 184)
        XCTAssertEqual(defaults.object(forKey: BodyAppearancePreference.warningMaxHeartRateKey) as? Double, 184)
    }

    func testMaxHeartRateIsStoredAsZeroWithoutAReadableBirthDate() async throws {
        let key = BodyAppearancePreference.warningMaxHeartRateKey

        let permissionOff = try scratchDefaults()
        XCTAssertNil(permissionOff.object(forKey: key), "absent until first resolved")
        let withoutBirthDatePermission = maxHeartRateEngine(
            BirthDateHealthStore(birthDate: birthDate), permissions: [.heart], defaults: permissionOff
        )
        let withPermissionOff = await withoutBirthDatePermission.userMaxHeartRate()
        XCTAssertNil(withPermissionOff)
        XCTAssertEqual(permissionOff.object(forKey: key) as? Double, 0)

        let noBirthDate = try scratchDefaults()
        let withoutBirthDate = maxHeartRateEngine(BirthDateHealthStore(birthDate: nil), defaults: noBirthDate)
        let withNoBirthDate = await withoutBirthDate.userMaxHeartRate()
        XCTAssertNil(withNoBirthDate)
        XCTAssertEqual(noBirthDate.object(forKey: key) as? Double, 0)
    }

    func testAnUnchangedMaxHeartRateIsNotWrittenAgain() async throws {
        let name = "BodyTests.WarningMaxHeartRate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(CountingDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let withoutBirthDate = maxHeartRateEngine(BirthDateHealthStore(birthDate: nil), defaults: defaults)

        _ = await withoutBirthDate.userMaxHeartRate()
        let firstWrites = defaults.writes
        XCTAssertGreaterThan(firstWrites, 0, "the first resolution is stored")
        _ = await withoutBirthDate.userMaxHeartRate()
        XCTAssertEqual(defaults.writes, firstWrites, "the same value is not written again")

        let withBirthDate = maxHeartRateEngine(BirthDateHealthStore(birthDate: birthDate), defaults: defaults)
        let now = try ageThirtySix()
        _ = await withBirthDate.userMaxHeartRate(asOf: now)
        XCTAssertGreaterThan(defaults.writes, firstWrites, "a changed value is stored")
        XCTAssertEqual(defaults.object(forKey: BodyAppearancePreference.warningMaxHeartRateKey) as? Double, 184)
    }

    // MARK: - Helpers

    /// Far from any year boundary, so the age can't depend on the time zone.
    private let birthDate = DateComponents(year: 1990, month: 6, day: 15)

    /// A day the user born on `birthDate` is 36, in the calendar
    /// `userMaxHeartRate` computes the age with.
    private func ageThirtySix() throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
    }

    /// 2026-10-05 at `hour`:`minute` in `calendar`'s time zone.
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute))!
    }

    private func sample(
        _ type: HKQuantityType,
        _ value: Double,
        unit: HKUnit? = nil,
        endingAt end: Date
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit ?? beatsPerMinute, doubleValue: value),
            start: end.addingTimeInterval(-30),
            end: end
        )
    }

    private func warningEvent(_ kind: MetricWarningKind, startingAt start: Date) -> MetricWarningEvent {
        MetricWarningEvent(kind: kind, startDate: start, endDate: start, extremeValue: 131, sampleCount: 1)
    }

    private func scratchDefaults() throws -> UserDefaults {
        let name = "BodyTests.WarningMaxHeartRate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// Heart only, default thresholds pinned (no `UserDefaults.standard` read
    /// decides the limit), no effort ledger on disk.
    private func engine(_ fake: FakeHealthStore) -> HealthKitFetchEngine {
        HealthKitFetchEngine(
            permission: .init(enabledPermissions: [.heart]),
            healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false,
            healthStore: fake,
            capturedWarningThresholds: .defaultValue,
            effortLedgerDirectoryURL: nil
        )
    }

    private func maxHeartRateEngine(
        _ store: any BodyHealthQuerying,
        permissions: Set<BodyHealthPermission> = [.heart, .dateOfBirth],
        defaults: UserDefaults
    ) -> HealthKitFetchEngine {
        HealthKitFetchEngine(
            permission: .init(enabledPermissions: permissions),
            healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false,
            healthStore: store,
            maxHeartRateDefaults: defaults,
            effortLedgerDirectoryURL: nil
        )
    }
}

/// `FakeHealthStore` can't script the birth date read, so these tests answer
/// it from an `HKHealthStore` that runs no queries; nothing else is read.
private final class BirthDateHealthStore: HKHealthStore, @unchecked Sendable {
    private let birthDate: DateComponents?

    init(birthDate: DateComponents?) {
        self.birthDate = birthDate
        super.init()
    }

    override func dateOfBirthComponents() throws -> DateComponents {
        guard let birthDate else {
            throw HKError(.errorNoData)
        }
        return birthDate
    }
}

/// Counts writes, so a value written again with the same contents shows.
private final class CountingDefaults: UserDefaults, @unchecked Sendable {
    private(set) var writes = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        writes += 1
        super.set(value, forKey: defaultName)
    }

    override func set(_ value: Double, forKey defaultName: String) {
        writes += 1
        super.set(value, forKey: defaultName)
    }
}

private final class FailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = 0

    func record(_ error: Error?) {
        lock.lock(); recorded += 1; lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }; return recorded
    }
}
