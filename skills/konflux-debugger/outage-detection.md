# Outage Detection Reference

## Known Outage Categories

### 1. Etcd Overload & Database Space Exhaustion
**Frequency:** Very frequent (described as a "repeated pattern almost every week" and occurring "at least 6 times in the last year").

*   **Symptoms (User Reports):**
    *   `etcdserver: mvcc: database space exceeded` (often seen during basic auth secret creation).
    *   `etcdserver: request timed out`.
    *   `admission webhook "vpipelineruns.konflux-ci.dev" denied the request: PipelineRun admission currently not allowed`.
*   **Actual Root Cause:** The cluster's underlying etcd database either exceeds its 8GB maximum size or is overwhelmed by short-lived/bursty resources (like massive amounts of PipelineRuns mounting secrets) causing the control plane to time out.
*   **Clusters Affected:** Usually isolated to a single heavily loaded cluster at a time, such as `stone-prd-rh01` or `stone-prod-p02`.
*   **Leading Indicators:** Etcd database size continuously growing, spikes in API admission webhook durations, and climbing etcd latency or disk sync times.
*   **Fastest Diagnostic Commands:**
    *   To check core cluster health: `oc get clusteroperators` (looking for `etcd` in a Degraded or Progressing state).
    *   To identify pending tasks: `oc describe pipelinerun <pipelinerun-name>` to view scheduler events.

### 2. Cloud Provider & Infrastructure Networking Outages
**Frequency:** Frequent and highly disruptive, appearing in bursts.

*   **Symptoms (User Reports):**
    *   *Quay.io:* `received unexpected HTTP status: 502 Bad Gateway` or messages stating Quay is in read-only mode.
    *   *IBM Cloud (s390x/ppc64le):* `Error allocating host: failed to provision host`, `Error allocating host: timed out waiting for instance address`, or `ssh: connect to host ... Connection timed out`.
    *   *AWS Subnets:* `api error InsufficientFreeAddressesInSubnet: There are not enough free addresses in subnet...`.
*   **Actual Root Cause:**
    *   Quay.io upgrades or outages causing severe rate limiting and 502 errors.
    *   Network connectivity outages between RH on-premise infrastructure and IBM Cloud Washington region, or IBM Cloud capacity limits for s390x/ppc64le instances.
    *   AWS Subnet IP address exhaustion, occurring when a `/24` subnet is overwhelmed by concurrent EC2 runners.
*   **Clusters Affected:** Quay and IBM Cloud outages affected multiple/all Konflux clusters simultaneously because they are external shared dependencies. AWS IP exhaustion affected specific cluster subnets.
*   **Leading Indicators:** General degraded performance on Quay before 502s appear, or prolonged VM provisioning wait times for IBM.
*   **Fastest Diagnostic Commands:**
    *   *For Quay:* Check `https://status.redhat.com/`.
    *   *For AWS/IBM:* `oc describe pod <stuck_pod_name>` and check the "Events" section for explicit infrastructure API errors like `InsufficientFreeAddressesInSubnet` or `FailedScheduling`.

### 3. API Server & Controller Saturation (Timeouts)
**Frequency:** Intermittent but common during peak hours or when massive PR updates occur.

*   **Symptoms (User Reports):**
    *   `Internal error occurred: resource quota evaluation timed out`.
    *   `resolver failed to get Pipeline : error requesting remote resource: resolution took longer than global timeout of 1m0s`.
    *   Optimistic locking errors: `Operation cannot be fulfilled... the object has been modified`.
*   **Actual Root Cause:** The KubeAPI server becomes bogged down and times out while calculating resource quotas during traffic bursts. Additionally, high load causes the `pipelines-as-code-controller` to lag, leading to resolution timeouts and write conflicts.
*   **Clusters Affected:** Usually isolated to the specific cluster under heavy load (e.g., `stone-prd-rh01` or `stone-prod-p02`).
*   **Leading Indicators:** A high or steadily increasing `workqueue_depth` metric on the Tekton controllers indicates they cannot keep up with events.
*   **Fastest Diagnostic Commands:**
    *   To check namespace events for quota timeouts: `oc get events -n <namespace> --sort-by='.lastTimestamp'`.
    *   To check controller load: `oc -n openshift-pipelines exec $(oc -n openshift-pipelines get pods -l app=tekton-pipelines-controller -o name) -- curl -s http://localhost:9090/metrics | grep "workqueue_depth"`.

### 4. Internal Signing & Integration Service (UMB/RADAS/IIB) Overload
**Frequency:** Intermittent, heavily correlated with large batches of concurrent releases.

