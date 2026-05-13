# Test PR Review — Report Template

## What to Exclude

The report is findings-only. Do NOT include any of these:
- **Strengths or Positives** — do not list things the PR does well
- **Verdict or Assessment** — do not rate the PR or give pass/fail
- **Summary or Overview** — do not summarize or describe the PR
- **PR context** — beyond the title, no PR description restatement
- **Evaluative commentary** — no "overall this is a good PR" or similar framing

If a section is not in the format below, it does not belong in the report.

## Report Format

```markdown
### [PR Title]

### Issues

#### Critical (Must Fix)
[Bugs, broken tests, security issues, tests that pass but don't actually test anything]

For each issue:
- File:line reference
- What's wrong
- Why it matters
- How to fix (if not obvious)

#### Important (Should Fix)
[Standards violations, missing scenario coverage, poor test organization, code quality issues]

#### Minor (Nice to Have)
[Style, naming, optimization opportunities]

### Coverage Opportunities
[Codecov validation + net-new gaps, suggested fixes on branch]
- Branch: coverage-suggestions/<pr-number>
- Changed files: [list]

### Recommendations
[Improvements for test quality, coverage strategy, code structure]
```

Omit any section with no findings.

## Review Criteria

### Test Code Quality (primary focus)

**Ginkgo structure and style:**
- `When()` not `Context()` — always
- `Should()` and `ShouldNot()` not `To()` and `NotTo()` — always
- Describe/When/It text forms a coherent, human-readable sentence
- Example: "User registration when email is empty should return validation error"

**Test organization:**
- Separate `When()` blocks by scenario type: happy path, sad path, edge cases
- Bug exposure tests in their own `When()` block with `GinkgoWriter.Printf` explaining expected vs actual behavior

**Compactness:**
- `DescribeTable()` for multiple tests with identical `Expect()` patterns and different inputs
- Inline function calls in `Expect()` — suggest as style improvement ONLY when the expression cannot panic or nil-pointer on test failure. If there is any risk of panic/nil-pointer when the test fails, do NOT suggest inlining.

**Test focus:**
- Tests should exercise the repo's code logic
- Do not test Go stdlib, well-tested third-party packages, or language operators
- Test: business logic, error handling, data transformations, integration between the repo's components

**Coverage breadth:**
- Happy path scenarios covered
- Sad path / error conditions covered
- Edge cases and boundary conditions covered

### Implementation Code Quality (diff lines only)

**Go coding standards:**
- Return early pattern instead of nested if/else
- DRY — no repeated logic; extract helpers when pattern appears 3+ times
- Single responsibility — each function does one thing
- Modularity — small, reusable pieces

**General quality (agent's own judgment):**
- Naming: clear, descriptive, idiomatic Go
- Clarity: code is easy to follow without comments
- Correctness: logic is sound, no bugs
- Error handling: errors checked and handled appropriately
- Performance: efficient algorithms, no unnecessary allocations or loops
- Security: input validation at boundaries, no injection vectors, no hardcoded secrets

### Coverage Opportunities

**Codecov integration:**
- If Codecov commented on the PR, fetch and review its report
- Validate Codecov's findings — note any incorrect estimations
- Skip lines Codecov already correctly identified as gaps

**Additional gaps:**
- Untested code paths in the implementation diff
- Missing edge cases, error conditions, boundary values
- Scenarios not covered by existing tests or Codecov's analysis

**Output:**
- List each gap with file:line reference and what should be tested
- If the coverage resolution chain ran, include the branch name and changed files
