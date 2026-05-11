---
name: body-rtk-tdd
description: >
  RTK TDD workflow for the Body Swift/iOS project. Auto-triggers on Body
  implementation, bug fixing, refactoring, testing, SwiftUI view changes,
  HealthKit/workout logic changes, formatting logic changes, and regression
  fixes. Enforces Red-Green-Refactor using XCTest and xcodebuild for this repo.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
effort: medium
tags: [rtk, tdd, testing, swift, ios, xctest, red-green-refactor, body]
---

# Body RTK TDD Workflow

Use this skill for every code-changing task in the Body project, including UI work, bug fixes, refactors, model changes, formatting changes, HealthKit/workout logic, widget logic, and test updates.

## Core Rule

Default to Red-Green-Refactor:

1. Identify the smallest behavior that should change.
2. Add or update a focused XCTest that fails for the current behavior.
3. Run the narrowest relevant test command and confirm the failure when practical.
4. Implement the smallest production change that should satisfy the test.
5. Re-run the focused test.
6. Run the broader relevant gate before finishing.

If a strict red step is not practical for a pure SwiftUI layout-only change, state why and still run the strongest available build or test gate.

## Test Placement

- Put model and formatting tests in `BodyTests/WorkoutMonthSnapshotTests.swift` unless a narrower existing test file fits better.
- Put HealthKit and store behavior tests in `BodyTests/HealthKitWorkoutStoreTests.swift`.
- Put workout type mapping, color, or symbol tests in `BodyTests/BodyWorkoutTypeTests.swift`.
- Put entitlement, target, asset, and configuration checks in `BodyTests/ProjectConfigurationTests.swift`.
- Add a new test file only when the existing files would become confusing or too broad.

## Commands

Use the narrowest useful test first:

```bash
xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO -only-testing:BodyTests/WorkoutMonthSnapshotTests/testName
```

Use the full test suite for behavior changes:

```bash
xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO
```

Use the build gate for UI-only changes or when simulator execution is not needed:

```bash
xcodebuild -project body.xcodeproj -scheme Body -destination generic/platform=iOS -derivedDataPath /private/tmp/body-derived CODE_SIGNING_ALLOWED=NO build
```

## Quality Bar

- Keep changes scoped to the requested behavior.
- Prefer existing app patterns and shared helpers before introducing new abstractions.
- Keep visual changes aligned with existing SwiftUI styles unless the user requests a specific source to mimic.
- Preserve user work and unrelated local changes.
- In the final response, state the RTK path used: red test added or updated, production change, and verification command.
