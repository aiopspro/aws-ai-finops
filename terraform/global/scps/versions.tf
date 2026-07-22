# =============================================================================
# IDK Digital Solutions — Service Control Policies (Phase 1)
# terraform/global/scps/versions.tf
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
    key          = "global/scps/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
