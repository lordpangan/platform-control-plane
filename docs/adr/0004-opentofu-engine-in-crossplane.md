# ADR 0004 — OpenTofu as the IaC engine, run inside Crossplane

- **Status:** Accepted
- **Date:** 2026-08-16

## Context

Phase 2 provisions real AWS (VPC, EKS). Two questions:

1. **How** does Crossplane create cloud resources — native cloud providers
   (`provider-aws`, one managed resource per object) or an IaC engine wrapped as a
   Crossplane resource?
2. **Which engine** — Terraform or OpenTofu?

Goals: reuse the community `terraform-aws-modules` (large, battle-tested), keep the
developer-facing API a small Crossplane claim, and avoid a licensing trap.

## Decision

- **Run IaC via `provider-opentofu`'s `Workspace` MR.** Each infra Composition
  emits exactly one `Workspace` running an OpenTofu module. The AWS resources live
  inside OpenTofu state, not as individual Crossplane managed resources.
- **Use OpenTofu, not Terraform.** HashiCorp relicensed Terraform to the BSL at
  1.6; the Apache-2.0 `provider-terraform` deliberately froze at Terraform 1.5.x.
  `provider-opentofu` runs **OpenTofu 1.10** (Apache-2.0, actively developed). The
  namespaced API group is `opentofu.m.upbound.io` (Crossplane v2).

## Alternatives considered

- **Native `provider-aws`** — one MR per cloud object, fully Crossplane-native
  (per-resource drift + observability). Rejected for Phase 2: we'd re-derive all
  the VPC/EKS wiring the community modules already encode. Native providers remain
  an option later where per-resource fidelity matters.
- **`provider-terraform` (Terraform 1.5.x)** — most battle-tested, but permanently
  frozen under the BSL; misses modern engine features. Rejected for OpenTofu.
- **Swap a newer Terraform binary into the provider** — BSL-licensed; defeats the
  open-source posture. Rejected.

## Consequences

- We get OpenTofu 1.10 features (plural backend args, state encryption, …) and an
  open license.
- AWS resources are managed by OpenTofu state, one level removed from Crossplane —
  per-resource drift/observability is OpenTofu's job, not Crossplane's. Accepted
  tradeoff for module reuse.
- The `providers/` Ansible role uses engine-agnostic variable names, so a future
  engine swap is a provider + `ClusterProviderConfig` change.
- OpenTofu resolves `hashicorp/aws` from the OpenTofu registry.
