# JQL Examples for Morning Report

All queries use `mcp__jira__jira_search` — not `acli`.

## Time-Based

| Window | JQL |
|--------|-----|
| Last 24h | `updated >= -24h` |
| Last 12h | `updated >= -12h` |
| Since start of day | `updated >= startOfDay()` |
| Since start of week | `updated >= startOfWeek()` |
| Last week | `updated >= -7d` |

## User-Specific

```
assignee = currentUser() AND updated >= -24h ORDER BY updated DESC
watcher = currentUser() AND updated >= -24h ORDER BY updated DESC
reporter = currentUser() AND updated >= -24h ORDER BY updated DESC
```

## Status Changes

```
status changed to 'In Review' during (-24h, now()) ORDER BY updated DESC
status changed to Done during (-24h, now()) ORDER BY updated DESC
status = Blocked AND updated >= -24h ORDER BY updated DESC
```

## Combined

```
assignee = currentUser() AND status in ('In Progress', 'In Review') AND updated >= -24h ORDER BY updated DESC
project in (PROJ, TEAM) AND priority in (Highest, High) AND updated >= -24h ORDER BY updated DESC
```

Always append `ORDER BY updated DESC` and use `limit` parameter on the tool call.
