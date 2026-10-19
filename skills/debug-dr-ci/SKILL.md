---
name: debug-dr-ci
description: Use when debugging DR CI prow job failures on infra-deployments PRs. Downloads prow artifacts from GCS, cross-references known pitfalls and environment facts, outputs structured findings for common-pitfalls.md. Maintains cross-session debug journal.
---

# Debug DR CI Failures

Analyze disaster recovery CI test failures from prow artifacts on infra-deployments PRs.

**When this skill is activated, tell the user:** "Using the **debug-dr-ci** skill to investigate this DR CI failure." Then show the checklist from the Workflow section so the user can track progress.

## Session Lifecycle

Each Claude Code session is one debug cycle. The session ends after triggering `/retest`. The user monitors the ~60-90 min CI run independently, then starts a new session if it fails.

```
Session N:
  1. Read debug journal + download prow artifacts (parallel)
  2. Parse failure artifacts (subagents)
  3. Diagnose root cause (pitfalls → archive → env facts → root cause analysis)
  4. Output structured finding
  5. Apply fix
  6. Local validation (go vet, go build)
  7. User commits + pushes
  8. Trigger /retest
  9. Update debug journal, rotate if needed, add pitfall if new
  10. SESSION ENDS

  ... user monitors CI run (~60-90 min) ...

Session N+1 (if CI failed):
  1. Read debug journal + download new prow artifacts (parallel)
  2. Repeat cycle
```

**Time budget:** ~20-30 minutes active CC work per session. CI wait happens outside CC.

**User role:** Approve git push + PR comment. Everything else runs autonomously.

Cross-session state lives entirely in these documents — not in conversation context:

| Document | Path | Purpose |
|----------|------|---------|
| Common Pitfalls | `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/common-pitfalls.md` | Known failure patterns and their fixes |
| Environment Facts | `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/environment-facts.md` | What CI provides vs what tests assume |
| Debug Journal | `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/debug-journal.md` | Iteration history and current state |
| Journal Archive | `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/debug-journal-archive.md` | Graduated entries (grep-accessed only) |

All paths relative to `/home/mrath/Desktop/Work/Konflux/`.

## Prerequisites

- `curl` available for downloading prow artifacts from GCS
- Prow job URL auto-extracted from PR status checks (user can override with explicit URL)

## Repository

| Repo | Local path | What changes |
|------|-----------|-------------|
| infra-deployments | `/home/mrath/Desktop/Work/Konflux/infra-deployments` | DR test Go code under `tests/disaster-recovery/` |

The step script in openshift/release is merged and stable. Only suspect it if the error clearly originates before ginkgo starts.

## Workflow

```
- [ ] Step 1: Read journal + download prow artifacts (parallel)
- [ ] Step 2: Parse failure (subagents)
- [ ] Step 3: Diagnose (pitfalls → archive → env facts → root cause analysis)
- [ ] Step 4: Output structured finding
- [ ] Step 5: Apply fix
- [ ] Step 6: Local validation
- [ ] Step 7: User commits and pushes
- [ ] Step 8: Trigger /retest
- [ ] Step 9: Update debug journal and pitfalls — SESSION ENDS
```

### Step 1: Read Journal + Download Prow Artifacts (Parallel)

Two independent tracks run simultaneously. Do NOT serialize them.

**Track A — Cross-session state (Read tool, inline):**

Read all three files in parallel:
- `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/debug-journal.md`
- `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/common-pitfalls.md`
- `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/environment-facts.md`

From the journal, determine: iteration number, last failure, last fixes, remaining gaps.

**Track B — Extract prow URL and download artifacts (Bash, parallel with Track A):**

Auto-extract the failed prow job URL from PR status checks:

```bash
cd /home/mrath/Desktop/Work/Konflux/infra-deployments
BRANCH=$(git branch --show-current)
PR_NUM=$(gh pr list --head "$BRANCH" --repo redhat-appstudio/infra-deployments --json number --jq '.[0].number')
# Extract the prow job URL for the DR job
PROW_URL=$(gh pr view "$PR_NUM" --repo redhat-appstudio/infra-deployments --json statusCheckRollup \
  --jq '.statusCheckRollup[] | select(.context // .name | test("disaster-recovery")) | select((.state // .conclusion) == "FAILURE") | (.targetUrl // .detailsUrl)' | head -1)
echo "PR: $PR_NUM"
echo "Prow URL: $PROW_URL"
```

If no FAILURE status found, tell the user and close the session — nothing to debug.

Convert the prow URL to a GCS artifact root and download:

