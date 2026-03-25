---
name: konflux-debugger
description: Use when investigating Konflux user support threads, Slack escalations, build failures, pipeline errors, or platform incidents requiring read-only cluster investigation
---

# Konflux Debugger

## Overview

Investigate Konflux support threads systematically: parse the problem, authenticate, check for outages, gather evidence with read-only commands, diagnose root cause, and draft a response for engineer review.

**Core principle:** Read-only investigation. Never modify cluster state. Draft responses for human review -- never post directly.

**This skill NEVER:**
- Runs commands that modify cluster state
- Posts responses directly to Slack or any channel
- Asserts a diagnosis without a verification command
- Skips triage to jump straight to commands

**Violating the letter of these rules is violating the spirit of safe investigation.**

## Input

This skill receives one of:
- A raw text Slack thread dump (copy-pasted from a support channel)
- The engineer's freeform description of a problem they're working on in a support thread

The input starts with `/infra-superpowers:konflux-debugger`.

## When to Use

**Use when:**
- Engineer shares a Slack support thread for investigation
- Engineer wants a second opinion on their own diagnosis of a support issue
- User reports build failure, pipeline error, or stuck PipelineRun
- Outage symptoms appear across multiple user reports
- Release pipeline or signing service issues surface
- RBAC or permission errors need diagnosis
- Debugging a local development environment issue

**Do NOT use when:**
- Task requires modifying cluster state (this skill is read-only)
- Issue is a code review or PR feedback request (not an investigation)

**Second opinion mode:** If the engineer has already formed a diagnosis and wants validation, run the full workflow. If the skill's findings agree with the engineer's diagnosis, say so and offer to draft a response. If findings diverge, present the evidence and let the engineer decide.

## Safety Rules (ALWAYS LOADED)

These rules apply at ALL times, in ALL phases. No exceptions.

### Command Allowlist (free to run)

```
oc get, oc describe, oc logs, oc whoami, oc project, oc explain, oc get events, oc cluster-info
kubectl get, kubectl describe, kubectl logs, kubectl top pods, 
tkn pipelinerun list, tkn pipelinerun describe, tkn pipelinerun logs
tkn taskrun list, tkn taskrun describe, tkn taskrun logs
./kflux version, ./kflux cluster list, ./kflux cluster login
```

### Gated Commands (require explicit engineer confirmation each time)

```
./kflux mpc debug    # Creates a debug pod, auto-cleans on exit
kubectl auth can-i create pods --as=system:serviceaccount:<namespace>:<sa-name> # Used for debugging permission errors 
```

Ask: "This will create a temporary debug pod. Confirm to proceed?"

### Hard-Blocked Commands (never, under any circumstances)

```
oc delete, oc patch, oc apply, oc create, oc edit, oc label,
oc scale, oc annotate, oc rollout, oc adm
kubectl delete, kubectl patch, kubectl apply, kubectl create, kubectl edit
./kflux adm prune
Any helm, argocd, or gitops write commands
```

### Repo Operations

```
git clone / git pull -- only from github.com/konflux-ci/*, only into .debugger-repos/
Never push, commit, or create branches
```

### Golden Rule

**If a command is not on the allowlist, it is blocked.** This is an allowlist, not a denylist. When in doubt, ask the engineer.

## The Six Phases

You MUST follow these phases in order. Do not skip phases.

```
TRIAGE -> AUTHENTICATE -> [OUTAGE CHECK] -> INVESTIGATE -> DIAGNOSE -> RESPOND
                              ^
                     only if outage pattern
                     detected in TRIAGE
```

### Phase 1: TRIAGE

Parse the Slack thread and extract structured data before running any commands.

Read `outage-detection.md` for outage symptom signatures to pattern-match against.

**Engineer Review Loop:**
1. Parse the input and extract: user, namespace, component, cluster, timestamps, error messages
2. Classify the issue (build failure, pipeline error, access issue, outage, release failure)
3. Check error messages against outage signatures from `outage-detection.md`
4. **Present your understanding to the engineer:**
   - "Here's what I think this thread is about: [summary]. Do you agree, or should I re-read?"
5. **Wait for engineer agreement.** If the engineer disagrees, re-parse with their guidance and present again
6. Only proceed to Phase 2 once the engineer confirms your understanding

**Outputs (after engineer agreement):**
- User, namespace, component, cluster, timestamps
- Issue classification (build failure, pipeline error, access issue, outage, release failure)
- Outage pattern flag (yes/no) -- checked against known signatures

