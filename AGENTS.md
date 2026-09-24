# Body Project Instructions

- Do not use removed TDD skills, and do not read removed skill files from git history.
- Keep changes scoped, preserve unrelated local work, and match existing project style.
- Verify changes with focused XCTest or the strongest relevant `xcodebuild` build gate when practical.
- Run tests via `./test.sh` (optionally `WORKERS=n`, `DEST=...`, `PLANS=Body`), never a bare `xcodebuild test`.
  It pins the simulator destination so runs are reproducible. All test plans are serial
  (`parallelizable: false`), so no simulator clones are created — keep it that way, or the worker
  cap in `test.sh` becomes load-bearing.
- `Body.xctestplan` and `BodySerial.xctestplan` are complementary halves of the suite, not
  alternatives: `Body` runs everything except the render/layout classes, `BodySerial` runs only
  those. Running just one does not cover the suite, so `test.sh` runs both by default; set `PLANS`
  to one plan only for a focused `-only-testing:` run.
