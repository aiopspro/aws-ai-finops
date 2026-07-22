# =============================================================================
# IDK Digital Solutions — AWS Organization
# terraform/global/organization/provider.tf
# =============================================================================
# WHY A SEPARATE PROVIDER FILE:
#   Separating provider configuration from resource definitions makes it
#   easy to see at a glance which AWS account and region a configuration
#   targets. In multi-account setups, you'll have multiple provider blocks
#   with aliases — keeping them isolated reduces confusion.
#
# ENTERPRISE PRACTICE:
#   Never hardcode access keys in provider blocks. Always use profiles,
#   IAM roles, or environment variables. Hardcoded keys in code = a security
#   incident waiting to happen, especially if code goes to GitHub.
# =============================================================================

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # Default tags applied to ALL resources created by this provider block.
  # WHY: Ensures no resource is ever created without the minimum required tags,
  # even if the resource block forgets to specify them explicitly.
  # This is a Terraform 0.13+ feature and is the enterprise standard approach.
  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Project     = "landing-zone"
      Environment = "management"
      BusinessUnit = "Technology"
      Department  = "Platform Engineering"
      CostCenter  = "CC1001"
      Owner       = "platform-team"
    }
  }
}
