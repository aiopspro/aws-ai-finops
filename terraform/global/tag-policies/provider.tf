# =============================================================================
# IDK Digital Solutions — Tag Policies
# terraform/global/tag-policies/provider.tf
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

data "terraform_remote_state" "organization" {
  backend = "s3"
  config = {
    bucket  = "idk-tfstate-management-${var.management_account_id}"
    key     = "global/organization/terraform.tfstate"
    region  = var.aws_region
    profile = var.aws_profile
  }
}

locals {
  org_root_id = data.terraform_remote_state.organization.outputs.organization_root_id
}
