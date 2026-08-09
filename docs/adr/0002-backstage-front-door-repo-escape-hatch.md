# ADR 0002 — Backstage is the front door; the Git repo is the escape hatch

- **Status:** Accepted
- **Date:** 2026-08-09

## Context

A core platform question: how thick should the abstraction be? One camp says
developers should never see Kubernetes. The other says hiding it creates a worse
debugging story and a platform-team bottleneck. We need a position, because it
decides what the developer's day-to-day interface actually is.

## Decision

**Hide Kubernetes in the *authoring* experience; expose it in the *debugging*
experience.**

- **Authoring (the front door):** developers use **Backstage**. Its scaffolder
  generates a thin `WebApp` claim and writes it into `platform-gitops/app-requests/`.
  A developer describes their app in a handful of fields and never writes raw
  Kubernetes.
- **Debugging (the escape hatch):** the Git repo and the live cluster stay
  readable. When something breaks, a developer can open the real claim, read the
  generated Deployment/Service/HPA/Ingress, and hit the cluster directly.

## Rationale

- Abstractions that can't be inspected are the ones that fail. A thin authoring
  surface keeps cognitive load low; an open debugging surface keeps power users
  from being trapped.
- It matches the platform's stated design goal: reduce cognitive load without
  becoming an opaque black box or a ticket queue.

## Consequences

- Backstage is in scope (Phase 8), not optional — it's the front door, not a
  nice-to-have.
- The generated resources must stay legible: prefer clear, readable Compositions
  over clever ones, because developers will read them when debugging.
- `app-requests/` is developer-facing but rarely hand-edited — the scaffolder is
  the normal way in. The repo is the fallback, not the primary path.
