# Service Control Policies (SCPs)

> **Run third** — after the organization layer, before Tag Policies.

Service Control Policies are the primary governance guardrail in AWS Organizations. They define the **maximum permissions** any account in an OU can have — regardless of what IAM policies inside that account allow.

---

## How SCPs Work

Think of an SCP as a permission ceiling, not a permission grant.

```
Effective permissions = SCP allows  AND  IAM allows
```

- If an SCP **denies** an action, no IAM policy in that account can allow it — not even the root user
- SCPs do **not grant** permissions on their own — they only restrict what IAM can grant
- The **management account** is never subject to SCPs

---

## Prerequisites

The organization layer must be applied first. This layer reads OU IDs from the organization layer's remote state.

```bash
cd terraform/global/organization
terraform init -backend-config=backend.hcl && terraform plan && terraform apply
```

---

## Setup — Fill In Your Values

**`terraform.tfvars`:**
```hcl
management_account_id = "<your-12-digit-account-id>"
aws_region            = "ap-south-1"
aws_profile           = "idk-management"
```

**`backend.hcl`:**
```hcl
bucket  = "idk-tfstate-management-<your-account-id>"
region  = "ap-south-1"
profile = "idk-management"
```

Both files are gitignored — your account ID never touches source control.

---

## Running Terraform

```bash
cd terraform/global/scps

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

---

## SCPs Implemented (Phase 1)

### SCP 1 — Deny Non-Mumbai Regions
**Attached to:** Security, SharedServices, NonProduction

Blocks all AWS API calls outside `ap-south-1`. Without this, a misconfigured automation or compromised account could spin up resources in other regions — creating unexpected costs and data residency violations.

**Why `NotAction`?** Many AWS services are global (IAM, STS, Route 53, CloudFront, Budgets, Cost Explorer). Blocking all non-Mumbai traffic would break these. `NotAction` exempts global services while blocking all regional services outside Mumbai.

Global services exempted: IAM, STS, Organizations, Billing, Budgets, Cost Explorer, Support, Trusted Advisor, Route 53, CloudFront, WAF, ACM, S3 bucket management, SSO, GuardDuty, SecurityHub, CloudTrail, Config.

---

### SCP 2 — Deny Root Account Actions
**Attached to:** Security, SharedServices, NonProduction

Prevents:
- Creating root access keys (the most dangerous credential in AWS)
- Deleting or creating virtual MFA devices via the root user
- Calling `organizations:LeaveOrganization` — prevents an account from escaping governance controls

---

### SCP 3 — Protect Security Services
**Attached to:** Security, SharedServices, NonProduction

When an account is compromised, the attacker's first move is usually to disable monitoring. This SCP makes that impossible.

Blocks disabling or modifying:
- **GuardDuty** — threat detection
- **CloudTrail** — audit log of all API calls
- **SecurityHub** — centralised security findings
- **AWS Config** — resource configuration tracking
- **Log archive S3 buckets** — `idk-logs-*` and `idk-cloudtrail-*`

---

### SCP 4 — NonProduction Cost Guardrails
**Attached to:** NonProduction only (`idk-development`, `idk-uat`)

Prevents accidental expensive resource creation in lab accounts.

Blocks:
- GPU EC2 instances (`p2`, `p3`, `p4`, `p5`, `g3`, `g4`, `g5`, `g6`) — can cost $2–$30/hour
- High-memory EC2 instances (`x1`, `x2`, `u-*`) and bare metal (`*.metal`)
- Large RDS instances (`db.r5.*`, `db.r6.*`, `db.x1.*`, `db.x2.*`)
- Reserved Instance purchases — 1–3 year financial commitments; only FinOps team should authorise

> **FinOps principle:** Guardrails prevent spend before it happens. Budgets alert after. SCPs are the hard stop — AWS Budgets (Phase 6) adds the soft alert.

---

## SCP Attachment Summary

| SCP | Security | SharedServices | NonProduction |
|---|---|---|---|
| Deny non-Mumbai regions | Yes | Yes | Yes |
| Deny root actions | Yes | Yes | Yes |
| Protect security services | Yes | Yes | Yes |
| NonProduction cost guardrails | — | — | Yes |

---

## Outputs

| Output | Description |
|---|---|
| `scp_ids.deny_non_mumbai_regions` | Policy ID for the region restriction SCP |
| `scp_ids.deny_root_actions` | Policy ID for the root protection SCP |
| `scp_ids.protect_security_services` | Policy ID for the security services SCP |
| `scp_ids.non_production_cost_guardrails` | Policy ID for the cost guardrails SCP |
| `scp_summary` | Human-readable map of each SCP and its attached OUs |

---

## Remote State

```
s3://idk-tfstate-management-<account-id>/global/scps/terraform.tfstate
```

Reads from:
```
s3://idk-tfstate-management-<account-id>/global/organization/terraform.tfstate
```

OU IDs are resolved via `terraform_remote_state` — no hardcoded IDs anywhere.

---

## After This — What to Run Next

```bash
cd ../tag-policies
terraform init -backend-config=backend.hcl && terraform plan && terraform apply
```

---

## File Reference

```
terraform/global/scps/
├── main.tf           # 4 SCP definitions and OU attachments
├── variables.tf      # management_account_id, aws_region, aws_profile
├── provider.tf       # AWS provider, remote state data source, OU ID locals
├── versions.tf       # Terraform and provider version pins, S3 backend config
├── outputs.tf        # SCP IDs and summary
├── terraform.tfvars  # Your values — gitignored, never committed
├── backend.hcl       # S3 backend config — gitignored, never committed
└── README.md         # This file
```
