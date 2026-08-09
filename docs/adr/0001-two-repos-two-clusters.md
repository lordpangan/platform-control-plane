# ADR 0001 — Two repos, one GitOps repo with owner-split folders, two clusters

- **Status:** Accepted
- **Date:** 2026-08-09

## Context

This is an internal developer platform (learning + portfolio). It follows the
backstack pattern. We need to decide how to split the code across repos and
clusters. Two forces pull against each other:

1. **Clear ownership boundaries.** Platform-team code (infra, API definitions)
   changes rarely and is dangerous; developer code (app requests) changes
   constantly and is low-risk. They deserve different review gates.
2. **Not too many moving parts.** This is a solo playground, not a 30-team org.
   Spreading things across many repos adds overhead with little payoff at this
   size.

## Decision

**Two repos:**

- `platform-control-plane` — installs the management cluster (the "brain").
- `platform-gitops` — everything ArgoCD watches, split into "templates" vs
  "live requests", with requests split by owner:
  - `definitions/` — XRDs + Compositions (templates for infra and apps). Platform-owned.
  - `infra-requests/` — infra **claims** (e.g. `XEKSCluster`) that spin up VPC/
    IAM/EKS. Platform-owned, rare, real cloud spend. The `Workspace` MR running
    the Terraform is hidden inside the infra Composition.
  - `app-requests/` — the app **claims** (`WebApp`). Developer-owned, constant.

**Two clusters:**

- **Management cluster** — small, always-on, on a Proxmox VM (kind). Runs
  Crossplane, Kyverno, ArgoCD, Backstage. Does not run apps.
- **Workload cluster (EKS)** — the real platform in AWS, built and managed by the
  management cluster.

## Alternatives considered

- **Three repos (infra repo + separate app-requests repo).** Cleaner ownership
  story and independent CODEOWNERS, and closer to how large orgs run. Rejected
  for now: too many repos for a solo project. Folder-level CODEOWNERS in one repo
  gets us the boundary without the sprawl. Revisit if this ever has real tenants.
- **One repo for everything (brain + gitops together).** Simplest, but mixes the
  "how to install the platform" concern with the "desired state ArgoCD syncs"
  concern, and would make the ArgoCD-watched surface noisy.

## Consequences

- One place (`platform-gitops`) for ArgoCD to watch; sync policy can differ per
  folder (e.g. auto-sync `app-requests/`, manual-approve `infra-requests/`).
- The management cluster is a hard dependency for everything — it must exist
  before any infra or app can be built. That's Phase 1.
- If tenants ever appear, splitting `app-requests/` into its own repo is a
  documented, non-breaking migration (a day-2 evolution).
