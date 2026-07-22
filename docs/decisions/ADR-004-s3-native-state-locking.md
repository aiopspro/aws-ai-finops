---
# ADR-004: S3 Native State Locking over DynamoDB
**Date**: 2026-07-22
**Status**: Accepted
**Deciders**: Platform Engineering Team

## Context
Terraform requires a state locking mechanism to prevent concurrent applies from corrupting state. The traditional AWS pattern uses a DynamoDB table alongside the S3 state bucket. AWS added native S3 locking support in Terraform AWS provider v5.x via `use_lockfile = true`.

## Decision
Use S3 native state locking (`use_lockfile = true`) instead of a DynamoDB table.

## Rationale
- **Fewer resources**: Eliminates a DynamoDB table that exists purely as infrastructure overhead with no business value.
- **Simpler bootstrap**: The bootstrap script only needs to create one resource (S3 bucket) instead of two. Less to go wrong, less to maintain.
- **Cost**: DynamoDB on-demand pricing adds a small but non-zero cost for read/write capacity on every `terraform plan` and `terraform apply`. S3 native locking has no additional cost beyond the S3 bucket already required.
- **Provider parity**: As of AWS provider v5.x, S3 native locking is the recommended approach. The `dynamodb_table` parameter is deprecated and will be removed in a future major version.

## Implementation
All three Terraform backend blocks use:
```hcl
backend "s3" {
  key          = "global/<layer>/terraform.tfstate"
  use_lockfile = true
  encrypt      = true
}
```
Bucket, region, and profile are supplied at `terraform init` time via `backend.hcl` (see ADR-005).

## Consequences
- **Positive**: Simpler architecture, no DynamoDB cost, aligned with current AWS provider recommendations.
- **Negative**: Requires Terraform AWS provider v5.x or later. Older provider versions must use DynamoDB.

## Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| DynamoDB table | Widely documented, supported in all provider versions | Additional resource, small cost, deprecated |
| **S3 native locking** (chosen) | No extra resource, no cost, provider-recommended | Requires provider v5.x+ |
| No locking | Zero setup | Unsafe — concurrent applies corrupt state |
