# =============================================================================
# IDK Digital Solutions — AWS Organization & OU Structure
# terraform/global/organization/main.tf
# =============================================================================
# WHAT THIS FILE DOES:
#   1. Imports the existing AWS Organization (created by bootstrap.sh)
#   2. Creates all Organizational Units (OUs) in the correct hierarchy
#   3. Creates all 9 member accounts
#   4. Associates accounts with their OUs
#
# WHY IMPORT INSTEAD OF CREATE:
#   bootstrap.sh already created the Organization to enable policy types.
#   Terraform can't create what already exists — we import it instead.
#   This is a common pattern: shell scripts for one-time bootstrap operations,
#   Terraform for ongoing state management.
#
# ACCOUNT CREATION NOTES:
#   - Each aws_organizations_account requires a UNIQUE email address
#   - AWS sends a verification email to each address
#   - Account creation is eventually consistent — it may take 2–5 minutes
#   - You cannot delete accounts immediately; there's a 90-day waiting period
#   - Each account starts with a root user (the email address) — we will
#     disable root user access via SCP
# =============================================================================

# ── Data: Fetch the existing Organization root ────────────────────────────────
# WHY DATA SOURCE: The Organization was created by bootstrap.sh, not Terraform.
# We use a data source to read its current state without managing it.
data "aws_organizations_organization" "this" {}

# ── Local values ──────────────────────────────────────────────────────────────
locals {
  # Root OU ID — used as parent for top-level OUs
  root_id = data.aws_organizations_organization.this.roots[0].id

  # Company prefix for consistent naming
  prefix = "idk"
}

# =============================================================================
# ORGANIZATIONAL UNITS
# =============================================================================
# WHY THIS OU STRUCTURE:
#   OUs are the primary governance boundary in AWS Organizations. SCPs attach
#   to OUs and cascade down. The structure below follows the AWS recommended
#   "functional" OU design from the AWS Security Reference Architecture (SRA).
#
#   Key principle: OUs represent SECURITY AND GOVERNANCE boundaries, not
#   team or application boundaries. A "Production" OU means "production-level
#   controls apply here" — not "all production apps live here."
# =============================================================================

# ── Security OU ───────────────────────────────────────────────────────────────
# Contains: Log Archive, Security Tooling accounts
# SCP intent: Highly restricted. Deny almost everything except security tooling.
# Why separate: Security accounts need STRONGER restrictions than other accounts,
#               not weaker. No one — not even developers — should be able to
#               modify logs or security configurations.
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = local.root_id

  tags = {
    Description = "Security tooling and immutable log archive accounts"
    Criticality = "critical"
  }
}

# ── Infrastructure OU ─────────────────────────────────────────────────────────
# Contains: Network account (Transit Gateway, DNS, Shared VPCs)
# SCP intent: Networking changes require elevated approval. Deny direct VPC
#             creation in other accounts (enforced in later SCP phase).
resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = local.root_id

  tags = {
    Description = "Core networking and infrastructure accounts"
    Criticality = "critical"
  }
}

# ── Shared Services OU ────────────────────────────────────────────────────────
# Contains: Shared Services account (IAM Identity Center, artifact repos)
# SCP intent: Moderate restrictions. Services here are consumed by other accounts.
resource "aws_organizations_organizational_unit" "shared_services" {
  name      = "SharedServices"
  parent_id = local.root_id

  tags = {
    Description = "Shared platform services consumed across all accounts"
    Criticality = "high"
  }
}

# ── Production OU ─────────────────────────────────────────────────────────────
# Contains: Production workload accounts
# SCP intent: Strict. No unapproved services. No untagged resources.
#             Change management controls enforced.
resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = local.root_id

  tags = {
    Description = "Production workload accounts — strict change controls"
    Criticality = "critical"
  }
}

# ── Non-Production OU ─────────────────────────────────────────────────────────
# Contains: Development, UAT accounts
# SCP intent: Moderate. Region restriction still applies. Expensive services
#             (e.g., large RDS instances) can be denied.
resource "aws_organizations_organizational_unit" "non_production" {
  name      = "NonProduction"
  parent_id = local.root_id

  tags = {
    Description = "Development and UAT accounts"
    Criticality = "medium"
  }
}

# ── Sandbox OU ────────────────────────────────────────────────────────────────
# Contains: AI Lab, FinOps Lab
# SCP intent: Permissive within cost guardrails. Allow experimentation but
#             prevent accidental expensive resources (e.g., ml.p3 instances).
# WHY SEPARATE FROM NON-PROD: Sandbox accounts are "break things and learn"
#   environments. They get looser controls than dev/uat but tighter cost guards.
resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = local.root_id

  tags = {
    Description = "Experimental and learning accounts — cost guardrails apply"
    Criticality = "low"
  }
}

# ── Suspended OU ──────────────────────────────────────────────────────────────
# Contains: Accounts pending closure or quarantined accounts
# SCP intent: DENY ALL except billing reads.
# WHY: Before AWS deletes an account (90-day process), you need a safe place
#      to park it where nothing new can be created or costs incurred.
resource "aws_organizations_organizational_unit" "suspended" {
  name      = "Suspended"
  parent_id = local.root_id

  tags = {
    Description = "Quarantined accounts pending closure — all actions denied"
    Criticality = "low"
  }
}

