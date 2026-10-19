# Common Pitfalls

## velero-cli-missing
- **Error pattern:** `velero CLI executable was not found in $PATH`
- **Root cause:** Step script did not install velero CLI binary. OADP deploys server-side velero pods but not the CLI.
- **Fix:** Added curl/tar/cp block to install velero CLI from GitHub releases.

## infra-deployments-path-mismatch
- **Error pattern:** `failed to open infra-deployments repo at ./tmp/infra-deployments`
- **Root cause:** Go code uses relative path `./tmp/infra-deployments` (resolves from ginkgo CWD = test suite dir). Step script cloned to absolute `/tmp/infra-deployments`.
- **Fix:** Created symlink `${INFRA_DIR}/tests/disaster-recovery/tmp/infra-deployments -> ${INFRA_DIR}`.

## generated-config-stale
- **Error pattern:** `generated-config` CI check fails
- **Root cause:** ci-operator config changed without running `make update`.
- **Fix:** Run `make update` in the release repo after any config change.

## ci-scheduling-timeout
- **Error pattern:** `pod pending for more than 1h0m0s: pod has not been scheduled`
- **Root cause:** CI build cluster (e.g. build06) under pressure — nodes tainted/unschedulable, pod affinity mismatch. Step script never runs.
- **Fix:** `/retest` — transient infrastructure issue. No code change needed.

## velero-install-path-permission
- **Error pattern:** `cp: cannot create regular file '/usr/local/bin/velero': Permission denied`
- **Root cause:** CI container runs as non-root user. `/usr/local/bin/` is not writable. `set -o errexit` kills the script immediately.
- **Fix:** Install velero to `/tmp/bin/velero` instead. The script already adds `/tmp/bin` to PATH (lines 7-8).

## install-konflux-cluster-unreachable
- **Error pattern:** `Unable to connect to the server: EOF` in `konflux-ci-install-konflux` step, exit code 124
- **Root cause:** Claimed cluster API becomes unreachable after health-check passes. Transient cluster instability.
- **Fix:** `/pj-rehearse` — transient infrastructure issue. No code change needed.

## hardcoded-fork-reference
- **Error pattern:** Clone fails or wrong test code version runs
- **Root cause:** Step script hardcoded `manish-jangra/infra-deployments` branch `K-2236-03` instead of upstream.
- **Fix:** Reverted to `redhat-appstudio/infra-deployments` branch `main` after companion PR merged.

## backup-minio-tenant-crd-unavailable
- **Error pattern:** `backup-in-cluster-local OutOfSync/Degraded` with `Secret/minio-storage-configuration: Missing`, `Job/create-velero-bucket: Missing`
- **Root cause:** MinIO Tenant CRD (`minio.min.io/v2`) not available on the cluster. The MinIO Operator (deployed by pipeline-service, sync wave -2) fails to register CRDs on OCP 4.19. All working `konflux-ci-install-konflux` jobs use OCP 4.18.
- **Fix:** Set `cluster_claim.version` to `"4.18"` in ci-operator config. Match the version used by `appstudio-e2e-tests`.

## pac-repository-ownerref-stripped
- **Error pattern:** `no PaC Repository CR owned by component`
- **Root cause:** Velero's `resetMetadata` strips ownerReferences during restore. PaC Repository CRs exist but lose their Component ownerReference. Build-service only sets ownerReferences during initial Repository creation — it does **not** re-establish them when reconciling an existing Repository CR. Annotating Components does not trigger ownership restoration.
- **Fix:** Direct ownerReference patching via K8s API. List PaC Repository CRs, get Component UIDs, set ownerReferences, verify with `GetRepositoryParams`. No build-service dependency.
- **Prior failed approach:** Annotating Components with `dr-restore-reconcile-trigger` to trigger build-service reconciliation. Timed out after 5m — build-service sees existing Repository and skips creation.

