# Service Control Policies (SCPs)

> **Run third** — after the organization layer, before Tag Policies.

Service Control Policies are the primary governance guardrail in AWS Organizations. They define the **maximum permissions** any account in an OU can have — regardless of what IAM policies inside that account allow.

---

## How SCPs Work

Think of an SCP as a permission ceiling, not a permission grant.

```
Effective permissions = SCP allows  AND  IAM allows
```

- If an SCP **denies** an action, no IAM policy in that account can allow it — not even the account's root user
- SCPs do **not grant** permissions on their own — they only restrict what IAM can grant
- The **management account** is never subject to SCPs — it is always exempt

**Evaluation order:**
1. An explicit `Deny` in any SCP always wins
2. For `Allow`: the action must be permitted by both the SCP and the IAM policy

---

## Prerequisites

The organization layer must be applied first. This layer reads OU IDs from the organization layer's remote state — it will fail if that state does not exist yet.

```bash
# Run this first if you haven't already
cd terraform/global/organization
terraform init && terraform plan && terraform apply
```

---

## Running Terraform

```bash
cd terraform/global/scps

# Download provider, connect to S3 backend, read organization remote state
terraform init

# Review what will be created — check SCP JSON and attachments carefully
terraform plan

# Create SCPs and attach to OUs
terraform apply
```

---

## SCPs Implemented (Phase 1)

### SCP 1 — Deny Non-Mumbai Regions
**Attached to:** Security, Infrastructure, SharedServices, Production, NonProduction, Sandbox

Blocks all AWS API calls outside `ap-south-1`. Without this, a misconfigured automation or compromised account could accidentally spin up resources in other regions — creating unexpected costs and potential data residency violations.

**Why `NotAction` instead of blocking all?**
Many AWS services are global and have no region in their API calls — IAM, STS, Route 53, CloudFront, Budgets, Cost Explorer. Blocking all non-Mumbai traffic would break these. The `NotAction` pattern exempts global services while still blocking all regional services outside Mumbai.

Global services exempted: IAM, STS, Organizations, Billing, Budgets, Cost Explorer, Support, Trusted Advisor, Route 53, CloudFront, WAF, ACM, S3 bucket management, SSO, GuardDuty, SecurityHub, CloudTrail, Config.

---

### SCP 2 — Deny Root Account Actions
**Attached to:** Security, Infrastructure, SharedServices, Production, NonProduction, Sandbox

Prevents:
- Creating root access keys (long-lived root credentials are the most dangerous credential in AWS)
- Deleting or creating virtual MFA devices via the root user

Also includes `DenyLeavingOrganization` — prevents any account from calling `organizations:LeaveOrganization`, which would remove it from governance controls entirely.

---

### SCP 3 — Protect Security Services
**Attached to:** Security, Infrastructure, SharedServices, Production, NonProduction, Sandbox

When an account is compromised, the attacker's first move is usually to disable monitoring. This SCP makes that impossible.

Blocks disabling or modifying:
- **GuardDuty** — threat detection
- **CloudTrail** — audit log of all API calls
- **SecurityHub** — centralised security findings
- **AWS Config** — resource configuration tracking
- **Log archive S3 buckets** — `idk-logs-*` and `idk-cloudtrail-*` bucket policies and lifecycle rules

---

### SCP 4 — Sandbox Cost Guardrails
**Attached to:** Sandbox only (`idk-ai-lab`, `idk-finops-lab`)

Prevents accidental expensive resource creation in lab accounts.

Blocks:
- GPU EC2 instances (`p2`, `p3`, `p4`, `p5`, `g3`, `g4`, `g5`, `g6`) — can cost $2–$30/hour
- High-memory EC2 instances (`x1`, `x2`, `u-*`)
- Bare metal instances (`*.metal`)
- Large RDS instances (`db.r5.*`, `db.r6.*`, `db.x1.*`, `db.x2.*`)
- Reserved Instance purchases — RI commitments are 1–3 year contracts worth thousands; only the FinOps team should authorise these

> **FinOps principle:** Guardrails prevent spend before it happens. Budgets alert after. Both are needed — this SCP is the hard stop; AWS Budgets (Phase 6) is the soft alert.

---

### SCP 5 — Deny All (Suspended OU)
**Attached to:** Suspended OU only

Accounts in the Suspended OU are quarantined or pending closure. This SCP denies everything except billing reads, so no new resources can be created and no costs can be incurred while the account awaits the 90-day AWS deletion process.

Allowed exceptions: `aws-portal:View*`, `budgets:View*`, `ce:Get*`, `ce:List*`, `organizations:Describe*`, `organizations:List*`

---

## SCP Attachment Summary

| SCP | Security | Infrastructure | SharedServices | Production | NonProduction | Sandbox | Suspended |
|---|---|---|---|---|---|---|---|
| Deny non-Mumbai regions | Yes | Yes | Yes | Yes | Yes | Yes | — |
| Deny root actions | Yes | Yes | Yes | Yes | Yes | Yes | — |
| Protect security services | Yes | Yes | Yes | Yes | Yes | Yes | — |
| Sandbox cost guardrails | — | — | — | — | — | Yes | — |
| Deny all | — | — | — | — | — | — | Yes |

**Why is Suspended excluded from the first three SCPs?**
The deny-all SCP already covers Suspended with a stricter policy. Stacking the other SCPs on top would be redundant and adds unnecessary policy complexity.

---

## Outputs

After `terraform apply`, these values are written to remote state:

| Output | Description |
|---|---|
| `scp_ids.deny_non_mumbai_regions` | Policy ID for the region restriction SCP |
| `scp_ids.deny_root_actions` | Policy ID for the root protection SCP |
| `scp_ids.protect_security_services` | Policy ID for the security services SCP |
| `scp_ids.sandbox_cost_guardrails` | Policy ID for the sandbox cost SCP |
| `scp_ids.deny_all_suspended` | Policy ID for the suspended deny-all SCP |
| `scp_summary` | Human-readable map of each SCP and its attached OUs |

---

## Remote State

This layer's state is stored at:
```
s3://idk-tfstate-management-<account-id>/global/scps/terraform.tfstate
```

This layer **reads** from the organization layer:
```
s3://idk-tfstate-management-<account-id>/global/organization/terraform.tfstate
```

OU IDs are resolved via `terraform_remote_state` — no hardcoded IDs anywhere.

---

## After This — What to Run Next

```bash
cd ../tag-policies
terraform init && terraform plan && terraform apply
```

---

## File Reference

```
terraform/global/scps/
├── main.tf       # All 5 SCP definitions and OU attachments
├── provider.tf   # AWS provider, remote state data source, OU ID locals
├── versions.tf   # Terraform and provider version pins, S3 backend config
├── outputs.tf    # SCP IDs and summary exported to remote state
└── README.md     # This file
```
