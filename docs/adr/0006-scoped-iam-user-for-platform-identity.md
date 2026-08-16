# ADR 0006 — A scoped IAM user for the platform (Crossplane) identity

- **Status:** Accepted
- **Date:** 2026-08-16

## Context

The management cluster is kind-on-a-VM, which **can't use IRSA**. So
`provider-opentofu` authenticates to AWS with a **static access key** held in a
Kubernetes Secret. How much power should that key carry?

## Decision

- A dedicated IAM user **`crossplane-terraform`** with a **service-scoped** policy:
  full `ec2` / `eks` / `autoscaling` / `kms`, the specific `iam` actions EKS needs
  (roles, instance profiles, OIDC, `PassRole`), and tightly resource-scoped
  `s3`/`dynamodb` for *this* state bucket + lock table. **Not** `AdministratorAccess`.
- `kms:*` is retained even though EKS runs with `create_kms_key = false` — kept for
  deliberate future use.
- The key is delivered via a Kubernetes Secret referenced by a cluster-scoped
  `ClusterProviderConfig`, and is **never committed** (read from local bootstrap
  state at wiring time).

## Alternatives considered

- **`AdministratorAccess`** — simplest; rejected: a leaked static admin key is a
  full-account compromise.
- **`PowerUserAccess` + IAM** — broad managed policy; rejected for an explicit
  service-scoped policy (a clearer least-privilege story — the security persona).
- **Fully resource-scoped least-privilege** — ideal, but impractical: ec2/eks
  resources don't exist before apply, and a hand-maintained per-action/per-resource
  allowlist breaks mid-apply. Service-scoping is the pragmatic middle; further
  tightening is tracked for Phase 3.
- **IRSA / SSO for the provider** — unavailable to kind-on-a-VM. Human access *does*
  use SSO (IAM Identity Center); the in-cluster provider can't.

## Consequences

- The static key is a standing liability — two plaintext copies exist (local
  bootstrap state on the operator's machine, and the in-cluster Secret).
  Mitigations: it's scoped, rotatable (taint the access key + re-wire), and
  destroyable (`make teardown-aws-state`). Encrypting the Secret at rest
  (SOPS / Sealed Secrets) is a Phase 3 hardening.
- The policy can craft IAM roles (`PassRole`) within the account, so a leak is
  serious — reinforcing no-commit + rotation discipline.
