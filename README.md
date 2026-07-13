# IDK Digital Solutions — AWS Enterprise Landing Zone
## Project Roadmap & Progress Tracker

**Last updated:** 2026-07-13
**Current phase:** Phase 1 — Complete
**Next action:** Fill in 9 email addresses → run `terraform apply`

---

## Changelog

| Version | Date | Phase | What Changed |
|---|---|---|---|
| v1.0 | 2026-07-13 | Phase 1 complete | Bootstrap, Organization, SCPs, Tag Policies, ADRs, READMEs |

> When you complete a phase, add a row here with the date and a one-line summary of what was built.

---

## Project Overview

A production-grade AWS Enterprise Landing Zone built as a personal learning lab.

| Property | Value |
|---|---|
| Company | IDK Digital Solutions |
| Management Account | `idk-management` |
| Primary Region | `ap-south-1` (Mumbai) |
| Monthly Budget | ₹1,000–₹1,500 |
| IaC Tool | Terraform |

---

## Repository Structure

```
aws-idk-lab/
├── docs/
│   └── decisions/          # Architecture Decision Records (ADRs)
├── scripts/
│   └── bootstrap/          # One-time bootstrap scripts (run before Terraform)
└── terraform/
    └── global/             # Org-wide configs (run from management account)
        ├── organization/   # Phase 1 — OUs and member accounts
        ├── scps/           # Phase 1 — Service Control Policies
        ├── tag-policies/   # Phase 1 — Tag enforcement
        ├── identity-center/ # Phase 2 — SSO (not started)
        ├── finops/          # Phase 6 — Cost management (not started)
        └── backup-policies/ # Phase 7 — Backup automation (not started)
    └── accounts/           # Per-account configs (run from each member account)
        ├── network/        # Phase 3 — VPC, subnets, routing (not started)
        ├── ai-lab/         # Phase 4 — EC2, Docker, AI stack (not started)
        ├── security/       # Phase 5 — GuardDuty, SecurityHub (not started)
        └── log-archive/    # Phase 5 — CloudTrail, centralised logs (not started)
```

---

## AWS Organization

### Accounts (10 total)

| Account | OU | Purpose | Compute |
|---|---|---|---|
| `idk-management` | Root | Terraform, billing, governance | None |
| `idk-log-archive` | Security | Immutable centralised log storage | None |
| `idk-security` | Security | GuardDuty admin, SecurityHub aggregator | None |
| `idk-network` | Infrastructure | Transit Gateway, Route 53, shared VPCs | None |
| `idk-shared-services` | SharedServices | IAM Identity Center, shared tooling | None |
| `idk-production` | Production | Production workloads | None |
| `idk-development` | NonProduction | Feature development | None |
| `idk-uat` | NonProduction | User acceptance testing | None |
| `idk-ai-lab` | Sandbox | Agentic AI platform | **Yes — Phase 4** |
| `idk-finops-lab` | Sandbox | FinOps tooling experimentation | None |

### Organizational Units (7 OUs)

| OU | Accounts | SCP Strictness |
|---|---|---|
| Security | log-archive, security | Highest — logs cannot be modified |
| Infrastructure | network | High — networking changes controlled |
| SharedServices | shared-services | Medium |
| Production | production | High — change management enforced |
| NonProduction | development, uat | Medium |
| Sandbox | ai-lab, finops-lab | Low + cost guardrails |
| Suspended | (none currently) | Deny all — quarantine zone |

---

## Phase Progress

---

### Phase 0 — Bootstrap
**Status: Complete**

One-time setup that must run before any Terraform.

| Task | Status | File |
|---|---|---|
| Python bootstrap script (Windows + Linux) | Done | `scripts/bootstrap/bootstrap.py` |
| Bash bootstrap script (Linux) | Done | `scripts/bootstrap/bootstrap.sh` |
| S3 state bucket created | Done | `idk-tfstate-management-<account-id>` |
| DynamoDB lock table created | Done | `idk-terraform-lock` |
| AWS Organization created | Done | Management console |
| SCP, Tag Policy, Backup Policy types enabled | Done | Management console |
| README for bootstrap | Done | `scripts/bootstrap/README.md` |

