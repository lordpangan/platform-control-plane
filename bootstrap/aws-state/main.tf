provider "aws" {
  region  = var.region
  profile = var.profile

  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = coalesce(
    var.state_bucket_name,
    "platform-eng-tfstate-${data.aws_caller_identity.current.account_id}",
  )
}

# ---------------------------------------------------------------------------
# Remote state backend.
# An S3 bucket (versioned + encrypted, no public access) holds Terraform state;
# a DynamoDB table provides locking. Every provider-terraform Workspace points
# its S3 backend here, each under its own key (network/, eks/, ...), so the two
# layers never share a lock.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name

  # No force_destroy: the state bucket is deliberately hard to delete by accident.
  # Full teardown empties it by hand first (see README).
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # keep history so a bad apply can be rolled back
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3: encrypted at rest, no KMS key to manage
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST" # pennies; only charged per lock op
  hash_key     = "LockID"          # the fixed key name Terraform's S3 backend expects

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ---------------------------------------------------------------------------
# The identity provider-terraform uses.
# kind-on-a-VM can't use IRSA, so Crossplane authenticates with a static access
# key (stored later in a Kubernetes Secret). The policy is SERVICE-SCOPED —
# limited to the services this provisioner needs (VPC/EKS + supporting IAM +
# this state backend), NOT AdministratorAccess. It can be tightened to
# action/resource level later (tracked for Phase 3).
# ---------------------------------------------------------------------------

resource "aws_iam_user" "crossplane" {
  name = var.crossplane_user_name
}

resource "aws_iam_policy" "crossplane" {
  name        = "${var.crossplane_user_name}-provisioner"
  description = "Scoped permissions for provider-terraform: provision VPC + EKS and use the S3/DynamoDB state backend."
  policy      = data.aws_iam_policy_document.crossplane.json
}

resource "aws_iam_user_policy_attachment" "crossplane" {
  user       = aws_iam_user.crossplane.name
  policy_arn = aws_iam_policy.crossplane.arn
}

resource "aws_iam_access_key" "crossplane" {
  user = aws_iam_user.crossplane.name
}

data "aws_iam_policy_document" "crossplane" {
  # --- Remote state backend: tightly scoped to OUR bucket + table ---
  statement {
    sid       = "TerraformStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "TerraformStateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.locks.arn]
  }

  # --- Provisioning surface: service-scoped to what VPC + EKS need. Resource-level
  #     scoping of ec2/eks is impractical (resources don't exist until apply), so we
  #     scope by service instead of granting AdministratorAccess. ---
  statement {
    sid       = "NetworkAndCompute"
    effect    = "Allow"
    actions   = ["ec2:*", "eks:*", "autoscaling:*", "kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "ControlPlaneLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
      "logs:ListTagsForResource", "logs:PutRetentionPolicy",
      "logs:TagResource", "logs:UntagResource",
    ]
    resources = ["*"]
  }

  # --- IAM: the EKS module creates cluster/node roles, instance profiles, and the
  #     OIDC provider. Scoped to the IAM actions those need (not iam:*). ---
  statement {
    sid    = "IamForEks"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:ListRoles",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
      "iam:TagRole", "iam:UntagRole", "iam:PassRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
      "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
      "iam:TagPolicy", "iam:UntagPolicy",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
      "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider", "iam:TagOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
  }
}
