---
# ADR-005: backend.hcl Pattern for S3 Backend Configuration
**Date**: 2026-07-22
**Status**: Accepted
**Deciders**: Platform Engineering Team

## Context
Terraform S3 backend blocks do not support variable interpolation — you cannot write `bucket = var.state_bucket`. This creates a problem: the bucket name contains the AWS account ID, which must not be committed to source control.

Two options exist:
1. Hardcode the bucket name (including account ID) directly in `versions.tf`
2. Pass backend configuration at `terraform init` time via a separate file

## Decision
Use a `backend.hcl` file (gitignored) passed to `terraform init -backend-config=backend.hcl` to supply the bucket name, region, and profile. Only the static `key`, `use_lockfile`, and `encrypt` values live in the `versions.tf` backend block.

## Rationale
- **Security**: The AWS account ID never touches source control. A public repository cannot reveal account IDs embedded in backend configuration.
- **Portability**: Any developer can clone the repo, create their own `backend.hcl` with their account ID, and run Terraform against their own state bucket. No file modifications needed.
- **Separation of concerns**: Static configuration (state key path, encryption) lives in code. Environment-specific configuration (bucket name, profile) lives in a local file.

## Implementation
**`versions.tf`** (committed):
```hcl
backend "s3" {
  key          = "global/organization/terraform.tfstate"
  use_lockfile = true
  encrypt      = true
}
```

**`backend.hcl`** (gitignored, created locally):
```hcl
bucket  = "idk-tfstate-management-<your-account-id>"
region  = "ap-south-1"
profile = "idk-management"
```

**Run command:**
```bash
terraform init -backend-config=backend.hcl
```

The same pattern applies to `terraform.tfvars` for variable values — the account ID is passed as `management_account_id` and used by the `terraform_remote_state` data source to construct the remote state bucket ARN dynamically.

## Consequences
- **Positive**: No sensitive values in source control. Repo is safe to make public. Works for multiple environments with different account IDs.
- **Negative**: Developers must create `backend.hcl` and `terraform.tfvars` locally before running Terraform. Plain `terraform init` without `-backend-config=backend.hcl` will fail or prompt for values.

## Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| Hardcode account ID in versions.tf | Simpler init command | Account ID in source control — security risk |
| Environment variables | No file to create | Less explicit, harder to document |
| **backend.hcl** (chosen) | Secure, portable, self-documenting | Requires extra file creation step |