---

### Phase 1 — Governance Foundation
**Status: Complete (pending email setup)**

| Task | Status | File |
|---|---|---|
| 7 Organizational Units | Done | `terraform/global/organization/main.tf` |
| 9 member accounts defined | Done | `terraform/global/organization/main.tf` |
| **Fill in 9 account email addresses** | **PENDING** | `terraform/global/organization/main.tf` lines 175, 199, 220, 239, 258, 279, 299, 319, 339 |
| SCP: Deny non-Mumbai regions | Done | `terraform/global/scps/main.tf` |
| SCP: Deny root account actions | Done | `terraform/global/scps/main.tf` |
| SCP: Protect security services | Done | `terraform/global/scps/main.tf` |
| SCP: Sandbox cost guardrails | Done | `terraform/global/scps/main.tf` |
| SCP: Deny all (Suspended OU) | Done | `terraform/global/scps/main.tf` |
| Tag Policy: 12 mandatory tags | Done | `terraform/global/tag-policies/main.tf` |
| ADR-001: No Control Tower | Done | `docs/decisions/ADR-001-no-control-tower.md` |
| ADR-002: IAM Identity Center | Done | `docs/decisions/ADR-002-iam-identity-center.md` |
| ADR-003: Single region | Done | `docs/decisions/ADR-003-single-region.md` |
| README: organization layer | Done | `terraform/global/organization/README.md` |
| README: scps layer | Pending | `terraform/global/scps/README.md` |
| README: tag-policies layer | Pending | `terraform/global/tag-policies/README.md` |

**How to run Phase 1:**
```bash
# Step 1 — fill in emails in organization/main.tf first

# Step 2 — organization (OUs + accounts)
cd terraform/global/organization
terraform init && terraform plan && terraform apply

# Step 3 — SCPs
cd ../scps
terraform init && terraform plan && terraform apply

# Step 4 — tag policies
cd ../tag-policies
terraform init && terraform plan && terraform apply
```

---

### Phase 2 — IAM Identity Center (SSO)
**Status: Not started**

All human access to AWS accounts goes through IAM Identity Center (per ADR-002). No long-lived IAM users.

| Task | Status | Notes |
|---|---|---|
| Enable IAM Identity Center | Pending | Enable in `idk-shared-services` account |
| Create permission sets | Pending | AdministratorAccess, ReadOnlyAccess, BillingAccess, SecurityAudit |
| Create groups | Pending | platform-team, finops-team, security-team, developers |
| Assign groups to accounts | Pending | Each group maps to specific accounts + permission sets |
| Break-glass access design | Pending | Emergency root-equivalent access procedure document |
| Terraform config | Pending | `terraform/global/identity-center/` |
| ADR-004: SSO group design | Pending | `docs/decisions/ADR-004-sso-groups.md` |

---

### Phase 3 — Networking
**Status: Not started**

All compute accounts need VPCs. The `idk-network` account owns shared networking resources.

| Task | Status | Notes |
|---|---|---|
| CIDR plan document | Pending | Supernet: `10.0.0.0/8`, per-account allocations |
| VPC in `idk-network` account | Pending | Public + private subnets, 2 AZs in `ap-south-1` |
| Internet Gateway | Pending | |
| NAT Gateway | Pending | Single AZ only — cost optimisation |
| VPC Endpoints (S3, DynamoDB) | Pending | Avoids NAT Gateway charges for AWS API calls |
| Route Tables | Pending | |
| Security Groups baseline | Pending | |
| NACLs | Pending | |
| Route 53 private hosted zone | Pending | Internal DNS for `idk.internal` |
| Terraform config | Pending | `terraform/accounts/network/vpc/` |
| ADR-005: Networking design | Pending | Single VPC vs shared VPC vs Transit Gateway decision |

