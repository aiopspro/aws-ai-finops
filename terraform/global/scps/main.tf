# =============================================================================
# IDK Digital Solutions — Service Control Policies
# terraform/global/scps/main.tf
# =============================================================================
#
# WHAT ARE SCPs:
#   Service Control Policies define the MAXIMUM permissions available to
#   accounts within an OU. They do not grant permissions — they restrict
#   what IAM policies CAN grant.
#
#   Think of SCPs as a permission ceiling. Even if an IAM policy says
#   "Allow *:*", the SCP can still block specific actions.
#   EXCEPTION: The Management Account is NEVER subject to SCPs.
#
# CURRENT OU STRUCTURE (3 OUs):
#   Security      → idk-log-archive
#   SharedServices → (empty — account added in future phase)
#   NonProduction  → idk-development, idk-uat
#
# SCPs IMPLEMENTED (Phase 1):
#   1. Deny non-Mumbai regions        → all 3 OUs
#   2. Deny root account actions      → all 3 OUs
#   3. Protect security services      → all 3 OUs
#   4. NonProduction cost guardrails  → NonProduction OU only
# =============================================================================

# =============================================================================
# SCP 1: REGION RESTRICTION — Deny actions outside ap-south-1
# =============================================================================
# WHY THIS SCP IS CRITICAL:
#   Without region restriction, a compromised account could spin up resources
#   in any AWS region — creating unexpected costs and data residency violations.
#
# WHY NotAction INSTEAD OF Action "*":
#   Many AWS services (IAM, STS, Route 53, CloudFront, Budgets) are "global"
#   and have no region in their API calls. Using Action "*" with a region
#   condition would block these global services. NotAction lets us exclude
#   them while still blocking all regional services outside Mumbai.
# =============================================================================
resource "aws_organizations_policy" "deny_non_mumbai_regions" {
  name        = "idk-deny-non-mumbai-regions"
  description = "Deny all AWS actions outside ap-south-1 except global services. Phase 1 region lockdown."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonMumbaiRegions"
        Effect = "Deny"
        NotAction = [
          # Identity & Access Management — global service
          "iam:*",
          "sts:*",

          # Organizations — management plane is global
          "organizations:*",

          # Billing & Cost Management — global
          "billing:*",
          "budgets:*",
          "ce:*",
          "cur:*",
          "pricing:*",
          "savingsplans:*",
          "tax:*",

          # Support & Trusted Advisor — global
          "support:*",
          "trustedadvisor:*",
          "health:*",

          # Route 53 — global DNS
          "route53:*",
          "route53domains:*",

          # CloudFront — global CDN
          "cloudfront:*",

          # WAF v2 global (CloudFront-attached)
          "wafv2:*",

          # ACM (us-east-1 certs for CloudFront)
          "acm:*",

          # S3 bucket management APIs are global even though data is regional
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation",

          # Account management
          "account:*",

          # Security Hub, GuardDuty — management APIs
          "securityhub:*",
          "guardduty:*",

          # CloudTrail — can be a global trail
          "cloudtrail:*",

          # Config — aggregator configuration is global
          "config:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = "ap-south-1"
          }
        }
      }
    ]
  })

  tags = {
    SCPPurpose  = "Region restriction — deny all non-Mumbai regions"
    Phase       = "1"
    Criticality = "critical"
  }
}

# Attach region restriction to all 3 OUs
resource "aws_organizations_policy_attachment" "region_restriction_security" {
  policy_id = aws_organizations_policy.deny_non_mumbai_regions.id
  target_id = local.ou_security_id
}

resource "aws_organizations_policy_attachment" "region_restriction_shared_services" {
  policy_id = aws_organizations_policy.deny_non_mumbai_regions.id
  target_id = local.ou_shared_id
}

resource "aws_organizations_policy_attachment" "region_restriction_non_production" {
  policy_id = aws_organizations_policy.deny_non_mumbai_regions.id
  target_id = local.ou_nonprod_id
}

# =============================================================================
# SCP 2: PROTECT ROOT ACCOUNT ACTIONS
# =============================================================================
# WHY:
#   The root user has special privileges that bypass IAM. This SCP prevents
#   high-risk root-only actions from being performed programmatically.
#   It also prevents accounts from leaving the organization to escape SCPs.
#
# NOTE: This does NOT prevent humans logging in as root — that is enforced
#   by organizational policy and MFA. IAM Identity Center (future phase)
#   will make root login unnecessary entirely.
# =============================================================================
resource "aws_organizations_policy" "deny_root_actions" {
  name        = "idk-deny-root-account-actions"
  description = "Prevent use of root credentials and leaving the organization. CIS Benchmark 1.1."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRootAccountActions"
        Effect = "Deny"
        Action = [
          "iam:CreateVirtualMFADevice",
          "iam:DeleteVirtualMFADevice",
          # Root access keys are the most dangerous credential in AWS
          "iam:CreateAccessKey"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = ["arn:aws:iam::*:root"]
          }
        }
      },
      {
        # A compromised account could leave the org to escape SCPs.
        # This closes that escape hatch permanently.
        Sid    = "DenyLeavingOrganization"
        Effect = "Deny"
        Action = ["organizations:LeaveOrganization"]
        Resource = "*"
      }
    ]
  })

  tags = {
    SCPPurpose  = "Root account protection and org membership enforcement"
    Phase       = "1"
    Criticality = "critical"
  }
}