# =============================================================================
# MEMBER ACCOUNTS
# =============================================================================
# IMPORTANT: Each account needs a UNIQUE email address.
# Pattern used: aws+<account-name>@yourdomain.com
# Replace <YOUR_EMAIL_DOMAIN> with your actual domain or use Gmail aliases:
#   yourname+idk-log-archive@gmail.com
#
# COST NOTE: Creating accounts is FREE. You only pay for resources created
# inside those accounts. Empty accounts cost nothing.
#
# iam_user_access_to_billing = "ALLOW"
#   WHY: Allows IAM users (and Identity Center roles) in the account to see
#   billing data for that account. Without this, only root can see billing.
#   In enterprise, FinOps teams need billing visibility across all accounts.
# =============================================================================

# ── Log Archive Account ───────────────────────────────────────────────────────
resource "aws_organizations_account" "log_archive" {
  name                       = "idk-log-archive"
  email                      = "aws+idk-log-archive@gmail.com" # CHANGE THIS
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.security.id

  tags = {
    AccountPurpose    = "Immutable centralized log storage"
    DataClassification = "confidential"
    Compliance        = "none"
    Backup            = "required"
    Criticality       = "critical"
  }

  # WHY lifecycle ignore_changes on email:
  #   After account creation, AWS doesn't allow email changes via API.
  #   Without this, Terraform will perpetually show a diff and try to
  #   update the email (which will fail). This is a known AWS/Terraform quirk.
  lifecycle {
    ignore_changes = [email]
  }
}

# ── Security Account ─────────────────────────────────────────────────────────
resource "aws_organizations_account" "security" {
  name                       = "idk-security"
  email                      = "aws+idk-security@gmail.com" # CHANGE THIS
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.security.id

  tags = {
    AccountPurpose     = "GuardDuty delegated admin, SecurityHub aggregator, SIEM"
    DataClassification = "confidential"
    Compliance         = "none"
    Backup             = "not-required"
    Criticality        = "critical"
  }

  lifecycle {
    ignore_changes = [email]
  }
}

# ── Network Account ───────────────────────────────────────────────────────────
resource "aws_organizations_account" "network" {
  name                       = "idk-network"
  email                      = "aws+idk-network@gmail.com" # CHANGE THIS
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.infrastructure.id

  tags = {
    AccountPurpose     = "Transit Gateway, Route 53 Resolver, shared networking"
    DataClassification = "internal"
    Compliance         = "none"
    Backup             = "not-required"
    Criticality        = "critical"
  }

  lifecycle {
    ignore_changes = [email]
  }
}

# ── Shared Services Account ───────────────────────────────────────────────────
resource "aws_organizations_account" "shared_services" {
  name                       = "idk-shared-services"
  email                      = "aws+idk-shared-services@gmail.com" # CHANGE THIS
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.shared_services.id

  tags = {
    AccountPurpose     = "IAM Identity Center, CodeArtifact, shared tooling"
    DataClassification = "internal"
    Compliance         = "none"
    Backup             = "not-required"
    Criticality        = "high"
  }

  lifecycle {
    ignore_changes = [email]
  }
}

# ── Production Account ────────────────────────────────────────────────────────
resource "aws_organizations_account" "production" {
  name                       = "idk-production"
  email                      = "aws+idk-production@gmail.com" # CHANGE THIS
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.production.id

  tags = {
    AccountPurpose     = "Production workloads"
    DataClassification = "confidential"
    Compliance         = "none"
    Backup             = "required"
    Criticality        = "critical"
  }

  lifecycle {
    ignore_changes = [email]
  }
}

# ── Development Account ───────────────────────────────────────────────────────
resource "aws_organizations_account" "development" {
  name                       = "idk-development"
  email                      = "aws+idk-development@gmail.com" # CHANGE THIS
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.non_production.id

  tags = {
    AccountPurpose     = "Developer workloads and feature development"
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
resource "aws_organizations_account" "uat" {
  name                       = "idk-uat"
  email                      = "aws+idk-uat@gmail.com" # CHANGE THIS
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.non_production.id

  tags = {
    AccountPurpose     = "User acceptance testing and pre-production validation"
    DataClassification = "internal"
    Compliance         = "none"
    Backup             = "not-required"
    Criticality        = "medium"
  }

  lifecycle {
    ignore_changes = [email]
  }
}

# ── AI Lab Account ────────────────────────────────────────────────────────────
# NOTE: This is the ONLY account running compute in Phase 1
resource "aws_organizations_account" "ai_lab" {
  name                       = "idk-ai-lab"
  email                      = "aws+idk-ai-lab@gmail.com" # CHANGE THIS
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.sandbox.id

  tags = {
    AccountPurpose     = "Agentic AI platform development and experimentation"
    DataClassification = "internal"
    Compliance         = "none"
    Backup             = "not-required"
    Criticality        = "low"
  }

  lifecycle {
    ignore_changes = [email]
  }
}

# ── FinOps Lab Account ────────────────────────────────────────────────────────
resource "aws_organizations_account" "finops_lab" {
  name                       = "idk-finops-lab"
  email                      = "aws+idk-finops-lab@gmail.com" # CHANGE THIS
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.sandbox.id

  tags = {
    AccountPurpose     = "FinOps tooling experimentation and cost optimization testing"
    DataClassification = "internal"
    Compliance         = "none"
    Backup             = "not-required"
    Criticality        = "low"
  }

  lifecycle {
    ignore_changes = [email]
  }
}
