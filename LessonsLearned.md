# Lessons Learned

Persistent project-specific troubleshooting notes for future Codex runs.

## Entries

### 2026-05-11 - Keep sleep duration display from rounding down partial minutes
- Context: Matching Body's Sleep card to Apple Health's displayed sleep duration.
- Symptom: Body could show `7h 20m` while Health showed `7h 21m` for the same sleep session.
- Cause: The shared `BodyValueFormat.durationText(for:)` rounds seconds to the nearest minute, which can round a partial sleep minute down.
- Fix: Use `BodyValueFormat.sleepDurationText(for:)` for Sleep card/detail display so partial HealthKit sleep minutes are counted instead of hidden.
- Reuse: When formatting sleep durations, use the sleep-specific formatter; keep the generic duration formatter for workout durations.

### 2026-05-11 - Give daily Swift Charts date marks an explicit unit
- Context: Checking runtime console warnings after adding recent-month Health metric charts.
- Symptom: Swift Charts logged `Falling back to a fixed dimension size for a mark`.
- Cause: Date-based chart marks were plotted without declaring their daily time unit, which is especially noisy for bar marks.
- Fix: Use `.value("Date", point.date, unit: .day)` for daily LineMark, PointMark, and BarMark x-values.
- Reuse: When plotting daily HealthKit trend points in Swift Charts, include `unit: .day` on date x-values before tuning bar widths or chart domains.

### 2026-05-11 - Use HealthKit statistics for cumulative energy charts
- Context: Comparing Body's Resting Energy card against Apple Health's weekly Resting Energy chart.
- Symptom: Body showed Resting Energy totals around 2-3x higher than Apple Health for the same days.
- Cause: Body manually summed raw `HKQuantitySample` values from `HKSampleQuery` and grouped them by sample end date; cumulative HealthKit quantities should be bucketed through statistics queries for daily totals.
- Fix: Use `HKStatisticsCollectionQuery` with `.cumulativeSum` for Active Energy and Resting Energy daily series and current-day summary values.
- Reuse: For cumulative HealthKit quantities such as energy, steps, and distance, prefer daily `HKStatisticsCollectionQuery` buckets over manually summing raw samples.

### 2026-05-11 - Align Sleep summary with Health's sleep-day bucket
- Context: Comparing Body's Sleep detail with Apple Health's Day sleep screen.
- Symptom: Body could show a slightly different Sleep headline and had no stage timeline to compare against Health's REM/Core/Deep/Awake chart.
- Cause: Body built the Sleep summary from asleep-only samples in a latest-session window, while Apple Health's Day screen presents a sleep-day bucket with staged samples.
- Fix: Group sleep-analysis samples by end-date day, compute Time Asleep from asleep stages only, and keep today's Awake/REM/Core/Deep segments for the Sleep detail timeline.
- Reuse: When matching Apple Health Sleep Day views, use the same sleep-day bucket for the headline and stage visualization; exclude Awake from duration but keep it in the timeline.

### 2026-05-10 - Treat RunningBoard process-state console spam as simulator noise
- Context: Checking Xcode console logs showing `RBServiceErrorDomain Code=1 "Client not entitled"`, `com.apple.runningboard.process-state`, `elapsedCPUTimeForFrontBoard couldn't generate a task port`, and `com.apple.mobile.usermanagerd.xpc`.
- Symptom: The console repeats entitlement/task-port errors even though Body has no code requesting RunningBoard process state.
- Cause: These are Simulator/Xcode system-service diagnostics, not app-level HealthKit, WidgetKit, or SwiftUI failures.
- Fix: Confirm there is no app call site for RunningBoard/process-state APIs and that build/tests still pass; do not change app code for this log alone.
- Reuse: When the app behaves normally and these strings appear without a Body stack trace or crash, treat them as non-actionable simulator logs.

### 2026-05-10 - Use async HealthKit authorization status API on current SDK
- Context: Fixing Body's HealthKit authorization-state handling with `statusForAuthorizationRequest`.
- Symptom: `xcodebuild build` failed with `extra trailing closure passed in call` when using the older callback-style API.
- Cause: The current iOS SDK exposes `statusForAuthorizationRequest(toShare:read:)` as an async throwing call.
- Fix: Call `try await healthStore.statusForAuthorizationRequest(toShare:read:)` directly instead of wrapping a completion handler.
- Reuse: When bridging HealthKit authorization status in this project, prefer the native async API before adding continuations.

