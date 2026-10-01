import HealthKit
import XCTest
@testable import Body

/// Opt-in simulator seeding: writes about 60 days of synthetic Apple Health data into
/// the simulator the test runs on, so Home, the trend cards, and the detail pages have
/// something to draw. Never part of ordinary gates: it skips outside the simulator and
/// without its environment flag.
///
/// Run it alone on the simulator to seed (the HealthKit share prompt appears in the
/// simulator; tap **Turn On All** and **Allow** while the test waits):
///
/// `TEST_RUNNER_BODY_SEED_SIMULATOR_HEALTH=1 PLANS=Body DEST='platform=iOS Simulator,name=iPhone Duo' ./test.sh -only-testing:BodyTests/SimulatorHealthSeedTests`
///
/// Wrist temperature and Apple Exercise Time are Apple-only types that no app may
/// write, so those cards stay empty. Running it twice adds a second copy of every sample. Erase the simulator (or delete
/// the app's data in the Health app) before seeding again.
final class SimulatorHealthSeedTests: XCTestCase {
    private struct Random {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15

        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }

        /// Uniform in `center ± spread`.
        mutating func around(_ center: Double, _ spread: Double) -> Double {
            center + (next() * 2 - 1) * spread
        }
    }

    private let dayCount = 60

    func testSeedsSimulatorHealthStore() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Seeds a simulator only")
        #else
        guard ProcessInfo.processInfo.environment["BODY_SEED_SIMULATOR_HEALTH"] == "1" else {
            throw XCTSkip("Set BODY_SEED_SIMULATOR_HEALTH=1 to seed the simulator's Health store")
        }

        let store = HKHealthStore()
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate,
            .oxygenSaturation, .bodyMass, .bodyFatPercentage, .stepCount, .activeEnergyBurned,
            .basalEnergyBurned, .timeInDaylight, .vo2Max, .distanceWalkingRunning
        ]
        var shareTypes = Set<HKSampleType>(quantityTypes.map { HKQuantityType($0) })
        shareTypes.insert(HKCategoryType(.sleepAnalysis))
        shareTypes.insert(HKObjectType.workoutType())

        try await store.requestAuthorization(toShare: shareTypes, read: [])
        // The share sheet is a manual tap in the simulator, so wait for it.
        let deadline = Date().addingTimeInterval(180)
        while store.authorizationStatus(for: HKQuantityType(.heartRate)) != .sharingAuthorized {
            guard Date() < deadline else {
                XCTFail("HealthKit sharing was not authorized within 3 minutes; tap Turn On All in the simulator")
                return
            }
            try await Task.sleep(for: .seconds(1))
        }

        let samples = makeSamples()
        try await store.save(samples)
        print("Seeded \(samples.count) Health samples over \(dayCount) days")
        #endif
    }

    private func makeSamples() -> [HKSample] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var random = Random()
        var samples: [HKSample] = []

        func quantity(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double, _ start: Date, _ end: Date? = nil) {
            samples.append(HKQuantitySample(
                type: HKQuantityType(id),
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: start,
                end: end ?? start
            ))
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())

        for dayOffset in 0..<dayCount {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            // Days from the oldest seeded day; the last stretch drifts so the trend
            // cards have something other than "stable" to say.
            let recentStrain = dayOffset < 10 ? Double(10 - dayOffset) / 10 : 0

            // Night before this day: stages from about 23:15 to 07:00.
            let bedtime = day.addingTimeInterval(-45 * 60 + random.around(0, 30 * 60))
            let wake = day.addingTimeInterval(7 * 3600 + random.around(0, 30 * 60))
            var cursor = bedtime
            var stageIndex = 0
            let stages: [HKCategoryValueSleepAnalysis] = [.asleepCore, .asleepDeep, .asleepCore, .asleepREM, .awake]
            while cursor < wake {
                let stage = stages[stageIndex % stages.count]
                let length = stage == .awake ? random.around(4 * 60, 2 * 60) : random.around(45 * 60, 20 * 60)
                let end = min(cursor.addingTimeInterval(length), wake)
                samples.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: stage.rawValue, start: cursor, end: end))
                cursor = end
                stageIndex += 1
            }

            // Overnight vitals, a few readings each.
            for reading in 0..<3 {
                let at = bedtime.addingTimeInterval(Double(reading + 1) * 2 * 3600)
                quantity(.heartRateVariabilitySDNN, .secondUnit(with: .milli), random.around(48 - 12 * recentStrain, 6), at)
                quantity(.respiratoryRate, bpm, random.around(14.5 + 0.8 * recentStrain, 0.6), at)
                quantity(.oxygenSaturation, .percent(), random.around(0.97, 0.01), at)
            }
            quantity(.restingHeartRate, bpm, random.around(56 + 5 * recentStrain, 2).rounded(), day.addingTimeInterval(6 * 3600))

            // Heart rate every 30 minutes: low asleep, higher awake.
            for slot in 0..<48 {
                let at = day.addingTimeInterval(Double(slot) * 30 * 60)
                let asleep = at < wake
                quantity(.heartRate, bpm, random.around(asleep ? 55 : 78, asleep ? 4 : 12).rounded(), at)
            }

            // Daytime activity, hourly from 08:00 to 22:00.
            for hour in 8..<22 {
                let start = day.addingTimeInterval(Double(hour) * 3600)
                let end = start.addingTimeInterval(3600)
                quantity(.stepCount, .count(), random.around(550, 400).rounded(), start, end)
                quantity(.activeEnergyBurned, .kilocalorie(), random.around(35, 20), start, end)
                if (10..<15).contains(hour) {
                    quantity(.timeInDaylight, .minute(), random.around(18, 12).rounded(), start, end)
                }
            }
            for hour in 0..<24 {
                let start = day.addingTimeInterval(Double(hour) * 3600)
                quantity(.basalEnergyBurned, .kilocalorie(), random.around(70, 5), start, start.addingTimeInterval(3600))
            }

            if dayOffset % 2 == 0 {
                quantity(.bodyMass, .gramUnit(with: .kilo), random.around(72.5 - Double(dayOffset) * 0.01, 0.4), day.addingTimeInterval(7.5 * 3600))
                quantity(.bodyFatPercentage, .percent(), random.around(0.185, 0.005), day.addingTimeInterval(7.5 * 3600))
            }
            if dayOffset % 7 == 0 {
                quantity(.vo2Max, HKUnit(from: "ml/kg*min"), random.around(42, 1.5), day.addingTimeInterval(18 * 3600))
            }

            // A run every other day at 17:30 with its own heart rate and distance.
            if dayOffset % 2 == 1 {
                let start = day.addingTimeInterval(17.5 * 3600)
                let minutes = random.around(40, 10).rounded()
                let end = start.addingTimeInterval(minutes * 60)
                let distance = minutes * 165
                samples.append(HKWorkout(
                    activityType: .running,
                    start: start,
                    end: end,
                    workoutEvents: nil,
                    totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: minutes * 10),
                    totalDistance: HKQuantity(unit: .meter(), doubleValue: distance),
                    metadata: [HKMetadataKeyIndoorWorkout: false]
                ))
                quantity(.distanceWalkingRunning, .meter(), distance, start, end)
                for minute in stride(from: 0.0, to: minutes, by: 2) {
                    quantity(.heartRate, bpm, random.around(152, 10).rounded(), start.addingTimeInterval(minute * 60))
                }
            }
        }

        return samples
    }
}
