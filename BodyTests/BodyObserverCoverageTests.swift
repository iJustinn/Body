import XCTest
import HealthKit
@testable import Body

final class BodyObserverCoverageTests: XCTestCase {
    func testSummaryCoverageIncludesSuccessfulEmptyReadButExcludesFailedAndSkippedLeaves() async throws {
        let health = FakeHealthStore()
        let mass = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .bodyMass))
        let fat = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .bodyFatPercentage))
        let bmi = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .bodyMassIndex))
        for type in [mass, fat, bmi] { health.scriptSources(for: type, .sources([])) }
        health.scriptSamples(for: mass, .samples([]))
        health.scriptSamples(for: fat, .failure(nil))
        health.scriptSamples(for: bmi, .failure(nil))
        let engine = HealthKitFetchEngine(permission: .init(enabledPermissions: [.basics]),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: health)
        _ = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian)
        let selection = BodyDashboardFetchSelection(summaryCards: .init(selectedCards: [.basics]),
            trendCards: .init(selectedCards: []))
        let result = await engine.fetchHealthSummary(calendar: .bodyGregorian, selection: selection)
        XCTAssertEqual(result.currentCoverage, [.bodyMass])
        XCTAssertTrue(result.hadQueryFailure)
        XCTAssertTrue(health.leafRequests.contains(.samples(mass.identifier)))
        XCTAssertFalse(health.leafRequests.contains(.samples(HKQuantityTypeIdentifier.vo2Max.rawValue)))
    }

    func testDisabledPermissionAndDerivedCacheDoNotProveCurrentCoverage() async {
        let health = FakeHealthStore()
        let engine = HealthKitFetchEngine(permission: .init(enabledPermissions: []),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: health)
        let result = await engine.fetchHealthSummary(calendar: .bodyGregorian)
        XCTAssertTrue(result.currentCoverage.isEmpty)
        XCTAssertTrue(health.leafRequests.isEmpty)
    }

    func testRetiredQuietEngineSetupCannotReplaceForegroundAnchor() async {
        let engine = HealthKitFetchEngine(permission: .defaultValue,
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: FakeHealthStore())
        let current = Date()
        await engine.setHealthTrendAnchorDate(current)
        let token = HealthDashboardPublicationToken()
        token.invalidate()
        await HealthDashboardPublicationToken.$quietCurrent.withValue(token) {
            await engine.setHealthTrendAnchorDate(nil)
        }
        let anchor = await engine.healthTrendAnchorDate
        XCTAssertEqual(anchor, current)
    }
}
