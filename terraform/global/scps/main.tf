# =============================================================================
# IDK Digital Solutions — Service Control Policies
# terraform/global/scps/main.tf
# =============================================================================
#
# WHAT ARE SCPs:
#   Service Control Policies are JSON policies that define the MAXIMUM
#   permissions available to accounts within an OU. They do not grant
#   permissions — they restrict what IAM policies CAN grant.
#
#   Think of SCPs as a permission ceiling. Even if an IAM policy in an
#   account says "Allow *:*", the SCP can still block specific actions.
#
# HOW SCPs WORK (the "AND" logic):
#   Effective permissions = SCP allows AND IAM allows
#   If SCP denies action X, no IAM policy in that account can allow X.
#   Even the account's own root user is subject to SCPs.
#   EXCEPTION: The Management Account is NEVER subject to SCPs.
#
# SCP EVALUATION ORDER:
#   1. An explicit Deny in any SCP always wins
#   2. For Allow: action must be allowed by BOTH SCP and IAM policy
#
# PHASE 1 SCPs IMPLEMENTED:
#   1. Deny non-Mumbai regions (applied to all OUs except management)
#   2. Deny root account actions (all OUs)
#   3. Deny leaving the organization (all OUs)
#   4. Deny all — Suspended OU only
#   5. Deny expensive services in Sandbox OU
# =============================================================================

