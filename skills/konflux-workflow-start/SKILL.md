---
name: konflux-workflow-start
description: Use at the start of any Konflux development session to establish workflow and check repository status
---

# Konflux Workflow - Session Start

## Overview

Start every Konflux session with proper setup: sync with upstream, verify environment, and understand context.

**Core principle:** Always know your baseline state before making changes.

## When to Use

**At the start of EVERY Konflux development session**

Even if it seems unnecessary - 2 minutes now saves hours debugging later.

## Session Start Checklist

Run through this checklist at the beginning of each session:

### 1. Update Fork with Upstream Changes

```bash
# Fetch latest from upstream
git fetch upstream

# Check status
git status

# If behind upstream:
git merge upstream/main
# or
git rebase upstream/main
```

**Why:** Changes accumulate quickly in active repos. Starting with stale code wastes time.

### 2. Identify Current Repository

Confirm which repo you're working in and its purpose:

**multi-platform-controller (mpc)**
- Go-based Kubernetes controller
- Allocates multi-architecture build hosts
- Uses Ginkgo/Gomega for testing
- Changes here often require infra-deployments updates

**infra-deployments**
- GitOps repository (Argo CD + Kustomize)
- Deploys Konflux components to clusters
- Multi-environment: development, staging, production
- Changes here deploy the controller

**mpc_dev_env**
- Development environment tooling
- Local cluster setup and testing utilities
- Use this to test mpc changes locally

### 3. Verify Development Environment

**For Go repos (mpc, mpc_dev_env):**
```bash
# Ensure dependencies are current
go mod tidy

# Run baseline tests
make test
```

**For GitOps repos (infra-deployments):**
```bash
# Verify preview mode environment variables if needed
echo $MY_GIT_FORK_REMOTE
echo $MY_GITHUB_ORG
```

### 4. Understand Cross-Repo Impact

**Ask yourself:**
- Does this change affect multiple repos?
- Do I need to update deployment configs?
- Should I test in dev environment first?

**Common flows:**

```
mpc code change → test in mpc_dev_env → update infra-deployments
                                            ↓
                                    dev → staging → production
```

## Red Flags - STOP and Sync

These indicate you should stop and sync before proceeding:

- "I haven't pulled in a few days"
- "Let me just make a quick change"
- "Tests were passing last time"
- "I'll sync later"

**All of these mean: STOP. Run the checklist.**

## Quick Start Commands

```bash
# Update fork
git fetch upstream && git merge upstream/main

# Verify baseline (Go repos)
make test

# Check which repo
pwd
```

## Integration with Other Skills

**After running this checklist:**
- If writing code: Use superpowers:test-driven-development
- If fixing bugs: Use superpowers:systematic-debugging
- If planning features: Use superpowers:brainstorming

This skill establishes your baseline. Other skills guide the work.

## Why This Matters

**Real scenarios this prevents:**

❌ "I spent 3 hours debugging, then realized it was fixed upstream yesterday"

❌ "My tests pass but CI fails - different dependency versions"

❌ "I made changes to mpc but forgot to update infra-deployments"

✅ "2-minute checklist, clean baseline, productive session"

## Checklist Summary

Before starting work:
- [ ] Fetched and merged upstream changes
- [ ] Confirmed current repository and purpose
- [ ] Verified baseline tests pass
- [ ] Understood cross-repo impact if applicable

All checked? You're ready to work with confidence.