---

### Phase 4 — AI Lab
**Status: Not started**

The only account running compute in Phase 1. Ubuntu EC2 for AI/ML development with VS Code Remote SSH.

| Task | Status | Notes |
|---|---|---|
| VPC for `idk-ai-lab` | Pending | Standalone or shared from network account |
| EC2 instance | Pending | Ubuntu 24.04, `t3.small`, 20GB `gp3` |
| Security Group | Pending | SSH (your IP only), HTTPS |
| Key pair | Pending | Ed25519 key for VS Code Remote SSH |
| IAM instance role | Pending | Least privilege — S3 read for artefacts |
| User data script | Pending | Docker, Docker Compose, Python, Git, Terraform, Ansible |
| Application stack | Pending | FastAPI, LangGraph, LangChain, CrewAI, AutoGen, MCP, LiteLLM |
| Data services | Pending | PostgreSQL, Redis, ChromaDB |
| Observability | Pending | Prometheus, Grafana, Nginx |
| Terraform config | Pending | `terraform/accounts/ai-lab/` |
| ADR: instance type choice | Pending | Why `t3.small` — cost vs capability |

---

### Phase 5 — Security Baseline
**Status: Not started**

Enable AWS-native security services across all accounts. Centralise findings in `idk-security`.

| Task | Status | Notes |
|---|---|---|
| Enable GuardDuty org-wide | Pending | Delegated admin to `idk-security` |
| Enable SecurityHub org-wide | Pending | Aggregated in `idk-security` |
| Enable AWS Config org-wide | Pending | Config rules for tag compliance, encryption |
| Organisation CloudTrail | Pending | All accounts → S3 in `idk-log-archive` |
| S3 log archive bucket | Pending | In `idk-log-archive` account, immutable |
| Config rules | Pending | Required tags, encryption at rest, no public S3 |
| Terraform: security account | Pending | `terraform/accounts/security/` |
| Terraform: log archive account | Pending | `terraform/accounts/log-archive/` |

---

### Phase 6 — FinOps
**Status: Not started**

Cost visibility, allocation, budgets, and anomaly detection.

| Task | Status | Notes |
|---|---|---|
| Activate Cost Allocation Tags | Pending | All 12 mandatory tags in management account |
| Cost Explorer hourly granularity | Pending | Additional cost ~$0.01/hour but required for accurate FinOps |
| Org-level budget alert | Pending | Alert at 80% of ₹1,500/month |
| Per-sandbox budget alerts | Pending | `idk-ai-lab` and `idk-finops-lab` have highest risk |
| Anomaly Detection monitors | Pending | Per service — EC2, RDS, S3 |
| Cost and Usage Report (CUR) | Pending | S3 bucket in `idk-finops-lab` |
| Savings Plans strategy doc | Pending | After 1 month of usage data |
| Showback/chargeback design | Pending | Which cost center owns what |
| Executive dashboard design | Pending | Cost by OU, account, and cost center |
| Terraform config | Pending | `terraform/global/finops/` |

---

### Phase 7 — Backup Policies
**Status: Not started**

Automate backups for resources tagged `Backup: required`.

| Task | Status | Notes |
|---|---|---|
| AWS Backup plan | Pending | Daily backup, 30-day retention |
| Backup vault | Pending | In `idk-log-archive` account |
| Backup policy | Pending | Attach to Production and Security OUs |
| Terraform config | Pending | `terraform/global/backup-policies/` |

---

### Ongoing / Cross-Cutting
**Status: Partial**

