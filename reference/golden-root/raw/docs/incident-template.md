# INC-YYYY-MM-DD — <short title>

**Status:** Open | Investigating | Resolved
**Severity:** P0 | P1 | P2 | P3
**Incident commander:** @handle
**Date opened:** YYYY-MM-DD HH:MM UTC
**Date resolved:** YYYY-MM-DD HH:MM UTC (leave blank if open)

---

## Summary

One paragraph. What happened, what was affected, and the outcome.

## Timeline

| Time (UTC) | Event |
|-----------|-------|
| HH:MM | First alert fired |
| HH:MM | On-call engineer paged |
| HH:MM | Root cause identified |
| HH:MM | Mitigation applied |
| HH:MM | Service restored |

## Root Cause

Describe the technical root cause. Use the 5-Whys if helpful:

1. Why did X fail? → Because Y
2. Why did Y happen? → Because Z
3. …

## Impact

- **Users affected:** N (estimated)
- **Duration:** HH hours MM minutes
- **Services affected:** list services, endpoints, or features
- **Data loss:** Yes / No / Under investigation

## Action Items

| # | Action | Owner | Due date | Status |
|---|--------|-------|----------|--------|
| 1 | Add circuit breaker to payment service | @handle | YYYY-MM-DD | Open |
| 2 | Add alerting for DB connection pool exhaustion | @handle | YYYY-MM-DD | Open |

## Blameless Statement

This incident review is conducted in the spirit of blameless post-mortems.
Systems fail; our goal is to understand failure modes and improve resilience —
not to assign individual blame. All contributors are encouraged to share
observations candidly.
