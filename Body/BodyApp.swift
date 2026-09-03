//
//  BodyApp.swift
//  Body
//

import SwiftUI

@main
struct BodyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var workoutStore: HealthKitWorkoutStore
    @State private var proStore: BodyProStore
    /// Owns the on-device Apple Intelligence readiness comment. Lives at the root so
    /// Home (which drives generation) and Settings (which reads `isSupported`) share
    /// one instance.
    @State private var readinessComment = ReadinessCommentGenerator()
    @AppStorage(BodyAppearancePreference.selectedThemeKey) private var selectedThemeRawValue = BodyAppTheme.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.workoutColorOverridesKey, store: BodyWorkoutColorStore.sharedDefaults)
    private var workoutColorOverridesRawValue = ""

    init() {
        // The permission-selection migrations run exactly once here, before
        // anything reads the selection. `workoutStore` is built on the line below
        // rather than in its declaration, so the `BodyHealthPermissionSelection.load()`
        // default argument inside `HealthKitWorkoutStore.init` runs after the
        // migration. Do not move the assignment above this line, and do not give the
        // property an inline default, which would construct the store first.
        BodyHealthPermissionSelection.migrateIfNeeded()
        _workoutStore = State(initialValue: HealthKitWorkoutStore())

        // Configure RevenueCat before constructing BodyProStore so the store's async
        // entitlement work always runs against a configured SDK.
        RevenueCatConfiguration.configure()
        _proStore = State(initialValue: BodyProStore())

        // Activate WatchConnectivity at startup so the session is ready and the
        // first snapshot push doesn't have to wait for activation.
        WatchConnectivityPublisher.shared.activate()

        // BGTask handlers must be registered before launch finishes, so this
        // belongs in `init()` rather than in a `.task`.
        BodyBackgroundRefreshScheduler.registerTask()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .bodyBaseInterfaceLevel()
                .environment(workoutStore)
                .environment(proStore)
                .environment(readinessComment)
                .environment(\.workoutColorPalette, workoutColorPalette)
                .tint(.primary)
                .accentColor(.primary)
                .preferredColorScheme(selectedTheme.colorScheme)
                .onChange(of: workoutColorOverridesRawValue) { _, _ in
                    BodyWidgetReloadCoalescer.shared.requestReload()
                }
                .task(priority: .utility) {
                    BodyBackgroundRefreshScheduler.setForegroundActive(true)
                    BodyBackgroundRefreshScheduler.schedule()
                    // The intraday day-sample sidecar is the only cached series not
                    // restored synchronously in the store's init, so the Day View
                    // charts would otherwise stay empty until a full refresh or a
                    // metric-detail visit hydrated it. Same task body as the sync
                    // below, not a second `.task` — sibling `.task` modifiers run
                    // concurrently, and the read has to win against any save the
                    // refresh triggers. Skipped on a true first launch: the
                    // day-sample fields count toward `needsInitialHealthDataLoad`,
                    // so hydrating a stranded sidecar there would suppress the load
                    // overlay and leave every passive load idled.
                    if !workoutStore.needsInitialHealthDataLoad {
                        await workoutStore.hydratePersistedDaySamplesIfNeeded()
                    }
                    await workoutStore.syncWhenAppBecomesActive()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // The background evaluator skips a pass while the app is on
                    // screen, where the foreground refresh owns detection.
                    BodyBackgroundRefreshScheduler.setForegroundActive(newPhase == .active)
                    if newPhase == .background {
                        workoutStore.noteAppDidEnterBackground()
                    }
                    guard newPhase == .active else {
                        return
                    }

                    BodyBackgroundRefreshScheduler.schedule()
                    Task(priority: .utility) {
                        await workoutStore.syncWhenAppBecomesActive()
                        // RevenueCat doesn't push backend changes; re-resolve on foreground
                        // so refunds / other-device purchases update Pro and the widgets.
                        await proStore.refreshEntitlement()
                    }
                }
        }
    }

    private var selectedTheme: BodyAppTheme {
        BodyAppTheme.storedValue(from: selectedThemeRawValue)
    }

    private var workoutColorPalette: BodyWorkoutColorPalette {
        BodyWorkoutColorPalette(rawOverrides: workoutColorOverridesRawValue, isProUnlocked: proStore.isPro)
    }
}
