---
name: project-issue-review
description: Whole-project audit workflow for the Body iOS app. Use when the user asks for a "project review", "issue audit", "full project review", "find bugs and issues", asks to refresh `Issues-cc.md`, or asks to archive the current `Issues-cc.md`. Inspects the project read-only and produces a fresh `Issues-cc.md` covering bugs, incomplete features, risky code, duplicated logic, unused files, inconsistent patterns, performance, UI/UX, and maintainability. Archives the prior `Issues-cc.md` to `docs/Issues-cc-XX.md` (zero-padded next number).
---

# Project Issue Review

## When to use

Invoke this skill when the user asks for a holistic, read-only audit of the
Body repository that should produce or refresh `Issues-cc.md`. Typical triggers:

- "Review the project and update Issues-cc.md."
- "Do a full project review."
- "Find any bugs, incomplete features, or risky code."
- "Audit the project end to end."
- "Archive the current Issues-cc.md and start a new one."

Do **not** invoke this skill for narrow code reviews (single PR / single
file), build-failure triage, or feature design discussions — those are direct
work, not an audit.

## Hard constraints

These rules are absolute. Violating any of them is a failed run.

1. **Inspect first, write last.** Do not write or modify anything until the
   project survey is complete. The only file edits this skill ever makes are
   the archive rename and the new `Issues-cc.md`.
2. **No code changes.** Do not edit Swift, plist, entitlements, project files,
   docs, or any other source. Read-only on everything except the two files
   above.
3. **No file moves or deletions** beyond renaming the existing `Issues-cc.md` to
   its archive name.
4. **No assumptions.** Every claim must be backed by a file path and (where
   feasible) a line range or short excerpt. If something is uncertain, mark
   it `Needs verification` and state exactly what should be checked.
5. **No commits, pushes, or builds.** The skill never runs `git commit`,
   `git push`, `xcodebuild`, or test suites. Mention any check that would
   require a build under the testing-gaps section.

## Output contract

A successful run produces exactly two filesystem changes:

1. The previous `Issues-cc.md` is renamed (with `git mv`) to
   `docs/Issues-cc-XX.md`, where `XX` is the next zero-padded integer
   after the highest existing `docs/Issues-cc-NN.md`. If no archives
   exist yet, use `01`. If `Issues-cc.md` does not exist at all, skip this
   step and create the new file directly. Create the `docs/` directory if
   it does not yet exist.
2. A fresh `Issues-cc.md` at the repository root, written in the structure
   under "Required structure of `Issues-cc.md`" below.

`git status --short` after the run should show only:

- `R  Issues-cc.md -> docs/Issues-cc-XX.md` (when archiving)
- `?? Issues-cc.md`
- any pre-existing changes that were already staged or unstaged before the
  skill ran (do not touch them).

## Workflow

Use `TaskCreate` to track progress when the run will take more than a few
tool calls. Steps must run in order; do not begin step 6 until steps 1–5 are
complete.

### 1. Determine the next archive number

- `ls docs/Issues-cc-*.md` (or equivalent) to enumerate existing
  archives.
- Parse the trailing two-digit number from each filename.
- The next archive number is `max(existing) + 1`, zero-padded to two digits.
  If no archives exist, use `01`.
- Note this number for step 6 — do **not** rename anything yet.

### 2. Orient

- Read the existing `Issues-cc.md` end to end if it exists. Note severity legend,
  section ordering, and any items it carried forward as unresolved.
- Read `README.md`, `VersionHistory.md`, `TestPlan.md`, and
  `LessonsLearned.md` for product context, recent release notes, the
  intended test surface, and known gotchas.
- Read the most recent `docs/Issues-cc-*.md` (highest existing number)
  for context on prior findings — this is reference, not a copy source.
- Run `git status --short`, `git diff --stat`, and
  `git log --oneline -20`. Distinguish committed changes on this branch
  from unstaged work-in-progress; both can introduce issues.

### 3. Survey the source

