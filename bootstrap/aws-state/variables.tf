variable "region" {
  description = "AWS region for the state bucket and lock table."
  type        = string
  default     = "ap-southeast-1"
}

variable "profile" {
  description = "AWS CLI profile (SSO) used to run this bootstrap with admin rights."
  type        = string
  default     = "platform-engineer-admin"
}

variable "state_bucket_name" {
  description = "S3 bucket for Terraform remote state. Empty = derive as platform-eng-tfstate-<account_id> (S3 names are global, so the account id keeps it unique)."
  type        = string
  default     = ""
}

variable "lock_table_name" {
  description = "DynamoDB table for Terraform state locking."
  type        = string
  default     = "platform-eng-tf-locks"
}

variable "crossplane_user_name" {
  description = "IAM user provider-terraform authenticates as (kind-on-VM can't use IRSA, so it needs a static key)."
  type        = string
  default     = "crossplane-terraform"
}

variable "tags" {
  description = "Tags applied to every bootstrap resource (cost tracking)."
  type        = map(string)
  default = {
    project    = "platform-engineering"
    managed-by = "terraform-bootstrap"
    layer      = "state-backend"
  }
}
