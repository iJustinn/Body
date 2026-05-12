---
name: project-issue-review
description: Whole-project audit workflow for the Body iOS app. Use when the user asks for a "project review", "issue audit", "full project review", "find bugs and issues", asks to refresh `Issues.md`, or asks to archive the current `Issues.md`. Inspects the project read-only and produces a fresh `Issues.md` covering bugs, incomplete features, risky code, duplicated logic, unused files, inconsistent patterns, performance, UI/UX, and maintainability. Archives the prior `Issues.md` to `docs/IssuesArchive-XX.md` when present.
---

# Project Issue Review

## When To Use

Invoke this skill for a holistic, read-only audit of the Body repository that
should create or refresh `Issues.md`.

Typical triggers:

- "Review the project and update Issues.md."
- "Do a full project review."
- "Find bugs and issues."
- "Audit the project end to end."
- "Archive the current Issues.md and start a new one."

Do not use this skill for narrow code reviews, build-failure triage, feature
implementation, or design discussions.

## Hard Constraints

1. Inspect first, write last.
2. Do not change app/source code during the audit.
3. The only allowed writes are archiving the previous `Issues.md` and writing
   the new `Issues.md`.
4. Every finding must cite concrete file evidence.
5. Do not commit, push, run app builds, or run test suites from this skill.
   Mention build/test checks under testing gaps instead.

## Workflow

1. Determine the next archive number from `docs/IssuesArchive-*.md`. If no
   archives exist, use `01`. Do not rename anything yet.
2. Orient by reading `Issues.md` if present, `README.md`, `VersionHistory.md`,
   `TestPlan.md`, `LessonsLearned.md`, and the latest archive if present.
3. Run `rtk git status --short`, `rtk git diff --stat`, and
   `rtk git log --oneline -20` to understand current branch state.
4. Survey the codebase with `rg` and narrow reads. Cover at minimum:
   `Body/Models`, `Body/Services`, `Body/Views`, `BodyShared`,
   `BodyWidgetExtension`, `BodyTests`, entitlements, Info.plist files, and
   `body.xcodeproj/project.pbxproj`.
5. Hunt for issues across:
   bugs, incomplete features, risky code, duplicated logic, unused files,
   inconsistent patterns, performance, UI/UX, maintainability, HealthKit data
   consistency, workout snapshot consistency, widget parity, permissions,
   localization, configuration, and testing gaps.
6. Filter against prior archives so resolved historical findings are not copied
   forward unless the current code has regressed.
7. Archive and rewrite only after the survey is complete:
   - Create `docs/` if needed.
   - If `Issues.md` exists, rename it to `docs/IssuesArchive-XX.md`.
   - Write a fresh root `Issues.md`.
8. Verify the new report structure, archive title, and `rtk git status --short`.

## Required `Issues.md` Shape

Use this structure:

```markdown
# Body - Issues Report

Audit of branch `<branch>` on <YYYY-MM-DD>. Read-only review; no code was
modified.

## Executive Summary

## Findings

### 1. <Finding Title>

- Severity: High | Medium | Low
- Related files: `path/to/file.swift`
- Description:
- Why it matters:
- Suggested fix:
- Risks / dependencies:

## Testing Gaps

## Not Checked

## Priority Recommendations
```

Severity must be `Critical`, `High`, `Medium`, or `Low`. Use `Critical` only
for confirmed data loss, privacy/security exposure, or a release-blocking build
failure.

## Body-Specific Audit Focus

- HealthKit authorization and requested/read quantity types.
- Daily HealthKit aggregation, sleep windows, time zones, and calendar anchors.
- Workout month snapshot generation and widget handoff through app group
  storage.
- In-app chart/detail behavior versus widget behavior.
- Home health cards and detail pages using the same summary/trend data.
- Settings unit preferences and formatting consistency.
- App icon assets, project file membership, entitlements, and privacy strings.
- Widget target isolation from app-only services.
