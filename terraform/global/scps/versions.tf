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

  # Reads OU IDs from the organization layer's remote state
  # WHY: Avoids hardcoding OU IDs. If the org layer recreates an OU,
  #      the SCP layer automatically picks up the new ID on next apply.
  backend "s3" {
    bucket         = "idk-tfstate-management-634222035434"
    key            = "global/scps/terraform.tfstate"
    region         = "ap-south-1"
    use_lockfile = true
    encrypt      = true
    profile        = "idk-management"
  }
}
