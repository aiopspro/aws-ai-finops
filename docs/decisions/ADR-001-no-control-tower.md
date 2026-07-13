---
# ADR-001: No AWS Control Tower
**Date**: 2026-07-10
**Status**: Accepted
**Deciders**: Platform Engineering Team

## Context
Building an enterprise AWS Landing Zone requires choosing between AWS Control Tower (managed service) or a custom implementation using AWS Organizations + Terraform.

## Decision
Build the Landing Zone manually using AWS Organizations, Terraform, and custom SCPs — without AWS Control Tower.

## Rationale
- **Learning depth**: Manual implementation exposes every architectural layer that Control Tower abstracts. For career development as an Enterprise Architect, understanding the primitives is essential.
- **Customization**: Control Tower's guardrails are opinionated and partially immutable. Custom SCPs give full control over what is allowed and denied.
- **Cost**: Control Tower itself is free, but Account Factory uses Lambda, SNS, and Step Functions which add cost at scale. For a 10-account lab, this is minimal — but the manual approach has zero overhead.
- **No vendor lock-in**: Knowledge of raw Organizations + SCPs transfers to any AWS environment, including those that predate or exclude Control Tower.

## Consequences
- **Positive**: Full understanding of every governance mechanism. Fully customizable policies. No managed service limitations.
- **Negative**: More upfront implementation work. Account vending is manual (no Account Factory). Guardrail updates require manual Terraform changes.

## Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| AWS Control Tower | Faster setup, built-in guardrails, Account Factory | Opinionated, partial customization, abstracts internals |
| **Custom Org + Terraform** (chosen) | Full control, transferable knowledge, zero overhead | More implementation work |
