# DR Debug Journal -- PR #13427 / PR #13583

## Current State
- Last result: **Iteration 36 — historical flakiness scan (110 runs, 2026-08-19 to 2026-09-03), 8 confirmed DR-specific failures, root-caused component-by-component.** Real cause: transient Quay registry-access failures (401 Unauthorized or CDN-fetch EOF) permanently failing a build PipelineRun, blocking that component's Release forever. `dr-release-stuck-timeout` and `dr-quay-push-auth-failure` pitfalls merged into `dr-quay-registry-transient-failure` — confirmed to be the same bug. Separate, non-blocking bug found: Velero restore drops `status` subresource on Release CRs. Fail-fast fix for the suite's blind-polling gap applied (not yet CI-validated).
- Last push: 2026-08-18 (Release CR counting fix, PR #13583) — no new push yet for iteration 36's fail-fast fix
- Step script points to: redhat-appstudio/infra-deployments main (no fork override)
- Remaining known issues: SprayProxy `payload signature check failed` errors (secondary, non-blocking). PaC webhook delivery post-upgrade still unknown (backwards-compat tests still commented out). MinIO tarball size check skipped (DNS resolution, non-blocking). OCP 4.19 cluster used despite config specifying 4.18 (pool availability change). Quay registry-access transient failures (see `dr-quay-registry-transient-failure` pitfall) — external, no suite-side fix possible; moshekipod is structurally more exposed (always pushed second in sequential trigger loops).
- **Status: Fix PR #13583 open as draft.** Merge to main required before rehearsal on openshift/release PR #83385 can validate.
- **Review changes applied (2026-08-10):** Context propagation, credential validation, conflict retry, log timeout, go mod tidy, minor style fixes. See Iteration 33.
- **Bot review fixes applied (2026-08-10):** `exec.CommandContext` timeout on diagnostics helpers, `PodLogTailLines` casing, `oc` error logging. See Iteration 33 addendum.
- **Fix applied (iteration 32):** Replaced `reconcileComponentOwnership` (1:1 name-based ownerReference patching) with `verifyPaCRepositories` (URL-based existence check). Build-service now creates shared Repository CRs named from git URL, not Component name. OwnerReference patching no longer needed.
- **Fix applied (iteration 30):** Replaced PR-based trigger with push-to-default-branch in `triggerBuildsAndVerify`. Push events produce push-type Snapshots eligible for auto-release. Removed no-op `dr.redhat.com/restore-trigger` ReleasePlan annotation. Enhanced `logReleaseChainDiagnostics` with Snapshot event-type and test-status annotation output.
- **Fix applied (iteration 17):** Merged `stripAllFinalizers` and `deleteNamespace` into single `stripAndDeleteNamespaces()` — strips finalizers per-namespace and immediately deletes. **CONFIRMED WORKING** in iteration 21.
- **Fix applied (iteration 21):** Added container log capture to `logFailedTaskRuns` — reads last 80 lines of each failing step container's pod logs. **CONFIRMED WORKING** — revealed root cause.
- **Fix applied (iteration 22):** Added `waitForPushSecretReadiness()` between `verifyResources` and `triggerBuildsAndVerify` in Phase 6. **CONFIRMED WORKING** — correctly detected damaged IR.
- **Fix applied (iteration 23):** Added damaged-IR recovery to `waitForPushSecretReadiness()`. **CONFIRMED WORKING** — all 6 IRs re-provisioned, all 6 builds succeeded.
- **Fix applied (iteration 24):** Extended `waitForPushSecretReadiness()` to validate pull secrets alongside push secrets. Same validation: `.dockerconfigjson` parse, base64 decode, colon separator. Both must pass within 5-minute timeout before builds trigger.
- **Fix applied (iteration 26):** Added `ensurePullSecretsOnSA()` — explicitly links IR pull secrets to pipeline SA `.secrets` and `.imagePullSecrets`. Tekton credential initialization reads SA `.secrets` only; pull secrets existed but were not linked. **UNTESTED** — iteration 26 run hit the overshoot stall before reaching EC verify.
- **Fix applied (iteration 27):** Added overshoot fail-fast in `waitForSucceededPRCount`. Preserves exact-equality semantics. **CONFIRMED WORKING** — fired correctly with diagnostic dump.
- **Fix applied (iteration 28):** Changed `Equal` to `BeNumerically(">=", expectedCount)` in `waitForSucceededPRCount`. Overshoot tolerated with diagnostic logging. TODO documents integration-service crash-recovery bug. Revert to `Equal` once upstream fixes annotation-only dedup.
- **Root cause confirmed (iteration 22-24):** Strip+delete race causes stale Quay robot credentials. Push side fixed (iterations 22-23). Pull side validated (iteration 24) but SA linkage gap remained (iteration 26).
- **Root cause confirmed (iteration 28):** Duplicate test PipelineRuns caused by integration-service crash-recovery bug — annotation-only dedup with deferred write. Evidence extracted to `debugger-evidence/`.
- **Investigation docs:** plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/pac-webhook-investigation/
- **Bug evidence:** plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/debugger-evidence/integration-service-crash-recovery-dedup/

## Recent Iterations (last 3)

### Iteration 36 -- 2026-09-08 (Quay registry-access failure root-caused; suite blind-polling fail-fast fix)
- **Source:** Historical flakiness scan of 110 Prow job-history runs (2026-08-19 to 2026-09-03), documented in `flakiness-history-2026-09-06.md`. 8 confirmed DR-specific test failures, each verified component-by-component (not pattern-matched) against `build-log.txt`, `releases.json`/`pipelineruns.json` (from the `redhat-appstudio-gather` Prow step, not previously downloaded), and integration-service's own controller-manager pod logs.
- **Root cause:** transient Quay registry-access failures in the build pipeline — two HTTP-level shapes: `401 Unauthorized` (read or write) and CDN-fetch `EOF`. Permanently fails one or more component builds; that component's Release is never created; the tenant namespace's released-count permanently stalls below `expectedCount`. External to the DR suite and to release-service — no code fix addresses the flake itself.
- **Structural detail found:** 3 of 8 occurrences are a "whole-tenant wipeout" of `moshekipod` specifically (every component fails), not random — `mergePaCConfigPRs` (Phase 1) and `triggerBuildsAndVerify` (Phase 6) both trigger tenants via a sequential `for` loop, kokohazamar always first, moshekipod always second, in every build wave in the suite.
- **Ruled out:** integration-service PR konflux-ci/integration-service#1680 (unrelated — a flaky-unit-test fix in that repo's own `loader_test.go`, nothing to do with PipelineRuns or Releases).
- **Catalog change:** merged `dr-release-stuck-timeout` and `dr-quay-push-auth-failure` into `dr-quay-registry-transient-failure` in `common-pitfalls.md` — deeper verification showed they were the same bug, split only because one run (2094710382030491648) got externally aborted before its internal hang fully played out.
- **Separate finding (non-blocking, does not fail the suite):** Velero restore does not restore the `status` subresource on Release CRs — confirmed directly via `releases.json` for run 2092002955354968064 (restored Release `creationTimestamp` lands 2s after the `Velero Restore` CR is created; `status.automated` and `Released` conditions both come back wiped). Catalogued as `dr-restore-wipes-release-status`. Doesn't block the suite because `waitForReleasedCount` counts all `Released=True` objects regardless of origin, and Phase 6 creates entirely fresh Releases independent of the broken restored ones.
- **Fix applied:** `waitForSucceededPRCount` and `waitForReleasedCount` (`tenant_application_lifecycle.go`) now call Gomega's `StopTrying()` on a terminal failure (`Succeeded=False` on a PipelineRun with no chance of a new one; `Released=False Reason=Failed` on a Release CR) instead of polling blindly to the full `PipelineTimeout`(90min)/`ReleaseChainTimeout`(60min) budget. Turns a silent 2h/no-JUnit hang into an immediate, diagnosable failure. Does not fix the Quay flake itself — catalogued as `dr-suite-blind-polling-timeout`.
- **Classification:** environment-gap (external Quay transience) for the primary bug; test-code (blind-polling gap) for the suite-side mitigation
- **Files changed:** `tenant_application_lifecycle.go`
- **Confidence:** high for root cause (component-by-component evidence across all 8 runs); the fail-fast fix is untested in CI as of this iteration.
- **Expected next-run outcome:** does not prevent the Quay flake from occurring; when it does occur, the suite now fails fast with a clear message instead of hanging 2h with no JUnit.

### Iteration 35 -- 2026-08-18 (release PLR cleanup race)
- **Prow job:** https://prow.ci.openshift.org/view/gs/test-platform-results/pr-logs/pull/openshift_release/83385/rehearse-83385-pull-ci-redhat-appstudio-infra-deployments-main-appstudio-konflux-disaster-recovery/2089639823907229696
- **Source PR:** openshift/release PR #83385 (broaden DR e2e trigger scope)
- **Failures found:** 12/13 passed, 1 failed. `waitForSucceededPRCount` timed out polling release PipelineRuns in managed namespace. Count went backwards: 2/3 → 1/3 → 0/3 (total: 3 → 1 → 0).
- **Root cause:** Release-service's `cleanupPipelineResources` (`controllers/release/adapter.go`) deletes completed release PipelineRuns from the managed namespace after Release CR finishes processing. Behavior exists since Nov 2025 (release-service PR #1042). Cleanup timing is non-deterministic — PLRs survived 17+ minutes in passing runs but were deleted within 10 minutes in this run. Test was always fragile; 3/4 historical runs won the race by catching PLRs before cleanup ran.
- **Evidence:** Pre-backup phase: 0/3 → 3/3 in 1 poll (PLRs still running when polled). Post-restore phase: 8-minute gap between PLR completion (~10:13:30) and polling start (~10:15:17). PLRs deleted within ~100s of completion. Diagnostics dump at 10:14:03 showed 2 Succeeded + 1 Running — all gone by first poll at 10:15:17. Historical analysis of 3 passing runs confirmed all caught PLRs in 1-2 poll cycles before cleanup.
- **Fix:** Replaced release PipelineRun counting with Release CR counting. New `countReleasedReleases` and `waitForReleasedCount` functions check `release.IsReleased()` on Release CRs in tenant namespace (not managed namespace). Release CRs persist with days-scale ExpirationTime. Submitted as PR #13583 on redhat-appstudio/infra-deployments.
- **Classification:** test-code (latent race condition — counting ephemeral PipelineRuns instead of persistent Release CRs)
- **Artifact:** Same prow job
- **Files changed:** `tenant_application_lifecycle.go`
- **Confidence:** high. `cleanupPipelineResources` confirmed in release-service source. `IsReleased()` is canonical API. No timing dependency.
- **Expected next-run outcome:** Release verification uses stable Release CRs → no race with PLR cleanup → 13/13 pass.

### Iteration 34 -- 2026-08-12 (Quay robot account name format mismatch)
- **Prow job:** https://prow.ci.openshift.org/view/gs/test-platform-results/pr-logs/pull/redhat-appstudio_infra-deployments/13427/pull-ci-redhat-appstudio-infra-deployments-main-appstudio-konflux-disaster-recovery/2087138920650248192
- **Failures found:** 10/13 passed, 1 failed, 2 skipped. `waitForPushSecretReadiness` timed out after 300s. Push secret auth username `redhat-appstudio-qe+robot_name` did not match expected `robot_name`.
- **Root cause:** `validateDockerConfigSecret` (added in iteration 33 review hardening) used exact equality to compare docker config auth username against `ImageRepository.Status.Credentials.PushRobotAccountName`. Quay stores auth as `org+robot_name`, but IR status stores only `robot_name`.
- **Fix:** Added `strings.HasSuffix(username, "+"+robotAccountName)` as alternative match on line 486 of `disaster_recovery.go`. Accepts both exact match and Quay's `org+name` format.
- **Classification:** test-code (incorrect string comparison in validation)
- **Artifact:** Same prow job
- **Files changed:** `disaster_recovery.go`
- **Confidence:** high. Error message shows exact mismatch. Quay `org+name` format is standard.
- **Expected next-run outcome:** Push/pull secret validation passes → builds trigger → 13/13 pass. If a different auth format surfaces, assertion fails with clear diagnostic.

### Iteration 33 -- 2026-08-10 (code review feedback — PR #13320)
- **Source:** External reviewer comments on PR #13320
- **Changes applied:**
  1. **Context propagation** — 8 functions across `tenant_application_lifecycle.go` and `backup_infra.go` now accept `ctx context.Context` from caller instead of creating `context.Background()` internally. Callers in `dr_same_version.go` updated. 17 additional occurrences identified in `disaster_recovery.go` (not applied — larger scope).
  2. **`validateDockerConfigSecret` hardened** — Now validates non-empty username AND password after base64 decode. Matches decoded username against expected `robotAccountName` when provided. Prevents false-positive readiness on stale/empty credentials.
  3. **`stripFinalizers` conflict retry** — Added bounded retry loop (5 attempts) with re-fetch on `IsConflict`. Treats `IsNotFound` as success. Prevents flaky failures when controllers update objects between List and Update.
  4. **`logFailedStepContainers` timeout** — Pod log streaming now uses `context.WithTimeout(ctx, 30s)` to prevent indefinite hangs on stalled API connections during failure diagnostics.
  5. **Webhook verification simplified** — Replaced `func() bool` + manual tracking with `func(g Gomega)` pattern. Preserves all DIAGNOSTIC logging. Fixes reviewer suggestion bugs (syntax + semantics).
  6. **`go mod tidy`** — Cleaned stale dependencies per reviewer request.
  7. **PipelineRun overshoot upper bound** — `waitForSucceededPRCount` now asserts `>= expected AND <= expected*2` via `SatisfyAll`. Tolerates known integration-service dedup bug overshoot, fails on pathological duplication.
  8. **Minor style:** `for _, ns := range` (cleanup loop), `path.Join` for Dockerfile path, `podLogTailLines` const, `// #nosec G204` on `collectPaCDiagnostics`.
- **Bot comments evaluated:** `len(repo.Status)` "compile error" is wrong — `Repository.Status` is `[]RepositoryRunStatus` (a slice). Other bot suggestions (overbroad cleanup, test-relaxation bounds) noted but not applied — low-risk or out of scope.
- **PaC version (v0.34.0 vs v0.50.0):** Under investigation — checking transitive dependency impact.
- **Classification:** review-feedback (no functional test changes)
- **Files changed:** `tenant_application_lifecycle.go`, `backup_infra.go`, `disaster_recovery.go`, `dr_same_version.go`, `go.mod`, `go.sum`

#### Iteration 33 addendum — bot review fixes (2026-08-10)
- **Source:** qodo-for-redhat-appstudio (review 4894946855), fullsend-ai-review (review 4895119460)
- **Fixes applied:**
  1. **`exec.CommandContext` timeout on diagnostics** — Both `run` closures in `logReleaseChainDiagnostics` and `collectPaCDiagnostics` now use `exec.CommandContext` with 2-minute timeout. Prevents indefinite hangs when API server is distressed during failure-path diagnostics.
  2. **`podLogTailLines` → `PodLogTailLines`** — Renamed to PascalCase to match package-level constant convention (`ComponentsPerTenant`, `BackupMinItemCount`, etc.).
  3. **`oc` error logging in diagnostics helpers** — Both `run` closures now capture `err` from `CombinedOutput()` and prefix output with command args, error, and `cmdCtx.Err()` (timeout vs cancel). Distinguishes empty results from command failures, especially relevant for the timeout we just added.
- **Pushed back:**
  1. **Webhook PLR count subtraction** (qodo) — Suite runs on isolated ROSA cluster with no PipelineRun pruning during the 5-minute webhook delivery window. Timestamp-based filtering adds complexity without addressing a real failure mode.
  2. **`stripFinalizers` variadic `bestEffort ...bool`** (fullsend-ai) — Idiomatic Go for optional flags. Converting to required bool adds `false` to 11 call sites for zero functional benefit.
- **Dismissed:**
  1. **`cleanupDanglingNamespaces` on failure path** (fullsend-ai) — Suite runs on ephemeral cluster claims destroyed after the job. No manual post-test investigation occurs. Unconditional cleanup prevents finalizer-blocked namespace deletion from stalling cluster teardown.
- **Files changed:** `disaster_recovery.go`, `tenant_application_lifecycle.go`


(Iterations 1-32 graduated to archive)
