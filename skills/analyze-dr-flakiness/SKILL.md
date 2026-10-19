---
name: analyze-dr-flakiness
description: Use when the DR e2e suite has been intermittently failing across multiple runs and you need to find when flakiness started, whether it's DR-specific or a shared-infrastructure cause, without a specific PR to debug reactively.
---

# Analyze DR Flakiness

Batch, read-only analysis of DR test flakiness across both DR-related Prow jobs. Walks job history backward, classifies each run, and produces one correlated report. Does not apply fixes or trigger `/retest` — for that, hand off to `infra_superpowers:debug-dr-ci`.

**When this skill is activated, tell the user:** "Using the **analyze-dr-flakiness** skill to scan DR job history." Then show the checklist from the Workflow section.

## Jobs Analyzed

| Job | Type | GCS root |
|-----|------|----------|
| `periodic-ci-redhat-appstudio-infra-deployments-main-ocp420-konflux-e2e-v420` | periodic, multi-suite | `logs/<job>/<build_id>/` |
| `pull-ci-redhat-appstudio-infra-deployments-main-appstudio-konflux-disaster-recovery` | PR-triggered, DR-only | `pr-logs/pull/redhat-appstudio_infra-deployments/<pr>/<job>/<build_id>/` |

**REQUIRED REFERENCE:** See `gcs-reference.md` in this directory for exact artifact paths, the GCS JSON API calls, the per-run record schema, and the floor date fact.

## Non-Goals

- Does not apply fixes or trigger `/retest` — diagnosis only.
- Does not replace `debug-dr-ci`'s single-PR reactive flow.
- Does not build an MCP server — `curl` against the GCS JSON API is sufficient.

## Workflow

```
- [ ] Step 1: Enumerate history + walk backward per job
- [ ] Step 2: Dispatch per-run classifier subagents
- [ ] Step 3: Diagnose (pitfalls → archive → env facts → correlation)
- [ ] Step 4: Write report + append new pitfalls
```

### Step 1: Enumerate History + Walk Backward Per Job

Run `scripts/enumerate-runs.sh` for both jobs (see `gcs-reference.md` for exact invocations). This gives the full list of build IDs, descending, for each job.

Walk backward through each job's list **independently** in batches (batch size: 10 runs). After classifying each batch (Step 2), check the stop conditions before dispatching the next batch:

**Stop conditions (first one to fire wins):**
1. **Consistent-pass streak** — 5 consecutive runs with `dr_result: "pass"`, no `"fail"` in between (a `"no-artifacts"` or `"absent"` run breaks a streak — it's not a pass). Default streak length is 5; the user can override per invocation.
2. **Floor date reached** — a run's `timestamp` is before **2026-08-19** (see `gcs-reference.md`). Stop the walk for that job; do not fetch further back.

If the floor is reached with no clean streak found, note in the report: "flakiness has been present since introduction, no clean baseline found." Do not guess further back than the floor.

If a batch's classifier results show a mismatch between the floor date and the observed `absent`/`no-artifacts` boundary (e.g. runs after 2026-08-19 still show `absent` rather than `pass`/`fail`), record this explicitly — it's a finding, not an error to reconcile silently.

### Step 2: Dispatch Per-Run Classifier Subagents

For each run in the current batch, construct the artifact URLs from `gcs-reference.md`'s path tables and dispatch one subagent using `classifier-prompt.md`, filling in `{{job_type}}`, `{{run_id}}`, and the four artifact URLs (`finished.json`, JUnit report, build log, `started.json`).

**Dispatch all runs in the batch in parallel** — one subagent per run, not sequentially. **Model: `claude-sonnet-5`.** This is an explicit, design-approved exception to the standing "always Opus" subagent preference — justified by expected volume (60-150+ subagents across both job histories in a single session). Do not extend this exception to other skills.

Collect all returned JSON records into the running list for that job. A subagent returning malformed JSON or timing out counts as `no-artifacts` for that run — log it and continue the walk. A single bad run must never abort the batch.

### Step 3: Diagnose

Run this pass after all batches for both jobs have been classified (or a stop condition fired for each).

**Pass 1 — Known pitfalls.** For every record with `dr_result: "fail"`, grep its `dr_error_signature` against `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/common-pitfalls.md`. Attach the matched pitfall ID to the record, or mark it `new-pattern` if no match.

**Pass 2 — Archived failures.** For records marked `new-pattern`, grep the signature against `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/debug-journal-archive.md`. If found, this is a documented-but-uncatalogued regression — note it.

**Pass 3 — Environment facts.** Read `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/environment-facts.md`. Cross-check any remaining `new-pattern` signatures against "Potential Remaining Gaps" for a plausible match.

**Pass 4 — Correlation (periodic job only).** For each periodic-job record:
- `dr_result: "fail"` AND any `other_suites` value is `"fail"` → tag `shared-cause candidate`.
- `dr_result: "fail"` AND all `other_suites` values are `"pass"` (or `other_suites` is empty) → tag `DR-specific candidate`.

**Pass 5 — Cross-job contradiction check.** For every `shared-cause candidate`, compare its `dr_error_signature` against every `"fail"` record in the presubmit (PR-triggered) job's history. The presubmit job is DR-only by construction, so any failure there is inherently DR-specific — if its signature matches a `shared-cause candidate`'s signature, that contradicts the shared-cause hypothesis for that signature. State this explicitly in the report. Do not pick a side.

### Step 4: Write Report + Append New Pitfalls

Write the report to `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/flakiness-history-<YYYY-MM-DD>.md`:

```markdown
# DR Flakiness History — <date>

## Periodic Job: periodic-ci-redhat-appstudio-infra-deployments-main-ocp420-konflux-e2e-v420

**Runs scanned:** <N> (from <newest timestamp> back to <oldest timestamp>)
**Stop reason:** <consistent-pass-streak found at <timestamp> | floor date 2026-08-19 reached, no clean streak>

| Run ID | Timestamp | DR Result | Other Suites | Tag | Pitfall Match |
|--------|-----------|-----------|---------------|-----|----------------|
<one row per classified run, most recent first>

## PR-Triggered Job: pull-ci-redhat-appstudio-infra-deployments-main-appstudio-konflux-disaster-recovery

**Runs scanned:** <N>
**Stop reason:** <as above>

| Run ID | PR | Timestamp | DR Result | Pitfall Match |
|--------|-----|-----------|-----------|----------------|
<one row per classified run, most recent first>

## Synthesis

- Shared-cause candidates: <list, with confirming/contradicting cross-job evidence per Pass 5>
- DR-specific candidates: <list>
- Floor/absent boundary check: <matches 2026-08-19 | mismatch — describe>
- New patterns not in common-pitfalls.md: <list, or "none">
```

For every record tagged `new-pattern` in Pass 1 that recurred across 2+ runs (not a one-off), append an entry to `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/common-pitfalls.md` in its existing format:

```markdown
## <short-kebab-id>
- **Error pattern:** `<grep-able error string>`
- **Root cause:** <best-effort description from the diagnosis passes>
- **Fix:** Not yet fixed — surfaced by analyze-dr-flakiness on <date>. See flakiness-history-<date>.md for occurrences.
```

Do not apply code fixes, do not trigger `/retest`. This skill's output feeds `debug-dr-ci` or manual work.
