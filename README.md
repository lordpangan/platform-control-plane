# platform-control-plane

The **brain** of a small internal developer platform. This repo sets up the
*management cluster* — the always-on control plane that builds and manages
everything else. It runs:

- **Crossplane** — turns simple requests into real cloud infrastructure
- **Kyverno** — enforces guardrails so self-service is safe
- **ArgoCD** — keeps clusters in sync with Git (GitOps)
- **Backstage** — the developer front door (portal, catalog, scaffolder)

The management cluster does **not** run your apps. It builds a separate
workload cluster (EKS on AWS) and deploys apps onto that.

> This is a learning playground and portfolio project. It follows the
> [backstack](https://github.com/TeraSky-OSS/backstack) pattern. See the
> [roadmap](../ROADMAP.md) for where it's going and the
> [grounding notes](../platform-engineering-grounding.md) for the why.

> **Who is this for?** A platform is a product with real users. Read the
> [product brief](./docs/product/README.md) first — the company, the dev-team
> pain, and the personas (Dana, Ravi, Priya) that drive every decision here.

## The two repos

| Repo | Job |
|------|-----|
| **platform-control-plane** (this repo) | Install the brain. Ansible sets it up on a VM; the README shows how to run it locally too. |
| **platform-gitops** | Everything ArgoCD watches: `definitions/` (templates for infra & apps), `infra-requests/` (Terraform-in-Crossplane → real EKS), `app-requests/` (the claims developers write). |

## Quickstart — local (kind)

Spin up the whole brain on your own machine — no VM, no cloud account. The same
Ansible that runs on the VM runs here; only the inventory differs.

**Prerequisites**

- **Docker** running (Docker Desktop, Colima, etc.)
- **kind**, **kubectl**, **helm**, **ansible**

You can get the tools either way:

```bash
# Option A — devbox (pins exact versions; recommended)
devbox shell            # provides kind, kubectl, helm, ansible, jq

# Option B — Homebrew (opt out of devbox)
brew install kind kubernetes-cli helm ansible jq
```

**Run it**

```bash
make up               # create the kind cluster + install Crossplane, Kyverno, ArgoCD
make status           # watch the pods come up healthy
make argocd-password  # print the ArgoCD admin password
make down             # tear the whole cluster down
```

That's it — `make up` gives you a local control plane with Crossplane, Kyverno,
and ArgoCD running.

## Running it on a real VM (Proxmox)

Same playbook, different inventory. The VM should be Debian/Ubuntu; the
`bootstrap` role installs docker/kind/kubectl/helm on it first.

```bash
cp ansible/inventories/proxmox/hosts.yml.example ansible/inventories/proxmox/hosts.yml
# edit hosts.yml with your VM's IP and SSH user, then:
make up-vm
```

`hosts.yml` is gitignored so your real host details never get committed.

## How it's built

- **Ansible is the single source of truth** — roles in `ansible/roles/` install
  each piece; `ansible/group_vars/all.yml` pins every version.
- **`make` is just a thin wrapper** around `ansible-playbook`.
- **kind config** is in `kind/config.yaml`.
- **The `argocd` role also seeds GitOps** — it applies one root `Application`
  pointing ArgoCD at `platform-gitops`. That seed can't live in the repo it
  watches; everything downstream (the child Applications, ordered by sync wave)
  is committed there and reconciled by ArgoCD itself. See
  [ADR 0007](./docs/adr/0007-gitops-bootstrap-seed.md).
- See [ADR 0003](./docs/adr/0003-kind-ansible-helm.md) for why kind + Ansible + Helm.

## Documentation

- **Decisions:** [`docs/adr/`](./docs/adr/) — why things are the way they are
- **Journal:** [`docs/journal/`](./docs/journal/) — dated learning notes

## Status

Phase 1 (build the brain) — Crossplane + Kyverno + ArgoCD via Ansible.
Backstage (the front door) comes in Phase 8. See [`../ROADMAP.md`](../ROADMAP.md).
