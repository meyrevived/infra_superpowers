---
name: test-pr-review
description: Use when reviewing a GitHub PR containing Go test code for quality, standards adherence, coverage gaps, and implementation code quality within the diff
---

# Test PR Review

Review a GitHub PR with focus on test quality, Ginkgo/Go standards adherence, and coverage opportunities. Produces a structured review report and optionally implements suggested coverage improvements on a new branch.

**Trigger:** User provides a PR link.

## Step 1: Load Review Standards

Read the following files from neighboring skill directories:

```
Read ../ginkgo-testing-standards/SKILL.md
Read ../ginkgo-testing-standards/testing-cheatsheet.md
Read ../go-coding-standards/SKILL.md
Read ../requesting-code-review/code-reviewer.md
```

These are the baseline review criteria. Also apply your own judgment on code quality beyond what the standards cover.

Then read `review-template.md` in this skill directory for the report format and detailed review criteria.

## Step 2: Fetch PR Metadata

Extract the org, repo, and PR number from the provided link, then use `gh` CLI:

```bash
# PR diff and changed files
gh pr diff <number> -R <org>/<repo>
gh pr view <number> -R <org>/<repo> --json files

# All review comments (human + bot)
gh api repos/<org>/<repo>/pulls/<number>/comments
gh api repos/<org>/<repo>/issues/<number>/comments
```

**Existing review comments:**
- Note comments from human reviewers
- Identify comments from AI bots: Qodo (qodo-merge-pro), CodeRabbit (coderabbitai), Gemini (gemini-code-assist)
- Incorporate AI findings: if they flagged something valid, don't duplicate it in your report. If they missed something or got something wrong, note that.

## Step 3: Ensure Local Repo Is Current

Check if the repo exists under `~/Desktop/Work/Konflux/<repo>`.

**If the repo does not exist locally:**
```bash
cd ~/Desktop/Work/Konflux
git clone https://github.com/<org>/<repo>.git
cd <repo>
git remote add upstream https://github.com/<org>/<repo>.git  # if fork
```

**If the repo exists locally:**
```bash
cd ~/Desktop/Work/Konflux/<repo>
git fetch upstream
git fetch origin

# Update origin/main and local main to match upstream/main
git checkout main
git merge upstream/main
git push origin main

# If repo was on a different branch, update that too
git checkout <original-branch>
git merge main
```

**Do NOT checkout the PR branch for review analysis.** The PR diff is already available from Step 2. The local repo is needed for context — understanding the codebase the PR targets.

### Create PR-Diff Branch

**This step is mandatory — always create this branch, every review, no exceptions.**

```bash
cd ~/Desktop/Work/Konflux/<repo>
git branch -D pr-diff/<pr-number> 2>/dev/null || true
gh pr checkout <number> -R <org>/<repo> --branch pr-diff/<pr-number>
git checkout main
```

This branch exists for the user's IDE workflow. They check out `pr-diff/<pr-number>` and diff it against `coverage-suggestions/<pr-number>` to see only the coverage additions. The review analysis still uses the diff text from Step 2, not this branch.

**Do NOT skip this step.** Do not rationalize that "the diff is already in context" or "the user didn't ask for it." The branch is always created.

## Step 4: Analyze the Diff

**Analyze the diff text you already have in context from Step 2.** Do NOT run grep, awk, or other shell commands to search for patterns like `Context()`, `To()`, etc. — read the diff directly and identify issues from the text.

**Test files (`_test.go`) — deep review against loaded standards:**
- Ginkgo structure and style (When/Should/sentence coherence)
- Test organization by scenario type (happy/sad/edge)
- Test focus: tests should exercise the repo's code logic, not stdlib or third-party packages
- Compactness: `DescribeTable()` for repeated patterns
- Inline `Expect()` as a style suggestion only — do NOT suggest inlining when the expression could panic or produce a nil-pointer dereference on test failure
- Bug exposure tests in separate `When()` blocks with `GinkgoWriter.Printf`

**Non-test files — quality review (diff lines only):**
- Go coding standards (return early, DRY, single responsibility, modularity)
- General quality: naming, clarity, correctness, error handling, performance
- Security considerations where relevant
- Your own judgment beyond the loaded standards

**If the PR contains no test files:** Flag missing test coverage as an Important finding.

## Step 5: Analyze Coverage Opportunities

**First — check Codecov:**
```bash
# Look for Codecov comment on the PR
gh api repos/<org>/<repo>/issues/<number>/comments | jq '.[] | select(.user.login == "codecov[bot]" or .user.login == "codecov-commenter")'
```
- If Codecov posted a comment, fetch the linked report
- If Codecov's estimation is wrong about something, note it in the report
- If Codecov correctly identified a gap, skip those lines in your own assessment

**Then — identify additional gaps:**
- Untested code paths in the implementation diff
- Missing edge cases, error conditions, boundary values
- Scenarios that Codecov missed

