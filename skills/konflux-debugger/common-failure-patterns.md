# Debugging Pipeline Failures

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

## Investigation Phases

### Phase 1: Identify Failed Component

**PipelineRun Status Check**:
```bash
kubectl get pipelinerun <pr-name> -n <namespace>
kubectl describe pipelinerun <pr-name> -n <namespace>
```

Look for:
- Overall status (Succeeded/Failed/Running)
- Conditions and reasons
- Which TaskRun(s) failed
- Duration and timestamps

**TaskRun Identification**:
```bash
kubectl get taskruns -l tekton.dev/pipelineRun=<pr-name> -n <namespace>
```

Identify failed TaskRuns by status.

### Phase 2: Log Analysis

**Get TaskRun Pod Logs**:
```bash
# Find the pod
kubectl get pods -l tekton.dev/taskRun=<tr-name> -n <namespace>

# Get logs from specific step
kubectl logs <pod-name> -c step-<step-name> -n <namespace>

# Get logs from all containers
kubectl logs <pod-name> --all-containers=true -n <namespace>

# For previous failures
kubectl logs <pod-name> -c step-<step-name> --previous -n <namespace>
```

**What to Look For**:
- Error messages (search for "error", "failed", "fatal")
- Exit codes
- Last successful operation before failure
- Timeout indicators
- Resource exhaustion messages

### Phase 3: Event Correlation

**Check Kubernetes Events**:
```bash
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Filter for specific resource
kubectl get events --field-selector involvedObject.name=<pod-name> -n <namespace>
```

**Critical Events**:
- `FailedScheduling` → Resource constraints
- `FailedMount` → Volume/PVC issues
- `ImagePullBackOff` → Registry/image problems
- `Evicted` → Resource pressure

### Phase 4: Resource Inspection

**PipelineRun Details**:
```bash
kubectl get pipelinerun <pr-name> -n <namespace> -o yaml
```

Check:
- Parameters passed correctly
- Workspace configurations
- ServiceAccount specified
- Timeout values

**TaskRun Details**:
```bash
kubectl get taskrun <tr-name> -n <namespace> -o yaml
```

Examine:
- Step definitions and images
- Resource requests/limits
- Status.steps for individual step states
- Conditions for failure reasons

**Pod Inspection**:
```bash
kubectl describe pod <pod-name> -n <namespace>
```

Look for:
- Container states and exit codes
- Resource requests vs limits
- Volume mounts
- Node placement

### Phase 5: Root Cause Analysis

**Correlate Findings**:
1. Timeline: When did failure occur?
2. First failure: Which step/component failed first?
3. Error pattern: Consistent or intermittent?
4. Recent changes: New code, config, images?

**Distinguish Symptom from Cause**:
- ❌ "Build failed" (symptom)
- ✓ "npm install timed out due to registry being unavailable" (root cause)

## Common Failure Patterns

### 1. Image Pull Failures

**Symptoms**: `ImagePullBackOff`, `ErrImagePull`

**Investigation**:
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Events"
```

**Check**:
- Image name and tag spelling
- Image exists in registry
- ServiceAccount has imagePullSecrets
- Registry is accessible

**Common Fixes**:
- Correct image name/tag
- Add imagePullSecret to ServiceAccount
- Verify registry credentials
- Check network policies

### 2. Resource Exhaustion

**Symptoms**: `OOMKilled`, `Pending` pods, quota errors

**Investigation**:
```bash
kubectl describe namespace <namespace> | grep -A5 "Resource Quotas"
kubectl top pods -n <namespace>
kubectl describe node | grep -A5 "Allocated resources"
```

**Common Causes**:
- Memory limits too low
- Namespace quota exceeded
- No nodes with available resources

**Fixes**:
- Increase resource limits in Task
- Adjust namespace quotas
- Optimize memory usage in build

### 3. Build Script Failures

**Symptoms**: Non-zero exit code, "command not found"

**Investigation**:
```bash
kubectl logs <pod-name> -c step-build -n <namespace>
```

**Check**:
- Script syntax errors
- Missing tools in container image
- Wrong working directory
- Environment variables not set

**Fixes**:
- Fix script errors
- Use image with required tools
- Set correct workingDir in Task
- Pass required params/env vars

### 4. Timeout Issues

**Symptoms**: TaskRun shows timeout in status

**Investigation**:
```bash
kubectl get taskrun <tr-name> -n <namespace> -o jsonpath='{.spec.timeout}'
kubectl get taskrun <tr-name> -n <namespace> -o jsonpath='{.status.startTime}{"\n"}{.status.completionTime}'
```

**Common Causes**:
- Timeout value too low
- Slow network operations (downloads)
- Build complexity underestimated
- Process hanging

**Fixes**:
- Increase timeout in Task/PipelineRun
- Use caching for dependencies
- Optimize build process
- Add progress logging to detect hangs

### 5. Workspace/Volume Issues

**Symptoms**: `CreateContainerError`, volume mount failures

**Investigation**:
```bash
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>
```

**Check**:
- PVC exists and is Bound
- Workspace name matches between Pipeline and PipelineRun
- AccessMode is correct (RWO vs RWX)
- Storage class exists

**Fixes**:
- Create or fix PVC
- Correct workspace name references
- Use appropriate access mode
- Verify storage provisioner

### 6. Permission Errors

**Symptoms**: "Forbidden", "unauthorized", RBAC errors

**Investigation**:
```bash
kubectl get sa <sa-name> -n <namespace>
kubectl get rolebindings -n <namespace>
kubectl auth can-i create pods --as=system:serviceaccount:<namespace>:<sa-name>
```

**Check**:
- ServiceAccount exists
- Role/RoleBinding grants needed permissions
- ClusterRole if cross-namespace access needed

**Fixes**:
- Create ServiceAccount
- Add RoleBinding for required permissions
- Grant pod creation, secret access, etc.