```bash
# Extract run ID from prow URL (last path segment)
RUN_ID=$(echo "$PROW_URL" | grep -oP '[0-9]{19}$')
ARTIFACT_BASE="https://storage.googleapis.com/test-platform-results/pr-logs/pull/redhat-appstudio_infra-deployments/${PR_NUM}/pull-ci-redhat-appstudio-infra-deployments-main-appstudio-konflux-disaster-recovery/${RUN_ID}"

WORKDIR="/tmp/dr-ci-debug-$(date +%s)"
mkdir -p "$WORKDIR"

curl -sL "${ARTIFACT_BASE}/build-log.txt" -o "$WORKDIR/build-log.txt"
curl -sL "${ARTIFACT_BASE}/artifacts/appstudio-konflux-disaster-recovery/redhat-appstudio-konflux-disaster-recovery/artifacts/dr-tests-report.xml" -o "$WORKDIR/junit_dr.xml" 2>/dev/null
curl -sL "${ARTIFACT_BASE}/finished.json" -o "$WORKDIR/finished.json"
curl -sL "${ARTIFACT_BASE}/started.json" -o "$WORKDIR/started.json"

echo "Artifacts in: $WORKDIR"
ls -la "$WORKDIR"
```

**Artifact directory structure varies by job.** If the paths above 404, browse the GCS directory listing:

```bash
curl -sL "${ARTIFACT_BASE}" | grep -oP 'href="[^"]*"' | head -40
```

The user can override with an explicit prow URL or GCS link if auto-extraction fails.

### Step 2: Parse Failure (Subagents)

**MANDATORY: Dispatch parallel subagents (Opus) for artifact parsing.** Do NOT parse artifacts inline in main context — no file-size exception exists. This rule is structural, not size-dependent. Dispatch these subagents in parallel:

1. **Subagent: finished.json** — Check pass/fail result and timestamp
2. **Subagent: build-log.txt** — Search for:
   - `ERROR`, `FAIL`, `error:`, `fatal:` markers
   - `exit code` or `exit status` lines
   - Last 50 lines before failure (crash context)
3. **Subagent: junit_dr.xml** (if exists) — Parse `<testcase>` elements with `<failure>` children for test names and assertion messages

Wait for all subagents to return. Synthesize their findings to determine failure location:
- Did the step script itself fail (before ginkgo ran)?
- Did ginkgo start but a test failed?
- Did a precondition check fail?

### Step 3: Diagnose

Five-pass diagnosis. Stop at the first match.

**Pass 1 — Known pitfalls.** Grep `build-log.txt` for each error pattern in `common-pitfalls.md`. If matched: confirm the fix from the pitfalls doc is applied in the current revision. If fix is missing, skip to Step 4.

**Pass 2 — Archived failures.** Search the archive for prior encounters with this error:

```bash
grep -i "<error pattern>" plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/debug-journal-archive.md
```

If matched: this is a regression. Investigate why the prior fix didn't hold.

**Pass 3 — Environment facts.** Read `environment-facts.md`. Check for gaps:
- Missing binary → compare "Binaries" sections
- Missing/empty env var → compare "Environment Variables" sections
- Path not found → compare "Path Resolution" / "Path Assumptions"
- Missing K8s resource → compare "K8s Resources Required" / "Cluster State"
- Match against "Potential Remaining Gaps"

**Pass 4 — Root cause analysis.** Focus on test code and cluster state. The step script is merged and stable — only suspect it if the error clearly originates before ginkgo starts.

**Context budget rule:** When investigating external dependencies (anything in GOMODCACHE, vendor dirs, or third-party repos), dispatch a subagent with a focused question. Do NOT read external source files in main context — they consume disproportionate context.

Test code issues:

| Pattern | Symptom | Investigation |
|---------|---------|---------------|
| Wrong assumption | Assertion fails on CI-correct value | Expected vs actual; hardcoded env-specific value? |
| Missing precondition | Fails before interesting logic | Check `BeforeAll`/`BeforeEach` setup |
| Timeout too short | `context deadline exceeded` | CI cluster slower than test expects? |
| CRD not installed | `server could not find the requested resource` | CRD installed by CI workflow step? |

Cluster state issues:

| Pattern | Symptom | Investigation |
|---------|---------|---------------|
| OADP not ready | Velero pod not running, BSL unavailable | OADP operator status in logs |
| Konflux not installed | Missing namespaces or CRDs | `konflux-ci-install-konflux` step completed? |
| Resource exhaustion | OOMKilled, pending pods | Pod events and node status in logs |
| ArgoCD sync failure | Application stuck `Syncing`/`Degraded` | ArgoCD application status |

Step script issues (only if error occurs before ginkgo starts):

| Pattern | Symptom | Investigation |
|---------|---------|---------------|
| Missing binary | `command not found` | Installed by step script or base image? |
| Wrong path | `no such file or directory` | Compare script path vs actual location |
| Wrong env var | Empty variable in critical path | Set in CI config or derived incorrectly? |
| Clone failure | `git clone` error, auth failure | Repo URL, branch name, token availability |

**Pass 5 — Cross-repo verification (test-code issues only).** When the issue is related to the test code, dispatch three parallel subagents (Opus) to validate the finding:

