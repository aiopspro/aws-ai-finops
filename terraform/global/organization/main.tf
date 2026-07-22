# =============================================================================
# IDK Digital Solutions — AWS Organization & OU Structure
# terraform/global/organization/main.tf
# =============================================================================
# WHAT THIS FILE DOES:
#   1. Reads the existing AWS Organization (created by bootstrap)
#   2. Manages 4 Organizational Units aligned to lab goals
#   3. Manages 4 member accounts
#
# LAB GOAL ALIGNMENT:
#   This is a hands-on enterprise architecture lab focused on:
#     - AI Platform engineering (agentic workloads, Bedrock, SageMaker)
#     - FinOps (cost visibility, tagging enforcement, budget alerts)
#     - Enterprise governance (SCPs, Tag Policies, IAM Identity Center)
#
#   The OU structure below mirrors real enterprise landing zones at a scale
#   appropriate for a single-person lab — same patterns, fewer accounts.
#
# OU STRUCTURE:
#   Root
#   ├── Security          → Log Archive (immutable logs, GuardDuty, SecurityHub)
#   ├── Infrastructure    → Reserved for networking practice (empty for now)
#   ├── SharedServices    → IAM Identity Center, shared tooling
#   └── NonProduction     → Development (primary AI/FinOps lab) + UAT
#
# WHY IMPORT INSTEAD OF CREATE:
#   Bootstrap already created the Organization. OUs and accounts were created
#   in earlier applies. All resources are imported into state, not created fresh.
#   This is the standard pattern for brownfield Terraform adoption.
#
# ACCOUNT CREATION NOTES:
#   - Each aws_organizations_account requires a UNIQUE email address
#   - You cannot delete accounts immediately — 90-day AWS waiting period
#   - lifecycle ignore_changes on email: AWS doesn't allow email updates via API
# =============================================================================

# ── Data: Fetch the existing Organization root ────────────────────────────────
data "aws_organizations_organization" "this" {}

# ── Local values ──────────────────────────────────────────────────────────────
locals {
  root_id = data.aws_organizations_organization.this.roots[0].id
  prefix  = "idk"
}

# =============================================================================
# ORGANIZATIONAL UNITS
# =============================================================================
# These 4 OUs represent the core governance boundaries for the lab.
# SCPs will be attached to each OU in the scps layer (Phase 2).
#
# ENTERPRISE PATTERN: OUs = security/governance boundaries, not team boundaries.
# The same account can serve multiple purposes — in a lab, idk-development
# hosts both AI experimentation and FinOps practice workloads.
# =============================================================================

# ── Security OU ───────────────────────────────────────────────────────────────
# LAB PURPOSE: Practice immutable logging, GuardDuty, SecurityHub delegation.
# SCP intent: Deny everything except security tooling reads/writes.
# ENTERPRISE INSIGHT: The security OU is the most restricted in the org —
#   even admins should not be able to modify logs or disable detectives.
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = local.root_id

  tags = {
    Description = "Security tooling and immutable log archive accounts"
    Criticality = "critical"
  }
}

# ── Infrastructure OU ─────────────────────────────────────────────────────────
# LAB PURPOSE: Reserved for future networking practice (Transit Gateway,
#   Route 53 Resolver, VPC sharing). Empty for now — kept to mirror
#   real enterprise landing zones where networking is always isolated.
# ENTERPRISE INSIGHT: Centralised networking is a key enterprise pattern.
#   Keeping this OU even when empty trains the habit of separation.
resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = local.root_id

  tags = {
    Description = "Core networking and infrastructure accounts (future use)"
    Criticality = "critical"
  }
}

# ── Shared Services OU ────────────────────────────────────────────────────────
# LAB PURPOSE: Practice IAM Identity Center (SSO), centralised tooling.
#   This is where you will configure federated access across all accounts —
#   a critical enterprise and AI platform skill.
# SCP intent: Moderate. Services here are consumed org-wide.
resource "aws_organizations_organizational_unit" "shared_services" {
  name      = "SharedServices"
  parent_id = local.root_id

  tags = {
    Description = "IAM Identity Center and shared platform services"
    Criticality = "high"
  }
}

