# Morning Report — Setup

## Jira (Already Configured)

Jira MCP server is configured in `~/.claude.json`. No additional setup needed.

## Slack MCP Server

```bash
# Install the Red Hat Community AI Tools Slack MCP server
claude mcp add slack-mcp -- npx @redhat-community-ai-tools/slack-mcp
```

Requires a Slack Bot Token (`xoxb-...`) or User Token (`xoxp-...`).
Set `SLACK_TOKEN` env var or configure in MCP server settings.

Full docs: https://github.com/redhat-community-ai-tools/slack-mcp

### Verify
```bash
claude mcp list  # Should show slack-mcp
```

## Gmail (via gws CLI — Google Workspace CLI)

Installed via Tailwind. Uses Red Hat's shared GCP OAuth credentials.

```bash
# If not already installed:
bash ~/Projects/tailwind/installer/bin/tailwind mcp add gws-cli

# Or if tailwind is on PATH:
tailwind mcp add gws-cli
```

Interactive setup prompts for Gmail and Calendar scope authorization. Opens browser for Red Hat SSO.

### Verify

```bash
gws gmail +triage    # Should show unread inbox summary
gws auth status      # Should show token_valid: true
```

## Permission Allowlists

Add to Claude Code settings to reduce permission prompts:

```json
{
  "permissions": {
    "allow": [
      "mcp__jira__jira_search",
      "mcp__jira__jira_get_issue"
    ]
  }
}
```

## Config File

Create `~/.claude/skills/morning-report/config.json` to customize channels, projects, and email filters.
See `config.example.json` in the skill directory.