# =============================================================================
# SCP 1: REGION RESTRICTION — Deny actions outside ap-south-1
# =============================================================================
# WHY THIS SCP IS CRITICAL:
#   Without region restriction, a compromised account or misconfigured
#   automation could accidentally spin up resources in us-east-1, eu-west-1,
#   etc. This creates:
#   - Unexpected costs (you won't see them until the bill arrives)
#   - Data residency violations (data leaving India without approval)
#   - Compliance failures (regulatory data must stay in approved regions)
#
# WHY ALLOW GLOBAL SERVICES:
#   Many AWS services are "global" — they don't have a region in their API
#   calls. IAM, STS, S3 (bucket creation), Route 53, CloudFront, WAF,
#   Trusted Advisor, Budgets, Cost Explorer — these would be blocked if we
#   denied everything outside ap-south-1 without exceptions.
#   The Condition "StringNotLike" with "aws:RequestedRegion" only applies
#   to regional services, so we must explicitly exempt global services.
#
# ENTERPRISE ALTERNATIVE:
#   Some enterprises use "Allow only ap-south-1" instead of "Deny others".
#   The Deny approach is more robust — it blocks new regions by default
#   even if AWS adds new regions in the future.
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
        # NotAction = deny everything EXCEPT these global services
        # WHY NotAction instead of Action "*":
        #   If we used Action "*" with a condition on region, we'd block
        #   global services too. NotAction lets us exclude global services
        #   from the region restriction while still blocking all regional
        #   services outside Mumbai.
        NotAction = [
          # Identity & Access Management — global service
          "iam:*",
          "sts:*",

          # Organizations — management plane is global
          "organizations:*",

          # Billing & Cost Management — global
          "aws-portal:*",
          "budgets:*",
          "ce:*",
          "cur:*",
          "pricing:*",
          "savingsplans:*",

          # Support & Trusted Advisor — global
          "support:*",
          "trustedadvisor:*",
          "health:*",

          # Route 53 — global DNS service
          "route53:*",
          "route53domains:*",
          "route53resolver:*",

          # CloudFront — global CDN
          "cloudfront:*",

          # WAF v2 global (CloudFront-attached)
          "wafv2:*",

          # ACM (us-east-1 certs for CloudFront)
          "acm:*",

          # S3 — bucket management APIs are global even though data is regional
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation",

          # Account management
          "account:*",

          # SSO / Identity Center — global
          "sso:*",
          "sso-directory:*",
          "identitystore:*",

          # Security Hub, GuardDuty aggregation (management APIs)
          "securityhub:*",
          "guardduty:*",

          # CloudTrail — can be global trail
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

# Attach region restriction to ALL OUs (not root — management account is exempt from SCPs anyway)
resource "aws_organizations_policy_attachment" "region_restriction_security" {
  policy_id = aws_organizations_policy.deny_non_mumbai_regions.id
  target_id = local.ou_security_id
}

resource "aws_organizations_policy_attachment" "region_restriction_infrastructure" {
  policy_id = aws_organizations_policy.deny_non_mumbai_regions.id
  target_id = local.ou_infra_id
}

resource "aws_organizations_policy_attachment" "region_restriction_shared_services" {
  policy_id = aws_organizations_policy.deny_non_mumbai_regions.id
  target_id = local.ou_shared_id
}

resource "aws_organizations_policy_attachment" "region_restriction_production" {
  policy_id = aws_organizations_policy.deny_non_mumbai_regions.id
  target_id = local.ou_production_id
}

resource "aws_organizations_policy_attachment" "region_restriction_non_production" {
  policy_id = aws_organizations_policy.deny_non_mumbai_regions.id
  target_id = local.ou_nonprod_id
}

resource "aws_organizations_policy_attachment" "region_restriction_sandbox" {
  policy_id = aws_organizations_policy.deny_non_mumbai_regions.id
  target_id = local.ou_sandbox_id
}

# =============================================================================
# SCP 2: PROTECT ROOT ACCOUNT ACTIONS
# =============================================================================
# WHY:
#   The root user of each account has special privileges that bypass IAM.
#   CIS Benchmark and AWS Security Best Practices require that root is
#   never used for day-to-day operations. This SCP doesn't prevent root
#   login (that would lock out recovery) but prevents specific high-risk
#   root-only actions from being performed programmatically.
#
# WHAT IT DENIES:
#   - Creating root access keys (long-lived root credentials = catastrophic)
#   - Changing account settings that only root can do (done in management)
#
# NOTE: This SCP does NOT prevent humans from logging in as root.
#   That's enforced by organizational policy and MFA requirements.
#   IAM Identity Center (Phase 3) will make root login unnecessary.
# =============================================================================
resource "aws_organizations_policy" "deny_root_actions" {
  name        = "idk-deny-root-account-actions"
  description = "Prevent use of root credentials for day-to-day operations. CIS Benchmark 1.1."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRootAccountActions"
        Effect = "Deny"
        Action = [
          # Prevent creating long-lived root access keys
          "iam:CreateVirtualMFADevice",
          "iam:DeleteVirtualMFADevice",

          # Prevent root from creating access keys for itself
          # (root access keys are the most dangerous credential in AWS)
          "iam:CreateAccessKey"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::*:root"
            ]
          }
        }
      },
      {
        # Deny anyone from leaving the organization
        # WHY: A compromised account could "leave" the org to escape SCPs.
        #      This closes that escape hatch.
        Sid    = "DenyLeavingOrganization"
        Effect = "Deny"
        Action = [
          "organizations:LeaveOrganization"
        ]
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

# Attach root protection to ALL OUs
resource "aws_organizations_policy_attachment" "root_protection_security" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.ou_security_id
}

resource "aws_organizations_policy_attachment" "root_protection_infrastructure" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.ou_infra_id
}

resource "aws_organizations_policy_attachment" "root_protection_shared_services" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.ou_shared_id
}

resource "aws_organizations_policy_attachment" "root_protection_production" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.ou_production_id
}

resource "aws_organizations_policy_attachment" "root_protection_non_production" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.ou_nonprod_id
}

resource "aws_organizations_policy_attachment" "root_protection_sandbox" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.ou_sandbox_id
}

