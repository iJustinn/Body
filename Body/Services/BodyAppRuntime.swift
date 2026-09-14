import Foundation

/// The UI and headless handlers share this store. Access on the main actor;
/// never construct a second store in a background callback.
@MainActor
final class BodyAppRuntime {
    static let shared = BodyAppRuntime {
        BodyNotificationPreferences.migrate()
        BodyHealthPermissionSelection.migrateIfNeeded()
        return HealthKitWorkoutStore()
    }

    /// Neutral lifecycle state; reading it does not instantiate the shared store.
    /// Starts inactive so a headless launch cannot masquerade as a visible scene.
    private(set) static var isForegroundActive = false
    private static weak var observingStore: HealthKitWorkoutStore?

    static func setForegroundActive(_ active: Bool) {
        isForegroundActive = active
        if active { BodyBackgroundAdmission.cancel(); observingStore?.retireBackgroundRefresh() }
        else { observingStore?.healthChangeCoordinator?.enteredBackground() }
    }

    let notificationRoute = BodyNotificationRoute()
    let workoutStore: HealthKitWorkoutStore

    func startObserving() {
        Self.observingStore = workoutStore
        guard workoutStore.healthChangeCoordinator == nil,
              let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let coordinator = BodyHealthChangeCoordinator(store: workoutStore,
            file: directory.appendingPathComponent("HealthChanges/domains.json"))
        workoutStore.healthChangeCoordinator = coordinator
        Task { await coordinator.configure() }
    }

    init(makeStore: () -> HealthKitWorkoutStore) {
        workoutStore = makeStore()
    }
}
