# =============================================================================
# IDK Digital Solutions — Tag Policies
# terraform/global/tag-policies/versions.tf
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state backend — bucket/region/profile supplied via backend.hcl
  # Run: terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "global/tag-policies/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