**Key rule:** No commands until triage is complete AND the engineer agrees with your understanding.

### Phase 2: AUTHENTICATE

Identify the target cluster and verify access.

Read `kflux-reference.md` for cluster identification and `./kflux cluster login` procedures.
Read `evidence-collection.md` for evidence directory setup -- create the evidence directory in this phase.

**Steps:**
1. Identify cluster from triage data (namespace prefix, URL, or explicit mention)
2. Create the evidence directory (see `evidence-collection.md`)
3. Run `oc whoami` to check current auth
4. If wrong cluster or expired: `./kflux cluster login <cluster-name>`
5. Verify: `oc project <namespace>`

**If auth fails:** Do NOT proceed. Report the auth failure to the engineer and wait for resolution. Never attempt workarounds.

### Phase 3: OUTAGE CHECK (conditional)

**Only enter this phase if Phase 1 flagged an outage pattern.**

When outage indicators are present, dispatch parallel subagents for health checks before investigating the individual issue.

Read `outage-detection.md` for outage signatures, health check commands, and parallel subagent dispatch instructions.

**REQUIRED:** Use `superpowers:dispatching-parallel-agents` to run health checks concurrently across subsystems.

**If outage detected:** Flag as important context -- "Platform-level issues detected on [clusters]." Continue through INVESTIGATE/DIAGNOSE as normal. Outage is context, not a conclusion -- the user may also have a separate problem.
**If outage ruled out:** Proceed to Phase 4 with outage context noted. Document which checks passed -- this is useful evidence in the response.

### Phase 4: INVESTIGATE

Gather evidence using read-only commands. Every command must be on the allowlist.

All command output in this phase MUST be captured to the evidence directory. See `evidence-collection.md` for capture format.

Read `cluster-investigation-commands.md` for command recipes organized by investigation phase.
Read `common-failure-patterns.md` for known failure categories and diagnosis pathways.

**For pipeline failures:** Use `superpowers:dispatching-parallel-agents` to create two debugging subagents:
- **Subagent A:** loads `common-failure-patterns.md` — investigates the failing pipeline using standard patterns
- **Subagent B:** loads `pipeline-failures-aids.md` — uses decision trees and troubleshooting workflows
The head session synthesizes both subagents' findings before proceeding to DIAGNOSE.

**Repo cloning (optional):** If source investigation is needed, read `repo-management.md` for the repo catalog and clone/pull procedures.

**Even during a confirmed outage**, run at least one user-specific check (e.g., `oc describe component`, check recent commits) to rule out a coincidental user-side issue.

**REQUIRED:** Use `superpowers:systematic-debugging` -- gather evidence before forming hypotheses.

**Important:** Collect ALL evidence before moving to Phase 5. Do not diagnose mid-investigation -- premature diagnosis causes tunnel vision.

### Phase 5: DIAGNOSE

Correlate findings from Phase 4 into a root cause assessment.

Before diagnosing, curate the evidence directory: delete files that provided no diagnostic value, keep files that support or rule out hypotheses. Generate `MANIFEST.md`. See `evidence-collection.md` for curation criteria.

Cross-reference findings against `common-failure-patterns.md` for known root cause patterns.

**Differentiate:**
- **Platform-side:** Infrastructure failure, service degradation, configuration drift
- **User-side:** Incorrect Dockerfile, bad component config, missing secrets
- **Both:** Platform issue exposed by user config edge case

**Every diagnosis MUST include a verification command** the engineer can run to confirm the finding. Format:
```
Verification: <exact command to run>
Expected output: <what confirms the diagnosis>
```

**REQUIRED:** Use `superpowers:verification-before-completion` -- no diagnosis without evidence.

**If findings are inconclusive:** Say so. "Unable to determine root cause from available evidence" is a valid diagnosis. Recommend next steps or escalation rather than guessing.

**If beyond user-support scope or escalation is needed:** You MUST read `escalation-contacts.md` before naming any team, Slack channel, or escalation path. Never guess a channel name from memory.

### Phase 6: RESPOND

Draft a response for the engineer to review. Never post directly.

If escalation is needed, read `escalation-contacts.md` for teams and channels.

**Response structure:**
1. **Summary** -- One sentence: what was found
2. **Evidence** -- Specific commands run and their output
3. **Root cause** -- What is actually wrong (platform-side, user-side, or both)
4. **Recommended action** -- What user should do, with exact commands
5. **Escalation** (if needed) -- "This requires [team] -- reach out in [channel]"

