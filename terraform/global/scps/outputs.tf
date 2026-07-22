# =============================================================================
# IDK Digital Solutions — SCP Outputs
# terraform/global/scps/outputs.tf
# =============================================================================

output "scp_ids" {
  description = "Map of SCP name to policy ID"
  value = {
    deny_non_mumbai_regions        = aws_organizations_policy.deny_non_mumbai_regions.id
    deny_root_actions              = aws_organizations_policy.deny_root_actions.id
    protect_security_services      = aws_organizations_policy.protect_security_services.id
    non_production_cost_guardrails = aws_organizations_policy.non_production_cost_guardrails.id
  }
}

output "scp_summary" {
  description = "Human-readable summary of SCPs and their target OUs"
  value = {
    "idk-deny-non-mumbai-regions"        = "Attached to: Security, SharedServices, NonProduction"
    "idk-deny-root-account-actions"      = "Attached to: Security, SharedServices, NonProduction"
    "idk-protect-security-services"      = "Attached to: Security, SharedServices, NonProduction"
    "idk-non-production-cost-guardrails" = "Attached to: NonProduction only"
  }
}
