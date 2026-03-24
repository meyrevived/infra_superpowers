# Cluster Investigation Commands Reference

Read-only commands for investigating Konflux cluster issues. All commands listed here are on the allowlist. Organized by investigation phase.

---

## 1. Authentication and Context

Establish who you are, where you are, and switch to the right namespace before doing anything else.

```bash
oc whoami                              # Verify current user identity
oc whoami --show-server                # Show which cluster you're connected to
oc project <namespace>                 # Switch to target namespace
oc cluster-info                        # Cluster API endpoint and health
```

- **What it reveals:** Confirms you're on the correct cluster as the expected user.
- **When to use:** Always first. Prevents investigating the wrong cluster or namespace.

---

## 2. Namespace Discovery

Locate the relevant namespaces and get a high-level view of what's deployed.

```bash
oc get namespaces | grep <tenant>      # Find tenant-specific namespaces
oc get all -n <namespace>              # Overview of pods, services, deployments, etc.
```

- **What it reveals:** Which namespaces exist for the tenant; a broad inventory of resources.
- **When to use:** Early in investigation to orient yourself, especially when the affected namespace isn't known.

---

## 3. Pod Investigation

Drill into pod status, placement, and logs. This is where most root causes surface.

```bash
oc get pods -n <ns>                    # List pods with current status
oc get pods -n <ns> -o wide            # Include node placement and IP
oc describe pod <pod> -n <ns>          # Full pod spec, conditions, and events
oc logs <pod> -n <ns>                  # Stdout/stderr from the pod's container
oc logs <pod> -c <container> -n <ns>   # Logs from a specific container (multi-container pods)
oc logs <pod> -n <ns> --previous       # Logs from the previous container instance (post-restart)
oc logs -f <pod> -n <ns>               # Follow logs in real-time (streaming)
```

- **What it reveals:**
  - `get pods` — CrashLoopBackOff, ImagePullBackOff, Pending, OOMKilled at a glance.
  - `get pods -o wide` — Whether pods landed on a specific node (useful for node-level issues).
  - `describe pod` — Scheduling failures, resource limits, mount errors, event history.
  - `logs` — Application-level errors, stack traces, startup failures.
  - `logs --previous` — What happened before the last restart (critical for crash loops).
- **When to use:** After identifying the affected namespace. Start with `get pods`, then `describe` and `logs` for unhealthy pods.

---

## 4. Events

Cluster events surface issues that don't always appear in pod logs.

```bash
oc get events -n <ns> --sort-by='.lastTimestamp'                    # Recent events, newest last
oc get events --field-selector=reason=BackOff -A                    # BackOff events across all namespaces
oc get events --field-selector involvedObject.name=<pod> -n <ns>    # Events for a specific pod
oc get events --field-selector=reason=FailedScheduling -n <ns>      # Scheduling failures
oc get events --field-selector=reason=FailedMount -n <ns>           # Volume mount failures
oc get events --field-selector=reason=Unhealthy -n <ns>             # Failed health checks
```

- **What it reveals:**
  - Scheduling failures, image pull errors, volume mount issues, quota exceeded.
  - `reason=BackOff -A` — Whether BackOff is isolated or cluster-wide (points to platform vs. app issue).
  - Pod-specific events — The chronological story of what happened to that pod.
- **When to use:** When `describe pod` events are truncated, or when you suspect a broader pattern beyond a single pod.

---

## 5. Resource Inspection

Check supporting resources: deployments, services, storage, and quotas.

```bash
oc get deployments -n <ns>                                  # Deployment status and replica counts
oc get services -n <ns>                                     # Service endpoints
oc get configmaps -n <ns>                                   # Configuration data
oc get pvc -n <ns>                                          # Persistent volume claims
oc describe pvc <pvc-name> -n <ns>                          # PVC binding status and events
oc describe namespace <ns> | grep -A5 "Resource Quotas"     # Quota limits and current usage
```

- **What it reveals:**
  - `deployments` — Desired vs. available replicas (rollout stuck?).
  - `services` — Whether endpoints exist and are correctly targeted.
  - `configmaps` — Whether expected configuration is present.
  - `pvc` / `describe pvc` — Storage binding failures, provisioning errors.
  - `Resource Quotas` — Whether the namespace has hit CPU/memory/pod limits.
- **When to use:** When pods look fine but the application isn't working (service routing), when pods won't schedule (quotas, PVCs), or when behavior seems misconfigured.

