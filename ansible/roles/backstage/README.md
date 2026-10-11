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
Each live XR (e.g. `dev-vpc-1`) becomes a catalog entry, with its Workspace
(MR) underneath and a link to its ArgoCD app.

It can also turn each XRD into a generated create form. That is **off**
(`xrds.enabled: false`): the generated forms wrote to the wrong folder, had no
sync-wave and a broken `source-file-url`. `ingestAllXRDs` stays on, because it
also tells the ingestor which XR kinds to catalog.

It runs every 600s and once at pod start. The catalog is in memory, so a
restart rebuilds it from the cluster. An initContainer (`wait-for-dns`) holds
the pod until cluster DNS answers, so the first run after a VM reboot doesn't
find an empty cluster.

**Our templates** — in platform-gitops, next to each API:
`definitions/<api>/backstage-template.yaml`. One catalog location with a glob
loads them all; ArgoCD skips them (`exclude` in `bootstrap/definitions.yaml`).
Each file has two documents:

1. `kind: Template` — the create form. Writes `infra-requests/<name>.yaml`
   with the sync-wave and the real `source-file-url`, then opens a PR.
2. `kind: API` — the schema the edit form draws its fields from. The edit form
   looks it up by name (`<kind>-<group>--<version>`). The generator used to
   make it; with generation off, we write it. **It copies the XRD's spec —
   change both together.**

**Updater** (`gitops-manifest-updater` plugin + `gitops-updater-template`) — the
edit flow for an XR that already exists. It shows up in the **Scaffolder Content** tab on an
entity page. The template is loaded from the upstream repo at runtime (a catalog
`location` in the values file); its fields come from our API document.

## Who writes to Git

Backstage never applies anything to the cluster, and never pushes to `main`.
Every change is a **pull request** on `platform-gitops`:

```
form submit ──▶ Backstage opens a PR ──▶ you review + merge ──▶ ArgoCD syncs
            ──▶ Crossplane composes ──▶ provider-opentofu applies to AWS
```

| Step | Who does it | Credential |
|---|---|---|
| Build the claim YAML (create) | our template: `roadiehq:utils:serialize:yaml` + `fs:write` | none |
| Read the existing claim file (edit) | your browser, as you | your GitHub login (OAuth app) |
| Create branch + open the PR (create and edit) | scaffolder action `publish:github:pull-request` | the vault PAT (`GITHUB_TOKEN`) |
| Merge | you | — |
| Apply to the cluster | ArgoCD | — |

## Gotchas

- **No XEKSCluster form or API document yet.** Only `definitions/network/`
  has a `backstage-template.yaml`. Request an EKS cluster by writing the claim
  in Git; editing one from Backstage fails with "No matching API entity found".
- **"No matching API entity found" on edit** means the API document for that
  kind is missing, misnamed, or not allowed by the location's
  `rules: allow: [Template, API]`.
- **The edit form doesn't validate.** It draws fields with its own renderer and
  ignores `minimum`, `enum` and `pattern`. `azCount: -5` went through and only
  failed at ArgoCD sync (rejected by the XRD). Some bad values pass the XRD
  too and fail later inside the Workspace (`cidr: 172.16.0.0/12` — AWS allows
  /16 to /28). Review the PR diff. The create form does validate.
- **Clearing a field in the edit form writes `""`, not "remove".** An integer
  field then fails the XRD (`must be of type integer`), and a string field
  stops falling back to the preset. Remove fields in Git directly.
- **One open edit PR per claim.** The upstream template always uses the branch
  `backstage-sourced-update-<path>`. While a PR from that branch is open, a new
  edit fails with "Pull request already exists". Close it and delete the
  branch first.
- **Edit flow needs the `terasky.backstage.io/source-file-url` annotation** on
  the claim, pointing at its file in Git. Without it, step 2 of the edit form
  is blank. Claims made by our create form get it; hand-written ones need it
  added.
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
