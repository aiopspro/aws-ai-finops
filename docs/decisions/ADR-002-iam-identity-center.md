---
# ADR-002: IAM Users over IAM Identity Center (Revised)
**Date**: 2026-07-22
**Status**: Revised — IAM Identity Center deferred
**Original Date**: 2026-07-10

## Decision
Use per-account IAM users for lab access. IAM Identity Center (SSO) is deferred — it will not be implemented in this lab.

## Rationale
- **Simplicity**: IAM Identity Center requires a SharedServices account with Identity Center enabled, permission sets, assignments, and browser-based `aws sso login` flow. For a personal lab, this is unnecessary overhead.
- **Direct access**: IAM users with access keys allow direct `aws configure --profile` setup — faster to get working, no SSO portal required.
- **Lab scope**: The primary goal is practicing AI platform engineering and FinOps, not identity federation. IAM users are sufficient for cross-account work in a 4-account lab.

## Constraints Accepted
- Access keys are long-lived — rotate them regularly and never commit them to source control.
- No central revocation — if a key is compromised, it must be deleted per-account manually.
- This is acceptable for a personal lab. A production enterprise environment would require Identity Center.

## SCP Impact
The `sso:*`, `sso-directory:*`, and `identitystore:*` action namespaces have been removed from the region restriction SCP's `NotAction` list, as they are no longer needed and `sso-directory` is not a valid SCP action namespace.

## When to Revisit
If this lab is extended to simulate enterprise access patterns or multi-team access, implement IAM Identity Center at that point. The SharedServices OU is already in place to host it.

## Original Rationale (for reference)
The original design favoured Identity Center for short-lived credentials, central revocation, MFA enforcement, and CIS Benchmark compliance. These remain valid enterprise reasons — they are simply deferred for this lab.

