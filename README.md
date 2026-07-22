# IDK Digital Solutions — AWS Learning Landing Zone

## Purpose

This repository is a personal AWS learning lab built with Terraform. It applies enterprise landing-zone practices at a deliberately small scale: separate AWS accounts, organization-wide guardrails, consistent tagging, centralized logging, and cost controls.

The lab is designed for hands-on AI platform engineering and FinOps practice in `ap-south-1` (Mumbai), while keeping the account structure and monthly spend manageable.

| Property | Value |
|---|---|
| Management account | `idk-management` |
| Primary region | `ap-south-1` (Mumbai) |
| IaC | Terraform >= 1.6, AWS provider ~> 5.0 |
| State | Hardened S3 bucket with native S3 lock files |
| Access model | Per-account IAM users and least-privilege roles |
| Budget target | ₹1,000–₹1,500/month |

> This is a lab, not a production reference implementation. In particular, it intentionally uses IAM users rather than IAM Identity Center. See [ADR-002](docs/decisions/ADR-002-iam-identity-center.md).

## Current Architecture

The Terraform source of truth defines three Organizational Units (OUs) and three member accounts.

```text
AWS Organization (idk-management)
├── Security
│   └── idk-log-archive      Centralized CloudTrail and security logs
├── SharedServices
│   └── (empty for now)      Reserved for future shared tooling
└── NonProduction
    ├── idk-development      Primary AI and FinOps experimentation account
    └── idk-uat              Separate account for deployment validation
```

The management account is used only for Terraform, organization governance, and billing. Workloads should run in member accounts, primarily `idk-development`.

## What Is Implemented

### Phase 0 — Bootstrap

`scripts/bootstrap/` contains idempotent Python and Bash bootstrap scripts. They create the prerequisite infrastructure that Terraform cannot create before its own remote backend exists:

- Hardened S3 state bucket: versioning, AES-256 encryption, public-access block, and a 90-day noncurrent-version lifecycle rule.
- AWS Organization with all features enabled.
- Service Control Policy, Tag Policy, and Backup Policy types enabled.
- Native S3 state locking (`use_lockfile = true`); no DynamoDB lock table is required.

### Phase 1 — Governance Foundation

The three Terraform configurations under `terraform/global/` provide the current governance layer:

| Configuration | Responsibility |
|---|---|
| `organization/` | Creates the three OUs and three member accounts. |
| `scps/` | Attaches organization guardrails to OUs. |
| `tag-policies/` | Defines and attaches the enterprise tag policy to the organization root. |

The SCPs provide a permission ceiling; they do not grant access. They currently:

- Deny regional AWS actions outside Mumbai, with necessary global-service exceptions.
- Deny selected root-user actions and prevent member accounts leaving the organization.
- Protect GuardDuty, CloudTrail, Security Hub, AWS Config, and log-archive buckets from destructive changes.
- Prevent expensive GPU, high-memory, bare-metal EC2, and large RDS classes in `NonProduction`.

The tag policy standardizes 12 tags. It reports tag-policy noncompliance, but does not block resource creation; blocking/remediation belongs in the planned security phase.

## Deployment Status and Immediate Next Step

The Terraform code for Phase 1 is present. Before the first apply, replace the three placeholder email addresses in `terraform/global/organization/main.tf` with globally unique email addresses. Gmail plus-addresses are convenient for a personal lab.

Then create local, gitignored configuration files for each Terraform layer:

```hcl
# terraform.tfvars
management_account_id = "123456789012"
aws_region            = "ap-south-1"
aws_profile           = "idk-management"
```

```hcl
# backend.hcl
bucket  = "idk-tfstate-management-123456789012"
region  = "ap-south-1"
profile = "idk-management"
```

Run the layers in this order and review every plan before applying:

