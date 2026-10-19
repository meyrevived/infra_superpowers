# DR CI Environment Facts

## CI Provides (step script)

### Binaries
- `velero` CLI: installed by step script (v1.14.1 default, override via VELERO_VERSION)
- `oc`: provided by OpenShift CI base image
- `git`: provided by base image
- `ginkgo`: installed by step script (existing logic at top of script)
- `kubectl`: provided by base image (symlink to oc)

### Environment Variables (set by step script)
- `UPGRADE_BRANCH`: derived from PR metadata or defaults to `main`
- `UPGRADE_FORK_ORGANIZATION`: derived from PR metadata or defaults to `redhat-appstudio`
- `INFRA_DEPLOYMENTS_DIR`: `/tmp/infra-deployments`
- `E2E_BIN_PATH`: `/tmp/infra-deployments/tests/disaster-recovery`
- `ARGO_TARGET_REVISION`: discovered from live cluster ArgoCD `all-application-sets` app
- `DR_TIMEOUT`: `185m`
- `DR_LABEL`: `disaster-recovery`
- `ARTIFACT_DIR`: provided by OpenShift CI

### Environment Variables (provided by CI infrastructure)
- `GITHUB_TOKEN`: injected from CI secrets
- `QUAY_TOKEN`: injected from CI secrets
- `RELEASE_CATALOG_TA_QUAY_TOKEN`: injected from CI secrets
- `MY_GITHUB_ORG`: defaults to `redhat-appstudio-qe` in test code if unset
- `QUAY_E2E_ORGANIZATION`: defaults to `redhat-appstudio-qe` in test code if unset
- `KUBECONFIG`: provided by cluster claim

### Git Remotes (on /tmp/infra-deployments clone)
- `upstream`: redhat-appstudio/infra-deployments (renamed from origin)
- `qe`: redhat-appstudio-qe/infra-deployments

### Cluster State (provided by CI workflow)
- Konflux installed (via `konflux-ci-install-konflux` step, added in ci-operator config)
- OADP operator running in `openshift-adp` namespace
- Velero deployment running in `openshift-adp` namespace
- BackupStorageLocation configured (MinIO)
- ArgoCD managing Konflux components

### Path Resolution
- Ginkgo CWD: `/tmp/infra-deployments/tests/disaster-recovery/`
- `./tmp/infra-deployments` -> symlink to `/tmp/infra-deployments` (created by step script)

## Tests Assume

### Binaries (exec.Command calls)
- `velero`: disaster_recovery.go:242 -- `velero restore create`
- `oc`: disaster_recovery.go:266 -- `oc apply -f -`
- `git`: dr_backwards_compat.go:272 -- `git merge -Xtheirs`

### Environment Variables (os.Getenv / os.LookupEnv)
- `UPGRADE_BRANCH`: dr_backwards_compat.go:184 -- **required, no default, Expect non-empty**
- `UPGRADE_FORK_ORGANIZATION`: dr_backwards_compat.go:187 -- default `redhat-appstudio`
- `GITHUB_TOKEN`: dr_backwards_compat.go:194 -- used for git push auth
- `MY_GITHUB_ORG` (via constant): backup_infra.go:49 -- default `redhat-appstudio-qe`
- `QUAY_TOKEN`: backup_infra.go:193 -- **required, no default**
- `RELEASE_CATALOG_TA_QUAY_TOKEN`: backup_infra.go:196 -- **required, no default**
- `QUAY_E2E_ORGANIZATION` (via constant): const.go:266 -- default `redhat-appstudio-qe`
- `RELEASE_SERVICE_CATALOG_URL`: const.go:255 -- default provided
- `RELEASE_SERVICE_CATALOG_REVISION`: const.go:260 -- default `development`

### Path Assumptions
- `./tmp/infra-deployments`: dr_backwards_compat.go:183 -- relative to ginkgo CWD

### Git Remotes Expected
- `upstream` on infra-deployments clone: dr_backwards_compat.go:228 -- for merging upgrade branch
- `qe` on infra-deployments clone: dr_backwards_compat.go:247 -- for pushing merged changes

### K8s Resources Required
- Namespace `openshift-adp`: Velero, OADP operator, BSL
- OADP operator pods (label: `control-plane=controller-manager`): preconditions.go:43
- Velero deployment (name: `velero`): preconditions.go:68
- BackupStorageLocation: preconditions.go:85
- DR tenant namespaces (8 total): const.go:115-147
- CRDs: Application, Component, IntegrationTestScenario, Snapshot, Environment, ImageRepository, Repository (PaC), Release, ReleasePlan, ReleasePlanAdmission, EnterpriseContractPolicy
- Tekton PipelineRuns/TaskRuns
- ArgoCD Applications (for upgrade sync)

## Gaps (resolved in this push)
- G1: velero CLI was missing -> installed by step script
- G2: path mismatch ./tmp vs /tmp -> symlink created
- G3: hardcoded fork reference -> reverted to upstream
- G4: generated-config stale -> make update run

## Potential Remaining Gaps (unverifiable without CI run)
- QUAY_TOKEN / RELEASE_CATALOG_TA_QUAY_TOKEN: must be in CI secrets for the rehearsal job. If missing, backup_infra.go will fail with empty-string assertions.
- GITHUB_TOKEN: must have push access to redhat-appstudio-qe/infra-deployments for the qe remote push.
- OADP operator readiness: preconditions check may timeout if OADP is slow to initialize on OCP 4.18 cluster claim.
- Velero CLI version mismatch: if OADP deploys a different velero version than v1.14.1, API incompatibilities may surface.
- **PaC webhook delivery post-upgrade (CONFIRMED GAP, iteration 11):** Konflux upgrade (ArgoCD sync of pipeline-service/TektonConfig) breaks PaC's ability to receive or process GitHub webhook events. PipelineRuns are never created for post-restore trigger PRs. Exact broken link unknown — candidates: SprayProxy backend URL stale after PaC pod restart, PaC event listener route changed, PaC controller config reset. Early detection check added (5min timeout) to get diagnostic data on next run.