## post-restore-pac-webhooks-broken
- **Error pattern:** `0/1 build PipelineRuns succeeded` for full PipelineTimeout with zero FAILED messages
- **Root cause:** PaC webhook delivery chain (GitHub App → SprayProxy → PaC event listener → PipelineRun) breaks after Konflux upgrade phase. PipelineRuns are never created — they do not exist, not stuck. Pre-upgrade webhooks work. Exact broken link unknown (SprayProxy registration stale, PaC config reset, or event listener route changed during ArgoCD sync).
- **Fix:** Added 5-minute early detection check (`WebhookDeliveryTimeout`) in `triggerBuildsAndVerify`. Snapshots total PipelineRun count before trigger PRs, verifies new ones appear within 5min. Added `(total: N)` to poll log lines. Underlying PaC issue remains — this fix provides diagnostic data and saves 85min of wasted CI time.
- **Diagnostic clue:** Zero FAILED messages means zero PipelineRuns exist (not failing, not stuck — absent). Compare against pre-upgrade build phase where cancelled/succeeded PipelineRuns are logged.

## trigger-pr-cel-path-mismatch
- **Error pattern:** `CEL expression for PipelineRun mathwizz-*-on-pull-request is not matching, skipping`
- **Root cause:** Trigger PRs modified `README.md` at repo root. PaC PipelineRun definitions use `.pathChanged()` CEL expressions scoped to component subdirectories (`frontend/***`, `history-worker/***`, `web-server/***`). Root-level files match no component.
- **Fix:** Modify each component's `Dockerfile` (or any file in its context directory) instead of root-level files.

## sa-token-secret-not-autocreated
- **Error pattern:** `at least one ServiceAccount token Secret should exist in namespace`
- **Root cause:** K8s 1.24+ deprecated auto-creation of `kubernetes.io/service-account-token` Secrets (GA removal in 1.26). On OCP 4.18 (K8s 1.31), no SA token secrets exist unless explicitly created. `rotateSATokens` correctly no-ops, but `verifyResources` hard-asserted they must exist.
- **Fix:** Converted the `Expect(hasTokenSecret).Should(BeTrue())` assertion in `verifyResources` to an informational `GinkgoWriter.Printf` log.

## trusted-artifact-push-secret-stale
- **Error pattern:** `step-create-trusted-artifact" exited with code 1`
- **Root cause:** During DR drill, `oc delete project` triggers image-controller finalizer on ImageRepository CRs, which deletes Quay robot accounts. Velero restores push secrets with credentials for non-existent robot accounts. `create-trusted-artifact` fails because it cannot authenticate to Quay. This is a drill methodology bug, not a controller bug — real etcd loss does not trigger finalizers. See KFLUXINFRA-3954, STONEBLD-3714.
- **Fix:** `stripAllFinalizers()` removes all finalizers from all resource types before namespace deletion. Matches real etcd-loss semantics. Velero resource modifier strips ImageRepository finalizers during restore (KFLUXINFRA-2177).

## namespace-deletion-finalizer-stall
- **Error pattern:** `namespace was not deleted in expected timeframe` with `Remaining resources in namespace:`
- **Root cause:** `oc delete project` triggers graceful deletion. Multiple Konflux controllers set finalizers on tenant resources: application-service (Application), image-controller (Application, Component, ImageRepository), integration-service (Component, PipelineRun), release-service (Release), pipelines-as-code (PipelineRun). Any finalizer that stalls (external API call, egress blocked, controller overloaded) blocks namespace deletion past the 10-minute timeout.
- **Fix:** Call `stripAndDeleteNamespaces()` — strips finalizers and immediately deletes per-namespace in the same function call. One deterministic operation — no NetworkPolicy, no per-type whack-a-mole, no gap for controller re-addition.
- **Supersedes:** `imagerepository-finalizer-deadlock` (iteration 15), `finalizer-strip-delete-race` (iteration 17).

## push-secret-reconciliation-race
- **Error pattern:** `unauthorized: Could not find robot with specified username: map[]` or `state: damaged (waiting for ready)` timeout
- **Root cause:** After Velero restore, image-controller must reconcile each ImageRepository — creating new Quay robot accounts and writing fresh push secret credentials. If the strip→delete race allowed Quay robot deletion, the controller sets the IR to `damaged` (terminal state) instead of reconciling. If builds trigger before reconciliation completes, `create-trusted-artifact` fails with stale credentials.
- **Fix (iteration 22):** Added `waitForPushSecretReadiness()` as a readiness gate between `verifyResources` and `triggerBuildsAndVerify` in Phase 6.
- **Fix (iteration 23):** Added damaged-IR recovery to `waitForPushSecretReadiness()`. When an IR is in `damaged` state, removes the `appstudio.openshift.io/image-repository` finalizer (once per IR). Image-controller then re-provisions with fresh Quay robot accounts. This is the controller's documented recovery mechanism.
- **Fix (iteration 24):** Extended `waitForPushSecretReadiness()` to validate pull secrets via `PullSecretName` and `PullRobotAccountName`. Same validation as push secrets. EC verify tasks use pull credentials — stale pull robot accounts cause `UNAUTHORIZED` failures even when push credentials are valid.

