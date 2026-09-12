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

### Reaching the ArgoCD UI

The cluster runs **inside the VM**, so getting to the UI takes two hops: an SSH
tunnel from your machine to the VM, then a `port-forward` from the VM into the
cluster. The `-vm` targets do both for you:

```bash
make argocd-ui-vm         # tunnel + port-forward -> https://localhost:8080
make argocd-password-vm   # the admin password (user: admin)
make argocd-apps-vm       # watch Applications sync, in wave order
make status-vm            # pod health on the VM cluster
```

Open **<https://localhost:8080>** and accept the self-signed certificate.
`Ctrl-C` closes the tunnel.

The same targets without `-vm` (`make argocd-ui`, `make argocd-password`,
`make status`) work against a **local** `make up` cluster — no tunnel needed.

> **How the `-vm` targets find your VM:** they read `ansible_host`,
> `ansible_user` and `tools_path` out of the gitignored proxmox inventory, so
> host details live in exactly one place. `tools_path` matters because a
> non-interactive SSH session skips your shell profile — without it the VM's
> devbox toolchain isn't on `PATH` and `kubectl` appears to be missing.

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