**Output:** Write all discovered coverage opportunities to `plans_n_docs/PR-review-reports/coverage-gaps-<repo>-<pr-number>.md`.

## Step 6: Coverage Resolution Chain

If coverage opportunities were identified, orchestrate three sequential subagents.

**SCOPE BOUNDARY: Subagents may ONLY edit files that are already part of the PR diff.** Pass the list of changed files from Step 2 to every subagent as the exhaustive list of files they are allowed to modify.

- **Never create new files** — if new files are needed, note that in the report
- **Never edit files outside the PR diff** — if other existing files need changes, note that in the report
- Suggestions that fall outside the PR's scope go in the report's Recommendations section, not into code

### Subagent 1: Coverage Brainstorming

Dispatch a subagent with the coverage gaps file and the list of PR-scoped files. The subagent uses `infra_superpowers:brainstorming` to refine solutions.

**Important:** This is a focused brainstorming session — no spec design stage, no design review, no approval gates. The brainstorming skill is used purely to refine the coverage gap solutions.

**The repo is already up to date locally from Step 3.** The subagent should use the Read tool to explore code in `~/Desktop/Work/Konflux/<repo>` — do NOT run git fetch, git pull, git checkout, or any other git commands to navigate the repo.

**Pass these constraints to the subagent:**
- Solutions must ONLY involve edits to files already in the PR diff
- If a solution requires changes outside the PR scope (new files or other existing files), describe it as a recommendation — do not plan to implement it
- Do not break the API of any methods that need to change
- Do not build new specialized mocks if existing mocks can easily have the required logic worked into them
- Mocks must be designed so new tests actually test their own logic, not the original code's logic
- Do not write code that breaks Ginkgo testing standards or Go coding standards

**The brainstorming subagent produces text output only.** It does NOT write code, create files, edit files, or commit anything.

**Subagent returns:** Refined list of coverage solutions with approach for each gap, split into: (1) implementable within PR scope, (2) recommendations for out-of-scope changes.

### Subagent 2: Implementation

Dispatch a subagent with the brainstorming output and the list of PR-scoped files. It creates a new branch and implements only the in-scope changes.

**The repo is already up to date locally from Step 3.** The subagent should use the Read tool to explore existing code. The only git commands needed are creating the branch and committing:

```bash
cd ~/Desktop/Work/Konflux/<repo>
git branch -D coverage-suggestions/<pr-number> 2>/dev/null || true
git checkout pr-diff/<pr-number>
git checkout -b coverage-suggestions/<pr-number>
# ... make changes with Edit tool to PR-scoped files ONLY ...
git add <changed files>
git commit -m "Coverage suggestions for PR #<number>"
```

**The branch MUST fork from `pr-diff/<pr-number>`, not from `main`.** This is critical for the user's IDE workflow — diffing `pr-diff/<pr-number>` against `coverage-suggestions/<pr-number>` should show only the coverage additions, not the entire PR diff.

- **Only edit files from the PR diff** — do not create new files or edit other files
- Every change gets detailed docstrings and comments marking it as a code change suggestion
- Follows Ginkgo testing standards and Go coding standards
- **After implementing, verify the code before committing.** First, check what CI checks the repo runs by examining its CI configuration (e.g., `.github/workflows/`, `Makefile`, `.golangci.yml`). Run the same checks CI would run — this may include `make fmt`, `make lint`, `gosec`, `go vet`, etc. At minimum always run:
  ```bash
  cd ~/Desktop/Work/Konflux/<repo>
  go build ./...
  make test  # most reviewed repos use Ginkgo via Makefile
  ```
- Fix any formatting, lint, build, or test failures before committing
- Do NOT commit code that wouldn't pass the repo's CI

**Subagent returns:** Branch name, list of changed files, and test results.

### Subagent 3: Code Review

Dispatch a subagent with the branch name, changed files, and the PR-scoped file list. It uses `infra_superpowers:requesting-code-review` to review the implemented changes.

**The subagent should use Read to examine code and Edit to make fixes.** Do NOT run git commands to navigate the repo — only git add/commit for fixes. **Only edit files from the PR diff.**

- If the review identifies issues, the subagent implements fixes on the same branch
- **After every fix, re-run the same CI checks identified above** (fmt, lint, build, test) to verify nothing is broken
- Review/fix cycle continues until the review passes and all tests pass

**Subagent returns:** Final branch name, list of changed files, and test results.

## Step 7: Generate Report

Produce the report using **exactly** the format in `review-template.md` — no extra sections, no evaluative commentary. Read the template's "What to Exclude" section and comply strictly.

- Omit any severity section that has no findings
- Include the coverage resolution branch name and changed files in the Coverage Opportunities section (if the chain ran)

Write the report to `plans_n_docs/PR-review-reports/review-<repo>-<pr-number>.md` and present it to the user.