## ec-pull-secret-sa-linkage
- **Error pattern:** `UNAUTHORIZED: Could not find robot with specified username; map[]` in EC verify tasks despite valid pull secret credentials
- **Root cause:** After IR re-provisioning, pull secrets are created but not linked to the pipeline ServiceAccount's `.secrets` field. Tekton credential initialization only reads SA `.secrets` (not `.imagePullSecrets`) to build `/tekton/creds/.docker/config.json`. Push secrets are linked (builds work), but pull secrets are not automatically linked by image-controller. EC `validate image` uses Tekton-injected creds for programmatic image access.
- **Fix:** Added `ensurePullSecretsOnSA()` between `waitForPushSecretReadiness` and `triggerBuildsAndVerify`. Discovers pipeline SA (`konflux-integration-runner` or `appstudio-pipeline`), iterates each IR's `PullSecretName`, links missing ones via `LinkSecretToServiceAccount` (adds to both `.secrets` and `.imagePullSecrets`).
- **Key distinction:** Push secrets linked → builds succeed. Pull secrets unlinked → EC verify fails. Both are Quay robot account credentials for the same image but served through different SA fields.

## finalizer-strip-delete-race
- **Error pattern:** `"step-create-trusted-artifact" exited with code 1` after successful `stripAllFinalizers()` run
- **Root cause:** `stripAllFinalizers()` and `deleteNamespace()` were in separate Ginkgo `It` specs. Controllers re-add finalizers in the gap between specs (2-43 seconds observed). Image-controller re-adds `appstudio.openshift.io/image-repository`, its handler fires during deletion, deletes Quay robot accounts. Restored push secrets become stale.
- **Fix:** Merged strip + delete into `stripAndDeleteNamespaces()` — one function call per namespace, no spec boundary gap.
- **Superseded by:** integrated into `namespace-deletion-finalizer-stall` fix.

## pr-count-exact-equality-stall
- **Error pattern:** `N/M test PipelineRuns succeeded (total: N)` repeating for 90+ minutes where N > M
- **Root cause:** `waitForSucceededPRCount` used `Equal(expectedCount)` inside `Eventually`. Succeeded PipelineRun count is monotonically increasing. When count overshoots expected (e.g., duplicate PipelineRun from integration-service crash-recovery bug), `Equal` never matches and `Eventually` polls until timeout.
- **Fix (iteration 27):** Added overshoot fail-fast with `Fail()` and diagnostic dump. Exact-equality preserved.
- **Fix (iteration 28):** Replaced `Equal(expectedCount)` with `BeNumerically(">=", expectedCount)`. Overshoot tolerated with diagnostic logging (dump preserved, `Fail()` removed). TODO comment documents integration-service crash-recovery bug — revert to `Equal` once upstream fixes annotation-only dedup.

## pac-repository-naming-change
- **Error pattern:** `expected 3 Repositories to match Components, but only 0 matched` or Repository CR named with URL-derived slug (e.g., `github-com-redhat-appstudio-qe-dr-mathwizz-eyrzqv`) instead of Component name
- **Root cause:** Build-service changed PaC Repository CR naming from Component-name-based (e.g., `mathwizz-web-server`) to URL-derived slugs. Also changed cardinality: monorepo Components now share 1 Repository CR instead of 1:1. Name-equality matching between Repository and Component names finds zero matches.
- **Fix:** Replaced `reconcileComponentOwnership` with `verifyPaCRepositories`. New function lists all Repository CRs in the namespace, verifies they exist and have correct `spec.url` matching the tenant fork URL. No ownerReference patching needed — build-service uses URL-based lookup.
- **Supersedes:** `pac-repository-ownerref-stripped` (iteration 9) — ownerReference patching is no longer relevant since build-service doesn't use ownerReferences for lookup.

