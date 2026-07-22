# Lessons Learned — AWS Organization Terraform Setup

> Reference document for issues encountered during Phase 1 bootstrap and organization layer setup.
> Use this before troubleshooting similar problems in future.

---

## 1. Deprecated `dynamodb_table` Parameter in S3 Backend

**What happened:**
`terraform init` produced a deprecation warning on `dynamodb_table = "idk-terraform-lock"` in `versions.tf`.

**Root cause:**
Terraform >= 1.10 introduced native S3 locking (`use_lockfile = true`), which writes a `.tflock` file directly to the state bucket. The DynamoDB-based locking is now deprecated.

**Fix:**
Replace in all `versions.tf` backend blocks:
```hcl
# Remove this
dynamodb_table = "idk-terraform-lock"

# Add this
use_lockfile = true
```

Also delete the DynamoDB table — it is no longer needed and incurs cost.

**Prevention:**
Use `use_lockfile = true` in all new S3 backend configurations. Do not provision a DynamoDB lock table in bootstrap scripts.

---

## 2. Stale S3 Lock File Blocking `terraform apply`

**What happened:**
`terraform apply` failed with `PreconditionFailed 412` and showed a `Lock Info` block with a lock ID.

**Root cause:**
A previous `terraform plan` or `apply` was interrupted (Ctrl+C or session timeout). The `.tflock` file in S3 was not cleaned up automatically.

**Fix:**
```bash
terraform force-unlock <lock-id>
# Example:
terraform force-unlock dd3e1a72-2708-fa42-7c7a-c81b36ee9f38
```

**Prevention:**
Always let Terraform complete naturally. If interrupted, run `force-unlock` before the next apply. Check for stale locks with:
```bash
aws s3 ls s3://<bucket>/global/organization/
```

---

## 3. `InvalidInputException: You provided a value that does not match the required pattern`

**What happened:**
`terraform apply` failed on `aws_organizations_organizational_unit` and `aws_organizations_account` resources with this cryptic error.

**Root cause — OU creation:**
Hit the AWS Organizations default limit of **4 OUs per parent** under the root. When the 5th OU creation was attempted, AWS rejected it with this non-obvious error message.

**Root cause — Account creation:**
The `parent_id` being passed was invalid — either empty or referencing an OU that did not yet exist in AWS (eventual consistency issue) or had been deleted.

**Fix for OU limit:**
Request a quota increase via AWS Service Quotas, or reduce the number of OUs to stay within the limit.

**Fix for invalid parent_id:**
1. Verify the OU actually exists: `aws organizations list-organizational-units-for-parent --parent-id <root-id>`
2. Check Terraform state has the correct ID: `terraform state show aws_organizations_organizational_unit.<name>`
3. If IDs don't match, re-import: `terraform import aws_organizations_organizational_unit.<name> <correct-id>`

**Prevention:**
- Keep OU count at or below 4 per parent for new organizations, or request a quota increase upfront
- Always verify OUs exist in AWS before expecting accounts to be created under them in the same apply

---

## 4. AWS Organizations OU Limit (4 per parent by default)

**What happened:**
Could not create more than 4 OUs under the root. The "Add OU" button in the console was greyed out.

**Root cause:**
New AWS organizations have a default soft limit of **4 OUs per parent container**.

**Fix:**
Request a quota increase:
```bash
aws service-quotas request-service-quota-increase \
  --service-code organizations \
  --quota-code Q-3fzsrq4h \
  --desired-value 10 \
  --profile idk-management \
  --region us-east-1
```

Or reduce the OU count to fit within the limit.

**Decision made:**
Reduced to 3 OUs (Security, SharedServices, NonProduction) which is sufficient for lab goals and stays within the default limit.

---

## 5. Terraform Attempting to Destroy and Recreate Accounts (`forces replacement`)

**What happened:**
`terraform plan` showed `-/+` (destroy and recreate) for all 3 member accounts due to `iam_user_access_to_billing = "ALLOW" # forces replacement`.

**Root cause:**
The accounts were originally created without `iam_user_access_to_billing` set (defaulting to `DENY` in AWS). The updated `main.tf` set it to `ALLOW`. AWS does not allow changing this attribute after account creation — Terraform treats any change as requiring a replacement.

Applying this plan would have attempted to delete the accounts, which AWS blocks for 90 days.

**Fix:**
Add `iam_user_access_to_billing` to `ignore_changes` for all account resources:
```hcl
lifecycle {
  ignore_changes = [email, iam_user_access_to_billing]
}
```

**Prevention:**
Always add both `email` and `iam_user_access_to_billing` to `ignore_changes` on `aws_organizations_account` resources. Neither can be changed via API after account creation.

---

## 6. State Drift — Resources Exist in AWS but Not in Terraform State

**What happened:**
Terraform tried to create OUs and accounts that already existed in AWS, causing failures.

**Root cause:**
`terraform state rm` was run to remove accounts from state during troubleshooting, but the resources still existed in AWS. On the next apply, Terraform tried to create them again.

**Fix:**
Import existing resources back into state:
```bash
terraform import aws_organizations_organizational_unit.security      ou-xxxx-xxxxxxxx
terraform import aws_organizations_account.log_archive               123456789012
```

**Prevention:**
- Never run `terraform state rm` unless you intend to either delete the resource from AWS or re-import it
- After any state manipulation, always run `terraform plan` before `terraform apply` to verify intent
- Keep a record of all resource IDs (OU IDs, account IDs) in a safe place for recovery

---

## 7. AWS Account Deletion Restriction (90-day wait)

**What happened:**
Could not delete member accounts that were accidentally created, even after removing them from Terraform state.

**Root cause:**
AWS requires a 90-day waiting period before an account can be closed. Accounts also cannot be removed from an organization while they have resources or outstanding charges.

**Workaround:**
- Move the account to a `Suspended` OU with a Deny-All SCP to prevent further resource creation
- Accept the account exists and work around it (e.g. repurpose it)

**Prevention:**
- Plan your account structure carefully before running `terraform apply` for the first time
- Use `terraform plan` and review every resource before applying
- Never create accounts experimentally — they are expensive to undo

---

## 8. `outputs.tf` Out of Sync with `main.tf`

**What happened:**
`terraform plan` failed with `Reference to undeclared resource` errors because `outputs.tf` still referenced resources (`ai_lab`, `finops_lab`) that had been removed from `main.tf`.

**Root cause:**
When resources are removed from `main.tf`, `outputs.tf` must be updated in the same commit. The two files were not updated together.

**Fix:**
Remove or update any output that references a deleted resource.

**Prevention:**
When removing a resource from `main.tf`, always grep for its name across all `.tf` files in the same module:
```bash
grep -r "ai_lab" terraform/global/organization/
```

---

## General Lessons

| Lesson | Rule |
|---|---|
| Always run `terraform plan` before `apply` | Review every `+`, `~`, `-/+` symbol carefully |
| `-/+` on an AWS account = danger | AWS accounts cannot be deleted — never apply a destroy on accounts |
| State drift is common | After manual console changes, always re-import or `state rm` to reconcile |
| AWS errors are often misleading | `InvalidInputException: does not match pattern` often means a quota limit, not a literal format error |
| `ignore_changes` is essential for accounts | `email` and `iam_user_access_to_billing` must always be ignored |
| OUs cannot be deleted if non-empty | Move accounts out first, then delete the OU |
| Keep resource IDs documented | OU IDs and account IDs are needed for imports and recovery |
