# Organization Layer

> **Run second** — after the bootstrap script, before SCPs and Tag Policies.

This Terraform configuration manages the AWS Organization structure: Organizational Units (OUs), member accounts, and their OU assignments.

---

## Current Structure

```
Root
├── Security        → idk-log-archive
├── SharedServices  → (empty — account added via Terraform in a future phase)
└── NonProduction   → idk-development, idk-uat
```

### Organizational Units (3 OUs)

| OU | Purpose | SCP Intent |
|---|---|---|
| `Security` | Immutable log archive, future GuardDuty/SecurityHub | Highly restricted — nobody modifies logs or security config |
| `SharedServices` | IAM Identity Center, shared tooling (account added later) | Moderate — services consumed by all other accounts |
| `NonProduction` | Primary AI/FinOps lab + UAT validation | Moderate — region restriction, cost guardrails |

### Member Accounts (3 accounts)

| Account | OU | Lab Purpose |
|---|---|---|
| `idk-log-archive` | Security | Immutable centralised log storage, CloudTrail org trail |
| `idk-development` | NonProduction | **Primary lab account** — AI (Bedrock, SageMaker), FinOps practice |
| `idk-uat` | NonProduction | Pre-production validation, cross-account deployment practice |

> The 4th account — `idk-management` — is your existing management account created during bootstrap. It is not managed here.

---

## Setup — Fill In Your Values

Before running Terraform, fill in two files:

**`terraform.tfvars`** — your AWS account details:
```hcl
management_account_id = "<your-12-digit-account-id>"
aws_region            = "ap-south-1"
aws_profile           = "idk-management"
```

**`backend.hcl`** — your S3 state bucket:
```hcl
bucket  = "idk-tfstate-management-<your-account-id>"
region  = "ap-south-1"
profile = "idk-management"
```

Both files are gitignored — your account ID never touches source control.

---

## Before You Run — Fill In Your Email Addresses

Each AWS account requires a globally unique email. Open `main.tf` and confirm the email on each `aws_organizations_account` resource matches what you used.

**Gmail plus-addressing** is the easiest approach for a personal lab — all emails arrive in one inbox:

```
yourname+idk-log-archive@gmail.com
yourname+idk-development@gmail.com
yourname+idk-uat@gmail.com
```

### Why emails cannot be changed after account creation

AWS does not allow email updates via API once an account exists. Every account resource has:

```hcl
lifecycle {
  ignore_changes = [email, iam_user_access_to_billing]
}
```

`iam_user_access_to_billing` is also ignored because AWS does not allow changing this via API after account creation — attempting to change it forces a destroy/recreate which will fail (accounts cannot be deleted for 90 days).

---

## Brownfield Import — Accounts Already Exist

If you are setting up this repo against an organization that already has these accounts and OUs (e.g. after a fresh `git clone`), import them into state before running `terraform apply`:

```bash
# Import OUs
terraform import aws_organizations_organizational_unit.security      <ou-id>
terraform import aws_organizations_organizational_unit.shared_services <ou-id>
terraform import aws_organizations_organizational_unit.non_production  <ou-id>

# Import accounts
terraform import aws_organizations_account.log_archive  <account-id>
terraform import aws_organizations_account.development  <account-id>
terraform import aws_organizations_account.uat          <account-id>
```

Get the IDs from the AWS console or:

```bash
# List OUs
aws organizations list-organizational-units-for-parent \
  --parent-id <root-id> \
  --profile idk-management \
  --query 'OrganizationalUnits[].{Name:Name,Id:Id}'

# List accounts
aws organizations list-accounts \
  --profile idk-management \
  --query 'Accounts[].{Name:Name,Id:Id}'
```

---

## Running Terraform

```bash
# 1. Initialise — pass backend config so Terraform knows which S3 bucket to use
terraform init -backend-config=backend.hcl

# 2. Plan — review carefully before applying
terraform plan

# 3. Apply
terraform apply
```

> Account creation is eventually consistent. AWS may take 2–5 minutes per account after apply completes.

---

## Outputs

These values are written to remote state and consumed by the SCPs and Tag Policies layers:

| Output | Description |
|---|---|
| `organization_id` | AWS Organization ID |
| `organization_root_id` | Root ID — parent of all top-level OUs |
| `master_account_id` | Management account ID |
| `ou_security_id` | Security OU ID |
| `ou_shared_services_id` | Shared Services OU ID |
| `ou_non_production_id` | Non-Production OU ID |
| `account_ids` | Map of all 3 member account IDs |
| `development_account_id` | Development account ID (primary lab account) |

---

## Remote State

```
s3://idk-tfstate-management-<account-id>/global/organization/terraform.tfstate
```

State locking uses S3 native locking (`use_lockfile = true`) — no DynamoDB table required.

---

## After This — What to Run Next

```bash
cd ../scps
terraform init -backend-config=backend.hcl && terraform plan && terraform apply

cd ../tag-policies
terraform init -backend-config=backend.hcl && terraform plan && terraform apply
```

---

## File Reference

```
terraform/global/organization/
├── main.tf        # OUs and member accounts
├── variables.tf   # management_account_id, aws_region, aws_profile
├── provider.tf    # AWS provider config and default tags
├── versions.tf    # Terraform and provider version pins, S3 backend config
├── outputs.tf     # OU IDs and account IDs exported for downstream layers
├── terraform.tfvars  # Your values — gitignored, never committed
├── backend.hcl       # S3 backend config — gitignored, never committed
└── README.md      # This file
```
