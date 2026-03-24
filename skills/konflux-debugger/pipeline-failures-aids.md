# Debugging Pipeline Failures — Decision Aids

> **Note:** This content is copied verbatim from [konflux-ci/skills](https://github.com/konflux-ci/skills) `debugging-pipeline-failures/SKILL.md`. Some commands referenced here (e.g., `kubectl top`, `kubectl auth can-i`) are NOT on the konflux-debugger allowlist. Always check `SKILL.md` safety rules before executing any command.

## Overview

**Core Principle**: Systematic investigation of Konflux CI/CD failures by correlating logs, events, and resource states to identify root causes.

**Key Abbreviations**:
- **PR** = PipelineRun
- **TR** = TaskRun
- **SA** = ServiceAccount
- **PVC** = PersistentVolumeClaim

## When to Use

Invoke when encountering:
- PipelineRun failures or stuck pipelines
- TaskRun errors with unclear messages
- Build container issues (ImagePullBackOff)
- Resource constraints (OOMKilled, quota exceeded)
- Pipeline timeouts
- Workspace or volume mount failures
- Permission errors

## Quick Reference

| Symptom | First Check | Common Cause |
|---------|-------------|--------------|
| ImagePullBackOff | Pod events, image name | Registry auth, typo, missing image |
| TaskRun timeout | Step execution time in logs | Slow operation, network issues |
| Pending TaskRun | Resource quotas, node capacity | Quota exceeded, insufficient resources |
| Permission denied | ServiceAccount, RBAC | Missing Role/RoleBinding |
| Volume mount error | PVC status, workspace config | PVC not bound, wrong access mode |
| Exit code 127 | Container logs, command | Command not found, wrong image |

## Common Confusions

### ✗ Incorrect Approach
"Pipeline failed, let me rerun it immediately"
- No root cause identified
- Will likely fail again
- Wastes resources and time

### ✓ Correct Approach
"Let me check logs and events to understand why it failed, then fix the root cause"
- Identifies actual problem
- Prevents repeat failures
- Efficient resolution

---

### ✗ Incorrect Approach
"Build timed out. I'll set timeout to 2 hours"
- May hide real issues
- Delays problem detection

### ✓ Correct Approach
"Let me check what operation is slow in the logs, then optimize or increase timeout if truly needed"
- Identifies slow operations
- Optimizes where possible
- Sets appropriate timeout

---

### ✗ Incorrect Approach
"Too many logs to read, I'll just try changing something"
- Random changes
- May make it worse
- Doesn't address root cause

### ✓ Correct Approach
"I'll search logs for error keywords and check the last successful step before failure"
- Focused investigation
- Finds actual error
- Targeted fix

## Troubleshooting Workflow

```
1. GET PIPELINERUN STATUS
   ↓
2. IDENTIFY FAILED TASKRUN(S)
   ↓
3. CHECK POD LOGS (specific step that failed)
   ↓
4. REVIEW EVENTS (timing correlation)
   ↓
5. INSPECT RESOURCE YAML (config issues)
   ↓
6. CORRELATE FINDINGS → IDENTIFY ROOT CAUSE
   ↓
7. APPLY FIX → VERIFY → DOCUMENT
```

## Decision Tree

**Q: Is the PipelineRun stuck in "Running"?**
- **Yes** → Check which TaskRuns are pending or running
  - Pending → Resource constraints (Phase 2: Resource Exhaustion)
  - Running too long → Check logs for progress (Phase 4: Timeouts)
- **No** → PipelineRun Failed → Continue

**Q: Which TaskRun failed first?**
- Check status of all TaskRuns to find first failure
- Focus investigation on that TaskRun

**Q: What does the pod log show?**
- Error message → Address specific error
- No output → Check if pod started (events)
- Exit code 127 → Command not found (wrong image)
- Exit code 137 → OOMKilled (increase memory)
- Other exit code → Script/command failure

**Q: Do events show image, volume, or scheduling issues?**
- ImagePullBackOff → Phase 1: Image Pull Failures
- FailedMount → Phase 5: Workspace/Volume Issues
- FailedScheduling → Phase 2: Resource Exhaustion

## Keywords for Search

Konflux pipeline failure, Tekton debugging, PipelineRun failed, TaskRun errors, build failures, CI/CD troubleshooting, ImagePullBackOff, OOMKilled, kubectl logs, pipeline timeout, workspace errors, RBAC permissions