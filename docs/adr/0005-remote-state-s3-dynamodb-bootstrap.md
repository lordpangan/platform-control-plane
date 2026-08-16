# ADR 0005 — Remote OpenTofu state in S3 + DynamoDB, via a one-time bootstrap

- **Status:** Accepted
- **Date:** 2026-08-16

## Context

`provider-opentofu` `Workspace`s run OpenTofu, which needs **remote state** (the
provider does not persist state itself). Whoever holds the state controls the
resources — lose it and you have orphaned, still-billing AWS. And a backend can't
create itself (chicken-and-egg): the bucket/table must exist before any Workspace
runs.

## Decision

- **State in S3 + locking in DynamoDB.** An S3 bucket (versioned, encrypted, no
  public access) holds state; a DynamoDB table provides locking. Each layer uses
  its own key (`network/`, `eks/`); `provider-opentofu`'s named workspaces add
  automatic per-claim isolation under `env:/<claim-name>/…` on top.
- **A one-time bootstrap** (`bootstrap/aws-state/`) creates the bucket, table, and
  the scoped IAM user. It runs with the operator's admin identity using **local
  state** — the root of trust, gitignored. Wrapped as `make bootstrap-aws`.
- **DynamoDB locking, not the S3 native lockfile.** `provider-opentofu` bundles its
  own OpenTofu; DynamoDB locking is compatible everywhere, whereas the S3 native
  lockfile needs a newer engine than some setups carry.

## Alternatives considered

- **In-cluster state** (the provider default, stored in a Kubernetes Secret) — zero
  bootstrap, but it dies with the kind cluster → orphaned EKS. Rejected: that's
  exactly the cost risk we care about.
- **S3 native lockfile (`use_lockfile`)** instead of DynamoDB — one fewer resource,
  but engine-version-dependent. DynamoDB is universally compatible. Can revisit.
- **Terraform Cloud / a managed remote backend** — turnkey, but adds an external
  account/dependency and moves state off our own infra. Rejected for a
  self-contained portfolio.

## Consequences

- Bootstrap is a manual one-time step before any claim can be applied.
- State survives cluster rebuilds, so teardown is always possible — no orphans.
- The bootstrap's own local state is the one piece not in a remote backend; it's
  gitignored and low-churn (it only changes when the backend/identity change).
