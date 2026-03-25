# Evidence Collection

Procedures for capturing, organizing, and curating command output during an investigation.

---

## Directory Setup

At the start of **Phase 2: AUTHENTICATE** (after triage is confirmed), create an evidence directory:

```bash
mkdir -p .debugger-evidence/<date>-<short-slug>
```

**Naming convention:**
- `<date>` -- ISO date: `YYYY-MM-DD`
- `<short-slug>` -- 2-4 words from the triage summary, kebab-case

Examples:
```
.debugger-evidence/2026-03-26-imagepullbackoff-build-svc
.debugger-evidence/2026-03-26-pipeline-stuck-pending
.debugger-evidence/2026-03-26-signing-timeout-release
```

Store the directory path in a variable for the rest of the session:
```bash
EVIDENCE_DIR=".debugger-evidence/2026-03-26-imagepullbackoff-build-svc"
```

---

## Capturing Output

During **Phase 3: OUTAGE CHECK** and **Phase 4: INVESTIGATE**, every command whose output you inspect must also be written to a file in the evidence directory.

**File naming:** `<sequence>-<command-summary>.txt`

- `<sequence>` -- zero-padded two-digit number in the order the command was run (01, 02, ...)
- `<command-summary>` -- short description of the command, kebab-case

Examples:
```
01-oc-whoami.txt
02-oc-get-pods.txt
03-tkn-pipelinerun-describe.txt
04-oc-describe-component.txt
05-oc-logs-build-container.txt
```

**How to capture:** Append the command as a header line, then the output:

```bash
echo "# Command: oc get pods -n <namespace>" > "$EVIDENCE_DIR/02-oc-get-pods.txt"
oc get pods -n <namespace> >> "$EVIDENCE_DIR/02-oc-get-pods.txt" 2>&1
```

**Rules:**
- Capture the exact command run, including all flags and arguments
- Include both stdout and stderr (`2>&1`)
- One file per command -- do not combine multiple commands into one file
- If a command is re-run with different arguments (e.g., different pod name), it gets a new sequence number

---

## Evidence Curation

At the start of **Phase 5: DIAGNOSE**, before writing the diagnosis, review the evidence directory and sort files into two categories:

### Useful evidence
Files whose output directly supports or rules out a hypothesis. These stay.

### Not useful
Files whose output was inspected but provided no diagnostic value (e.g., a healthy pod listing that confirmed nothing was wrong in that area). Delete these:

```bash
rm "$EVIDENCE_DIR/<filename>.txt"
```

**Curation criteria -- keep the file if:**
- It shows an error, warning, or unexpected state
- It confirms a hypothesis (positive evidence)
- It rules out a hypothesis (negative evidence that narrows the diagnosis)
- It provides context needed to understand another piece of evidence

**Delete the file if:**
- It was a dead-end that provided no information toward any hypothesis
- It duplicates information already captured in another file

After curation, create a manifest file summarizing what remains:

```bash
# Auto-generate manifest from remaining files
echo "# Evidence Manifest" > "$EVIDENCE_DIR/MANIFEST.md"
echo "" >> "$EVIDENCE_DIR/MANIFEST.md"
echo "Investigation: <triage summary>" >> "$EVIDENCE_DIR/MANIFEST.md"
echo "Date: <date>" >> "$EVIDENCE_DIR/MANIFEST.md"
echo "Cluster: <cluster-name>" >> "$EVIDENCE_DIR/MANIFEST.md"
echo "Namespace: <namespace>" >> "$EVIDENCE_DIR/MANIFEST.md"
echo "" >> "$EVIDENCE_DIR/MANIFEST.md"
echo "## Evidence Files" >> "$EVIDENCE_DIR/MANIFEST.md"
echo "" >> "$EVIDENCE_DIR/MANIFEST.md"
for f in "$EVIDENCE_DIR"/*.txt; do
  cmd=$(head -1 "$f" | sed 's/^# Command: //')
  echo "- **$(basename "$f")** -- \`$cmd\`" >> "$EVIDENCE_DIR/MANIFEST.md"
done
```

---

## Reporting Evidence in RESPOND

In **Phase 6: RESPOND**, after drafting the response, append an evidence summary:

```
## Evidence Trail

Evidence directory: `<path to evidence dir>`

Files:
- `03-tkn-pipelinerun-describe.txt` -- `tkn pipelinerun describe <name> -n <ns>`
- `05-oc-logs-build-container.txt` -- `oc logs <pod> -c step-build -n <ns>`
- `07-oc-describe-component.txt` -- `oc describe component <name> -n <ns>`
```

This gives the engineer a ready-made audit trail they can reference later or attach to an incident report.

---

## Cleanup Policy

Evidence directories are **not** automatically deleted. They persist across sessions so engineers can revisit past investigations. If the `.debugger-evidence/` directory grows large, the engineer can clean up old directories manually.

To list existing evidence directories:
```bash
ls -lt .debugger-evidence/
```