| Agent | Repo | Searches for |
|-------|------|-------------|
| 1 | `infra-deployments` | Existing patterns, API type availability, consistency with codebase conventions |
| 2 | `sop` | DR documentation, operational procedures, known issues that validate or conflict |
| 3 | `users` (or other doc repos) | User-facing documentation, any references to the affected behavior |

Each agent must:
1. `git fetch upstream main` before searching
2. Report facts, not opinions — under 300 words
3. Flag any existing code, documentation, or procedures that contradict the finding.

Do not proceed to Step 4 until all three agents complete. If any agent surfaces a conflict, revisit the diagnosis.

### Step 4: Output Structured Finding

Present the finding in this format:

```markdown
## DR CI Failure Analysis

**Job:** <prow job URL>
**Failed step:** <step name or "ginkgo test">
**Error pattern:** `<grep-able error string>`

### Root Cause
<Concise description of why the failure happened>

### Classification
<One of: test-code / cluster-state / environment-gap / step-script>

### Evidence
<Key log excerpts — include line numbers from build-log.txt if available>

### Proposed Fix
<Specific change to make. Include file path and what to change.>

### Confidence
<high / medium / low — explain what would increase confidence>

### Known Pitfall Match
<pitfall ID if matched, or "New failure — candidate for common-pitfalls.md">
```

### Step 5: Apply Fix

Apply the fix in `/home/mrath/Desktop/Work/Konflux/infra-deployments` — test code under `tests/disaster-recovery/`.

If the fix changes any assumptions, also update `environment-facts.md`.

### Step 6: Local Validation

Before burning a ~60-90 min CI cycle, validate locally:

**Test code (compile check):**
```bash
cd /home/mrath/Desktop/Work/Konflux/infra-deployments/tests/disaster-recovery
GOWORK=off go vet ./...
GOWORK=off go build ./...
```

**`GOWORK=off` is required.** The workspace file in the parent directory causes resolution failures in CI context.

**Diff review:**
```bash
cd /home/mrath/Desktop/Work/Konflux/infra-deployments
git diff HEAD -- tests/disaster-recovery/
```

Present diffs to the user. **Do not commit** — the user commits and pushes.

### Step 7: User Commits and Pushes

Wait for the user to commit and push.

Verify push succeeded:
```bash
cd /home/mrath/Desktop/Work/Konflux/infra-deployments
git log --oneline @{upstream}..HEAD
```

Should show no output (all commits pushed).

### Step 8: Trigger /retest

`/retest` retriggers all failed prow jobs on the PR (~60-90 min for DR tests).

Trigger (requires user approval):
```bash
cd /home/mrath/Desktop/Work/Konflux/infra-deployments
PR_NUM=$(gh pr list --head "$(git branch --show-current)" --repo redhat-appstudio/infra-deployments --json number --jq '.[0].number')
gh pr comment "$PR_NUM" --repo redhat-appstudio/infra-deployments --body '/retest'
```

**This is the session exit point.** After triggering, proceed to Step 9 and end the session.

### Step 9: Update Debug Journal and Pitfalls — SESSION ENDS

#### 9a. Update Debug Journal

Add an iteration entry to `plans_n_docs/KFLUXINFRA-2236_dr-ci-debug/debug-journal.md`:

```markdown
### Iteration N -- <date>
- **Prow job:** <URL>
- **Failures found:** <brief list>
- **Root cause:** <classification and summary>
- **Fix:** <what was changed>
- **Artifact:** <prow job link for reference>
```

Update the "Current State" section at the top of the journal with the latest result.

#### 9b. Rotate Journal (if needed)

If the "Recent Iterations" section has 4 or more entries, move the oldest entry to `debug-journal-archive.md`. The journal should hold at most 3 recent iterations — older entries are accessed via `grep` only.

#### 9c. Add New Pitfall (if applicable)

If this is a new failure pattern (not already in common-pitfalls.md), add an entry:

```markdown
## <short-id>
- **Error pattern:** `<grep-able error string>`
- **Root cause:** <what caused it>
- **Fix:** <what fixed it>
```

The short ID should be descriptive and kebab-case (e.g., `velero-cli-missing`, `quay-token-empty`).

## Key Differences from debug-e2e-tests

1. **Prow artifacts, not GitHub Actions** — GCS bucket via curl, not `gh run download`.
2. **DR-specific environment facts** — Cross-references `environment-facts.md` for CI-vs-test gaps.
3. **Pitfall format output** — Structured findings for `common-pitfalls.md`.
4. **Cross-session state** — Debug journal, archive, and pitfalls persist across sessions.

## Exit Criteria

DR prow job passes on the infra-deployments PR with all expected specs passing.

## When Process Stalls

If after completing Steps 2-3 the root cause is still unclear:

1. Check if the prow job has additional artifact directories not yet downloaded
2. Look for a `prowjob.json` or `clone-log.txt` that may reveal earlier failures
3. Compare against a passing run of the same job (if one exists) — diff the `build-log.txt` files
4. Check the PR's CI bot comments for job configuration clues
5. Tell the user what you investigated and what remains unclear — do not guess
