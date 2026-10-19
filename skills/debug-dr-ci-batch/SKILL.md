---
name: debug-dr-ci-batch
description: Use when diagnosing many historical, already-closed DR CI prow job failures over a date range (batch flakiness triage) rather than one live PR — no fix/commit/retest, just a root-cause finding per run at controlled cost via a two-model split.
---

# Debug DR CI Failures — Batch Mode

Diagnostic-only adaptation of `debug-dr-ci` Steps 1-4, for scanning dozens of closed prow runs instead of debugging one live PR. No fix, no commit, no `/retest`, no `debug-journal.md` mutation — each run produces one structured finding, then all findings roll into one aggregate report.

**REQUIRED BACKGROUND:** Read `debug-dr-ci`'s common-pitfalls.md, environment-facts.md, and Step 3 diagnosis passes — this skill reuses that diagnostic logic, only the artifact-handling and model assignment differ.

## When to Use

- "Debug every failed DR run since \<date>" / batch flakiness analysis over a date range.
- NOT for a single live PR with a failure to fix now — use `debug-dr-ci` for that (it has the fix→commit→retest cycle this skill deliberately omits).

## Step 0: Build the Run List

Prow's job-history page embeds a JSON array in the HTML (`var allBuilds = [...]`), not just the last page. Paginate backward with `?buildId=<oldest ID from previous page>` until the oldest `Started` timestamp passes your date floor:

```bash
curl -s "https://prow.ci.openshift.org/job-history/gs/test-platform-results-public/pr-logs/directory/pull-ci-redhat-appstudio-infra-deployments-main-appstudio-konflux-disaster-recovery" \
  | grep -o 'var allBuilds = \[.*\];'
```

Filter to `"Result":"FAILURE"` within range. **Do not construct the GCS artifact path yourself.** Take each run's exact path from its own `SpyglassLink` field — bucket name is per-run, not constant:

- Recent runs: `test-platform-results-public` (anonymous curl works).
- Older runs (observed: pre ~2026-09-15 for this job): `test-platform-results` — **private**, anonymous curl returns 403. Try `gsutil cat gs://test-platform-results/...` as fallback (requires an IAM grant on that bucket, separate from `gcloud auth login` — reauth alone does not fix a 403 `storage.objects.get` denial). If both fail, classify the run as `artifacts-inaccessible` and move on — do not guess at its cause.

## Step 1: Per-Run Two-Model Pipeline

One evidence directory per run: `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/debugger-evidence/flakiness-evidence/<run-id>/` (existing convention — reuse it, don't invent a new path).

**The orchestrating session never reads raw build-log.txt/junit.xml itself.** It only dispatches the two subagents below and reads their final text output. Every raw-artifact byte gets read by exactly one model, exactly once.

### 1a. Mechanical pass — dispatch with `model: "haiku"`

Give it the run's artifact paths (or download URLs) and this exact order of operations:

1. **Install/setup fast path first, before touching junit.xml.** Grep `build-log.txt` for, in order: the `install-konflux-cluster-unreachable` pattern (`Unable to connect to the server: EOF` in the `konflux-ci-install-konflux` step, exit 124), the `ci-scheduling-timeout` pattern (`pod has not been scheduled`), and any other step failure/non-zero exit **before** the Ginkgo suite-start marker. A pass-only inference like "junit exists, so ginkgo ran" is not a substitute for this grep — run it even when a fast pattern match looks unlikely.
   - **If matched:** write the evidence file with just the pitfall ID, the exact quoted line(s) with line numbers, and the failing step name. Stop — do not parse junit.xml. That match *is* the finding for this run.
2. **If no install-stage match:** parse `finished.json` for pass/fail + timestamp; extract every `<testcase>`/`<failure>` from `junit_dr.xml` verbatim; pull enough surrounding `build-log.txt` context around each failure/error marker (lines before/after, stage timeline, exit codes) that nobody needs to reopen the raw log afterward.
3. **Write everything to `<evidence-dir>/evidence.md`, quoted verbatim — no paraphrasing, no conclusions.** Root-cause judgment is not this model's job.
4. Report back only the evidence file's path, not its content.

### 1b. Judgment pass — dispatch with `model: "sonnet"` (not Opus — see Model Assignment)

Give it only the evidence file path. Instruct it explicitly: **for the CI run itself, read that file and nothing else** — not `build-log.txt`, not `junit_dr.xml`, not `finished.json`. If the evidence is too thin to reach a confident conclusion, say exactly what's missing rather than opening the raw artifacts to compensate.

This restriction covers only the raw per-run artifacts. It must still read the standing reference docs to run `debug-dr-ci` Step 3's diagnosis passes in order — `common-pitfalls.md` (pass 1), `debug-journal-archive.md` (pass 2, grep for the error pattern), `environment-facts.md` (pass 3) — against the evidence file's content, before falling back to pass 4 root-cause reasoning. Skipping this cross-reference (treating "read only the evidence file" as forbidding these too) is the most common misreading of this step — don't make it. Then emit `debug-dr-ci` Step 4's structured finding format, with `Classification` extended to include `install-setup` and `artifacts-inaccessible` alongside the original four. Confidence must reflect what the evidence file actually contained.

## Model Assignment (pinned, not inferred per-run)

| Stage | Model | Why |
|---|---|---|
| Run-list discovery, orchestration | (this session) | Never touches raw artifacts |
| Mechanical extraction | `haiku` | Cheap, mechanical: grep, quote, no judgment |
| Root-cause judgment | `sonnet` | Overrides the standing all-Opus subagent default — approved exception for high-volume batch fan-out (dozens+ runs), same basis as the `analyze-dr-flakiness` skill design |

## What Not to Do (found by baseline testing without this skill)

| Observed behavior | Why it's wrong |
|---|---|
| Orchestrator reads `finished.json` itself, then further compresses Haiku's extraction before pasting it to the judgment model | Every paraphrase hop between the log and the judgment model risks dropping exactly the detail needed — baseline run's judgment model landed at "medium-low confidence" and named a gap that its own re-summarized input had already erased. Haiku writes the file; the judgment model reads that file directly. No third party touches the content in between. |
| Inferring install-vs-test from "Ginkgo start marker present" instead of grepping the named pitfalls first | Works by luck, not by design — always run the pitfall greps in Step 1a order 1, even when a suite clearly ran. |
| Defaulting to Opus for the judgment pass | 5x Sonnet's cost per output token at this volume; Sonnet is the approved exception model here, not Opus. |

## No Fix, No Retest, No Journal

This skill never edits `infra-deployments`, never runs `/retest`, never appends to `debug-journal.md`. It stops at one structured finding per run.

## Aggregate Report

One file: `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/flakiness-history-<date>.md`. Two sections only:

1. **Main analysis** — runs scanned, date range, stop reason (floor date reached / consistent-pass streak), then category counts + percentages (aborted, install/setup failure, test failure by pattern, artifacts-inaccessible, etc.).
2. **Synthesis** — brief prose: new recurring patterns not yet in `common-pitfalls.md`, shared-infra-vs-DR-specific signal, notable one-off anomalies.

Do **not** include a per-run pitfall-match-rate table or a PR-clustering/retest-follow-up section — out of scope for this skill (contrast with the fuller `flakiness-history-2026-09-06.md` precedent, which included both).
