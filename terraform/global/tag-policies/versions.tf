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

  backend "s3" {
    bucket         = "idk-tfstate-management-634222035434"
    key            = "global/tag-policies/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "idk-terraform-lock"
    encrypt        = true
    profile        = "idk-management"
  }
}
