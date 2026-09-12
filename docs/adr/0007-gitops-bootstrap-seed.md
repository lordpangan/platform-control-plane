# ADR 0007 — The GitOps bootstrap seam: a seed here, content in the GitOps repo

- **Status:** Accepted
- **Date:** 2026-09-12

## Context

ArgoCD does whatever the GitOps repo (`platform-gitops`) tells it to. But you
cannot put *"here is the GitOps repo"* **inside** the GitOps repo — nothing would
ever read it. Something has to point ArgoCD at the repo once, imperatively.

That creates a boundary question: how much ArgoCD configuration belongs in
`platform-control-plane` (this repo, which bootstraps the brain), and how much
belongs in `platform-gitops` (the repo ArgoCD watches)?

The app-of-apps pattern needs at least three objects: a root `Application`, and
one child `Application` per watched folder (`definitions/`, `infra-requests/`),
ordered by sync wave so XRDs are established before any claim references them.

## Decision

**Only the seed lives here. Everything else lives in `platform-gitops`.**

- The **seed** is the single root `Application` pointing ArgoCD at
  `platform-gitops` path `bootstrap/`. It is applied imperatively by the
  `argocd` Ansible role, rendered from
  `ansible/roles/argocd/templates/root-app.yaml.j2` with the repo URL, revision
  and path pinned in `group_vars/all.yml`.
- The **content** — the child Applications and their `sync-wave` annotations —
  is committed to `platform-gitops/bootstrap/`, so ArgoCD reconciles its own
  wiring.

The rule, stated once: *if it is needed **before** ArgoCD can read the GitOps
repo, it belongs here; everything else belongs in `platform-gitops`.* Only the
root Application passes that test.

There is **no static `argocd/root-app.yml`** in this repo. Per
[ADR 0003](./0003-kind-ansible-helm.md), Ansible is the single source of truth;
a second hand-maintained copy of the same manifest would silently drift.

## Alternatives considered

- **All three Applications in this repo** — simplest to read, everything in one
  place. Rejected: editing a child Application would then do nothing until
  someone re-runs Ansible, which breaks the "continuously reconciled" GitOps
  principle for the very objects that implement GitOps.
- **A static `argocd/root-app.yml` applied via `kubectl apply -f`, with Ansible
  copying it** — keeps a hand-runnable manifest. Rejected: it duplicates the
  Ansible template, and the repo URL/revision stop being configurable from
  `group_vars`. Trades configurability for one less abstraction; not worth it.
- **ApplicationSet instead of app-of-apps** — generates children from a directory
  generator. Deferred: more machinery than two folders justify, and explicit
  child manifests make the sync-wave ordering easy to see and explain.

## Consequences

- The brain comes up fully bootstrapped: `make up` installs ArgoCD **and** seeds
  it, so the cluster starts reconciling `platform-gitops` with no manual step.
- Changing the watched repo, branch, or bootstrap path is a `group_vars` edit.
- Pointing at a fork requires re-running the play, not editing a file in-cluster.
- The seed itself is **not** self-healing — if someone deletes the root
  Application in-cluster, ArgoCD will not restore it; re-running the play does.
  Acceptable: it is one object, recreated by the same command that built the brain.
- The child Applications use `prune: true`, so removing a claim from
  `infra-requests/` tears down real AWS resources. Intentional for this sandbox;
  a production setup would gate that behind manual sync or a separate project.
