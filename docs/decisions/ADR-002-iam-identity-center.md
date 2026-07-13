---
# ADR-002: IAM Identity Center over IAM Users
**Date**: 2026-07-10
**Status**: Accepted

## Decision
All human access to AWS accounts is via IAM Identity Center (SSO). No long-lived IAM users except the temporary `terraform-bootstrap` user (deleted after Phase 3).

## Rationale
- **No long-lived credentials**: IAM Identity Center issues short-lived session tokens (1–12 hours). A leaked token expires. A leaked IAM access key is valid until manually rotated.
- **Centralized control**: Disable one Identity Center user to revoke access across all 10 accounts simultaneously. With IAM users, you'd need to disable users in each account individually.
- **MFA enforcement**: Identity Center can require MFA at the SSO level — applies universally. With IAM users, MFA is per-user per-account policy.
- **Full audit trail**: All console and CLI actions via Identity Center are logged with the SSO user's identity in CloudTrail. IAM user trails can be harder to correlate across accounts.
- **CIS Benchmark 1.x compliance**: Multiple CIS controls require avoiding long-lived credentials.

## Consequences
- **Positive**: Dramatically reduced credential risk. Single identity plane. Easier access reviews.
- **Negative**: Requires browser-based login for CLI (aws sso login). Slightly more setup complexity upfront.

## Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| IAM Users per account | Simple, no SSO setup | Long-lived keys, no central control, CIS violations |
| External IdP (Okta/Azure AD) | Enterprise SSO, existing identity | Complex setup, licensing cost |
| **IAM Identity Center** (chosen) | AWS-native, free, short-lived creds, central control | Browser login flow for CLI |
