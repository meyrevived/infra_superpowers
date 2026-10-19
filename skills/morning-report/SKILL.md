---
name: morning-report
description: Use when the user asks for a morning report, daily summary, daily standup prep, team updates, or catch-up on overnight activity. Aggregates Slack channels, Jira tickets, and email into a single briefing.
---

# Morning Report

Generate a morning briefing aggregating Slack, Jira, and email updates.

## Usage

```
/morning-report                                    # Last 24 hours
/morning-report since yesterday 5pm               # Custom time window
/morning-report channels:#eng,#prod projects:PROJ # Filtered sources
```

## When Invoked

1. **Determine time window:**
   - Read `~/.claude/skills/morning-report/last_run.json` for the last report timestamp.
   - If `last_run.json` exists: default window = everything since last report.
   - If no `last_run.json`: fall back to `timeWindow` from config (default 24h).
   - User args override both: `/morning-report since yesterday 5pm` sets an explicit floor.
   - Display the resolved window in the report header: "Covering: [start] — [now]"

2. **Load config** if it exists at `~/.claude/skills/morning-report/config.json`. Override with inline args.

3. **Gather from all three sources in parallel** using subagents or sequential calls:

### Slack (via slack-mcp MCP tools)

- Use `ToolSearch` to find available Slack tools
- Retrieve messages from configured channels using the resolved time window as the `oldest` parameter
- Prioritize: direct mentions > @channel/@here > active threads > general messages
- If Slack MCP unavailable: report "Slack integration not configured — see setup instructions"

### Jira (via Jira MCP tools)

Use the `mcp__jira__jira_search` tool with JQL queries. Do NOT use `acli`.

Use the resolved time window. Substitute `WINDOW_START` with the ISO date from step 1 (e.g., `2026-07-26`).

```
# Assigned to user, updated since last report
mcp__jira__jira_search(jql="assignee = currentUser() AND updated >= 'WINDOW_START' ORDER BY updated DESC")

# Watched tickets
mcp__jira__jira_search(jql="watcher = currentUser() AND updated >= 'WINDOW_START' ORDER BY updated DESC")

# Status changes in user's projects
mcp__jira__jira_search(jql="status changed during ('WINDOW_START', now()) AND (assignee = currentUser() OR watcher = currentUser()) ORDER BY updated DESC")
```

For each ticket with interesting activity, use `mcp__jira__jira_get_issue` for details.

Group results by project and status. Highlight status transitions and new comments.

If config specifies projects, add `AND project in (PROJ, TEAM)` to JQL.

### Email (via gws CLI — Google Workspace CLI)

Use the `gws` CLI installed via Tailwind. Invoke the `gws-gmail` skill for full reference.

Email has native unread tracking — use `is:unread` to avoid re-surfacing read messages. Combine with `after:YYYY/MM/DD` from the resolved window for belt-and-suspenders filtering.

```bash
# Quick unread inbox summary (sender, subject, date)
gws gmail +triage

# Unread since last report, excluding noise
gws gmail users messages list --params '{"q": "is:unread after:WINDOW_START -from:noreply@ -from:no-reply@"}'

# Read a specific message
gws gmail +read <message_id>
```

Substitute `WINDOW_START` with `YYYY/MM/DD` format from step 1.

Additional queries (Gmail search syntax):
```
# Important/starred unread
is:unread (is:important OR is:starred) after:YYYY/MM/DD

# From team, excluding noise
is:unread from:@redhat.com -category:promotions after:YYYY/MM/DD
```

If `gws` unavailable: report "Gmail integration not configured — install via: tailwind mcp add gws-cli"

4. **Generate report** in this format:

```markdown
# Morning Report — [Date]

## Email Highlights ([count] unread)
- **[Sender]**: [Subject] — [Brief summary]

## Slack Activity
### #[channel-name]
- **@[user]**: [Key message or discussion summary]

## Jira Updates
### [Project Name]
- **[TICKET-ID]**: [Title] — Status: [Old] -> [New]
- **[TICKET-ID]**: [Recent comment summary]

## Action Items
- [ ] [Messages requiring response]
- [ ] [Tickets needing attention]
- [ ] [Follow-ups from discussions]
```

5. **Save run timestamp** — after generating the report, write `~/.claude/skills/morning-report/last_run.json`:

```json
{"last_run": "2026-07-27T08:30:00Z"}
```

This becomes the default floor for the next invocation.

6. **Handle missing sources gracefully** — always produce the report with available sources. Never fail entirely because one source is unavailable.

## Config File

Optional: `~/.claude/skills/morning-report/config.json`

```json
{
  "slack": {
    "channels": ["#engineering", "#product"],
    "excludeChannels": ["#random"]
  },
  "jira": {
    "projects": [],
    "customQueries": [
      {
        "name": "My Active Work",
        "jql": "assignee = currentUser() AND status in ('In Progress', 'In Review') ORDER BY updated DESC"
      }
    ]
  },
  "email": {
    "excludeSenders": ["noreply@", "notifications@", "jira@", "github@"],
    "importantSenders": []
  },
  "timeWindow": "24h"
}
```

## Setup Requirements

| Source | Tool | Status Check |
|--------|------|-------------|
| Jira | Jira MCP server | `mcp__jira__jira_search` available |
| Slack | slack-mcp MCP server | Slack tools in ToolSearch |
| Email | `gws` CLI (via Tailwind) | `gws gmail +triage` succeeds |

See `references/setup.md` for installation instructions.
