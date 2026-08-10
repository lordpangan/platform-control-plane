terraform {
  # This bootstrap intentionally uses LOCAL state — it is the root of trust that
  # creates the remote backend everything else uses. Its state file is gitignored.
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