*   **Symptoms (User Reports):**
    *   The `rh-sign-image` task times out (e.g., after 1 hour and 15 minutes) or gets stuck looping the message `Checking IR statuses...`.
    *   The `add-fbc-contribution-to-index-image` task consistently times out waiting for InternalRequests.
*   **Actual Root Cause:** The internal signing service (RADAS/UMB) or the Image Index Build (IIB) queues become fully saturated and back up due to high traffic volumes (e.g., hundreds of FBC builds pushing simultaneously).
*   **Clusters Affected:** Impacts multiple tenants across various clusters because RADAS/UMB/IIB are centralized internal services.
*   **Leading Indicators:** Increasing wait times or missing messages observed in UMB latency graphs on Splunk dashboards.
*   **Fastest Diagnostic Commands:**
    *   To check if an internal request is stuck: `oc get internalrequests -n <namespace> -l pipelines.openshift.io/pipelinerun=<run-name>`.
    *   To check the status of the backing pipeline: `oc describe pipelinerun <internalrequest-name> -n internal-services`.

---

## Trigger Conditions

During TRIAGE, match error messages against the symptoms listed in each outage category above (sections 1-4). Additionally, these **cross-cutting signals** should trigger an outage check even if they don't match a specific category:

- `context deadline exceeded` (generic API server overload)
- `connection refused` (networking or service down)
- `throttling` / `429 Too Many Requests` (rate limiting)
- `server is currently unable to handle the request` (API server saturation)
- Multiple users reporting similar symptoms across different tenants
- `ImagePullBackOff` or `ErrImagePull` across multiple unrelated components
- Pods stuck in `Terminating` or `Pending` for extended periods

## Health Check Commands by Outage Type

When an outage pattern is detected, run the **targeted commands** for that category first, then the **baseline commands** for general context.

### Baseline (run for all suspected outages)
```bash
oc get nodes                                            # Any NotReady nodes?
oc get clusteroperators                                 # Any Degraded operators?
oc get pods -A --field-selector=status.phase=Pending    # Unusual pending count? (>20 outside deployment window is unusual)
```

### Category 1: Etcd Overload
```bash
oc get clusteroperators | grep etcd                     # Etcd Degraded or Progressing?
oc get events -A --sort-by='.lastTimestamp' | grep -i etcd   # Etcd-related events
oc describe pipelinerun <pr-name> -n <ns>               # Scheduler events on affected PR
```

### Category 2: Cloud Provider / Infrastructure
```bash
# Quay: check https://status.redhat.com/ (ask engineer to check manually)
oc describe pod <stuck-pod> -n <ns>                     # Events for InsufficientFreeAddressesInSubnet, FailedScheduling
oc get events --field-selector=reason=BackOff -A        # Widespread BackOff across namespaces?
```

### Category 3: API Server / Controller Saturation
```bash
oc get events -n <ns> --sort-by='.lastTimestamp'        # Quota timeout events
oc get events -A | grep -i "quota.*timed out"           # Cross-namespace quota timeouts
oc get events -A | grep -i "resolution.*timeout"        # Resolver timeouts
```

### Category 4: Signing / Integration Service (UMB/RADAS/IIB)
```bash
oc get internalrequests -n <ns> -l pipelines.openshift.io/pipelinerun=<run-name>   # Stuck InternalRequests?
oc describe pipelinerun <ir-name> -n internal-services                              # Backing pipeline status
```

## Parallel Health Check Workflow

Use `superpowers:dispatching-parallel-agents` to run health checks across clusters.

1. **Determine scope:**
   - Engineer gives a specific cluster name? -> check that cluster only
   - Outage pattern detected? -> check the affected cluster group (staging, production, or all)
   - Engineer asks "is this an outage?" -> check all clusters
2. Dispatch one subagent per cluster or cluster group
3. Each subagent runs the **baseline commands** + the **targeted commands** for the suspected outage category
4. Note: if commands are slow to respond, that itself is evidence of API server saturation
5. Subagents return structured findings
6. Synthesize: "X of Y clusters showing symptoms -> likely platform issue" or "isolated to this cluster/namespace -> user-specific issue"

## Manual Trigger

Engineer can invoke outage check at any time by:
- Asking "is this an outage?" or "check platform health"
- Giving a cluster name: "check if there's an outage on stone-prd-m01"
- Requesting a cross-cluster check: "check all production clusters"

## Key Principle

Outage detection is enrichment context, not a short-circuit. An outage doesn't mean the user doesn't also have a separate problem. Investigation continues regardless.
