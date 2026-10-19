# Gmail Search Queries for Morning Report

Used with the `search_threads` Gmail MCP tool. Standard Gmail search syntax.

## Time Windows

| Window | Syntax |
|--------|--------|
| Last hour | `newer_than:1h` |
| Last 12h | `newer_than:12h` |
| Last 24h | `newer_than:1d` |
| Last week | `newer_than:7d` |
| Since date | `after:YYYY/MM/DD` |

## Common Patterns

```
# Unread, excluding automated
is:unread -from:noreply@ -from:no-reply@ newer_than:1d

# Important/starred
(is:important OR is:starred) newer_than:1d

# From team, excluding noise
from:@redhat.com -from:noreply@ -from:jira@ -category:promotions newer_than:1d

# Direct messages only
to:me -cc:me is:unread newer_than:1d

# Primary inbox only
category:primary newer_than:1d

# With attachments
has:attachment newer_than:1d
```

## Operators

| Operator | Meaning |
|----------|---------|
| `from:` | Sender |
| `to:` | Recipient |
| `cc:` | CC'd |
| `subject:` | Subject line |
| `is:unread` | Unread only |
| `is:important` | Priority inbox |
| `is:starred` | Starred |
| `has:attachment` | Has attachments |
| `category:primary` | Primary tab |
| `-` | NOT (exclude) |
| `OR` | Either condition |
| `()` | Group conditions |

Reference: https://support.google.com/mail/answer/7190
