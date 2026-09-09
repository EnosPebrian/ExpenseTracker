# Architecture/Process Decision — Repository-Driven Autonomous Engineering

**Date:** 2026-09-09
**Status:** Accepted

## Decision

Pilgrim Tracker adopts a repository-driven autonomous engineering loop.

The owner will no longer act as the routine messenger between the Lead Architect and Codex after each sprint.

Codex may continuously execute the highest-priority READY engineering item, validate it, document it, commit it, push it, and continue to the next READY item.

## Guardrails

Autonomy does not grant authority to invent:

- product scope;
- accounting semantics;
- persistence identity;
- security boundaries;
- destructive migrations;
- synchronization authority.

Those remain governed by accepted architecture documents and the escalation protocol.

## Consequences

Positive:

- less manual prompt relay;
- reliable continuation after context/session interruptions;
- explicit durable engineering state;
- repeatable validation and Git completion;
- clearer separation between implementation blockers and owner-only gates.

Tradeoff:

- a repository-defined queue and handoff state must be kept accurate;
- an architecture decision still requires an actual architecture-authority response when no existing rule resolves it;
- owner/runtime acceptance remains human.

## Related documents

- `docs/AUTONOMOUS_ENGINEERING_PROTOCOL.md`
- `docs/CODEX_WORK_QUEUE.md`
- `docs/ENGINEERING_HANDOFF.md`
- `docs/ARCHITECT_ESCALATIONS.md`
