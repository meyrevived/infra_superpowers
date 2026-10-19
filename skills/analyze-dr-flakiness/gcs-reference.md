# GCS Reference — analyze-dr-flakiness

## Bucket

`test-platform-results`, accessed via:
- Direct object fetch: `https://storage.googleapis.com/test-platform-results/<object-path>`
- JSON API listing: `https://storage.googleapis.com/storage/v1/b/test-platform-results/o?prefix=<prefix>&delimiter=<delim>&fields=<fields>&pageToken=<token>`

## Floor Date (fixed fact, do not recompute)

**2026-08-19** — DR started being run properly on infra-deployments from this date. This is team knowledge, not derivable from `git log` (the DR Ginkgo suite in `e2e-tests/tests/disaster-recovery/dr_suite.go` was added 2026-04-12 with no gating changes since, and no release-repo commit near 2026-08-19 touches DR wiring — verified, not guessed). Treat 2026-08-19 as a constant. If a run's `absent`/`no-artifacts` boundary doesn't line up with this date, that mismatch is itself a finding — report it, don't silently override the constant.

## Job A: Periodic (multi-suite)

**Job name:** `periodic-ci-redhat-appstudio-infra-deployments-main-ocp420-konflux-e2e-v420`

**Enumerate build IDs (descending):**
```bash
scripts/enumerate-runs.sh periodic periodic-ci-redhat-appstudio-infra-deployments-main-ocp420-konflux-e2e-v420
```
Outputs one build ID per line, most recent first.

**Per-run artifact paths** (root = `logs/<job>/<build_id>/`):
| Artifact | Path |
|----------|------|
| Overall result | `<root>/finished.json` |
| Start metadata (ocp_version/cluster_pool, best-effort) | `<root>/started.json` |
| DR + other suites, combined | `<root>/artifacts/konflux-e2e-v420/redhat-appstudio-e2e/artifacts/e2e-report.xml` |
| Step build log | `<root>/artifacts/konflux-e2e-v420/redhat-appstudio-e2e/build-log.txt` |
| Step result | `<root>/artifacts/konflux-e2e-v420/redhat-appstudio-e2e/finished.json` |

**Parsing `e2e-report.xml` for DR vs other suites:**

Every `<testcase>` name has the form `[It] [<suite-label> <Suite Describe Name>] <spec text> [<ginkgo labels>]`. The suite label is the first word inside the first bracket group. Verified labels seen in practice: `disaster-recovery`, `upgrade-suite`, `enterprise-contract-suite`.

```bash
python3 - "$XML_PATH" <<'EOF'
import re, sys, json
from collections import defaultdict
content = open(sys.argv[1]).read()
cases = re.findall(r'<testcase name="\[It\] \[([a-zA-Z0-9_-]+)[^"]*"[^>]*(?:/>|>(.*?)</testcase>)', content, re.S)
stats = defaultdict(lambda: [0, 0])
for suite, body in cases:
    stats[suite][0] += 1
    if '<failure' in body:
        stats[suite][1] += 1
print(json.dumps({k: {"total": v[0], "failed": v[1]} for k, v in stats.items()}))
EOF
```

- `dr_result`: `"absent"` if `disaster-recovery` key is missing entirely; `"fail"` if its `failed > 0`; else `"pass"`.
- `other_suites`: every other key, `"fail"` if `failed > 0` else `"pass"`.
- `dr_error_signature`: if `dr_result == "fail"`, extract the `<failure message="...">` text from the first failing `disaster-recovery` testcase.

## Job B: Presubmit (DR-only)

**Job name:** `pull-ci-redhat-appstudio-infra-deployments-main-appstudio-konflux-disaster-recovery`

**Enumerate build IDs (descending, with resolved PR number):**
```bash
scripts/enumerate-runs.sh presubmit pull-ci-redhat-appstudio-infra-deployments-main-appstudio-konflux-disaster-recovery
```
Outputs `<build_id> <pr_number>` per line, most recent first.

**Per-run artifact paths** (root = `pr-logs/pull/redhat-appstudio_infra-deployments/<pr>/<job>/<build_id>/`):
| Artifact | Path |
|----------|------|
| Overall result | `<root>/finished.json` |
| Start metadata (ocp_version/cluster_pool, best-effort) | `<root>/started.json` |
| DR JUnit (DR-only) | `<root>/artifacts/appstudio-konflux-disaster-recovery/redhat-appstudio-konflux-disaster-recovery/artifacts/dr-tests-report.xml` |
| Step build log | `<root>/artifacts/appstudio-konflux-disaster-recovery/redhat-appstudio-konflux-disaster-recovery/build-log.txt` |
| Step result | `<root>/artifacts/appstudio-konflux-disaster-recovery/redhat-appstudio-konflux-disaster-recovery/finished.json` |

**Parsing `dr-tests-report.xml`:** top-level `<testsuites tests="N" failures="M" errors="E">` gives the result directly — no suite-prefix filtering needed (DR-only by construction).

- `dr_result`: `"pass"` if `failures="0"` and `errors="0"`; else `"fail"`.
- `other_suites`: always `{}` (not populated for this job — see design doc).
- `dr_error_signature`: if `dr_result == "fail"`, extract the `<failure message="...">` text from the first failing testcase.

**Note on `no-artifacts`:** some presubmit runs 404 on the DR step directory entirely (e.g. the install-konflux step failed first and DR never ran). Confirmed live: build `2045793251427880960` (PR 11347) only has `gather-audit-logs/` and `gather-extra/` under its artifacts root — no `redhat-appstudio-konflux-disaster-recovery/` directory at all. Record `dr_result: "no-artifacts"` for these, do not treat as `"absent"` (absent = predates DR; no-artifacts = DR should have run but didn't produce output).

## Per-Run Record Schema

```json
{
  "run_id": "2089639823907229696",
  "job_type": "periodic | pr-triggered",
  "timestamp": "2026-08-18T10:13:30Z",
  "dr_result": "pass | fail | absent | no-artifacts",
  "dr_error_signature": "<grep-able string, or null>",
  "other_suites": { "<suite name>": "pass | fail" },
  "ocp_version": "4.20",
  "cluster_pool": "<pool name if discoverable>"
}
```

`timestamp` comes from `finished.json`'s `timestamp` field (Unix epoch, convert to ISO 8601). `ocp_version` and `cluster_pool` come from the ci-operator config / cluster claim metadata in `started.json` or `prowjob.json` if present — best-effort, `null` if not discoverable without extra fetches.
