# =============================================================================
# IDK Digital Solutions — SCP Outputs
# terraform/global/scps/outputs.tf
# =============================================================================

output "scp_ids" {
  description = "Map of SCP name to policy ID"
  value = {
    deny_non_mumbai_regions   = aws_organizations_policy.deny_non_mumbai_regions.id
    deny_root_actions         = aws_organizations_policy.deny_root_actions.id
    protect_security_services = aws_organizations_policy.protect_security_services.id
    sandbox_cost_guardrails   = aws_organizations_policy.sandbox_cost_guardrails.id
    deny_all_suspended        = aws_organizations_policy.deny_all_suspended.id
  }
}

output "scp_summary" {
  description = "Human-readable summary of SCPs and their target OUs"
  value = {
    "idk-deny-non-mumbai-regions"   = "Attached to: Security, Infrastructure, SharedServices, Production, NonProduction, Sandbox"
    "idk-deny-root-account-actions" = "Attached to: Security, Infrastructure, SharedServices, Production, NonProduction, Sandbox"
    "idk-protect-security-services" = "Attached to: Security, Infrastructure, SharedServices, Production, NonProduction, Sandbox"
    "idk-sandbox-cost-guardrails"   = "Attached to: Sandbox only"
    "idk-deny-all-suspended"        = "Attached to: Suspended only"
  }
}
