# =============================================================================
# IDK Digital Solutions — Tag Policy Outputs
# terraform/global/tag-policies/outputs.tf
# =============================================================================
# These outputs allow future configurations (e.g., a compliance reporting layer)
# to reference the tag policy ID without hardcoding it.
# =============================================================================

output "tag_policy_id" {
  description = "The ID of the enterprise tag policy"
  value       = aws_organizations_policy.idk_tag_policy.id
}

output "tag_policy_arn" {
  description = "The ARN of the enterprise tag policy"
  value       = aws_organizations_policy.idk_tag_policy.arn
}

output "tag_policy_attachment_id" {
  description = "The ID of the root-level tag policy attachment"
  value       = aws_organizations_policy_attachment.tag_policy_root.id
}
