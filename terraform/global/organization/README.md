# Organization Layer

> **Run second** — after the bootstrap script, before SCPs and Tag Policies.

This Terraform configuration creates the AWS Organization structure: all Organizational Units (OUs), all 9 member accounts, and their OU assignments.

---

## Before You Run — Fill In Your Email Addresses

**This is the only manual step required before `terraform apply`.**

Each AWS account requires a unique email address. Open `main.tf` and replace the placeholder email on every `aws_organizations_account` resource.

**File:** `terraform/global/organization/main.tf`

| Account | OU | Line | Replace this placeholder |
|---|---|---|---|
| `idk-log-archive` | Security | 175 | `aws+idk-log-archive@gmail.com` |
| `idk-security` | Security | 199 | `aws+idk-security@gmail.com` |
| `idk-network` | Infrastructure | 220 | `aws+idk-network@gmail.com` |
| `idk-shared-services` | Shared Services | 239 | `aws+idk-shared-services@gmail.com` |
| `idk-production` | Production | 258 | `aws+idk-production@gmail.com` |
| `idk-development` | Non-Production | 279 | `aws+idk-development@gmail.com` |
| `idk-uat` | Non-Production | 299 | `aws+idk-uat@gmail.com` |
| `idk-ai-lab` | Sandbox | 319 | `aws+idk-ai-lab@gmail.com` |
| `idk-finops-lab` | Sandbox | 339 | `aws+idk-finops-lab@gmail.com` |

The 10th account — `idk-management` — is your existing account (the one you ran the bootstrap script against). It already exists and is not created here.

---

## Choosing Your Email Addresses

Each email must be **globally unique across all of AWS**. No two AWS accounts anywhere in the world can share the same email address.

### Option A — Gmail plus-addressing (recommended for a personal lab)

If your Gmail is `yourname@gmail.com`, AWS treats `yourname+anything@gmail.com` as a unique address — but all emails still arrive in your single inbox. No extra accounts needed.

```
yourname+idk-log-archive@gmail.com
yourname+idk-security@gmail.com
yourname+idk-network@gmail.com
yourname+idk-shared-services@gmail.com
yourname+idk-production@gmail.com
yourname+idk-development@gmail.com
yourname+idk-uat@gmail.com
yourname+idk-ai-lab@gmail.com
yourname+idk-finops-lab@gmail.com
```

### Option B — Your own domain

```
aws+idk-log-archive@idkdigitalsolutions.com
aws+idk-security@idkdigitalsolutions.com
aws+idk-network@idkdigitalsolutions.com
... and so on
```

---

## Critical: Emails Cannot Be Changed After Account Creation

AWS does not allow email changes via API once an account is created. Every `aws_organizations_account` resource has this block for exactly this reason:

```hcl
lifecycle {
  ignore_changes = [email]
}
```

Without it, Terraform would show a diff on every plan and attempt to update the email — which would always fail. With it, Terraform ignores the email field after the initial creation.

**Fill in the correct emails before running `terraform apply` for the first time. You cannot fix this later without deleting the account, which requires a 90-day wait.**

---

## Running Terraform

Ensure the bootstrap script has already completed successfully before proceeding.

```bash
# 1. Initialise — downloads the AWS provider and connects to the S3 backend
terraform init

# 2. Plan — shows exactly what will be created, review carefully
terraform plan

# 3. Apply — creates the OUs and member accounts
terraform apply
```

> Account creation is eventually consistent. AWS may take 2–5 minutes to fully provision each new member account after `terraform apply` completes.

---

## What Gets Created

### Organizational Units (7 OUs)

| OU | Purpose | SCP intent |
|---|---|---|
| `Security` | Log Archive and Security Tooling accounts | Highly restricted — nobody modifies logs or security config |
| `Infrastructure` | Network account (Transit Gateway, DNS) | Networking changes require elevated approval |
| `SharedServices` | IAM Identity Center, shared tooling | Moderate — services consumed by all other accounts |
| `Production` | Production workloads | Strict — no unapproved services, no untagged resources |
| `NonProduction` | Development and UAT | Moderate — region restriction still applies |
| `Sandbox` | AI Lab, FinOps Lab | Permissive within cost guardrails |
| `Suspended` | Quarantined accounts pending closure | Deny all except billing reads |

### Member Accounts (9 accounts)

| Account | OU | Purpose |
|---|---|---|
| `idk-log-archive` | Security | Immutable centralised log storage |
| `idk-security` | Security | GuardDuty admin, SecurityHub aggregator |
| `idk-network` | Infrastructure | Transit Gateway, Route 53, shared VPCs |
| `idk-shared-services` | SharedServices | IAM Identity Center, CodeArtifact |
| `idk-production` | Production | Production workloads |
| `idk-development` | NonProduction | Developer workloads and feature development |
| `idk-uat` | NonProduction | User acceptance testing |
| `idk-ai-lab` | Sandbox | Agentic AI platform — **only account running compute in Phase 1** |
| `idk-finops-lab` | Sandbox | FinOps tooling experimentation |

---

## Outputs

After `terraform apply`, these values are written to remote state and consumed by the SCPs and Tag Policies layers:

| Output | Description |
|---|---|
| `organization_id` | AWS Organization ID |
| `organization_root_id` | Root ID — parent of all top-level OUs |
| `master_account_id` | Management account ID |
| `ou_security_id` | Security OU ID |
| `ou_infrastructure_id` | Infrastructure OU ID |
| `ou_shared_services_id` | Shared Services OU ID |
| `ou_production_id` | Production OU ID |
| `ou_non_production_id` | Non-Production OU ID |
| `ou_sandbox_id` | Sandbox OU ID |
| `ou_suspended_id` | Suspended OU ID |
| `account_ids` | Map of all 9 member account IDs |
| `ai_lab_account_id` | AI Lab account ID (used frequently in Phase 1) |

---

## Remote State

This layer's state is stored at:

```
s3://idk-tfstate-management-<account-id>/global/organization/terraform.tfstate
```

The SCPs and Tag Policies layers read OU IDs from this state via `terraform_remote_state` data sources. Run this layer first before those two.

---

## After This — What to Run Next

```bash
# Apply Service Control Policies
cd ../scps
terraform init && terraform plan && terraform apply

# Apply Tag Policies
cd ../tag-policies
terraform init && terraform plan && terraform apply
```

---

## File Reference

```
terraform/global/organization/
├── main.tf        # OUs and member accounts — edit email addresses here
├── provider.tf    # AWS provider config and default tags
├── versions.tf    # Terraform and provider version pins, S3 backend config
├── outputs.tf     # OU IDs and account IDs exported for downstream layers
└── README.md      # This file
```