---

## 6. Tekton Resources (Active)

Inspect currently-running or recently-completed pipeline and task runs.

### Using `tkn` CLI

```bash
tkn pipelinerun list -n <ns>                    # List PipelineRuns with status
tkn pipelinerun describe <pr-name> -n <ns>      # Detailed status of each task in the pipeline
tkn pipelinerun logs <pr-name> -n <ns>          # Aggregated logs across all tasks
tkn taskrun list -n <ns>                        # List TaskRuns with status
tkn taskrun describe <tr-name> -n <ns>          # TaskRun details, params, results
tkn taskrun logs <tr-name> -n <ns>              # Logs for a specific TaskRun
```

### Using `kubectl`

```bash
kubectl get pipelinerun <pr-name> -n <ns>                              # PipelineRun resource status
kubectl describe pipelinerun <pr-name> -n <ns>                         # Full spec, conditions, child TaskRuns
kubectl get taskruns -l tekton.dev/pipelineRun=<pr-name> -n <ns>       # All TaskRuns belonging to a PipelineRun
kubectl logs <pod> -c step-<step-name> -n <ns>                         # Logs from a specific Tekton step container
kubectl logs <pod> --all-containers=true -n <ns>                       # All step logs from a TaskRun pod
```

- **What it reveals:**
  - `pipelinerun list/describe` — Which tasks succeeded, failed, or are still running.
  - `pipelinerun logs` — The full build output; where the failure occurred.
  - `taskrun describe` — Input parameters, results, and failure messages for a single task.
  - `step-<step-name>` logs — Targeted output from one step (e.g., `step-build`, `step-push`).
  - `--all-containers` — Everything a TaskRun pod produced, useful when you're not sure which step failed.
- **When to use:** When a build, test, or release pipeline has failed or is stuck. Start with `pipelinerun describe` to find the failing task, then drill into its logs.

---

## 7. Tekton Resources (Archived / Pruned)

**Important:** Most Konflux PipelineRuns and TaskRuns are automatically pruned after completion and stored in **Tekton Results**. Standard `oc get pipelineruns` will NOT show them.

### Using `kubectl tekton` plugin (Tekton Results)

```bash
kubectl tekton get pr -n <ns>                          # List archived PipelineRuns from Tekton Results
kubectl tekton logs tr <taskrun-name> -n <ns>          # Retrieve archived TaskRun logs
```

- **What it reveals:** Historical pipeline execution data that no longer exists as live Kubernetes resources.
- **When to use:** When `tkn pipelinerun list` returns nothing or is missing the run you're looking for. This is common — pruning happens quickly in Konflux.

### Alternative Methods for Archived Data

If `kubectl tekton` is unavailable, ask the engineer to check the Konflux UI or Splunk dashboards directly — this skill cannot access web UIs.

---

## 8. Platform Health Checks

Zoom out to check whether the problem is platform-wide rather than application-specific.

```bash
oc get nodes                                            # Node status — any NotReady?
oc get clusteroperators                                 # Operator health — any Degraded?
oc get pods -A --field-selector=status.phase=Pending    # Cluster-wide pending pods — scheduling pressure?
```

- **What it reveals:**
  - `get nodes` — Node failures, cordoned nodes, resource pressure (MemoryPressure, DiskPressure).
  - `get clusteroperators` — Degraded operators can cause cascading failures across the cluster.
  - `Pending pods -A` — A high count suggests scheduling issues: insufficient resources, node affinity problems, or tainted nodes without tolerations.
- **When to use:** When multiple tenants or namespaces are affected, when pods won't schedule, or when the issue doesn't seem application-specific. Check here before spending time debugging a single pod.

---

## Quick Lookup Index

| Symptom | Start With |
|---|---|
| Pod not starting | `oc describe pod`, `oc get events` |
| CrashLoopBackOff | `oc logs --previous`, `oc describe pod` |
| Build pipeline failed | `tkn pipelinerun describe`, `tkn pipelinerun logs` |
| Old build not found | `kubectl tekton get pr`, Konflux UI |
| PVC not binding | `oc describe pvc`, `oc get events` |
| Namespace at capacity | `oc describe namespace`, `oc get events` |
| Cluster-wide issues | `oc get nodes`, `oc get clusteroperators` |
| Pods stuck Pending | `oc describe pod` (scheduling), `oc get nodes`, Pending pods `-A` |
