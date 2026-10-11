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

**Our templates** — all in platform-gitops, all named `backstage-template.yaml`.
One catalog location with a glob (`definitions/*/backstage-template.yaml`)
loads them; ArgoCD skips them (`exclude` in `bootstrap/definitions.yaml`).

- `definitions/<api>/backstage-template.yaml` — one per API, two documents:
  1. `kind: Template` — the **create** form. Writes `infra-requests/<name>.yaml`
     with the sync-wave and the real `source-file-url`, then opens a PR.
  2. `kind: API` — the schema the **edit** form draws its fields from. The edit
     form looks it up by name (`<kind>-<group>--<version>`). The generator used
     to make it; with generation off, we write it. **It copies the XRD's spec —
     change both together.**
- `definitions/_shared/backstage-template.yaml` — `update-claim`, the **edit**
  flow for every kind. It shows up in an entity's **Scaffolder Content** tab
  (label `target: component`). Based on the upstream `gitops-updater-template`,
  with three changes: it **replaces** `spec` instead of deep-merging it (so
  removed fields really go away), drops `""` and empty objects, and uses a
  unique branch per run (`backstage-update-<path>-<millis>`).

**Updater field** (`gitops-manifest-updater` plugin) — the form widget on step 2
of `update-claim`. It reads the claim file from Git as you, finds the API
document, and draws the fields pre-filled.

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
| Read the existing claim file (edit form) | your browser, as you | your GitHub login (OAuth app) |
| Replace `spec` in the claim file (edit) | `update-claim`: `fetch:plain:file` + `roadiehq:utils:jsonata:yaml:transform` + `fs:write` | the vault PAT, to download the file (Backstage's GitHub integration) |
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
- **The edit form writes `""` for a cleared field.** `update-claim` drops
  those, so clearing a field removes it from the claim. (The upstream template
  wrote the `""` into the file, and the sync failed.)
- **Edit replaces the whole `spec`.** Anything the form doesn't show is dropped.
  The form shows every field in our API document, so keep that document in
  step with the XRD. YAML comments in the claim file are lost too (the file is
  parsed and written back).
- **Some removals are refused on purpose.** Removing or changing `cidr`,
  changing `mode`, or lowering `azCount` makes a PR that ArgoCD can't sync. The
  XRD's CEL rules reject it (platform-gitops ADR 0008).
- **Every edit opens a new PR**, even with no changes (an empty diff). Close
  empty ones.
- **Edit flow needs the `terasky.backstage.io/source-file-url` annotation** on
  the claim, pointing at its file in Git. Without it, step 2 of the edit form
  is blank, and `update-claim` fails with "no source-file-url annotation".
  Claims made by our create form get it; hand-written ones need it added.
- **Edit flow needs GitHub login.** Step 2 opens a GitHub popup. That is the
  OAuth app (`auth.providers.github`), not the PAT.
- **Changes show up slowly.** New XRs, new XRDs and annotation changes can
  take up to 10 minutes (the 600s poll). Restart the pod to refresh now.
- **Sign-in is guest only.** Everyone is the same user and permissions are
  off. Real users, tenant ownership and permission rules are on the ROADMAP
  (Phase 8).