# =============================================================================
# SCP 3: PROTECT SECURITY & LOGGING INFRASTRUCTURE
# =============================================================================
# WHY:
#   GuardDuty, CloudTrail, SecurityHub, and Config are your security eyes.
#   If an attacker compromises an account, their FIRST action is usually to
#   disable these services to prevent detection. This SCP makes that
#   impossible — even for account administrators.
#
# ENTERPRISE PATTERN:
#   "Security tools must be enabled and cannot be disabled by workload accounts"
#   is a universal enterprise requirement. This is how Control Tower's
#   "strongly recommended" guardrails work — we're implementing the same
#   protection manually.
# =============================================================================
resource "aws_organizations_policy" "protect_security_services" {
  name        = "idk-protect-security-services"
  description = "Prevent disabling or modifying GuardDuty, CloudTrail, Config, SecurityHub. Security cannot be turned off."
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
          # Prevent deleting or modifying the centralized log S3 bucket
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:PutLifecycleConfiguration",
          "s3:PutReplicationConfiguration"
        ]
        Resource = [
          # Log archive bucket ARN pattern
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

# Attach security protection to all OUs
resource "aws_organizations_policy_attachment" "security_protection_security_ou" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = local.ou_security_id
}

resource "aws_organizations_policy_attachment" "security_protection_infrastructure" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = local.ou_infra_id
}

resource "aws_organizations_policy_attachment" "security_protection_shared_services" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = local.ou_shared_id
}

resource "aws_organizations_policy_attachment" "security_protection_production" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = local.ou_production_id
}

resource "aws_organizations_policy_attachment" "security_protection_non_production" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = local.ou_nonprod_id
}

resource "aws_organizations_policy_attachment" "security_protection_sandbox" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = local.ou_sandbox_id
}

# =============================================================================
# SCP 4: SANDBOX COST GUARDRAILS
# =============================================================================
# WHY:
#   Sandbox accounts are for experimentation. The risk is someone accidentally
#   launches expensive resources (GPU instances, large RDS, high-memory EC2)
#   that run up the bill. These denies prevent the most common expensive
#   mistakes while still allowing normal lab work.
#
# FINOPS PRINCIPLE: "Guardrails before budgets"
#   Budgets alert you AFTER you've spent money. SCPs prevent the spend
#   from happening at all. Both are needed — SCPs for hard stops,
#   Budgets for soft alerts.
# =============================================================================
resource "aws_organizations_policy" "sandbox_cost_guardrails" {
  name        = "idk-sandbox-cost-guardrails"
  description = "Prevent expensive resource types in Sandbox OU. Protects lab budget."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyExpensiveEC2Families"
        Effect = "Deny"
        Action = ["ec2:RunInstances"]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          # Block GPU instances (p, g families) — can cost $2–$30/hour
          # Block high-memory instances (x, u families) — enterprise-grade pricing
          # Block bare metal — not needed for lab work
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
              "db.r5.*",
              "db.r6.*",
              "db.x1.*",
              "db.x2.*"
            ]
          }
        }
      },
      {
        # Prevent purchasing Reserved Instances from sandbox
        # WHY: RIs are 1-3 year commitments costing thousands of dollars.
        #      Only FinOps team should be authorized to purchase them.
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
    SCPPurpose  = "Cost guardrails for Sandbox OU"
    Phase       = "1"
    Criticality = "high"
  }
}

resource "aws_organizations_policy_attachment" "sandbox_cost_guardrails" {
  policy_id = aws_organizations_policy.sandbox_cost_guardrails.id
  target_id = local.ou_sandbox_id
}

# =============================================================================
# SCP 5: SUSPENDED OU — DENY ALL
# =============================================================================
# WHY:
#   Accounts in the Suspended OU are either quarantined or pending closure.
#   Nothing should be creatable or modifiable. The only exception is billing
#   reads (needed to verify final charges before account closure).
# =============================================================================
resource "aws_organizations_policy" "deny_all_suspended" {
  name        = "idk-deny-all-suspended"
  description = "Deny all actions in Suspended OU accounts except billing reads. Quarantine policy."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyAllExceptBilling"
        Effect = "Deny"
        NotAction = [
          "aws-portal:View*",
          "budgets:View*",
          "ce:Get*",
          "ce:List*",
          "organizations:Describe*",
          "organizations:List*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    SCPPurpose  = "Full deny for suspended/quarantined accounts"
    Phase       = "1"
    Criticality = "critical"
  }
}

resource "aws_organizations_policy_attachment" "deny_all_suspended" {
  policy_id = aws_organizations_policy.deny_all_suspended.id
  target_id = local.ou_suspended_id
}