Read the project broadly enough to support a whole-project audit. Prefer
narrow `Read` calls on the highest-signal files; use `rg` for cross-cutting
questions (duplication, dead code, schema drift, naming inconsistencies).

Default reading list (skip files clearly unrelated to recent activity, but
note the skip in "Not checked"):

- `Body/BodyApp.swift`
- `Body/Models/*.swift` (e.g. `BodyAppearancePreferences.swift`,
  `HealthSummarySnapshot.swift`)
- `Body/Services/*.swift` (e.g. `HealthKitWorkoutStore.swift`)
- `Body/Views/MainTabView.swift`, `BodyHomeView.swift`, `BodyChartsView.swift`,
  `BodySettingsView.swift`, plus any other view files present
- `BodyShared/Models/*.swift` (e.g. `WorkoutMonthSnapshot.swift`,
  `BodyWorkoutType.swift`, `WorkoutSummary.swift`)
- `BodyShared/Components/*.swift` (e.g. `WorkoutCalendarView.swift`,
  `WorkoutTypeBreakdownView.swift`, `BodyWidgetBackground.swift`)
- `BodyShared/Services/*.swift` (e.g. `WorkoutSnapshotStore.swift`)
- `BodyWidgetExtension/*.swift`
- `Body/Resources/*` if present (localizations, assets, Info.plist additions)
- `Body/Info.plist`, `Body/Body.entitlements`,
  `BodyWidgetExtension.entitlements`, `body.xcodeproj/project.pbxproj`
  (skim build settings, capabilities, schemes, HealthKit usage strings)
- `BodyTests/*.swift`
- Any files surfaced in `git diff --stat` not already covered above

For large view files, it is acceptable to scan by `rg` and read only the
regions a finding points to — but do at least scan each one.

### 4. Hunt for issues

Treat each category below as a checklist. Not every category will yield
findings; cover all of them.

- **Bugs.** Logic errors, off-by-ones, wrong comparisons, mishandled
  optionals, swallowed errors, race conditions, stale-result application
  without a generation guard.
- **Incomplete features.** TODOs / FIXMEs, stubbed methods, feature flags
  with no off-ramp, UI affordances that lead nowhere, half-wired services.
- **Risky code.** Force-unwraps on user input, untrusted data paths,
  unchecked array indexing, date / timezone math without an explicit
  calendar or anchor.
- **Duplicated logic.** Same calculation or formatting reimplemented across
  view models / views / widgets / shared components. Copy-pasted helpers.
- **Unused or outdated files.** Whole files / types / methods with no
  production callers. Use `rg` to confirm before flagging.
- **Inconsistent patterns.** Mix of async/await and completion handlers,
  inconsistent error propagation, inconsistent naming (camelCase vs.
  snake_case in keys, plural vs. singular collection names, etc.).
- **Performance.** Per-body filters/sorts on full collections, per-row
  `UserDefaults` reads, repeated HealthKit queries without caching,
  retained large objects, main-thread blocking, expensive computations in
  SwiftUI view bodies.
- **UI/UX.** Layout collisions, unclear copy, inconsistent spacing or
  typography, missing or inconsistent empty / loading / error states,
  hit-target issues, accessibility gaps (Dynamic Type, VoiceOver labels,
  contrast).
- **Maintainability.** Files or functions that have grown past comprehension,
  tight coupling, leaky abstractions, magic numbers, undocumented
  invariants.
- **HealthKit and workout-data consistency.** Whenever a code path queries
  HealthKit, builds a `WorkoutSummary`, or aggregates into a
  `WorkoutMonthSnapshot`: confirm calendar views, charts, breakdowns, and
  widget timelines agree on the same value, the same date boundaries, and
  the same workout-type taxonomy. Flag any path that derives totals
  independently instead of consuming the snapshot.
- **Persistence and data.** `WorkoutSnapshotStore` and any other storage
  paths, JSON / `UserDefaults` fallbacks, app-group keys,
  Darwin-notification or `WidgetCenter` invalidations, migration /
  schema-version logic, possible data loss on update or deletion, stale
  caches, sync-related races between app and widget.
