# konflux-debugger

A Claude Code skill for systematically investigating Konflux user support threads, Slack escalations, build failures, pipeline errors, and platform incidents using read-only cluster commands.

## Prerequisites

### kflux CLI (required)

The `kflux` binary **must be available in the directory where your Claude Code session is started**. The skill references it as `./kflux` throughout all phases.

**Install kflux:**

1. Follow the instructions on https://gitlab.cee.redhat.com/hares/kflux
2. Place the `kflux` binary in the working directory you launch Claude Code from
3. Verify: `./kflux version`

### Other CLI tools

The skill also expects these standard tools to be available on your `PATH`:

- `oc` (OpenShift CLI)
- `kubectl`
- `tkn` (Tekton CLI)
- `git` and `gh` (GitHub CLI, for repo lookups)

## How It Works

The skill follows a six-phase investigation workflow:

```
TRIAGE -> AUTHENTICATE -> [OUTAGE CHECK] -> INVESTIGATE -> DIAGNOSE -> RESPOND
```

1. **TRIAGE** -- Parse the support thread, classify the issue, check for outage signatures
2. **AUTHENTICATE** -- Login to the correct cluster via `./kflux cluster login`, set up evidence directory
3. **OUTAGE CHECK** -- (conditional) Run parallel health checks across clusters if outage patterns detected
4. **INVESTIGATE** -- Gather evidence with read-only commands, capture all output to evidence files
5. **DIAGNOSE** -- Correlate findings, differentiate platform vs user issues, include verification commands
6. **RESPOND** -- Draft a response for engineer review (never posted directly)

**Core safety principle:** All investigation is read-only. The skill never modifies cluster state and always drafts responses for human review.

## File Structure

| File | Purpose |
|------|---------|
| `SKILL.md` | Main skill definition -- phases, safety rules, allowlists |
| `kflux-reference.md` | Full `kflux` CLI reference with permission tiers |
| `cluster-investigation-commands.md` | Allowed `oc`/`kubectl` commands organized by investigation phase |
| `common-failure-patterns.md` | Known failure categories with symptoms, diagnostics, root causes |
| `pipeline-failures-aids.md` | Decision trees and troubleshooting workflows for pipeline failures |
| `outage-detection.md` | Outage symptom signatures, health check commands, parallel dispatch |
| `evidence-collection.md` | Evidence directory setup, output capture format, curation criteria |
| `escalation-contacts.md` | Team contacts, Slack handles, escalation vs keep-digging guidance |
| `repo-management.md` | konflux-ci repo catalog, clone/pull procedures for source investigation |

## Usage

Invoke the skill in Claude Code:

```
/infra_superpowers:konflux-debugger <paste Slack thread or describe the issue>
```

The skill will walk through each phase, asking for engineer confirmation at key decision points.

## Related Skills

The skill depends on these other superpowers skills during execution:

- `superpowers:dispatching-parallel-agents` -- Phase 3 (outage health checks across clusters)
- `superpowers:systematic-debugging` -- Phase 4 (evidence-first investigation)
- `superpowers:verification-before-completion` -- Phase 5 (diagnosis backed by proof)
