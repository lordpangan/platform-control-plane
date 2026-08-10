# Bootstrap — AWS Terraform state backend + Crossplane identity

A **one-time** step that creates the things Phase 2 can't create itself:

- an **S3 bucket** (versioned, encrypted, no public access) for Terraform remote state,
- a **DynamoDB table** for state locking,
- a scoped **IAM user** (`crossplane-terraform`) + policy that `provider-terraform`
  authenticates as, and its **access key**.

## Why this exists (the chicken-and-egg)

Terraform can't use a remote backend to *create* that backend, so this module runs
with **local state** — which is why its state file is gitignored. It's the root of
trust: run it once with your admin identity, and everything downstream uses the
remote backend and the scoped IAM user it produces.

## Prerequisites

- `terraform` and the `aws` CLI v2 installed.
- The `platform-engineer-admin` SSO profile working:
  ```sh
  aws sso login --profile platform-engineer-admin
  aws sts get-caller-identity --profile platform-engineer-admin   # should print your account
  ```

## Run it

From the repo root:

```sh
make bootstrap-aws
```

or directly:

```sh
cd bootstrap/aws-state
terraform init
terraform apply
```

## After it applies

Grab the outputs (the secret is marked sensitive):

```sh
terraform output state_bucket_name
terraform output crossplane_access_key_id
terraform output -raw crossplane_secret_access_key
```

The access key id + secret go into the Kubernetes Secret in **Step 2** (creating
`provider-terraform`'s `ProviderConfig`). Never commit them.

## Notes / decisions

- **DynamoDB locking, not S3 native lockfile.** Terraform 1.10+ can lock via an S3
  lockfile (`use_lockfile`) without DynamoDB, but `provider-terraform` bundles its
  own (often older) Terraform to run the Workspaces, so the widely-compatible
  DynamoDB lock is the safe choice here.
- **Service-scoped IAM, not admin.** The policy is limited to the services this
  provisioner touches (`ec2`, `eks`, `autoscaling`, `kms`, scoped `iam`, plus this
  bucket/table). It is *not* `AdministratorAccess`. Resource-level scoping of
  ec2/eks is impractical (the resources don't exist until apply), so we scope by
  service; tightening further is tracked for Phase 3.
- **State bucket has no `force_destroy`.** It won't delete while it holds state —
  deliberate, so you can't wipe your state by accident.

## Teardown (rare)

Only when you want to remove the backend entirely (all real infra must be destroyed
first). The versioned bucket must be emptied by hand before destroy:

```sh
aws s3 rm "s3://$(terraform output -raw state_bucket_name)" --recursive --profile platform-engineer-admin
# then remove old versions in the console or via the CLI, and:
make teardown-aws-state
```
