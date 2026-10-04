# backstage role

Installs Backstage on the brain cluster as the front door for the infra API
(ADR 0002). It uses the backstack image (`ghcr.io/vrabbi/backstack-demo`),
which has the TeraSky plugins baked in.

Open it with `make backstage-ui-vm`, then go to http://localhost:7007.

## What the role creates

| Object | Purpose |
|---|---|
| `backstage` namespace | Created first; RBAC and secrets go in before Helm runs. |
| ServiceAccount `backstage` + `backstage-read` ClusterRole | Read-only access to XRDs, XRs, Workspaces and workloads. No Secrets. |
| Secret `backstage-secrets` | From the vault: `GITHUB_TOKEN` (PAT), `ARGOCD_PASSWORD`, `AUTH_GITHUB_CLIENT_ID/SECRET` (OAuth app). |
| Helm release `backstage` | The pod. Config is in `templates/backstage-values.yaml.j2`. |

Secrets stay as `${VAR}` in the values file. Backstage fills them in at
runtime from env vars, so they never land in the rendered file or ConfigMap.

## Plugins

**Ingestor** (`kubernetesIngestor`) — reads the cluster and fills the catalog.
It has two jobs:

1. **XRD → form.** Each XRD (`XNetwork`, `XEKSCluster`) becomes a Software
   Template on the Create page. The form fields come from the XRD schema.
   Add an XRD and a new form appears. Nobody writes the forms by hand.
2. **XR → catalog entry.** Each live XR (e.g. `dev-vpc-1`) becomes a catalog
   entry, with its Workspace (MR) underneath and a link to its ArgoCD app.

It runs every 600s and once at pod start. The catalog is in memory, so a
restart rebuilds it from the cluster.

**Updater** (`gitops-manifest-updater` plugin + `gitops-updater-template`) — the
edit flow for an XR that already exists. It shows up in the **Scaffolder Content** tab on an
entity page. It is loaded from the upstream repo at runtime (a catalog
`location` in the values file).

## Who writes to Git

Backstage never applies anything to the cluster, and never pushes to `main`.
Every change is a **pull request** on `platform-gitops`:

```
form submit ──▶ Backstage opens a PR ──▶ you review + merge ──▶ ArgoCD syncs
            ──▶ Crossplane composes ──▶ provider-opentofu applies to AWS
```

| Step | Who does it | Credential |
|---|---|---|
| Build the claim YAML (create) | scaffolder action `terasky:claim-template` | none |
| Read the existing claim file (edit) | your browser, as you | your GitHub login (OAuth app) |
| Create branch + open the PR (create and edit) | scaffolder action `publish:github:pull-request` | the vault PAT (`GITHUB_TOKEN`) |
| Merge | you | — |
| Apply to the cluster | ArgoCD | — |

## Gotchas

- **Create form: pick the manifest layout `custom` with base path
  `infra-requests`.** The default (`cluster-scoped`) writes the file under a
  folder named after the cluster at the repo root. ArgoCD only watches
  `infra-requests/`, so it would never apply it. `custom` writes
  `infra-requests/<name>.yaml`.
- **After a `custom` create, fix two things in the PR before merging:**
  the `source-file-url` annotation points at a scratch `temp/...` path
  (plugin bug — change it to the real `infra-requests/<name>.yaml` URL, or
  the edit flow can't find the file), and there is no
  `argocd.argoproj.io/sync-wave` (add it: XNetwork `"1"`, XEKSCluster `"2"`).
- **The form doesn't enforce required XRD fields.** A missing `mode`
  submits fine and only fails at ArgoCD sync (`spec.mode: Required value`).
  Check the spec in the PR.
- **Edit flow needs the `terasky.backstage.io/source-file-url` annotation** on
  the claim, pointing at its file in Git. Without it, step 2 of the edit form
  is blank. Claims made by the create form get it automatically; hand-written
  ones need it added.
- **Edit flow can add and change fields, but not remove them.** The upstream
  updater template deep-merges the form into the existing file
  (`roadiehq:utils:merge`). A key you delete in the form is just missing, so
  the merge keeps the old value and the PR comes out empty. This hits any
  removal: a tag, or an optional field like `cidr`. Remove things by editing
  the claim in Git directly. Real fix: own a copy of the template and replace
  `spec` instead of merging (note: that also drops any field the form doesn't
  show). The template also opens a PR when nothing changed — check the diff
  before merging.
- **Edit flow needs GitHub login.** Step 2 opens a GitHub popup. That is the
  OAuth app (`auth.providers.github`), not the PAT.
- **Changes show up slowly.** New XRs, new XRDs and annotation changes can
  take up to 10 minutes (the 600s poll). Restart the pod to refresh now.
- **Sign-in is guest only.** Everyone is the same user and permissions are
  off. Real users, tenant ownership and permission rules are on the ROADMAP
  (Phase 8).
