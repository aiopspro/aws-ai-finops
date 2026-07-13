---
# ADR-003: Single Primary Region (ap-south-1) for Phase 1
**Date**: 2026-07-10
**Status**: Accepted — reviewed at Phase 5

## Decision
All workloads deploy exclusively to ap-south-1 (Mumbai) in Phase 1. A region restriction SCP enforces this. Multi-region architecture is deferred to a later phase.

## Rationale
- **Cost**: Running NAT Gateways, VPC infrastructure, or any persistent services in multiple regions doubles baseline costs. For a ₹1,500/month budget, single-region is the only viable option.
- **Complexity**: Multi-region adds inter-region routing, data replication, failover automation, and DNS complexity. Mastering single-region fundamentals first is the correct learning sequence.
- **Data residency**: ap-south-1 is appropriate for India-based workloads. Keeping everything in Mumbai is a correct default for a company building Indian AI/Tech services.
- **SCP enforcement**: The region restriction SCP ensures this decision is technically enforced, not just policy — accidental resource creation in other regions is blocked.

## Consequences
- **Positive**: Simplified architecture, controlled costs, clear learning scope.
- **Negative**: No geographic redundancy. Single region failure = full outage. Acceptable for a lab.

## When to Revisit
Phase 5+ — when introducing DR strategy, global applications, or if budget increases.
Multi-region would add ap-southeast-1 (Singapore) as the secondary region for Mumbai.
