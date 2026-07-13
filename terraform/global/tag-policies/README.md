# Tag Policies

> **Run fourth** — after the organization layer and SCPs.

Tag Policies define the canonical tag keys and allowed values across your entire AWS Organization. They are the foundation of FinOps cost allocation — without consistent tags, Cost Explorer reports are unreliable and chargeback is impossible.

---

## How Tag Policies Work

Tag Policies are different from SCPs. They do **not** block resource creation.

| | SCPs | Tag Policies |
|---|---|---|
| Block API calls? | Yes | No |
| Grant permissions? | No | No |
| Purpose | Governance guardrail | Tag standardisation |
| Non-compliance effect | API call is denied | Resource reported as non-compliant |
| Where to see violations | CloudTrail | AWS Tag Editor, Resource Groups |

Tag Policies enforce:
1. **Key name casing** — `CostCenter` not `costcenter` or `cost_center`
2. **Allowed values** — `production` not `Production` or `prod`
3. **Enforcement scope** — which resource types must carry which tags

To **block** resource creation when tags are missing, an SCP or AWS Config rule is required (planned for Phase 5).

---

## Why Tag Policies Matter for FinOps

Inconsistent tags are the single most common reason Cost Explorer reports are inaccurate. Common problems this policy prevents:

- `Environment: Production` vs `Environment: production` vs `Environment: prod` — all treated as different values, breaking filters
- `CostCenter: cc1001` vs `CostCenter: CC1001` — cost allocation tags are case-sensitive
- Missing tags entirely — costs show up as "untagged" with no owner

Once tags are consistent, you can accurately answer: *"How much did each team, project, and environment cost this month?"*

---

## Prerequisites

The organization layer must be applied first. This layer reads the organization root ID from the organization layer's remote state.

```bash
# Run this first if you haven't already
cd terraform/global/organization
terraform init && terraform plan && terraform apply
```

---

## Running Terraform

```bash
cd terraform/global/tag-policies

# Download provider, connect to S3 backend, read organization remote state
terraform init

# Review the tag policy JSON — check keys and allowed values
terraform plan

# Create and attach the tag policy to the organization root
terraform apply
```

---

## Tag Policy Defined

One policy — `idk-enterprise-tag-policy` — is attached to the **organization root**, so it applies to all accounts in all OUs automatically.

### Tags with Enforced Values

These tags have a fixed list of allowed values. Any resource tagged with a value outside this list will be reported as non-compliant.

| Tag | Allowed Values | Enforced On |
|---|---|---|
| `Department` | Platform Engineering, AI & Data, Finance, HR, Sales, Marketing, Operations, Security, Customer Support, Research & Development | ec2:instance, ec2:volume, rds:db, rds:cluster, s3:bucket, lambda:function |
| `CostCenter` | CC1001, CC1002, CC1003, CC1004, CC1005, CC1006, CC1007, CC1008, CC1009, CC1010 | ec2:instance, ec2:volume, rds:db, rds:cluster, s3:bucket, lambda:function, elasticloadbalancing:loadbalancer |
| `Environment` | production, uat, development, sandbox, management | ec2:instance, ec2:volume, rds:db, rds:cluster, s3:bucket, lambda:function |
| `ManagedBy` | terraform, ansible, cloudformation, console, bootstrap-script, github-actions | (all resources) |
| `DataClassification` | public, internal, confidential, restricted | s3:bucket, rds:db, rds:cluster, dynamodb:table |
| `Criticality` | critical, high, medium, low | ec2:instance, rds:db, rds:cluster, elasticloadbalancing:loadbalancer |
| `Backup` | required, not-required | ec2:instance, ec2:volume, rds:db, rds:cluster, dynamodb:table |
| `BusinessUnit` | Technology, Finance, Sales, Operations, HR | (all resources) |
| `Compliance` | none, pci-dss, hipaa, sox, gdpr, iso27001 | (all resources) |

### Tags with Free-Form Values

These tags have no restricted value list — any value is valid. The policy only enforces the key name casing.

| Tag | Purpose |
|---|---|
| `Project` | Project name within a cost center — changes frequently, not restricted |
| `Application` | Application name from the enterprise app catalog |
| `Owner` | Team name or email address for accountability and alerting |

---

## Cost Center Reference

| Code | Department |
|---|---|
| CC1001 | Platform Engineering |
| CC1002 | AI & Data |
| CC1003 | Finance |
| CC1004 | HR |
| CC1005 | Sales |
| CC1006 | Marketing |
| CC1007 | Operations |
| CC1008 | Security |
| CC1009 | Customer Support |
| CC1010 | Research & Development |

---

## Checking Compliance

After applying, use AWS Tag Editor to see which resources are non-compliant:

1. Go to **AWS Console → Resource Groups & Tag Editor → Tag Editor**
2. Select region: `ap-south-1`
3. Select resource types you want to audit
4. Filter by tag key — resources missing mandatory tags will appear
5. Or go to **AWS Console → Organizations → Policies → Tag Policies** → select the policy → view compliance report

Non-compliant resources are reported — they are not blocked at this stage. Blocking enforcement is added in Phase 5 via AWS Config rules.

---

## Outputs

After `terraform apply`, these values are written to remote state:

| Output | Description |
|---|---|
| `tag_policy_id` | ID of the enterprise tag policy |
| `tag_policy_arn` | ARN of the enterprise tag policy |
| `tag_policy_attachment_id` | ID of the root-level policy attachment |

---

## Remote State

This layer's state is stored at:
```
s3://idk-tfstate-management-<account-id>/global/tag-policies/terraform.tfstate
```

This layer **reads** from the organization layer:
```
s3://idk-tfstate-management-<account-id>/global/organization/terraform.tfstate
```

The organization root ID is resolved via `terraform_remote_state` — no hardcoded IDs.

---

## After This — Phase 1 Complete

All Phase 1 Terraform is now applied. Your governance foundation is in place:

```
✓ Bootstrap       — S3 state bucket, DynamoDB lock, AWS Organization
✓ Organization    — 7 OUs, 9 member accounts
✓ SCPs            — 5 guardrails covering all OUs
✓ Tag Policies    — 12 mandatory tags enforced org-wide
```

Next: **Phase 2 — IAM Identity Center**
```bash
# Coming in Phase 2
cd terraform/global/identity-center
terraform init && terraform plan && terraform apply
```

---

## File Reference

```
terraform/global/tag-policies/
├── main.tf       # Tag policy definition and root attachment
├── provider.tf   # AWS provider, remote state data source, root ID local
├── versions.tf   # Terraform and provider version pins, S3 backend config
├── outputs.tf    # Tag policy ID and ARN exported to remote state
└── README.md     # This file
```
