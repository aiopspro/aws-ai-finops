# =============================================================================
# IDK Digital Solutions — SCPs Variables
# terraform/global/scps/variables.tf
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS credentials profile to use"
  type        = string
  default     = "idk-management"
}

variable "management_account_id" {
  description = "12-digit AWS management account ID"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit number."
  }
}