### 2026-05-10 - Use build verification when simulator test launch is busy
- Context: Verifying Body after adding medium Workout Types widget support.
- Symptom: `xcodebuild test` compiled targets but failed to launch the test runner with `Application failed preflight checks` and `BSErrorCodeDescription = Busy`.
- Cause: The selected simulator can be temporarily busy even after the Swift build succeeds.
- Fix: Retry once; if it remains busy, run `xcodebuild build` on the same destination to verify compile/product integration and report the simulator-launch limitation separately.
- Reuse: When repeated test runs fail only at simulator app launch with `Busy`, do not chase source changes; use build verification and rerun tests when Simulator is available.

### 2026-05-10 - In-app charts may diverge from widget styling
- Context: User asked to stop 100% matching widget and in-app chart styling, then requested Coin's solid dark gray in-app chart card background.
- Symptom: Previous guidance pushed the Charts tab toward the widget gradient background even when the desired in-app look was Coin's solid card surface.
- Cause: Widget and in-app charts share chart components but should not always share wrapper backgrounds.
- Fix: Use Coin-style solid card backgrounds for in-app chart panels while leaving widget backgrounds untouched.
- Reuse: When styling Body charts, confirm whether the request targets widget, in-app, or both before applying shared wrapper changes.

### 2026-05-10 - Use installed simulator names for Body tests
- Context: Verifying Body with `xcodebuild test` after adding chart month history.
- Symptom: The command failed with `Unable to find a device matching the provided destination specifier` for `iPhone 16 Pro`.
- Cause: This machine currently has iOS 26.4.1 simulators such as `iPhone 17 Pro`, not `iPhone 16 Pro`.
- Fix: Rerun with `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- Reuse: If a simulator destination fails, read the available destinations in the `xcodebuild` error and retry with an installed iPhone simulator.

### 2026-05-10 - Keep in-app charts and widgets visually aligned
- Context: User clarified that the Workout Types widget now matches the intended Coin-style layout, but the in-app Charts version drifted.
- Symptom: Fixes to the widget and in-app chart surfaces can diverge if they are edited independently.
- Cause: The widget and Charts tab reuse related components but have separate wrappers, backgrounds, padding, and style arguments.
- Fix: When editing `WorkoutCalendarView`, `WorkoutTypeBreakdownView`, `BodyChartsView`, or `WorkoutCalendarWidget`, compare both the widget and in-app chart presentations and update both wrappers/styles together.
- Reuse: Before finalizing any visual change to Body's workout calendar or workout type breakdown, verify the paired widget and Charts tab remain intentionally aligned.

### 2026-05-10 - Unwrap synthetic HealthKit activity raw values in tests
- Context: Adding tests for unsupported `HKWorkoutActivityType` raw values while expanding Body workout recognition.
- Symptom: `xcodebuild test` failed with `Value of optional type 'HKWorkoutActivityType?' must be unwrapped`.
- Cause: Swift imports `HKWorkoutActivityType(rawValue:)` as a failable initializer even for numeric values that can represent unknown future HealthKit cases.
- Fix: Use `XCTUnwrap(HKWorkoutActivityType(rawValue:))` before passing the activity type into the mapper.
- Reuse: When testing unknown HealthKit enum raw values, unwrap the failable initializer explicitly.

### 2026-05-10 - Type HealthKit void continuations explicitly
- Context: Building the first Body HealthKit workout reader with `withCheckedThrowingContinuation`.
- Symptom: `xcodebuild test` failed in `HealthKitWorkoutStore.swift` with `Generic parameter 'T' could not be inferred`.
- Cause: The authorization bridge resumes with no return value, so Swift could not infer the continuation's `Void` success type.
- Fix: Declare the closure parameter as `CheckedContinuation<Void, Error>`.
- Reuse: Apply this whenever wrapping callback APIs that only report success/failure and do not return a value.

### 2026-05-10 - Break up SwiftUI-adjacent collection chains
- Context: Restyling the shared workout calendar and computing the dominant workout type for the widget header.
- Symptom: `xcodebuild test` failed in `WorkoutCalendarView.swift` with `The compiler is unable to type-check this expression in reasonable time`.
- Cause: A chained `map`/`filter`/`sorted` expression over enum cases created too much inference work inside a SwiftUI-heavy file.
- Fix: Replace the chain with an explicit dictionary-count loop and `max` comparison.
- Reuse: When SwiftUI files hit type-check timeouts, simplify helper expressions before changing view structure.

### 2026-05-10 - Patch docs from the live file
- Context: Updating README/TestPlan/VersionHistory after earlier implementation rounds.
- Symptom: A combined `apply_patch` failed because the README text in the working tree no longer matched the summarized context.
- Cause: Documentation had already been expanded from its original placeholder, so the stale patch anchor was wrong.
- Fix: Re-read the current docs, then patch against exact live snippets.
- Reuse: Before editing files that may have changed across turns, read the current file instead of relying on the conversation summary.

### 2026-05-10 - Validate asset catalog JSON with a JSON parser
- Context: Checking newly added `.xcassets` `Contents.json` files.
- Symptom: `plutil -lint` reported `Unexpected character { at line 1` even though Xcode had already built the asset catalog successfully.
- Cause: These asset catalog files are JSON, not XML property lists.
- Fix: Use `rtk node -e` with `JSON.parse` for quick JSON validation.
- Reuse: When validating `.xcassets/Contents.json`, prefer a JSON parser; rely on `xcodebuild` for asset catalog integration.

### 2026-05-10 - Keep `rtk find` predicates simple
- Context: Looking for a referenced sibling project under the local Code folder.
- Symptom: `rtk find` rejected a command with grouped `-iname` predicates and `-o`.
- Cause: The wrapped `find` implementation supports only simple predicates.
- Fix: Use a simple `rtk find <path> -maxdepth <n> -type d` and filter the output separately.
- Reuse: When searching project folders through `rtk`, avoid compound `find` expressions.

### 2026-05-10 - Use stable indices for duplicate weekday glyphs
- Context: Debugging SwiftUI warnings from the workout calendar header.
- Symptom: Runtime logs said `ForEach<Array<String>, String...>: the ID T occurs multiple times` and the same for `S`.
- Cause: Very-short weekday symbols contain duplicate letters (`S` and `T`), but the header used `id: \.self`.
- Fix: Iterate over `symbols.indices` and use the index as the stable ID.
- Reuse: Any SwiftUI `ForEach` over non-unique display strings should use a stable index or model ID, not `\.self`.

### 2026-05-10 - Guard App Group defaults before opening the suite
- Context: Debugging `CFPrefsPlistSource` warnings for `group.com.zihengthedeveloper.Body`.
- Symptom: Runtime logs warned that `kCFPreferencesAnyUser` with a container is only allowed for system containers.
- Cause: The app group container can be unavailable in previews or mis-signed debug runs, leaving CFPreferences with a null container.
- Fix: Check `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` before creating `UserDefaults(suiteName:)`; previews return `nil` and use the placeholder snapshot path.
- Reuse: Guard app group storage before opening shared defaults when code also runs in previews, tests, or extensions.

### 2026-05-10 - Add explicit returns after computed-property guard statements
- Context: Adding guard logic to `WorkoutSnapshotStore.sharedUserDefaults`.
- Symptom: `xcodebuild test` failed with `Missing return in getter expected to return 'UserDefaults?'`.
- Cause: Once a computed property body contains multiple statements, Swift needs an explicit `return` for the final value.
- Fix: Change the final `UserDefaults(suiteName:)` expression to `return UserDefaults(suiteName:)`.
- Reuse: When converting one-expression computed properties into guarded blocks, make the final return explicit.

### 2026-05-10 - Add explicit returns in `some View` helpers with local bindings
- Context: Capturing weekday symbols in a local `let` before returning an `HStack`.
- Symptom: `xcodebuild test` failed with `Function declares an opaque return type, but has no return statements`.
- Cause: A `some View` function with local statements needs an explicit `return` for the final view expression.
- Fix: Use `return HStack(...)` after the local binding.
- Reuse: When adding local constants to non-`@ViewBuilder` `some View` helpers, make the returned view explicit.

### 2026-05-10 - Qualify nested static snapshots in typed initializers
- Context: Building `HealthSummarySnapshot` from optional HealthKit query results.
- Symptom: `xcodebuild test` failed with `Type 'SleepSummary' has no member 'empty'` and similar errors for `HealthMetricSummary`.
- Cause: In a `HealthSummarySnapshot(...)` initializer argument, `.empty.sleep` was inferred from the argument type instead of the containing snapshot type.
- Fix: Use `HealthSummarySnapshot.empty.sleep` and the fully qualified metric paths.
- Reuse: When accessing a static aggregate fixture from inside a typed initializer, qualify the root type instead of relying on shorthand member lookup.