- **Permissions and entitlements.** HealthKit authorization flow, missing
  or unclear permission prompts, paths that assume authorized without
  checking, types requested but never read (or vice versa).
- **Localization.** Hardcoded user-facing strings, missing keys in
  `Localizable.strings` (if present), plural-rules omissions, format-string
  drift.
- **Widget parity.** The widget target compiles a subset of the shared
  models; references to app-only services must not appear in shared model
  files. Confirm the widget reads the same snapshot the app writes, and
  that timeline reloads are triggered on the right data changes.
- **Configuration and platform.** Info.plist keys (especially
  `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`),
  entitlements, capabilities (HealthKit, App Groups), app group IDs, URL
  schemes, background modes, iOS deployment target, signing, Swift package
  versions. Anything that could break a build, a runtime feature, or App
  Store submission.
- **Testing gaps.** Features with no coverage that are most at risk if they
  regress; missing tests around HealthKit query shaping, snapshot building,
  persistence, and widget reloads.

For each candidate issue, capture: file path, line range, the concrete
evidence (a short code excerpt or grep result), the user-visible effect, and
a suggested fix. If you cannot confirm a finding without running the app,
mark it `Needs verification` and state what would confirm it.

### 5. Filter against archives

- Skip an issue when it appears in any `docs/Issues-cc-*.md` and the
  current code matches the prior resolution.
- Keep an issue when the archive lists it as resolved but the code says
  otherwise (regression) — call this out in the entry.
- Merge duplicates within the current run into a single entry.

### 6. Archive and rewrite

Only after steps 1–5 are complete:

1. If `Issues-cc.md` exists at the repo root:
   - Ensure `docs/` exists (create it if missing — `mkdir -p docs`).
   - `git mv Issues-cc.md docs/Issues-cc-XX.md` using the number from
     step 1.
   - Verify the rename with `git status --short`.
2. Write the new `Issues-cc.md` at the repository root using the structure in
   "Required structure of `Issues-cc.md`" below.
3. Run `git status --short` and `ls Issues-cc.md docs/Issues-cc-XX.md`
   to confirm the only changes are the archive rename and the new file
   (plus any pre-existing unstaged work).

### 7. Verify

- `head -1 docs/Issues-cc-XX.md` should match the prior `Issues-cc.md`
  title line.
- Every issue entry in the new `Issues-cc.md` has: title, severity, related
  file(s), description, why it matters, suggested fix, and risks /
  dependencies.
- The priority recommendations section at the bottom is populated and is
  consistent with severities assigned above.
- `grep -rn "Issues-cc\|IssuesArchive" --include='*.md'` to confirm no
  internal links need updating (the `IssuesArchive` alternation catches
  references to the legacy archive name, which existed prior to the
  `Issues-cc-NN.md` rename). If any internal references appear, update
  them as part of this run.

## Required structure of `Issues-cc.md`

The new file must contain the following nine sections in order. Use Markdown
headings exactly as shown so future runs can parse them. Severity must be
one of `Critical`, `High`, `Medium`, `Low` (capitalized, no emoji required).

