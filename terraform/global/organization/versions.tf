# =============================================================================
# IDK Digital Solutions — AWS Organization
# terraform/global/organization/versions.tf
# =============================================================================
# WHY THIS FILE:
#   Pinning provider and Terraform versions is mandatory in enterprise IaC.
#   Without version pins, a `terraform init` six months from now might pull
#   a breaking provider version and silently destroy your plan output or
#   worse, apply incorrectly. Version constraints are your reproducibility
#   guarantee.
#
# ENTERPRISE PRACTICE:
#   Pin to a minor version (e.g., ~> 5.0) not an exact patch version.
#   This allows security patches within the minor version while preventing
#   major breaking changes. Update minor versions deliberately after testing.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state backend — created by bootstrap.sh
  # WHY S3 + DynamoDB:
  #   S3 stores the state file (infrastructure reality snapshot).
  #   DynamoDB provides distributed locking (prevents concurrent writes).
  #   This is the AWS-native, lowest-cost remote state solution.
  #   Alternative: Terraform Cloud — more features but adds cost and vendor lock-in.
  backend "s3" {
    bucket         = "idk-tfstate-management-634222035434"
    key            = "global/organization/terraform.tfstate"
    region         = "ap-south-1"
    use_lockfile = true
    encrypt      = true
    profile        = "idk-management"
  }
}
