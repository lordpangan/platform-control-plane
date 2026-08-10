output "region" {
  description = "Region the state backend lives in."
  value       = var.region
}

output "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state."
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "DynamoDB table used for state locking."
  value       = aws_dynamodb_table.locks.name
}

output "crossplane_access_key_id" {
  description = "Access key ID for the provider-terraform IAM user."
  value       = aws_iam_access_key.crossplane.id
}

output "crossplane_secret_access_key" {
  description = "Secret key for the provider-terraform IAM user. Read it with: terraform output -raw crossplane_secret_access_key"
  value       = aws_iam_access_key.crossplane.secret
  sensitive   = true
}

output "backend_config_hint" {
  description = "Backend block for provider-terraform Workspaces — set a unique key per layer."
  value       = <<-EOT
    backend "s3" {
      bucket         = "${aws_s3_bucket.state.id}"
      key            = "<layer>/terraform.tfstate"   # e.g. network/ or eks/
      region         = "${var.region}"
      dynamodb_table = "${aws_dynamodb_table.locks.name}"
      encrypt        = true
    }
  EOT
}
