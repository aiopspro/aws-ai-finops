# =============================================================================
# IDK Digital Solutions — AWS Organization Outputs
# terraform/global/organization/outputs.tf
# =============================================================================
# WHY OUTPUTS MATTER:
#   Outputs serve two purposes:
#   1. They display important values after `terraform apply` so you don't
#      have to hunt through the AWS console
#   2. They can be read by OTHER Terraform configurations via remote state
#      data sources — enabling loose coupling between configurations
#
#   Example: The SCP configuration will read the OU IDs from this output
#   rather than hardcoding them. This means if OU names change, only
#   this file needs updating.
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
# These are consumed by the SCPs and tag policies Terraform configurations
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

output "ou_production_id" {
  description = "OU ID for the Production organizational unit"
  value       = aws_organizations_organizational_unit.production.id
}

output "ou_non_production_id" {
  description = "OU ID for the Non-Production organizational unit"
  value       = aws_organizations_organizational_unit.non_production.id
}

output "ou_sandbox_id" {
  description = "OU ID for the Sandbox organizational unit"
  value       = aws_organizations_organizational_unit.sandbox.id
}

output "ou_suspended_id" {
  description = "OU ID for the Suspended organizational unit"
  value       = aws_organizations_organizational_unit.suspended.id
}

# ── Account IDs ───────────────────────────────────────────────────────────────
output "account_ids" {
  description = "Map of account name to account ID for all member accounts"
  value = {
    log_archive     = aws_organizations_account.log_archive.id
    security        = aws_organizations_account.security.id
    network         = aws_organizations_account.network.id
    shared_services = aws_organizations_account.shared_services.id
    production      = aws_organizations_account.production.id
    development     = aws_organizations_account.development.id
    uat             = aws_organizations_account.uat.id
    ai_lab          = aws_organizations_account.ai_lab.id
    finops_lab      = aws_organizations_account.finops_lab.id
  }
}

output "ai_lab_account_id" {
  description = "Account ID for idk-ai-lab — the primary compute account in Phase 1"
  value       = aws_organizations_account.ai_lab.id
}
