# =============================================================================
# IDK Digital Solutions — AWS Organization Outputs
# terraform/global/organization/outputs.tf
# =============================================================================
# WHY OUTPUTS MATTER:
#   Outputs serve two purposes:
#   1. They display important values after `terraform apply` so you don't
#      have to hunt through the AWS console
#   2. They are read by OTHER Terraform configurations via remote state
#      data sources — the SCPs and tag-policies layers read OU IDs from here
#      rather than hardcoding them. Loose coupling between configurations.
# =============================================================================

# ── Organization ──────────────────────────────────────────────────────────────
output "organization_id" {
  description = "The ID of the AWS Organization"
  value       = data.aws_organizations_organization.this.id
}

output "organization_root_id" {
  description = "The ID of the organization root — used as parent for top-level OUs"
  value       = data.aws_organizations_organization.this.roots[0].id
}

output "master_account_id" {
  description = "The AWS account ID of the management (master) account"
  value       = data.aws_organizations_organization.this.master_account_id
}

# ── Organizational Unit IDs ───────────────────────────────────────────────────
# Consumed by the scps and tag-policies Terraform layers
output "ou_security_id" {
  description = "OU ID for the Security organizational unit"
  value       = aws_organizations_organizational_unit.security.id
}

output "ou_infrastructure_id" {
  description = "OU ID for the Infrastructure organizational unit"
  value       = aws_organizations_organizational_unit.infrastructure.id
}

output "ou_shared_services_id" {
  description = "OU ID for the Shared Services organizational unit"
  value       = aws_organizations_organizational_unit.shared_services.id
}

output "ou_non_production_id" {
  description = "OU ID for the Non-Production organizational unit"
  value       = aws_organizations_organizational_unit.non_production.id
}

# ── Account IDs ───────────────────────────────────────────────────────────────
output "account_ids" {
  description = "Map of account name to account ID for all member accounts"
  value = {
    log_archive = aws_organizations_account.log_archive.id
    development = aws_organizations_account.development.id
    uat         = aws_organizations_account.uat.id
  }
}

output "development_account_id" {
  description = "Account ID for idk-development — primary AI and FinOps lab account"
  value       = aws_organizations_account.development.id
}
