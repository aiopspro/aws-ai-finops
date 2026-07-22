# =============================================================================
# IDK Digital Solutions — SCP Provider & Remote State
# terraform/global/scps/provider.tf
# =============================================================================

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      ManagedBy    = "terraform"
      Project      = "landing-zone"
      Environment  = "management"
      BusinessUnit = "Technology"
      Department   = "Platform Engineering"
      CostCenter   = "CC1001"
      Owner        = "platform-team"
    }
  }
}

# ── Read OU IDs from organization layer ───────────────────────────────────────
# WHY REMOTE STATE DATA SOURCE:
#   SCPs need OU IDs to know where to attach. Instead of hardcoding those IDs
#   (which could change if OUs are recreated) or duplicating the organization
#   resources, we read the outputs from the organization layer's state file.
#   This is the standard pattern for cross-configuration dependencies in
#   enterprise Terraform setups.
data "terraform_remote_state" "organization" {
  backend = "s3"
  config = {
    bucket  = "idk-tfstate-management-${var.management_account_id}"
    key     = "global/organization/terraform.tfstate"
    region  = var.aws_region
    profile = var.aws_profile
  }
}

# ── Local aliases for cleaner references ──────────────────────────────────────
locals {
  ou_security_id    = data.terraform_remote_state.organization.outputs.ou_security_id
  ou_shared_id      = data.terraform_remote_state.organization.outputs.ou_shared_services_id
  ou_nonprod_id     = data.terraform_remote_state.organization.outputs.ou_non_production_id
  master_account_id = data.terraform_remote_state.organization.outputs.master_account_id
}
