# =============================================================================
# IDK Digital Solutions — AWS Organizations Tag Policy
# terraform/global/tag-policies/main.tf
# =============================================================================
#
# WHAT ARE TAG POLICIES:
#   Tag Policies are an AWS Organizations feature that define standardized
#   tag keys and allowed values across your organization. They are different
#   from SCPs — they don't deny API calls but instead:
#   1. Report non-compliant resources in AWS Tag Editor and Resource Groups
#   2. (Optionally) enforce case-sensitivity for tag keys
#   3. Provide the data foundation for FinOps cost allocation
#
# IMPORTANT LIMITATION:
#   Tag Policies in AWS do NOT block resource creation if tags are missing.
#   They report non-compliance. To BLOCK creation, you need an SCP or
#   AWS Config + Lambda remediation. We implement the reporting layer here
#   and add Config enforcement in Phase 6.
#
# WHY TAG POLICIES STILL MATTER EVEN WITHOUT ENFORCEMENT:
#   1. They define the canonical list of allowed tag values (prevents "Dev" vs
#      "dev" vs "DEV" inconsistency that breaks FinOps cost allocation)
#   2. Tag Editor console shows you exactly which resources are non-compliant
#   3. Cost Explorer filtering only works correctly with consistent tag values
#   4. This is the first step toward full tag governance maturity
#
# FINOPS IMPACT:
#   Inconsistent tags are the #1 reason Cost Explorer reports are inaccurate.
#   "I can't tell which team owns these costs" is almost always a tag problem.
#   Tag Policies fix this at the source.
# =============================================================================

resource "aws_organizations_policy" "idk_tag_policy" {
  name        = "idk-enterprise-tag-policy"
  description = "Mandatory tag standards for IDK Digital Solutions. Enforces key names and allowed values."
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {

      # ── Department ─────────────────────────────────────────────────────────
      # Maps resources to business departments for accountability
      Department = {
        tag_key = {
          "@@assign" = "Department"
        }
        tag_value = {
          "@@assign" = [
            "Platform Engineering",
            "AI & Data",
            "Finance",
            "HR",
            "Sales",
            "Marketing",
            "Operations",
            "Security",
            "Customer Support",
            "Research & Development"
          ]
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "rds:db",
            "rds:cluster",
            "s3:bucket",
            "lambda:function"
          ]
        }
      }

      # ── CostCenter ─────────────────────────────────────────────────────────
      # The single most important tag for FinOps chargeback
      # Maps directly to your cost center list
      CostCenter = {
        tag_key = {
          "@@assign" = "CostCenter"
        }
        tag_value = {
          "@@assign" = [
            "CC1001",
            "CC1002",
            "CC1003",
            "CC1004",
            "CC1005",
            "CC1006",
            "CC1007",
            "CC1008",
            "CC1009",
            "CC1010"
          ]
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "rds:db",
            "rds:cluster",
            "s3:bucket",
            "lambda:function",
            "elasticloadbalancing:loadbalancer"
          ]
        }
      }

      # ── Environment ────────────────────────────────────────────────────────
      # Used for filtering in Cost Explorer and Config rules
      # CASE MATTERS: "Production" != "production" in tag value matching
      Environment = {
        tag_key = {
          "@@assign" = "Environment"
        }
        tag_value = {
          "@@assign" = [
            "production",
            "uat",
            "development",
            "sandbox",
            "management"
          ]
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "rds:db",
            "rds:cluster",
            "s3:bucket",
            "lambda:function"
          ]
        }
      }

      # ── ManagedBy ──────────────────────────────────────────────────────────
      # Critical for detecting IaC drift — resources not managed by Terraform
      # are manually created and may not follow standards
      ManagedBy = {
        tag_key = {
          "@@assign" = "ManagedBy"
        }
        tag_value = {
          "@@assign" = [
            "terraform",
            "ansible",
            "cloudformation",
            "console",
            "bootstrap-script",
            "github-actions"
          ]
        }
      }

      # ── DataClassification ─────────────────────────────────────────────────
      # Required for data governance and compliance reporting
      # Used by security teams to apply appropriate controls
      DataClassification = {
        tag_key = {
          "@@assign" = "DataClassification"
        }
        tag_value = {
          "@@assign" = [
            "public",
            "internal",
            "confidential",
            "restricted"
          ]
        }
        enforced_for = {
          "@@assign" = [
            "s3:bucket",
            "rds:db",
            "rds:cluster",
            "dynamodb:table"
          ]
        }
      }

      # ── Criticality ────────────────────────────────────────────────────────
      # Used by SRE/Ops to prioritize incident response
      # P1 incidents on "critical" resources require immediate response
      Criticality = {
        tag_key = {
          "@@assign" = "Criticality"
        }
        tag_value = {
          "@@assign" = [
            "critical",
            "high",
            "medium",
            "low"
          ]
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "rds:db",
            "rds:cluster",
            "elasticloadbalancing:loadbalancer"
          ]
        }
      }

      # ── Backup ─────────────────────────────────────────────────────────────
      # Drives AWS Backup automation — resources tagged "required" are
      # automatically included in backup plans (Phase 6)
      Backup = {
        tag_key = {
          "@@assign" = "Backup"
        }
        tag_value = {
          "@@assign" = [
            "required",
            "not-required"
          ]
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "rds:db",
            "rds:cluster",
            "dynamodb:table"
          ]
        }
      }

      # ── Project ────────────────────────────────────────────────────────────
      # Free-form project identifier — no enforced values (projects change often)
      # Allows FinOps to track cost by project within a cost center
      Project = {
        tag_key = {
          "@@assign" = "Project"
        }
      }

      # ── Application ────────────────────────────────────────────────────────
      # Free-form application name — maps to your enterprise application catalog
      Application = {
        tag_key = {
          "@@assign" = "Application"
        }
      }

      # ── Owner ──────────────────────────────────────────────────────────────
      # Email or team name — used for alerting and cost accountability
      Owner = {
        tag_key = {
          "@@assign" = "Owner"
        }
      }

      # ── BusinessUnit ───────────────────────────────────────────────────────
      # Top-level business unit for executive cost rollup reporting
      BusinessUnit = {
        tag_key = {
          "@@assign" = "BusinessUnit"
        }
        tag_value = {
          "@@assign" = [
            "Technology",
            "Finance",
            "Sales",
            "Operations",
            "HR"
          ]
        }
      }

      # ── Compliance ─────────────────────────────────────────────────────────
      # Used by security and audit teams to identify regulated workloads
      Compliance = {
        tag_key = {
          "@@assign" = "Compliance"
        }
        tag_value = {
          "@@assign" = [
            "none",
            "pci-dss",
            "hipaa",
            "sox",
            "gdpr",
            "iso27001"
          ]
        }
      }
    }
  })

  tags = {
    PolicyPurpose = "Enterprise tag governance — key names and allowed values"
    Phase         = "1"
    Criticality   = "high"
  }
}

# Attach tag policy to the organization root
# WHY ROOT ATTACHMENT: Tag policies cascade down. Attaching to root means
# all accounts in all OUs inherit this policy. We use one policy here
# rather than per-OU policies because the tag standards are universal.
resource "aws_organizations_policy_attachment" "tag_policy_root" {
  policy_id = aws_organizations_policy.idk_tag_policy.id
  target_id = local.org_root_id
}
