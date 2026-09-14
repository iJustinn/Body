# Validation — revision 2

This is the acceptance checklist. Executed checks and outstanding device scenarios are recorded in [05-implementation-evidence.md](05-implementation-evidence.md). Retain existing ledger, context, batch, timeout, source, and durability regressions. Add tests only for the adopted phases; re-derive date-cursor tests if Phase C is later approved.

## Phase A focused tests

| Scenario | Required evidence |
| --- | --- |
| Clean, history-only, current+history activation | Proper freshness decision; only required foreground work; no awaiting historical task before current admission. |
| Broad 18-domain burst and repeated Watch deliveries | One retained quiet owner; fresh receipts captured before reads; newer callbacks survive; successful unrelated domains stay complete. |
| Successful ordinary/manual full-scope read | Its proven coverage drains matching obligations without a redundant quiet reread; partial/incremental/cache-only results cannot clear history. |
| Blocked/never-returning quiet read, then user refresh | Foreground read starts before old gate opens, using interactive permits; old task cannot publish, send, mutate setup, or release the new owner. |
| Cancellation while queued or during callback | At-most-once resume/release; no stale queued query starts; background saturation does not occupy interactive permits; no unbounded replacement quiet tasks. |
| Journal, records, stress input/history plus metric queue | Unit-level rotation despite retained handles; dependencies honored; no circular waits; automatic journal repair does not restore the badge. |
| Payload/ledger failure and restart | Pending flags survive; crash after payload repeats safely; completed same-generation domains are not reread. |
| Source/context/cache reset and day rollover | Retired tokens rejected; no mixed sources or stale disk saves; day-only change still avoids global historical dirtiness. |
| Initial load/permission/rebuild | No maintenance admitted before initial load completes or during transactions; explicit recovery UI retained. |
| Independent stress admission regression | Source resolved before required raw reads; no-query cached score cannot clear the receipt. |
| Notification task and derived/companion publication | Visible completion independent of evaluation; valid-cache activations still evaluate; deduplication and send-time revision/consent checks; no false freshness. |
| Empty, hidden, and failed query results | Existing accessible-data semantics retained; no claim that sharing authorization, discovered sources, or neighboring samples prove read permission; failure does not become empty. |

Use gated fake reads and actual query/persistence assertions. The cancellation test must include the shared pool and stale queued save paths, not merely observe a cancelled Task flag. Integration tests for journal/backfill ownership are required even though their historical algorithms remain unchanged.

## Phase B additions

- A history-only receipt is admitted during a background opportunity and can clear only after the required full coverage/publication succeeds.
- One completed domain survives reload while a second interrupted domain stays pending.
- Full retained intraday versus passive incremental coverage is distinguished.
- Lock/expiry/source change/foreground takeover rejects late writes and acknowledgments.
- History does not delay earlier background notifications beyond their existing ordering; periodic staleness creates no synthetic obligations.
- A domain that cannot finish inside the lease remains eligible for quiet foreground completion; no false checkpoint or manufactured completion.

## Measurements and acceptance

Measure per-domain source, summary, daily/range, comparison, intraday, compute and persistence cost; total query count, payload/ledger write count and bytes; foreground admission/current publication/badge duration; quiet/background drain time and oldest pending age. Do not sum overlapping timers.

Acceptance is **no application-level waiting for maintenance on the foreground refresh path** and no badge/gesture lock owned by quiet history. Existing distinct pools make this possible without increasing limits. HealthKit service contention or OS scheduling can still affect actual latency; physical healthd concurrency is not a claimed guarantee.

Exercise scrolling, chart scrubbing, navigation, and pull-to-refresh during maintenance. Long main-actor compute/merge or disk work that freezes interaction fails the goal. Completed coverage and truthful freshness remain mandatory even if the UI is fast.

Phase A should not add repeated full-scope reads or persistence work for domains the foreground already covered. Domain splitting is justified only by a before/after latency and total-work comparison. Stop a domain's immediate self-retry after failure; prove later external opportunities retry it.

## Device sequence: iPhonePro only

1. Record exact destination, build/local diff, OS, launch reference/PID, and settings. Preserve container and personal health data.
2. Capture cold/warm clean and history-pending openings, distinguishing cached presentation, current publication, badge completion, and queue drain.
3. Capture natural Watch deliveries; the user need not predict sync timing. Confirm pending work remains truthful during bursts and converges after sufficient stable eligible runtime.
4. While quiet repair is active, navigate/scrub/pull. Background and reopen; verify foreground preemption and durable domain-level resume.
5. For Phase B, capture a natural background opportunity when available. Debug-triggered execution may validate code paths but does not prove iOS scheduling.
6. Use fixtures for destructive/rare scenarios. Do not fabricate personal HealthKit records or clear caches. Report uncaptured device scenarios instead of waiting indefinitely or treating absence of events as success.

## Build and reporting gates

Focused tests first, then full Body XCTest, generic iOS Release, and signed device build. Include Watch verification when shared query/companion contracts change. Re-run appropriate checks after Phase B. Record result paths and distinguish simulated logic from physical device performance.

Extend existing diagnostics with purpose, token/pass, domain/generation, coverage, queue age/count, preemption and durability. Avoid health values, event dates, source/sample/workout identifiers. Raw captures remain ignored; findings go in ObserverRefreshValidation.md.

Overall completion requires both Phase A responsiveness/quiet progress and Phase B background historical progress where eligible. Neither opportunistic iOS execution nor perpetually changing generations provides a guaranteed completion deadline. Existing stress failure cannot be reported as a successful drain.
