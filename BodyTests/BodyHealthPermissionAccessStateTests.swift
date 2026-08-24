import XCTest
@testable import Body

/// The Permissions sheet reports one derived sentence per row. The resolution
/// ORDER is the contract: an earlier case must always win, because the later
/// ones make claims that would be wrong if an earlier condition held. These
/// pin that order rather than any single case's text.
final class BodyHealthPermissionAccessStateTests: XCTestCase {
    private func resolve(
        _ permission: BodyHealthPermission,
        selection: BodyHealthPermissionSelection,
        isFetchedForDashboard: Bool = true,
        hasCompletedInitialLoad: Bool = true,
        isLoadInFlight: Bool = false,
        presence: BodyHealthPermissionDataPresence = .present
    ) -> BodyHealthPermissionAccessState {
        BodyHealthPermissionAccessState.resolve(
            permission: permission,
            selection: selection,
            isFetchedForDashboard: isFetchedForDashboard,
            hasCompletedInitialLoad: hasCompletedInitialLoad,
            isLoadInFlight: isLoadInFlight,
            presence: presence
        )
    }

    private func selection(_ permissions: Set<BodyHealthPermission>) -> BodyHealthPermissionSelection {
        BodyHealthPermissionSelection(enabledPermissions: permissions)
    }

    // MARK: - Precedence

    /// A switch the user turned off must never report missing data: Body did not
    /// look, so "no data" would blame Apple Health for the user's own choice.
    func testOffWinsOverEveryOtherSignal() {
        for permission in BodyHealthPermission.allCases {
            XCTAssertEqual(
                resolve(
                    permission,
                    selection: selection([]),
                    isFetchedForDashboard: false,
                    hasCompletedInitialLoad: false,
                    isLoadInFlight: true,
                    presence: .absent
                ),
                .off,
                "\(permission) with the switch off"
            )
        }
    }

    func testNeedsParentWinsOverDashboardAndLoadSignals() {
        XCTAssertEqual(
            resolve(
                .dateOfBirth,
                selection: selection([.dateOfBirth]),
                isFetchedForDashboard: false,
                hasCompletedInitialLoad: false,
                isLoadInFlight: true,
                presence: .absent
            ),
            .needsParent(.heart)
        )
    }

    /// A hidden card means Body never queried the category, so absence there says
    /// nothing about access and must not read as missing data.
    func testNotUsedByDashboardWinsOverLoadStateAndPresence() {
        XCTAssertEqual(
            resolve(
                .heart,
                selection: selection([.heart]),
                isFetchedForDashboard: false,
                hasCompletedInitialLoad: false,
                isLoadInFlight: true,
                presence: .absent
            ),
            .notUsedByDashboard
        )
    }

    func testCheckingWinsOverAbsentPresence() {
        XCTAssertEqual(
            resolve(.heart, selection: selection([.heart]), hasCompletedInitialLoad: false, presence: .absent),
            .checking
        )
        XCTAssertEqual(
            resolve(.heart, selection: selection([.heart]), isLoadInFlight: true, presence: .absent),
            .checking
        )
    }

    func testPresenceMapsToTerminalStates() {
        XCTAssertEqual(resolve(.heart, selection: selection([.heart]), presence: .present), .hasData)
        XCTAssertEqual(resolve(.heart, selection: selection([.heart]), presence: .absent), .noData)
        XCTAssertEqual(
            resolve(.dateOfBirth, selection: selection([.dateOfBirth, .heart]), presence: .unobservable),
            .readOnDemand
        )
    }

    // MARK: - Parent attribution

    /// Only the two dependent toggles have a parent. Getting this wrong would put
    /// "it needs X on as well" under a row that needs nothing.
    func testOnlyDependentPermissionsHaveAParent() {
        for permission in BodyHealthPermission.allCases {
            switch permission {
            case .dateOfBirth:
                XCTAssertEqual(permission.parentPermission, .heart)
            case .workoutMetrics:
                XCTAssertEqual(permission.parentPermission, .workouts)
            default:
                XCTAssertNil(permission.parentPermission, "\(permission) should not claim a parent")
            }
        }
    }

