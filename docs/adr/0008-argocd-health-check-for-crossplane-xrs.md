# ADR 0008 — Teach ArgoCD to read XR readiness with a Lua health check

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

ArgoCD sync waves gate on health: a later wave does not start until every
resource in the earlier wave is Healthy. The platform relies on this to order the
VPC (wave 1) before the EKS cluster (wave 2), because the EKS Composition
discovers the VPC by tag at apply time. If EKS runs before the VPC exists, tag
discovery finds nothing and the apply fails.

The problem is that ArgoCD ships no health check for custom kinds. For an
`XNetwork` or `XEKSCluster` it has no way to judge health, so it reports Healthy
the instant the object applies — it never looks at the XR's `Ready` condition. So
the waves ordered the *apply*, not the *readiness*. Wave 2 could start while the
VPC was still building.

This did not break in testing, but only by accident: provider-opentofu runs a
single worker, so it applied the VPC and then the EKS one after another. The
ordering was a timing coincidence, not a guarantee. With more workers the two
would apply in parallel and the discovery race could fire.

## Decision

**Add a per-kind Lua health check to `argocd-cm` that reads the XR's `Ready`
condition.** ArgoCD only reports Healthy when `status.conditions[Ready] == True`;
otherwise it reports Progressing, which holds the next wave.

- The check is defined in the argo-cd Helm chart's `configs.cm` values, under
  `resource.customizations.health.platform.meridian.io_XNetwork` and
  `..._XEKSCluster`. The chart renders these into the `argocd-cm` ConfigMap.
- The values file is rendered by the `argocd` Ansible role
  (`templates/argocd-values.yaml.j2`) and passed to `helm upgrade --values`, so it
  follows the same source-of-truth rule as everything else (see
  [ADR 0003](./0003-kind-ansible-helm.md)).
- The Lua walks `status.conditions`, returns Healthy on `Ready=True`, and
  Progressing otherwise. It is a pure function: ArgoCD re-runs it each poll, so
  the readiness is re-evaluated continuously, not once.

Verified on the VM: re-adding the VPC claim, the `platform-infra-requests`
Application held at Progressing while the XR was `READY=False` and flipped to
Healthy in the same poll the XR reached `READY=True`. The two now move in lockstep.

## Alternatives considered

- **Leave the caveat open** — rely on the single worker serializing applies, plus
  ArgoCD's retry-until-healthy to self-heal a failed discovery. Rejected: it is
  correctness by coincidence. The moment the provider is scaled to more workers
  (the production direction, see learning record 0007) the ordering guarantee
  disappears, and "it retries until it works" is not something to demo.
- **A community Crossplane health-check bundle** — ArgoCD has shipped/contributed
  Lua for some Crossplane kinds. Rejected for now: it targets generic Crossplane
  types, not our `platform.meridian.io` XRs, and pulling in a bundle we do not
  control for two kinds is more surface than a six-line script we understand.
- **ApplicationSet or sync hooks to sequence layers** — heavier machinery to force
  ordering outside the health model. Rejected: the health check fixes the root
  cause (ArgoCD not knowing what "ready" means for an XR) rather than working
  around it, and it is the idiomatic ArgoCD answer.

## Consequences

- Wave gating is now deterministic: EKS waits on the VPC's real readiness, not on
  provider timing. This holds even after the provider is scaled to more workers.
- **Every new XR kind needs its own health-check entry.** The customization is
  keyed by `group_Kind`; a new XRD added to the platform will report Healthy on
  apply (the old broken behavior) until a matching entry is added to the values
  file. This is the maintenance cost of the decision and must be remembered when
  adding kinds.
- The current script is two-state (Healthy / Progressing). A genuinely failed
  apply reports Progressing forever rather than surfacing as a failure, because
  ArgoCD has no health timeout. A follow-up to return `Degraded` on a failure
  reason is noted in learning record 0007; it improves diagnosis, not gating.
- The check reads only `Ready`. It deliberately ignores `Synced`, since an XR can
  be Synced (composition reconciled) long before it is Ready (resources built).