```markdown
# Body — Issues Report

Audit of branch `<branch>` on <YYYY-MM-DD>. Read-only review; no code was
modified.

Severity legend: Critical (data loss / crash / store-blocking), High
(incorrect behavior or significant UX regression under normal use), Medium
(bug or hygiene risk under specific conditions), Low (quality, performance,
or maintainability delta).

---

## 1. Project review summary

<2–4 sentences on overall condition: stability, scope of recent changes,
biggest risk areas. List the main areas reviewed (e.g. UI, data flow,
HealthKit integration, persistence, settings, widgets, models, services,
configuration). Note anything intentionally not reviewed and why.>

---

## 2. Issue list

### N1. <Short, specific title naming the symptom>

- **Severity:** Critical | High | Medium | Low
- **Related files:** `path/to/File.swift:line-range`, `path/to/Other.swift`
- **Description:** <what the code does and what input or sequence triggers
  the wrong behavior. Include a minimum code excerpt only if it materially
  proves the issue.>
- **Why it matters:** <user-visible effect, frequency, blast radius>
- **Suggested fix:** <local, specific change. If multiple options trade
  off, list them as bullets.>
- **Risks / dependencies:** <other code that would need to change, data
  migrations required, potential regressions, ordering with other fixes>

### N2. ...

(Order entries by severity descending, then by impact within severity.
Renumber on every run; do not preserve IDs across runs.)

---

## 3. Code quality findings

- **Duplicated code:** <list with file:line pointers>
- **Unused or outdated files / symbols:** <list with file:line pointers and
  the grep that confirmed no callers>
- **Overly complex files or functions:** <list with file:line pointers and a
  one-line reason>
- **Naming inconsistencies:** <list>
- **Structural improvements:** <suggested boundaries, no implementation>

---

## 4. Functional issues

<Broken or incomplete features. Walk through settings, HealthKit
authorization, workout aggregation, charts, calendar, widget, and
navigation; flag each that does not behave consistently. Call out edge
cases that may error.>

---

## 5. UI/UX issues

<Confusing layouts, unclear copy, spacing/style inconsistencies, missing or
poor empty / loading / error states. Suggest small, surgical improvements;
no redesigns.>

---

## 6. Data and persistence issues

<Save / load / update / delete correctness. Possible data loss, stale data,
migration concerns, app-to-widget sync risks. Cite the storage path and the
operation that exposes the issue.>

---

## 7. Configuration and platform issues

<Project settings, entitlements, permissions (especially HealthKit usage
strings and App Groups), plist keys, build settings, platform-specific
setup, signing. Anything that could cause build, runtime, or App Store
submission problems.>

---

## 8. Testing gaps

- **Highest-risk uncovered features:** <list>
- **Suggested tests:** <specific tests, manual or automated, targeting the
  Critical/High items above. Note when a real device or build is required
  to verify (HealthKit usually requires a device).>

---

## 9. Priority recommendations

- **Fix first:** <Critical / High items by ID, in the order they should be
  tackled, with one-line justification each>
- **Fix next:** <Medium items by ID, ordered>
- **Optional cleanup:** <Low items by ID, ordered>

---

## What was checked

- <reading list actually covered, with section/file specificity>
- <grep queries run>
- <archives cross-referenced>

## Not checked (worth a follow-up)

- <areas skipped and why>
- <items that would require a build, device, or Instruments run>
- <items carried forward from archives that this run did not verify>
```

Numbering rules:

- Issue IDs in the new file use the `N` prefix (`N1`, `N2`, ...). Archives
  retain whatever prefix they were written with.
- Renumber at every run.

## Style rules

- Lead each issue with a single-sentence title that names the symptom, not
  the fix. Titles should be readable on their own in a table of contents.
- Cite evidence with `file:line` or `file:line-range`. Quote the smallest
  excerpt that proves the claim. If a claim cannot be cited concretely,
  mark it `Needs verification` and state what would confirm it.
- Explain user-visible effect in one paragraph. Avoid speculation about
  causes the code does not demonstrate.
- Suggest a fix only if the right fix is locally evident. If multiple fixes
  trade off, list them as bullets.
- Keep the tone descriptive and specific — the file is a future
  implementation checklist.
- Skip noise: formatting nits, "you could extract a helper," personal
  taste. Flag only items a reasonable senior engineer would act on.

## Anti-patterns to avoid

- Writing anything before the survey is complete.
- Adding issues without evidence (no `file:line`, no excerpt or grep).
- Editing source code, project files, or any docs other than `Issues-cc.md`
  and the new archive.
- Running a build, tests, push, or commit. If a check requires a build,
  list it under "Testing gaps" or "Not checked".
- Restating archive issues that are no longer present in the code.
- Renumbering or trimming archive files. They are immutable once written.
- Skipping the priority recommendations section, the "What was checked"
  footer, or the "Not checked" footer — all are required.