| Task | Status | Notes |
|---|---|---|
| `.gitignore` | Done | Covers Terraform, AWS creds, Python, secrets |
| `.terraform.lock.hcl` committed | Pending | Needs `terraform init` to generate first |
| CI/CD pipeline | Pending | GitHub Actions: `terraform plan` on PR, `terraform apply` on merge |
| Pre-commit hooks | Pending | `terraform fmt`, `terraform validate`, `tflint` |
| Terraform module extraction | Pending | Once networking + compute patterns repeat — `modules/vpc`, `modules/ec2` |
| ADR-004: SSO group design | Pending | |
| ADR-005: Networking design | Pending | |

---

## Architecture Decisions

| ADR | Title | Status |
|---|---|---|
| [ADR-001](docs/decisions/ADR-001-no-control-tower.md) | No AWS Control Tower | Accepted |
| [ADR-002](docs/decisions/ADR-002-iam-identity-center.md) | IAM Identity Center over IAM Users | Accepted |
| [ADR-003](docs/decisions/ADR-003-single-region.md) | Single Primary Region (ap-south-1) for Phase 1 | Accepted — review at Phase 5 |
| ADR-004 | SSO group and permission set design | Pending — Phase 2 |
| ADR-005 | Networking design (VPC strategy) | Pending — Phase 3 |

---

## Tagging Standards

All resources must carry these 12 tags. The Tag Policy enforces key names and allowed values.

| Tag | Allowed Values | FinOps Use |
|---|---|---|
| `Department` | Platform Engineering, AI & Data, Finance, HR, Sales, Marketing, Operations, Security, Customer Support, Research & Development | Cost by department |
| `CostCenter` | CC1001–CC1010 | Chargeback |
| `Project` | Free-form | Cost by project |
| `Application` | Free-form | Cost by application |
| `Environment` | production, uat, development, sandbox, management | Cost by environment |
| `Owner` | Free-form (team or email) | Accountability |
| `BusinessUnit` | Technology, Finance, Sales, Operations, HR | Executive rollup |
| `ManagedBy` | terraform, ansible, cloudformation, console, bootstrap-script, github-actions | Drift detection |
| `DataClassification` | public, internal, confidential, restricted | Security controls |
| `Compliance` | none, pci-dss, hipaa, sox, gdpr, iso27001 | Audit |
| `Backup` | required, not-required | Backup automation |
| `Criticality` | critical, high, medium, low | Incident response priority |

---

## Remote State Locations

All Terraform state is stored in `idk-tfstate-management-<account-id>` (ap-south-1).

| Layer | State Key |
|---|---|
| Organization | `global/organization/terraform.tfstate` |
| SCPs | `global/scps/terraform.tfstate` |
| Tag Policies | `global/tag-policies/terraform.tfstate` |
| Identity Center | `global/identity-center/terraform.tfstate` *(Phase 2)* |
| FinOps | `global/finops/terraform.tfstate` *(Phase 6)* |
| Backup Policies | `global/backup-policies/terraform.tfstate` *(Phase 7)* |
| Network | `accounts/network/vpc/terraform.tfstate` *(Phase 3)* |
| AI Lab | `accounts/ai-lab/terraform.tfstate` *(Phase 4)* |
| Security | `accounts/security/terraform.tfstate` *(Phase 5)* |
| Log Archive | `accounts/log-archive/terraform.tfstate` *(Phase 5)* |

---

## Quick Reference — Run Order

```
Phase 0:  scripts/bootstrap/bootstrap.py --account-id <your-account-id>

Phase 1:  terraform/global/organization/   → terraform init && plan && apply
          terraform/global/scps/           → terraform init && plan && apply
          terraform/global/tag-policies/   → terraform init && plan && apply

Phase 2:  terraform/global/identity-center/

Phase 3:  terraform/accounts/network/vpc/

Phase 4:  terraform/accounts/ai-lab/

Phase 5:  terraform/accounts/log-archive/
          terraform/accounts/security/

Phase 6:  terraform/global/finops/

Phase 7:  terraform/global/backup-policies/
```

Each layer must be applied in order — later layers read outputs from earlier layers via remote state.
