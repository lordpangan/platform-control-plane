# ADR 0003 — kind for the management cluster; Ansible as source of truth; Helm for components

- **Status:** Accepted
- **Date:** 2026-08-09

## Context

Phase 1 builds the management cluster ("the brain"). Three choices to make: what
kind of cluster, how to automate its setup, and how to install the components
(Crossplane, Kyverno, ArgoCD). Two constraints shape it:

- It must run on a Proxmox VM (my real setup) **and** be runnable locally by any
  reader who wants to try it — without two separate implementations drifting.
- The management cluster is small and always-on; it does not run apps.

## Decision

- **kind** for the management cluster. It's lightweight, disposable, and runs the
  same way on a laptop and on a VM. The brain doesn't need production-grade
  compute — it just runs Crossplane/Kyverno/ArgoCD/Backstage. (The *workload*
  cluster is real EKS; that's Phase 2.)
- **Ansible is the single source of truth.** The same roles build the cluster
  locally and on the VM; only the inventory changes (`local` uses
  `connection: local`; `proxmox` uses SSH). A thin `Makefile` wraps the commands
  so the quickstart is one line (`make up`).
- **Helm** installs all three components (`helm upgrade --install`, pinned chart
  versions in `group_vars/all.yml`). Idempotent and reproducible.
- **devbox** provides the toolchain (kind/kubectl/helm/ansible), with a Homebrew
  fallback listed for anyone who wants to opt out.

## Alternatives considered

- **k3d / minikube / k3s** instead of kind — all fine; kind chosen for its
  ubiquity in tutorials and CI, and because backstack uses it (fewer surprises
  when following that pattern).
- **A local shell script + separate Ansible for the VM** — simplest local
  experience, but two implementations drift. One Ansible codebase avoids that.
- **Raw manifests / `kubectl apply`** instead of Helm — more moving parts to pin
  and upgrade; Helm gives versioning and idempotency for free.
- **kubernetes.core Ansible modules** instead of shelling out to `helm`/`kind` —
  cleaner in theory, but adds a Python `kubernetes` dependency. Shelling out to
  the pinned binaries keeps the dependency surface to just the CLIs devbox
  already provides.

## Consequences

- A reader needs Docker running plus the four CLIs; the `preflight` role fails
  early with a clear message if something's missing.
- On the VM, `bootstrap_host: true` installs the toolchain first. Adding the SSH
  user to the docker group needs a re-login — if the first run can't reach
  docker, reconnect and re-run (the playbook is idempotent).
- Everything is disposable: `make down` deletes the cluster; `make up` rebuilds
  it. This is a study/playground posture, not an HA control plane.
- Chart versions are pinned and will go stale — bump them deliberately.
