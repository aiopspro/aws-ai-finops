---
# ADR-006: Three-OU Organization Structure
**Date**: 2026-07-22
**Status**: Accepted
**Deciders**: Platform Engineering Team

## Context
The original design called for 7 OUs: Security, SharedServices, Infrastructure, Production, NonProduction, Sandbox, and Suspended. During implementation, `terraform apply` failed with `InvalidInputException` errors when creating the 5th OU under the root. AWS Organizations enforces a default limit of **4 OUs per parent** for new organizations. Requesting a quota increase requires a support case and takes time.

The lab goal is hands-on practice in AI platform engineering, FinOps, and enterprise governance — not production scale. The structure needed to be simplified to fit within the default quota while still covering the core governance patterns.

## Decision
Reduce the organization structure to **3 OUs** under root, fitting comfortably within the default 4-OU-per-parent limit.

```
Root
├── Security        → idk-log-archive
├── SharedServices  → (empty — Phase 2: IAM Identity Center)
└── NonProduction   → idk-development, idk-uat
```

## Rationale
- **Default quota compliance**: 3 OUs under root leaves one slot free, within the default limit of 4 without needing a support case.
- **Lab goal alignment**: The primary lab accounts (`idk-development` for AI/FinOps, `idk-uat` for validation) both sit in NonProduction. This is sufficient for all Phase 1–6 lab work.
- **Core patterns preserved**: All three enterprise OU archetypes are represented — security/logging isolation (Security), shared platform services (SharedServices), and workload environments (NonProduction). The governance patterns are identical whether there are 3 OUs or 7.
- **Production excluded intentionally**: This is a lab environment. A dedicated Production OU would require real production workloads to be meaningful. It can be added when the quota is increased or if a support case is raised.

## What Was Removed vs Original Design
| OU | Original Plan | Decision |
|----|---------------|----------|
| Security | ✓ Kept | Core — log archive isolation |
| SharedServices | ✓ Kept | Core — Phase 2 identity center |
| NonProduction | ✓ Kept | Core — primary lab accounts |
| Infrastructure | Removed | Not needed for lab scope |
| Production | Removed | No production workloads in lab |
| Sandbox | Merged into NonProduction | `idk-development` serves as sandbox |
| Suspended | Removed | No suspended accounts at this stage |

## SCP Coverage with 3 OUs
All 4 SCPs (region restriction, root protection, security services protection, cost guardrails) are attached to the 3 OUs — governance coverage is complete.

## Consequences
- **Positive**: Fits within default AWS quota. Simpler to manage. Covers all governance patterns needed for lab phases 1–6.
- **Negative**: No dedicated Production OU. Scaling to a real enterprise structure requires quota increase (support case) and Terraform changes to add OUs.

## When to Revisit
If real production workloads are introduced or the AWS Organizations OU quota is increased, add a Production OU for `idk-management` promoted workloads and optionally an Infrastructure OU for network/DNS accounts.

## Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| Request quota increase (7 OUs) | Matches enterprise reference architecture | Requires support case, delays progress |
| **3 OUs** (chosen) | Within default quota, covers all lab patterns | Not a full enterprise OU hierarchy |
| 4 OUs (add Sandbox) | One more slot, more separation | Marginal benefit for lab scope |