    /// Regression: an earlier draft derived the parent by differencing
    /// `readObjectTypes` with and without the permission. Read types OVERLAP, so
    /// that reported "needs Heart" while Heart was already on. `.cardioFitness`
    /// contributes the date-of-birth type independently of `.heart`, which makes
    /// the default all-on selection the failing case.
    func testDateOfBirthNeverClaimsMissingParentWhenHeartIsOn() {
        XCTAssertEqual(
            resolve(
                .dateOfBirth,
                selection: selection([.dateOfBirth, .heart, .cardioFitness]),
                presence: .unobservable
            ),
            .readOnDemand
        )
        XCTAssertEqual(
            resolve(.dateOfBirth, selection: .defaultValue, presence: .unobservable),
            .readOnDemand
        )
    }

    /// Same overlap trap from the other side: `.stepCount` is contributed by
    /// Workouts plus Workout Metrics as well as by Steps, so a set difference
    /// would find Steps unlocking nothing and invent a parent for it.
    func testStepsNeverReportsNeedsParent() {
        XCTAssertEqual(
            resolve(.steps, selection: selection([.steps, .workouts, .workoutMetrics]), presence: .present),
            .hasData
        )
    }

    func testWorkoutMetricsReportsNeedsParentOnlyWithWorkoutsOff() {
        XCTAssertEqual(
            resolve(.workoutMetrics, selection: selection([.workoutMetrics]), presence: .absent),
            .needsParent(.workouts)
        )
        XCTAssertEqual(
            resolve(.workoutMetrics, selection: selection([.workoutMetrics, .workouts]), presence: .present),
            .hasData
        )
    }

    /// With everything on and data present, no row may fall into a "something is
    /// wrong" state. Table-driven so a newly added permission is covered as it is
    /// written rather than defaulting into a misleading branch.
    func testEveryPermissionResolvesCleanlyUnderTheDefaultSelection() {
        for permission in BodyHealthPermission.allCases {
            let presence: BodyHealthPermissionDataPresence =
                permission == .dateOfBirth ? .unobservable : .present
            let state = resolve(permission, selection: .defaultValue, presence: presence)
            XCTAssertFalse(state.wantsAttention, "\(permission) resolved to \(state) with data present")
        }
    }

    // MARK: - Copy

    func testWantsAttentionMarksOnlyTheActionableStates() {
        XCTAssertTrue(BodyHealthPermissionAccessState.noData.wantsAttention)
        XCTAssertTrue(BodyHealthPermissionAccessState.notUsedByDashboard.wantsAttention)
        XCTAssertTrue(BodyHealthPermissionAccessState.needsParent(.heart).wantsAttention)
        XCTAssertFalse(BodyHealthPermissionAccessState.off.wantsAttention)
        XCTAssertFalse(BodyHealthPermissionAccessState.checking.wantsAttention)
        XCTAssertFalse(BodyHealthPermissionAccessState.hasData.wantsAttention)
        XCTAssertFalse(BodyHealthPermissionAccessState.readOnDemand.wantsAttention)
    }

    /// No footer may claim Apple Health granted or denied anything: iOS never
    /// discloses read authorization, and the published values may have come from
    /// the persisted dashboard rather than a live read.
    func testFootersNeverClaimAppleHealthGrantedOrDeniedAccess() {
        let states: [BodyHealthPermissionAccessState] = [
            .off, .needsParent(.heart), .notUsedByDashboard, .checking, .hasData, .noData, .readOnDemand
        ]
        for state in states {
            let text = state.footerText
            XCTAssertFalse(text.localizedCaseInsensitiveContains("denied"), "\(state): \(text)")
            XCTAssertFalse(text.localizedCaseInsensitiveContains("allowed"), "\(state): \(text)")
            XCTAssertFalse(text.localizedCaseInsensitiveContains("sharing"), "\(state): \(text)")
            XCTAssertFalse(text.isEmpty, "\(state) has no footer")
            // Standing copy rule for this project: no dashes in a user-facing sentence.
            XCTAssertFalse(text.contains("—"), "\(state) uses an em dash: \(text)")
            XCTAssertFalse(text.contains(" - "), "\(state) uses a dash: \(text)")
        }
    }
}