# ── Non-Production OU ─────────────────────────────────────────────────────────
# LAB PURPOSE: Your primary hands-on lab environment.
#   idk-development = main AI + FinOps experimentation account
#   idk-uat         = practice deploying to a separate environment,
#                     simulating a real promotion pipeline
# SCP intent: Moderate controls — region restriction, no runaway costs.
resource "aws_organizations_organizational_unit" "non_production" {
  name      = "NonProduction"
  parent_id = local.root_id

  tags = {
    Description = "Primary lab accounts for AI and FinOps practice"
    Criticality = "medium"
  }
}

# =============================================================================
# MEMBER ACCOUNTS
# =============================================================================
# 4 accounts aligned to lab goals. All were created in earlier Terraform runs
# or manually — imported into state rather than created fresh.
#
# COST NOTE: Empty accounts cost nothing. You only pay for resources created
# inside them. All 4 accounts together cost ~$0/month when idle.
# =============================================================================

# ── Log Archive Account ───────────────────────────────────────────────────────
# LAB PURPOSE: Centralised, immutable log storage.
#   Practice: CloudTrail org trail, S3 Object Lock, S3 lifecycle policies,
#   GuardDuty findings export, SecurityHub aggregation.
# ENTERPRISE INSIGHT: Log archive is always a separate account so that even
#   compromised workload accounts cannot tamper with audit trails.
resource "aws_organizations_account" "log_archive" {
  name                       = "idk-log-archive"
  email                      = "idkwealthclub+idk-log-archive@gmail.com"
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.security.id

  tags = {
    AccountPurpose     = "Immutable centralised log storage and security tooling"
    DataClassification = "confidential"
    Compliance         = "none"
    Backup             = "required"
    Criticality        = "critical"
  }

  lifecycle {
    ignore_changes = [email]
  }
}

# ── Shared Services Account ───────────────────────────────────────────────────
# LAB PURPOSE: IAM Identity Center (SSO) home account.
#   Practice: Configure permission sets, assign users to accounts,
#   set up federated access — eliminates need for IAM users in each account.
# ENTERPRISE INSIGHT: SSO via Identity Center is the enterprise standard.
#   No one should be logging in with long-lived IAM user keys in production.
resource "aws_organizations_account" "shared_services" {
  name                       = "idk-shared-svc"
  email                      = "idkwealthclub+idk-shared-services@gmail.com"
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.shared_services.id

  tags = {
    AccountPurpose     = "IAM Identity Center and shared platform tooling"
    DataClassification = "internal"
    Compliance         = "none"
    Backup             = "not-required"
    Criticality        = "high"
  }

  lifecycle {
    ignore_changes = [email]
  }
}

# ── Development Account ───────────────────────────────────────────────────────
# LAB PURPOSE: Primary hands-on AI + FinOps lab account.
#   AI practice:    Amazon Bedrock, SageMaker, Lambda AI agents, Step Functions
#   FinOps practice: Cost Explorer, Budgets, Cost Anomaly Detection,
#                    resource tagging compliance, Compute Optimizer
# ENTERPRISE INSIGHT: In a real enterprise, AI workloads get their own account
#   for blast radius control. In this lab, development doubles as the AI sandbox
#   — same governance patterns, consolidated for cost efficiency.
resource "aws_organizations_account" "development" {
  name                       = "idk-development"
  email                      = "idkwealthclub+idk-development@gmail.com"
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.non_production.id

  tags = {
    AccountPurpose     = "Primary AI platform and FinOps lab experimentation"
    DataClassification = "internal"
    Compliance         = "none"
    Backup             = "not-required"
    Criticality        = "low"
  }

  lifecycle {
    ignore_changes = [email]
  }
}

# ── UAT Account ───────────────────────────────────────────────────────────────
# LAB PURPOSE: Simulate a promotion pipeline — deploy to dev, promote to UAT.
#   Practice: Cross-account IAM roles, CodePipeline cross-account deployments,
#   environment parity validation, pre-production cost estimation.
# ENTERPRISE INSIGHT: Having a separate UAT account enforces the discipline
#   of treating environments as cattle — identical config, different data.
resource "aws_organizations_account" "uat" {
  name                       = "idk-uat"
  email                      = "idkwealthclub+idk-uat@gmail.com"
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.non_production.id

  tags = {
    AccountPurpose     = "Pre-production validation and promotion pipeline practice"
    DataClassification = "internal"
    Compliance         = "none"
    Backup             = "not-required"
    Criticality        = "medium"
  }

  lifecycle {
    ignore_changes = [email]
  }
}