```powershell
# One time: creates state storage and the AWS Organization
python scripts/bootstrap/bootstrap.py --account-id 123456789012

cd terraform/global/organization
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

cd ../scps
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

cd ../tag-policies
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

If the OUs or member accounts already exist, import them before applying. See the [organization README](terraform/global/organization/README.md) for import commands.

## Complete Forward Plan

Future phases are intentionally scoped to the three-account lab. Each phase should be implemented only after the previous phase is stable and its Terraform plan has been reviewed.

| Phase | Outcome | Planned implementation |
|---|---|---|
| 2 — Lab IAM access | Secure usable access without IAM Identity Center. | Create a named administrator IAM user in each account, require MFA, avoid root use, create cross-account roles where needed, document CLI profiles, and rotate/remove access keys. A future `terraform/global/iam-access/` configuration can manage policies, users, groups, and roles. |
| 3 — Development networking | A low-cost network for experiments. | Create a VPC in `idk-development`, two AZ subnets, Internet Gateway, route tables, restrictive security groups, and S3/DynamoDB gateway endpoints. Prefer no NAT Gateway unless a workload proves it is necessary. Document the CIDR allocation and use `terraform/accounts/development/network/`. |
| 4 — AI lab workload | A small, disposable AI development environment. | Deploy a cost-capped EC2 instance (start with `t3.small`, 20 GB `gp3`), an instance role with least privilege, SSM Session Manager access, and Docker/Python tooling. Use `idk-development`; do not create a separate AI account. Stop or terminate resources when idle. |
| 5 — Logging and security baseline | Centralized audit records and basic detective controls. | Create immutable log storage in `idk-log-archive`, an organization CloudTrail, GuardDuty, Security Hub, AWS Config, and a small set of rules for public S3, encryption, and required tags. Delegate administration only if the benefits justify the additional lab complexity. |
| 6 — FinOps | Spend visibility and guardrails. | Activate cost-allocation tags, create a ₹1,500 monthly organization budget with alerts at 50%, 80%, and 100%, add a development-account budget, configure anomaly detection for EC2/RDS/S3, and document a monthly cost-review routine. Use `terraform/global/finops/`. |
| 7 — Backups | Backup only resources that need it. | Create an AWS Backup plan and vault for resources tagged `Backup = required`, with daily backups and 30-day retention. Start with development resources and log storage where applicable. Use `terraform/global/backup-policies/`. |
| 8 — Delivery quality | Repeatable, safe infrastructure changes. | Commit `.terraform.lock.hcl`, add `terraform fmt -check` and `terraform validate` to CI, run `terraform plan` on pull requests, require manual approval for applies, and add `tflint` when the configurations grow. |

## IAM-User Rules for This Lab

- Do not use the AWS root user for normal work; enable root MFA and keep recovery details secure.
- Use separate named IAM users per account, with MFA enabled.
- Grant only the permissions needed for the exercise; use roles instead of duplicating broad permissions where practical.
- Store access keys only in the local AWS credentials file or a secure secret manager—never in this repository, Terraform variables, shell history, or source code.
- Prefer short-lived workflows such as AWS CloudShell or IAM roles when they fit the experiment, even though Identity Center is out of scope.
- Rotate and delete unused access keys after each lab activity.

## Tagging Standard

All resources should include these tags. The existing organization tag policy standardizes their spelling and, for selected tags, permitted values.

| Tag | Purpose |
|---|---|
| `Department`, `BusinessUnit`, `CostCenter` | Cost allocation and reporting |
| `Project`, `Application`, `Environment`, `Owner` | Ownership and workload context |
| `ManagedBy` | Identifies Terraform, console, or other management paths |
| `DataClassification`, `Compliance`, `Criticality` | Security and operational context |
| `Backup` | Drives planned backup selection |

## Remote State Keys

All state is stored in `idk-tfstate-management-<account-id>` in `ap-south-1`.

| Layer | State key |
|---|---|
| Organization | `global/organization/terraform.tfstate` |
| SCPs | `global/scps/terraform.tfstate` |
| Tag policies | `global/tag-policies/terraform.tfstate` |
| Lab IAM access (planned) | `global/iam-access/terraform.tfstate` |
| Development network (planned) | `accounts/development/network/terraform.tfstate` |
| AI lab workload (planned) | `accounts/development/ai-lab/terraform.tfstate` |
| Log archive/security (planned) | `accounts/log-archive/security/terraform.tfstate` |
| FinOps (planned) | `global/finops/terraform.tfstate` |
| Backup policies (planned) | `global/backup-policies/terraform.tfstate` |

## Architecture Decisions

| ADR | Decision | Status |
|---|---|---|
| [ADR-001](docs/decisions/ADR-001-no-control-tower.md) | Do not use AWS Control Tower. | Accepted |
| [ADR-002](docs/decisions/ADR-002-iam-identity-center.md) | Use IAM users for this lab; defer IAM Identity Center. | Revised |
| [ADR-003](docs/decisions/ADR-003-single-region.md) | Use `ap-south-1` as the primary region. | Accepted |
| ADR-004 (planned) | Low-cost development-network design. | Planned |
| ADR-005 (planned) | IAM-user and cross-account role operating model. | Planned |

## Repository Layout

```text
docs/
  decisions/                 Architecture Decision Records
  lessons_learned.md         Issues and recovery guidance from Phase 1
scripts/bootstrap/           One-time S3 state and Organization bootstrap
terraform/global/
  organization/              OUs and member accounts
  scps/                      Service Control Policies
  tag-policies/              Organization tag policy
  iam-access/                Planned lab IAM access configuration
  finops/                    Planned budgets and cost controls
  backup-policies/           Planned AWS Backup policies
terraform/accounts/
  development/network/       Planned VPC and baseline networking
  development/ai-lab/        Planned AI workload
  log-archive/security/      Planned centralized logging and security
```

## Safety Notes

- Never apply an account replacement or destruction plan. AWS account closure is slow and difficult to reverse.
- Run `terraform plan` before every apply and investigate any unexpected `-/+` output.
- Terraform state can contain sensitive values. Keep it in the encrypted S3 backend and keep local state/plan files out of Git.
- See [lessons learned](docs/lessons_learned.md) for known AWS Organizations and Terraform pitfalls.
