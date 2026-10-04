# ADR 0009 — How Backstage is deployed: in the brain, by Ansible, prebuilt image

- **Status:** Accepted
- **Date:** 2026-10-04

## Context

[ADR 0002](./0002-backstage-front-door-repo-escape-hatch.md) made Backstage the
front door. It did not say where Backstage runs or how it is configured.

The reference setup is backstack. There, kind, Crossplane, Kyverno and ArgoCD
ran on the VM, but Backstage ran on a laptop with `yarn start`. It reached the
cluster through a public Cloudflare tunnel, with a `cluster-admin` token. Its
config had a hardcoded API token from the upstream repo and turned off TLS
checks for every outbound call.

We wanted the front door for the infra API first: request forms for `XNetwork`
and `XEKSCluster`, and a catalog of live XRs. The TeraSky `kubernetes-ingestor`
plugin does both. It reads the XRDs and XRs from the cluster.

## Decision

**Backstage runs inside the brain cluster. A `backstage` Ansible role installs
it with the official Helm chart and the prebuilt backstack image.**

- **Where:** in the brain, next to Crossplane, Kyverno and ArgoCD. `make up-vm`
  builds it like any other component ([ADR 0003](./0003-kind-ansible-helm.md)).
  It runs last, because it reads the XRDs Crossplane serves and talks to ArgoCD.
- **Image:** `ghcr.io/vrabbi/backstack-demo`, with the TeraSky plugins built in.
  We do not build our own image yet.
- **Cluster access:** a ServiceAccount bound to a read-only ClusterRole. It can
  list XRDs, XRs, Workspaces and workloads. It cannot read Secrets. It reaches
  the API server in-cluster and checks its certificate with the cluster CA.
- **Secrets:** the GitHub PAT, the ArgoCD password and the GitHub OAuth app
  credentials live in an ansible-vault file in the repo. The vault password
  lives outside the repo. The role copies the secrets into a Kubernetes
  Secret. The Helm values only hold `${VAR}` references, which Backstage fills
  in from env vars at runtime. The SA token goes straight from its Secret to
  the pod and never passes through Ansible.
- **ArgoCD access:** `argocd-server` runs with `server.insecure`, so Backstage
  reaches it over plain HTTP inside the cluster.
- **User access:** port-forward (`make backstage-ui-vm`). No ingress yet.
- **Sign-in:** guest. A GitHub OAuth app is registered only so the edit flow
  can read claim files as the user.
- **Writes:** Backstage never applies to the cluster and never pushes to
  `main`. Every change is a pull request on `platform-gitops`.

## Alternatives considered

- **Run Backstage on a laptop, like backstack.** No VM resources used. Rejected:
  it needs the kube API reachable from outside, which backstack did by putting
  a `cluster-admin` token behind a public URL. It is also a manual step that
  `make up-vm` cannot rebuild. The VM has room: the brain used 2.4 of 15 GB.
- **Deploy Backstage as an ArgoCD Application.** More GitOps-native. Rejected:
  Backstage is part of the brain, and the brain is built by Ansible. It would
  also make ArgoCD deploy the tool that submits work to ArgoCD.
- **Build our own image.** Full control over plugins and versions. Rejected for
  now: a Backstage build is heavy (yarn, multi-stage Docker, image hosting) and
  gives the same front door on day one. Revisit when there is a concrete need:
  permission policies are code, so real multi-tenant permissions will likely
  force it.
- **A gitignored `secrets.yml` instead of ansible-vault.** Simpler. Rejected:
  one wrong `git add` leaks plaintext. With the vault, the committed file is
  ciphertext, and only the password file has to stay out of Git.
- **`NODE_TLS_REJECT_UNAUTHORIZED=0`, as backstack did.** It turns off
  certificate checks for every outbound call, GitHub included. Rejected for
  scoped fixes: the cluster CA for the API server, and HTTP for ArgoCD, which
  never leaves the cluster.
- **Copy backstack's values as they are.** Rejected: they include a static API
  token published in the upstream repo, and bind `cluster-admin`.

## Consequences

- The brain comes up with its front door in one command. Rebuilding the cluster
  rebuilds Backstage.
- The catalog lives in memory. A restart empties it, and the ingestor refills
  it from the cluster. The ingestor polls every 600s, so new XRs can take up to
  10 minutes to appear.
- We depend on someone else's image and plugin versions. Changing a plugin
  means building our own image.
- The edit-flow template is loaded at runtime from an upstream repo. Its owner
  can change what our portal does, and it opens PRs with our PAT.
- The generated create and update templates have known limits: no field
  removal, a wrong default folder, no sync-wave, and a wrong `source-file-url`
  with the `custom` layout. Owning our templates is the planned fix (ROADMAP
  Phase 8).
- The ArgoCD admin password in the vault is the one ArgoCD generated. A cluster
  rebuild makes a new one, so the vault value goes stale unless we pin it.
- The OAuth app asks for the `repo` scope. That covers every repo the user can
  reach, not only `platform-gitops`. Fine for one user; a scoped GitHub App is
  the multi-tenant answer.
- `argocd-server` serves plain HTTP. The ArgoCD UI is now `http://` through the
  port-forward.
- Guest sign-in and disabled permissions mean everyone is the same user. Real
  users, tenant ownership and permission rules are on the ROADMAP.
