# Repo Management Reference

## Dedicated Directory

`~/Desktop/Work/Konflux/.debugger-repos/`

This directory is completely separate from personal forks. The skill owns this directory.

## Repo Catalog — Issue Type to Repo Mapping

| Issue Type | Primary Repos | Secondary Repos |
|------------|--------------|-----------------|
| Build failures | `build-service`, `build-definitions` | `mintmaker`, `renovate-config` |
| Pipeline failures | `build-definitions`, `tekton-catalog` | `build-service` |
| Integration test failures | `integration-service` | `build-service` |
| Release issues | `release-service`, `release-service-catalog` | `integration-service` |
| Deployment/GitOps | `infra-deployments` | `konflux-ci` |
| Access/onboarding | `infra-deployments` | `service-provider-integration` |
| Image/registry | `image-controller` | `build-service` |
| Multi-arch builds | `multi-platform-controller` | `build-service` |

## When to Clone

Only clone repos when source code investigation is needed — not for every support thread. Indicators:
- Error message references specific controller logic or task implementation
- Need to verify how a feature works at the code level
- Investigating whether behavior is a bug vs intended design
- Checking task definitions in build-definitions or tekton-catalog

**Example:** user reports 'my build uses the wrong Dockerfile path' → clone `build-service` to check how Dockerfile discovery works.

## Clone/Pull Behavior

For each repo needed:
1. Check if it exists in `.debugger-repos/`:
   - **Exists?** -> `git -C .debugger-repos/<repo> pull origin main` (silently update)
   - **Doesn't exist?** -> `git clone https://github.com/konflux-ci/<repo>.git .debugger-repos/<repo>` (silently clone)
   - **Clone/pull fails?** → Fall back to `gh api` for file reads (e.g., `gh api repos/konflux-ci/<repo>/contents/<path>`)
2. Investigate using Grep/Read on local files

## Restrictions

- **Never** push, commit, branch, or modify any file in `.debugger-repos/`
- **Never** clone from outside `github.com/konflux-ci/`
- **Never** clone repos not in the catalog above without explicit engineer approval
- All operations are read-only

## Example Usage

```bash
# Issue classified as "build failure" — clone primary repos
mkdir -p ~/Desktop/Work/Konflux/.debugger-repos
cd ~/Desktop/Work/Konflux/.debugger-repos

# Clone or update
git clone https://github.com/konflux-ci/build-service.git 2>/dev/null || \
  git -C build-service pull origin main

git clone https://github.com/konflux-ci/build-definitions.git 2>/dev/null || \
  git -C build-definitions pull origin main

# Investigate
grep -r "error message from user report" build-service/
```