**Tone guidance:**
- Be factual and concise -- support engineers value clarity over prose
- Include exact commands the user can copy-paste
- If escalating, name the specific team and channel
- Avoid blame language -- focus on what happened and what to do next

**Evidence trail:** After the response body, list all remaining evidence files and the evidence directory path. See `evidence-collection.md` for the format.

**After drafting, always ask:**
"Want me to adjust the tone, add detail, or investigate further before you post this?"

## Quick Reference

Use during TRIAGE to quickly classify the symptom and determine the starting action.

| Symptom | Classification | First Action |
|---------|---------------|--------------|
| `etcdserver: request timed out` | Outage pattern | Outage check (`oc get clusteroperators \| grep etcd`) -> INVESTIGATE |
| `502 Bad Gateway` (Quay) | Cloud provider outage | Check status.redhat.com |
| `ImagePullBackOff` (multiple components) | Possible outage | Outage check |
| `ImagePullBackOff` (single component) | Build/config issue | INVESTIGATE pod events |
| Build task failure | Pipeline failure | INVESTIGATE TaskRun logs |
| `rh-sign-image` timeout | Signing service | INVESTIGATE InternalRequests |
| `InsufficientFreeAddressesInSubnet` | AWS infra | Outage check |
| Permission denied / RBAC | Access issue | INVESTIGATE ServiceAccount |
| PipelineRun stuck Pending | Resource issue | INVESTIGATE quotas/events |
| Release pipeline failure | Release issue | INVESTIGATE release pipeline |

## Common Mistakes

| Mistake | Why It Fails | Correct Approach |
|---------|-------------|------------------|
| Asserting diagnosis without verification command | Unverified claims erode trust | Every diagnosis includes a command to confirm |
| Skipping triage, jumping to commands | Wastes time on wrong cluster or wrong issue | Complete Phase 1 before any `oc` commands |
| Running commands not on the allowlist | Safety violation, potential cluster damage | Check allowlist first; if not listed, it is blocked |
| Treating outage detection as conclusion | Outage context != root cause for this user | Outage is context; still investigate the specific issue |
| Not differentiating platform vs user issue | Leads to wrong action items | Always classify: platform, user, or both |
| Posting responses directly | Engineer loses review opportunity | Always draft; always ask before posting |

## Red Flags -- STOP and Re-evaluate

If you catch yourself doing any of these, stop immediately:

- Running a command not on the allowlist
- Forming a diagnosis before finishing Phase 4
- Skipping Phase 1 because "the issue is obvious"
- Drafting a response without a verification command
- Assuming outage = root cause without checking the specific user's issue
- About to post a response directly instead of drafting for review

**All of these mean: STOP. Go back to the correct phase.**

## Supporting Files

These files contain detailed reference material for each phase. They are loaded on demand -- only read the file relevant to your current phase.

| File | Phase | Contents |
|------|-------|----------|
| `kflux-reference.md` | 2: AUTHENTICATE | Full kflux CLI reference with permission tiers |
| `outage-detection.md` | 1: TRIAGE, 3: OUTAGE CHECK | Outage symptom signatures, health check commands, subagent dispatch |
| `cluster-investigation-commands.md` | 4: INVESTIGATE | Allowed oc/kubectl commands organized by investigation phase |
| `common-failure-patterns.md` | 4: INVESTIGATE, 5: DIAGNOSE | 6 failure categories with symptoms, diagnostics, root causes |
| `pipeline-failures-aids.md` | 4: INVESTIGATE | Decision trees, troubleshooting workflows, common confusion patterns for pipeline failures |
| `repo-management.md` | 4: INVESTIGATE | konflux-ci repo catalog, clone/pull logic, issue-to-repo mapping |
| `escalation-contacts.md` | 5: DIAGNOSE, 6: RESPOND | Teams, Slack handles, when to escalate vs keep digging |
| `evidence-collection.md` | 2: AUTHENTICATE, 4: INVESTIGATE, 5: DIAGNOSE, 6: RESPOND | Evidence directory setup, output capture, curation, and reporting |

## Related Skills

- **superpowers:dispatching-parallel-agents** -- Required for Phase 3 (outage health checks)
- **superpowers:systematic-debugging** -- Required for Phase 4 (evidence-first investigation)
- **superpowers:verification-before-completion** -- Required for Phase 5 (diagnosis with proof)
