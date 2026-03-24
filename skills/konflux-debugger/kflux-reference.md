# kflux CLI Reference

Quick reference for all `kflux` commands, flags, and permission tiers.

---

## Permission Tiers

| Tier | Rule |
|------|------|
| **Free** | Safe to run without confirmation |
| **Gated** | Requires explicit engineer confirmation before execution |
| **BLOCKED** | Never run under any circumstances |

---

## Commands

### Free (allowlisted)

| Command | Description |
|---------|-------------|
| `kflux version` | Print CLI version |
| `kflux cluster list` | List all Konflux clusters |
| `kflux cluster login` | Login to all Konflux clusters (requires chromedriver) |

#### `kflux cluster list`

| Flag | Description |
|------|-------------|
| `--format json` / `-f json` | Output as JSON array instead of aligned text |

**Default output** (aligned text — name + host):

```
stg-es01    kflux-stg-es01.21tc.p1.openshiftapps.com
stg-p01     stone-stage-p01.hpmt.p1.openshiftapps.com
prd-es01    kflux-prd-es01.1ion.p1.openshiftapps.com
```

**JSON output** (`-f json`):

```json
[
  {"name": "stg-es01", "host": "kflux-stg-es01.21tc.p1.openshiftapps.com", "kind": "ROSA"},
  {"name": "stg-p01", "host": "stone-stage-p01.hpmt.p1.openshiftapps.com", "kind": "ROSA"}
]
```

#### `kflux cluster login`

| Flag | Description |
|------|-------------|
| `--aliases` | Display shell aliases for quick cluster switching |
| `--debug` / `-d` | Enable debug mode for Selenium, showing the browser UI |

**Mac alternative** (avoids chromedriver browser popup):

```bash
kinit --keychain <userid>@IPA.REDHAT.COM && kflux cluster login
```

**Note:** When this command is needed, prompt the engineer for their userid. Never store or save the userid anywhere.

---

### Gated (require engineer confirmation)

| Command | Description |
|---------|-------------|
| `kflux mpc debug` | Create a debug pod in multi-platform-controller namespace |
| `kflux mpc debug --cleanup` | List and delete all existing debug pods |

#### `kflux mpc debug`

Creates a debug pod with SSH keys for connecting to multi-arch build VMs. Supported architectures: amd64, arm64, s390x, ppc64le. Pod is automatically cleaned up on exit.

| Flag | Description |
|------|-------------|
| `--cleanup` | List and delete all existing debug pods instead of creating one |

---

### BLOCKED (never run)

| Command | Description |
|---------|-------------|
| `kflux adm prune` | Prune old PipelineRuns. **DESTRUCTIVE — NEVER RUN.** |

| Flag | Description |
|------|-------------|
| `--older-than` | Age threshold for pruning |
| `--namespace` | Target namespace |
| `--all-namespaces` | Target all namespaces |
| `--dry-run` | Simulate without deleting |
| `--workers` | Parallel worker count |
| `--per-namespace` | List and delete PipelineRuns per namespace instead of cluster-wide |
| `--finalizers` | Handle finalizers on resources |

---

## Scripting Examples

### Iterate over all clusters

```bash
for cluster in $(kflux cluster list | awk '{print $1}'); do
  echo "Processing $cluster"
done
```

### Filter clusters by kind with jq

```bash
kflux cluster list -f json | jq -r '.[] | select(.kind == "ROSA") | .name'
```