## quay-robot-account-org-prefix
- **Error pattern:** `auth username "org+robot_name" does not match expected robot account "robot_name"`
- **Root cause:** Quay docker config auth stores robot account names as `org+robot_name` (e.g., `redhat-appstudio-qe+dr_test_...`). `ImageRepository.Status.Credentials.PushRobotAccountName` stores only the short name without org prefix. Exact equality comparison fails.
- **Fix:** Use `strings.HasSuffix(username, "+"+robotAccountName)` as alternative match alongside exact equality in `validateDockerConfigSecret`.

## pr-event-type-blocks-auto-release
- **Error pattern:** `expected at least N successful release PipelineRuns` with zero new Release CRs despite post-restore Snapshots existing and ReleasePlan/RPA both "Matched"
- **Root cause:** `triggerBuildsAndVerify` created trigger PRs → PaC fired `pull_request`-type PipelineRuns → Snapshots labeled with `pac.test.appstudio.openshift.io/event-type: pull_request`. Integration-service's `CanSnapshotBePromoted()` only auto-releases Snapshots with event-type `push` or absent. Pre-backup builds used PaC onboarding push events (Component creation), so auto-release worked. Post-restore PR events → auto-release blocked → zero Release CRs → zero release PipelineRuns.
- **Fix:** Replaced PR-based trigger with push-to-default-branch in `triggerBuildsAndVerify`. Push events produce push-type Snapshots eligible for auto-release. Also removed no-op `dr.redhat.com/restore-trigger` ReleasePlan annotation (integration-service creates Releases, not release-service).

## release-plr-cleanup-race
- **Error pattern:** `expected N–M successful release PipelineRuns in namespace` with count going backwards (e.g., 2/3 → 1/3 → 0/3) or `(total: 0)` after previously seeing PLRs
- **Root cause:** Release-service's `cleanupPipelineResources` (`controllers/release/adapter.go`) deletes completed release PipelineRuns from the managed namespace after a Release CR finishes processing. Behavior exists since Nov 2025 (release-service PR #1042). Cleanup timing is non-deterministic — PLRs may survive 2-17+ minutes after completion. The test raced against cleanup when counting PLRs; passing runs caught PLRs before deletion, failing runs did not.
- **Fix:** Replaced release PipelineRun counting with Release CR counting. `waitForReleasedCount` checks `release.IsReleased()` on Release CRs in the tenant namespace. Release CRs persist with days-scale ExpirationTime and are not affected by `cleanupPipelineResources`.

## dr-quay-registry-transient-failure
- **Error pattern:** two HTTP-level shapes, both from Quay, both hitting the build pipeline (never release-service):
  1. **401 Unauthorized** — `response status code 401: Unauthorized` / `unexpected status code 401 Unauthorized` / `unauthorized: access to the requested resource is not authorized`, on either a manifest read (`rpm_verifier`, `rpms-signature-scan`) or an image/blob push (`build-container`, `step-upload-sbom`).
  2. **CDN fetch EOF** — `cannot retrieve image configuration for manifest ...: Get "https://cdn01.quay.io/...": EOF`, or `step-use-trusted-artifact` exiting non-zero on a `tar` failure.
  Downstream symptom in both cases: `Waiting for 3 released Releases in dr-test-{kokohazamar,moshekipod}-same-version-dr` (or the build/test-PipelineRun wait) repeating with a partial count that never increases.
- **Root cause:** a transient Quay registry-access failure permanently fails one (or more) component's build PipelineRun. No Snapshot is ever produced for that component, so no Release is ever created for it, so the tenant namespace's released-count permanently stalls below `expectedCount`. The DR suite has no internal timeout that fires before Prow's 2h entrypoint kill, so the job runs to the full 2h with no JUnit report (surfaces as `no-artifacts` unless the build log is inspected for genuine-hang evidence). Confirmed component-by-component (not just pattern-matched) across all 8 occurrences below — see the table in flakiness-history-2026-09-06.md.
- **Two failure shapes observed:**
  - *Isolated, symmetric* (4 runs) — one component (usually `mathwizz-frontend`) fails in one or both tenants; the rest of that tenant's builds succeed normally. Consistent with a one-off transient Quay hiccup.
  - *Whole-tenant wipeout, moshekipod only* (3 of 8 runs) — every component in `dr-test-moshekipod-same-version-dr` fails with `401 Unauthorized`, while kokohazamar is unaffected or loses at most one component. Not random: `SVTenant1` (kokohazamar) and `SVTenant2` (moshekipod) are fixed in `const.go:111-125`, and the step that actually fires the push webhook — `mergePaCConfigPRs` (`dr_same_version.go:59-61`, Phase 1) and `triggerBuildsAndVerify` (`tenant_application_lifecycle.go:431`, Phase 6) — both iterate tenants in a plain sequential `for` loop, not goroutines. Kokohazamar is *always* pushed first, moshekipod *always* second, in every wave of builds in the suite. All 3 wipeout occurrences happened before any restore, ruling out a restore-related credential race as the explanation — this is a timing/ordering effect, most likely a per-run Quay rate-limit or credential-propagation window that kokohazamar's earlier burst exhausts before moshekipod's turn.
