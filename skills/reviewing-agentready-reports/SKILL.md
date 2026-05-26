---
name: reviewing-agentready-reports
description: Use when running AgentReady assessments or reviewing AgentReady reports for accuracy — verifies every finding against actual repository state to identify false negatives, irrelevant checks, and scoring errors
---

# Reviewing AgentReady Reports

## Overview

AgentReady scores repositories on "agent-readiness" but uses pattern-matching that can produce inaccurate results. This skill runs AgentReady with correct environment setup, then verifies every finding against actual repository state to produce a counter-report that separates accurate findings from false negatives, irrelevant checks, and scoring errors.

**Core principle:** Every AgentReady finding must be verified against the actual repository state before being accepted or acted upon. Do not limit verification to known issues — check everything.

## When to Use

- Running an AgentReady assessment on a repository
- Reviewing an existing AgentReady report for accuracy
- Preparing an actionable summary of AgentReady findings for a team

## Process

Detect Go repo → Install gocyclo if needed → Run AgentReady (with PATH for Go) → Read JSON report → Verify each finding against repo → Classify findings → Write counter-report using template

## Phase 1: Environment Setup and Execution

### Detect Language and Install Tools

```bash
# Check if Go repo
if [ -f go.mod ]; then
  # Check for gocyclo (AgentReady uses it for cyclomatic complexity)
  if ! command -v gocyclo &>/dev/null; then
    go install github.com/fzipp/gocyclo/cmd/gocyclo@latest
  fi
  GOCYCLO_PATH="$(go env GOPATH)/bin"
fi
```

Report what you find: whether gocyclo was already installed or had to be installed, and the path. This confirms the environment is correct before running AgentReady.

### Run AgentReady

`uvx` creates an ephemeral, isolated Python environment each time it runs. This environment does NOT inherit the user's full shell PATH — tools like `gocyclo` installed in `~/go/bin` will not be found unless the PATH is explicitly augmented in the command.

```bash
# For Go repos — augment PATH so uvx can find gocyclo
PATH="${GOCYCLO_PATH}:$PATH" uvx --from git+https://github.com/ambient-code/agentready agentready -- assess .

# For non-Go repos
uvx --from git+https://github.com/ambient-code/agentready agentready -- assess .
```

Output lands in `.agentready/` — read the JSON report (not the markdown) for structured parsing:

```bash
cat .agentready/assessment-latest.json
```

The JSON contains machine-readable scores, evidence arrays, and remediation data. Use it instead of parsing markdown.

## Phase 2: Verify Each Finding

For EVERY finding (pass or fail), verify the claim against the actual repo. Do not accept any finding at face value.

### Verification Checklist

Read these files (when they exist) before assessing any finding:

| File | What it tells you |
|------|-------------------|
| `Makefile` | Build targets, test commands, lint commands, target dependencies |
| `.github/workflows/*.yaml` | CI gates, quality checks, what actually runs on PRs |
| `AGENTS.md` / `CLAUDE.md` | Documented commands, conventions, project layout |
| `.gitignore` | Actual patterns (check if "missing" patterns are already covered by globs) |
| `README.*` | Check ALL extensions: `.md`, `.adoc`, `.rst`, `.txt` |
| `.pre-commit-config.yaml` | Git hooks |
| `.githooks/` | Custom git hooks (commit-msg, pre-push, etc.) |
| `codecov.yml` / `.codecov.yml` | Coverage configuration |
| `skills/` or `docs/` | Agent reference docs, design docs, pattern guides |

**Go repos only** (when `go.mod` exists):

| File | What it tells you |
|------|-------------------|
| `.golangci.yaml` / `.golangci.yml` | Configured linters — count them, AgentReady often undercounts |

### Known False Negative Patterns

AgentReady commonly misses these. Check each one:

**1. Makefile target indirection**
AgentReady searches for literal strings like `go test` but does not follow Makefile targets. A `make test` target that invokes Ginkgo, gotest, or any other test runner will be missed.
- Check: Read the Makefile `test` target. Does it run tests with coverage and race detection?
- Check: Does `make test` depend on other targets (`fmt`, `vet`) that provide additional enforcement?

**2. Non-Markdown READMEs**
AgentReady only searches for `README.md`. Many projects (especially Red Hat/enterprise) use `README.adoc` (AsciiDoc), `README.rst`, or `README.txt`.
- Check: `ls README*` — does a README exist in any format?

**3. Go compilation model** *(Go repos only)*
AgentReady expects a separate "type-check" CI gate. In Go, the compiler IS the type checker. `go build` and `go vet` are type-checking. There is no equivalent of `mypy` or `tsc --noEmit` because Go is a compiled language.
- Check: Does CI run `go build` or `make build`? That IS the type-check gate.

