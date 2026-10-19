# Per-Run Classifier Subagent Prompt

Dispatch one of these per run, in parallel batches, model `claude-sonnet-5`.

---

You are classifying one Prow CI run for DR (disaster-recovery) test flakiness analysis. You have no access to prior conversation context — everything you need is below.

**Job type:** {{job_type}} (periodic | pr-triggered)
**Run ID:** {{run_id}}
**Artifact URLs to fetch:**
- Overall result: {{finished_json_url}}
- JUnit report: {{junit_url}}
- Build log: {{build_log_url}}
- Started metadata (best-effort, for ocp_version/cluster_pool): {{started_json_url}}

**Task:**

1. Fetch each URL with `curl -sf`. If a fetch 404s or the response is an `<Error><Code>NoSuchKey</Code>` XML body, record that artifact as missing — do not retry more than once, do not fail the task.
2. If ALL of `finished.json`, the JUnit report, and the build log are missing: return `dr_result: "no-artifacts"`, `ocp_version: null`, `cluster_pool: null`, and stop — do not guess a result. (`started.json` failing alone does not trigger `no-artifacts` — it only affects `ocp_version`/`cluster_pool`.)
3. Parse `finished.json` for the `timestamp` field (Unix epoch — convert to ISO 8601).
4. Parse the JUnit report:
   - **If job_type is "periodic":** testcases are named `[It] [<suite-label> ...] ...`. Group by the suite-label (first bracketed word). `dr_result` = `"fail"` if any `disaster-recovery`-labeled testcase has a `<failure>` child, `"pass"` if disaster-recovery testcases exist and all pass, `"absent"` if no disaster-recovery-labeled testcase exists at all. Populate `other_suites` with every other suite-label found and its pass/fail status.
   - **If job_type is "pr-triggered":** read the top-level `<testsuites tests="N" failures="M" errors="E">` attributes directly. `dr_result` = `"fail"` if `failures>0` or `errors>0`, else `"pass"`. `other_suites` is always `{}`.
5. If `dr_result` is `"fail"`, extract the `message` attribute of the first `<failure>` element belonging to a DR testcase as `dr_error_signature`. Else `null`.
6. If `started.json` fetched successfully, best-effort extract `ocp_version` and `cluster_pool` from whatever cluster-claim/version fields are present in it. If the fields aren't present or the fetch failed, use `null` — do not guess.
7. Return exactly this JSON structure, nothing else:

```json
{
  "run_id": "{{run_id}}",
  "job_type": "{{job_type}}",
  "timestamp": "<ISO 8601>",
  "dr_result": "pass | fail | absent | no-artifacts",
  "dr_error_signature": "<string or null>",
  "other_suites": { "<suite>": "pass | fail" },
  "ocp_version": "<string or null>",
  "cluster_pool": "<string or null>"
}
```

Do not editorialize, do not add a root-cause guess — this is a classification pass only. The diagnosis engine runs separately, on your returned records.
