# =============================================================================
# IDK Digital Solutions — Tag Policies
# terraform/global/tag-policies/provider.tf
# =============================================================================

provider "aws" {
  region  = "ap-south-1"
  profile = "idk-management"

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
    bucket  = "idk-tfstate-management-634222035434"
    key     = "global/organization/terraform.tfstate"
    region  = "ap-south-1"
    profile = "idk-management"
  }
}

locals {
  org_root_id = data.terraform_remote_state.organization.outputs.organization_root_id
}