**4. AGENTS.md as command reference**
AgentReady may not parse AGENTS.md command tables when evaluating test/lint/build capabilities.
- Check: Are commands documented in AGENTS.md that AgentReady claims are "not configured"?

**5. Commit convention bias**
AgentReady only recognizes "Conventional Commits" (`feat:`, `fix:`, etc.). Other structured conventions (Jira-prefix `KFLUXINFRA-1234`, Gerrit-style, etc.) score 0.
- Check: Does the project have a defined, documented commit convention? If yes, the 0/100 is unfair.
- Check: Run `git log --oneline -20` to verify the convention is actually followed in practice, not just documented.

**6. Linter undercounting** *(Go repos only)*
AgentReady may report "golangci-lint" as a single linter when `.golangci.yaml` actually configures many individual linters.
- Check: Count the linters in the `linters.enable` list. 15+ linters is excellent coverage.

**7. Irrelevant checks for project type**
AgentReady applies all checks regardless of project type:
- OpenAPI/Swagger for Kubernetes controllers (which use CRDs, not REST APIs)
- Issue templates when the project uses Jira/external issue tracking
- Specific README sections for libraries vs services vs controllers
- Check: Would this check apply to this type of project? Mark as N/A if not.

**8. .gitignore glob coverage**
AgentReady checks for specific patterns but may not recognize that existing globs already cover them.
- Check: Does `*.out` already cover `cover.out`? Is `vendor/` relevant if the project doesn't vendor? Is `*.exe` relevant for Linux-only deployments?

**9. N/A cascade failures**
When AgentReady misses a file (e.g., README.adoc), other checks that depend on it may cascade to N/A or 0. If you discover a missed file, re-evaluate ALL findings that reference it — especially One-Command Build/Setup, Concise Documentation, and any check that says "not found in README."

**10. Pattern reference directories**
AgentReady may not look inside `skills/`, `docs/`, or other reference directories. Check if the repo has deep-dive reference files that AgentReady's "Pattern References" score missed.

**11. Makefile target chaining as enforcement**
If `make test` depends on `make fmt` and `make vet`, that IS deterministic enforcement — formatting and static analysis are enforced on every test run. AgentReady may not recognize this because it looks for git hooks or pre-commit frameworks, not Makefile dependency chains.

## Phase 3: Classify and Score

For each finding, assign one of these verdicts:

| Verdict | Meaning | Score Impact |
|---------|---------|--------------|
| **Fair** | Finding is accurate and relevant | Keep original score |
| **Partially fair** | Finding has merit but overstates the issue | Adjust score upward |
| **False negative** | Something exists that the tool missed | Significant score increase |
| **Unfair** | Tool penalizes a valid alternative approach | Adjust score upward |
| **Irrelevant** | Check doesn't apply to this project type | Should be N/A |

## Phase 4: Write Counter-Report

Use the template in `counter-report-template.md` in this skill directory. The report must include ALL of these sections:

1. **Executive Summary** — Original score, adjusted score, why they differ
2. **Tool Issues** — Problems with AgentReady execution or detection
3. **Finding-by-Finding Assessment** — Table with original score, adjusted score, verdict, and explanation for every finding grouped by tier
4. **Actionable Improvements** — Genuinely valuable actions ranked by effort-to-impact, separated into Quick Wins / Medium Effort / Not Recommended
5. **AgentReady Tool Feedback** — Specific issues worth reporting to AgentReady maintainers

### Output Format

Write the counter-report as Jira-compatible markdown:
- No HTML tags (`<details>`, `<summary>`)
- No shield badge images
- Use standard markdown tables and headers
- File goes in the repo's `.agentready/` directory as `agentready-review-YYYYMMDD.md`

## Pitfalls When Running This Skill

**Over-adjusting scores** — If something genuinely doesn't exist (no ADRs, no issue templates), don't inflate the score just because it's "low priority." Adjust only when the tool's evidence contradicts what actually exists in the repo.

**Stopping at known patterns** — The false negative patterns above are common but not exhaustive. If a finding feels wrong and isn't covered by the list, investigate it anyway. The goal is to verify every finding, not just pattern-match against a checklist of known issues.

**Flagging remediation templates as findings** — AgentReady's remediation examples are generic templates (often Python/JS-oriented regardless of project language). Note these in the Tool Feedback section, but don't confuse bad remediation advice with an inaccurate finding. Score the finding on whether the diagnosis is correct, not whether the suggested fix makes sense.