- **Not yet fixed** — root cause is external to the DR suite (Quay-side transient behavior); no code fix available for the flake itself. Suite-side mitigation: see `dr-suite-blind-polling-timeout` below.
- **Occurrences (8 confirmed):** 2095096894299574272 (PR 13323, all 4 builds, both tenants — CDN EOF), 2095052503837052928 (PR 13811, both tenants frontend-only — CDN EOF; reached restore), 2094710382030491648 (PR 13048, kokohazamar frontend + moshekipod all 3 — 401), 2092551666044768256 (PR 13048, kokohazamar frontend + moshekipod all 3 — 401), 2092296245245644800 (PR 13557, moshekipod all 3, kokohazamar fully healthy — 401), 2092006064814821376 (PR 13469, both tenants frontend-only — CDN EOF), 2092002955354968064 (PR 13580, kokohazamar web-server-only — CDN EOF; reached restore), 2091956438011219968 (PR 13371, both tenants frontend-only — 401; reached restore). Full per-run breakdown: flakiness-history-2026-09-06.md.
- **Supersedes:** `dr-release-stuck-timeout` and `dr-quay-push-auth-failure` (iteration 2026-09-06/07) — these were catalogued as two separate patterns only because one run (2094710382030491648) happened to get externally aborted by a force-push before its internal hang fully played out; deeper verification (component-by-component, cross-referenced against `releases.json`/`pipelineruns.json` gathered by the `redhat-appstudio-gather` Prow step and integration-service's own controller-manager logs) showed they are the same bug. Also supersedes `dr-pipeline-chain-hang` (already superseded by `dr-quay-push-auth-failure`, carried forward here).

## dr-restore-wipes-release-status (non-blocking, does not fail the suite)
- **Error pattern:** after a Velero restore, pre-backup Release CRs that were already `Released=True Succeeded` come back as `Validated=False Reason=Failed message="automated not set in status for automated release"` (and lose their `Released` condition entirely) — visible only in `releases.json` gathered by the `redhat-appstudio-gather` Prow step, not in the DR suite's own `build-log.txt` (its diagnostics only print `Reason=Failed`, no message).
- **Root cause:** Kubernetes status subresources are not populated by a plain object restore/create — they require a dedicated `/status` write. Integration-service sets `status.automated=true` via `Status().Patch()` once, at original Release creation (`snapshot_adapter.go` `createAutomatedRelease()`) — confirmed directly in its controller-manager log (`"Marked Release status automated"`). Nothing re-invokes this after a Velero restore recreates the object (new `creationTimestamp`, matching the restore CR's start time to the second — confirmed for run 2092002955354968064: Release `creationTimestamp` 22:18:50Z, 2s after `STEP: Creating Velero Restore ... @ 22:18:48`). `release-service`'s `validateAuthor()` (`controllers/release/adapter.go:2202-2213`) sees the `AutomatedLabel: "true"` label (labels survive restore) but `!IsAutomated()`, gives a 5-minute grace period, then permanently invalidates the Release with no retry path.
- **Why it doesn't fail the suite:** `waitForReleasedCount` counts *all* `Released=True` Release objects in the namespace, regardless of origin. The restored, permanently-broken Releases just sit as inert junk; Phase 6's `triggerBuildsAndVerify` creates entirely fresh Snapshots/Releases independent of them, and the suite only needs `expectedCount` of those to succeed.
- **Confirmed directly** (via `releases.json`) in 1 run: 2092002955354968064 (6/6 pre-backup Releases across both tenants uniformly invalidated with the identical message, restore timestamps `dr_same_version.go`-triggered restores at 22:18:48/22:19:48). Not yet re-confirmed in the other 2 runs that reached restore (2095052503837052928, 2091956438011219968) — the mechanism (K8s status-subresource + Velero restore semantics) gives no reason to expect it wouldn't recur, but this hasn't been independently checked there.
- **Not yet fixed** — this is a genuine disaster-recovery correctness defect in release-service/Velero-restore interaction (restored Releases silently lose their history), independent of the suite's pass/fail outcome. Worth filing against `release-service` (or wherever the Velero restore-hook/resource-modifier config for Release CRs lives) on its own merits.

## dr-suite-blind-polling-timeout
- **Error pattern:** any DR test failure that produces no JUnit report and runs to Prow's full 2h entrypoint timeout, despite the underlying condition (a permanently failed build, or a permanently invalidated Release) being determinable within seconds of it occurring.
- **Root cause:** `waitForSucceededPRCount` and `waitForReleasedCount` (`tenant_application_lifecycle.go`) poll via `Eventually()` for their full configured timeout (`PipelineTimeout=90min`, `ReleaseChainTimeout=60min`, `const.go:308,317,330,338`) regardless of whether the thing being waited on is still progressing or has already terminally failed (`Succeeded=False` on a PipelineRun never flips; `Released=False Reason=Failed` on a Release CR never flips — confirmed unchanged for 90+ minutes in run 2092002955354968064). Worst case, these sum to more than Prow's 2h job budget, so Prow's external kill wins the race before Ginkgo's own `Eventually()` can fire `Fail()` and produce a JUnit entry.
- **This is not a timeout-sizing problem** — normal runs finish in ~1h, so Prow's 2h budget is already generous headroom. Retuning the timeout numbers (either direction) does not fix the defect; it only changes how long the suite waits before giving up on something it could already tell was hopeless.
- **Fix (not yet applied):** teach both `Eventually()` loops to recognize a terminal failure and stop immediately via Gomega's `StopTrying()`, instead of exhausting the timeout. Turns a silent 2h/no-JUnit hang into an immediate, diagnosable failure citing the specific Release/PipelineRun. Does not fix `dr-quay-registry-transient-failure` itself (that's external) — only makes every future occurrence of it (and any other terminal-failure case) fail fast and visibly instead of hanging.

## dr-go-proxy-compile-failure
- **Error pattern:** JUnit report present but `tests="0"`; build log shows `proxy.golang.org` stream errors (e.g. `stream error; INTERNAL_ERROR`) fetching a Go module dependency (`github.com/conforma/crds`, `github.com/redhat-appstudio/jvm-build-service` seen) before any Ginkgo spec runs
- **Root cause:** Transient Go module proxy network failure fails the test binary compile step entirely. Pure infra/network flake, unrelated to DR logic. A literal `tests=0, failures=0` read misreports this as a "pass" — classification tooling and any future flakiness analysis must treat zero-test JUnit reports as `no-artifacts`, not `pass`. Not yet fixed (infra-level flake, no code fix applicable) — surfaced by analyze-dr-flakiness on 2026-09-06. See flakiness-history-2026-09-06.md for occurrences (2 confirmed).

## periodic-suite-timeout-generic
- **Error pattern:** `A suite timeout occurred` (Ginkgo top-level suite-timeout message, no further detail)
- **Root cause:** Unknown — this is a methodology gap as much as a root cause. Every DR failure observed in the periodic job (`periodic-ci-redhat-appstudio-infra-deployments-main-ocp420-konflux-e2e-v420`) carries only this generic message because the periodic classification path parses the JUnit `<failure message>` and does not fetch/grep the periodic job's build log. Plausibly the same underlying causes as `dr-release-stuck-timeout` or `dr-pipeline-chain-hang` surfacing through the periodic job's own top-level suite timeout instead of Prow's per-step timeout, but unconfirmed. Not yet fixed — surfaced by analyze-dr-flakiness on 2026-09-06. See flakiness-history-2026-09-06.md for occurrences (10/10 periodic runs scanned). Recommend a follow-up pass that fetches periodic build logs for these runs specifically.
