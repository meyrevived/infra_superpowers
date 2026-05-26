# AgentReady Assessment Review - {REPO_NAME}

**AgentReady Score:** {ORIGINAL_SCORE}/100 ({ORIGINAL_TIER})
**Adjusted Score:** ~{ADJUSTED_SCORE}/100 (after correcting false negatives)
**Reviewed:** {DATE}
**Reviewer:** {REVIEWER}
**Commit:** {COMMIT_SHA} | **Branch:** {BRANCH}

---

## Executive Summary

{2-3 sentences: what AgentReady scored, what the adjusted score is, and the main reasons for the gap. Be specific about which false negatives had the biggest impact.}

---

## Tool Issues Discovered

{List each issue with AgentReady's execution or detection. Include:}
{- The specific problem}
{- What AgentReady reported vs what actually exists}
{- Workaround if applicable}

---

## Finding-by-Finding Assessment

### Tier 1 Findings (Highest Priority)

| # | Finding | AgentReady Score | Adjusted Score | Verdict |
|---|---------|-----------------|----------------|---------|
| 1 | {Finding name} | {X/100} | {Y/100} | {Fair/False negative/Unfair/Irrelevant} |

{For each finding that is NOT "Fair", provide a paragraph explaining:}
{- What AgentReady claimed}
{- What actually exists in the repo (with file paths and line numbers)}
{- Why the adjusted score is different}

### Tier 2 Findings

{Same table and detail format as Tier 1}

### Tier 3 Findings

{Same table and detail format as Tier 1}

### Tier 4 Findings

{Same table and detail format as Tier 1}

---

## Actionable Improvements (Priority Order)

### Quick Wins (< 1 hour each)

{Numbered list of genuinely valuable, low-effort improvements. Include specific commands or file changes.}

### Medium Effort (1-4 hours)

{Numbered list of medium-effort improvements worth pursuing.}

### Not Recommended

{List items from the report that are NOT worth acting on, with a one-line explanation for each.}

---

## AgentReady Tool Feedback

{Numbered list of specific issues worth reporting to AgentReady maintainers. Focus on detection gaps, not feature requests. Include:}
{- What the tool does wrong}
{- What it should do instead}
{- Example from this specific assessment}
