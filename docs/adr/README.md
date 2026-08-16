# Architecture Decision Records

Short records of decisions that shaped this platform, and the alternatives we
rejected. Newest decisions get the next number. Don't rewrite history — if a
decision changes, add a new ADR that supersedes the old one.

| # | Decision | Status |
|---|----------|--------|
| [0001](./0001-two-repos-two-clusters.md) | Two repos, one GitOps repo with owner-split folders, two clusters | Accepted |
| [0002](./0002-backstage-front-door-repo-escape-hatch.md) | Backstage is the front door; the Git repo is the escape hatch | Accepted |
| [0003](./0003-kind-ansible-helm.md) | kind cluster; Ansible as source of truth; Helm for components | Accepted |
| [0004](./0004-opentofu-engine-in-crossplane.md) | OpenTofu as the IaC engine, run inside Crossplane (over native providers / Terraform) | Accepted |
| [0005](./0005-remote-state-s3-dynamodb-bootstrap.md) | Remote OpenTofu state in S3 + DynamoDB, via a one-time bootstrap | Accepted |
| [0006](./0006-scoped-iam-user-for-platform-identity.md) | A scoped IAM user for the platform (Crossplane) identity | Accepted |

> These two are system-wide decisions, so they live in the control-plane repo.
> Repo-specific decisions live in that repo's own `docs/adr/`.