# Attach root protection to all 3 OUs
resource "aws_organizations_policy_attachment" "root_protection_security" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.ou_security_id
}

resource "aws_organizations_policy_attachment" "root_protection_shared_services" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.ou_shared_id
}

resource "aws_organizations_policy_attachment" "root_protection_non_production" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.ou_nonprod_id
}

# =============================================================================
# SCP 3: PROTECT SECURITY & LOGGING INFRASTRUCTURE
# =============================================================================
# WHY:
#   GuardDuty, CloudTrail, SecurityHub, and Config are your security eyes.
#   If an attacker compromises an account, their first action is usually to
#   disable these services to prevent detection. This SCP makes that
#   impossible even for account administrators.
#
# ENTERPRISE PATTERN:
#   "Security tools must be enabled and cannot be disabled by workload accounts"
#   is a universal enterprise requirement — same pattern used by AWS Control Tower.
# =============================================================================
resource "aws_organizations_policy" "protect_security_services" {
  name        = "idk-protect-security-services"
  description = "Prevent disabling GuardDuty, CloudTrail, Config, SecurityHub. Security cannot be turned off."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDisablingGuardDuty"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:DisassociateMembers",
          "guardduty:StopMonitoringMembers",
          "guardduty:UpdateDetector"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDisablingCloudTrail"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
          "cloudtrail:PutEventSelectors"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyModifyingLogArchive"
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:PutLifecycleConfiguration",
          "s3:PutReplicationConfiguration"
        ]
        Resource = [
          "arn:aws:s3:::idk-logs-*",
          "arn:aws:s3:::idk-cloudtrail-*"
        ]
      },
      {
        Sid    = "DenyDisablingSecurityHub"
        Effect = "Deny"
        Action = [
          "securityhub:DeleteHub",
          "securityhub:DisableSecurityHub",
          "securityhub:DisassociateFromMasterAccount",
          "securityhub:DisassociateMembers"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDisablingConfig"
        Effect = "Deny"
        Action = [
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    SCPPurpose  = "Immutable security service protection"
    Phase       = "1"
    Criticality = "critical"
  }
}

# Attach security protection to all 3 OUs
resource "aws_organizations_policy_attachment" "security_protection_security_ou" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = local.ou_security_id
}

resource "aws_organizations_policy_attachment" "security_protection_shared_services" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = local.ou_shared_id
}

resource "aws_organizations_policy_attachment" "security_protection_non_production" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = local.ou_nonprod_id
}

# =============================================================================
# SCP 4: NON-PRODUCTION COST GUARDRAILS
# =============================================================================
# WHY:
#   The NonProduction OU hosts your primary lab accounts. The risk is
#   accidentally launching expensive resources (GPU instances, large RDS,
#   Reserved Instance purchases) that run up the bill.
#
# FINOPS PRINCIPLE: "Guardrails before budgets"
#   Budgets alert you AFTER you've spent money. SCPs prevent the spend
#   from happening at all. Both are needed — SCPs for hard stops,
#   Budgets for soft alerts.
#
# LAB NOTE: This SCP still allows t3/t4g, m5, c5 instances and standard
#   RDS classes — everything you need for AI and FinOps lab work.
# =============================================================================
resource "aws_organizations_policy" "non_production_cost_guardrails" {
  name        = "idk-non-production-cost-guardrails"
  description = "Prevent expensive resource types in NonProduction OU. Protects lab budget."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Block GPU and high-memory EC2 instances — can cost $2–$30/hour
        Sid    = "DenyExpensiveEC2Families"
        Effect = "Deny"
        Action = ["ec2:RunInstances"]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringLike = {
            "ec2:InstanceType" = [
              "p2.*", "p3.*", "p4.*", "p5.*",
              "g3.*", "g4.*", "g5.*", "g6.*",
              "x1.*", "x2.*",
              "u-*",
              "*.metal"
            ]
          }
        }
      },
      {
        # Block large RDS instance classes
        Sid    = "DenyLargeRDS"
        Effect = "Deny"
        Action = [
          "rds:CreateDBInstance",
          "rds:CreateDBCluster"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "rds:DatabaseClass" = [
              "db.r5.*", "db.r6.*",
              "db.x1.*", "db.x2.*"
            ]
          }
        }
      },
      {
        # Reserved Instances are 1-3 year commitments costing thousands.
        # Only FinOps team should be authorized to purchase them.
        Sid    = "DenyReservedInstancePurchases"
        Effect = "Deny"
        Action = [
          "ec2:PurchaseReservedInstancesOffering",
          "ec2:ModifyReservedInstances",
          "rds:PurchaseReservedDBInstancesOffering"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    SCPPurpose  = "Cost guardrails for NonProduction OU"
    Phase       = "1"
    Criticality = "high"
  }
}

resource "aws_organizations_policy_attachment" "non_production_cost_guardrails" {
  policy_id = aws_organizations_policy.non_production_cost_guardrails.id
  target_id = local.ou_nonprod_id
}
