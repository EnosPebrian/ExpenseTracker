# Pilgrim Tracker — Architect Escalations

Use this file only for decisions that cross the architecture escalation boundaries in `docs/AUTONOMOUS_ENGINEERING_PROTOCOL.md`.

Ordinary implementation questions do not belong here.

## Open escalations

None seeded.

## Escalation template

```markdown
### ARCH-YYYYMMDD-NN — Short title

**Work item:**
**State:** BLOCKED_ARCHITECT

**Decision required**
One precise question.

**Why Codex cannot decide autonomously**
Identify the architecture/domain/security boundary.

**Existing repository evidence**
- document / section
- document / section

**Option A**
- behavior
- benefits
- risks

**Option B**
- behavior
- benefits
- risks

**Codex recommendation**
A recommendation is allowed, but Codex must not implement across the boundary before an accepted decision exists.

**Work that can continue independently**
List any safe independent work, or `none`.
```

## Resolved escalations

Move resolved items here with:

- decision;
- date;
- resulting ADR/document update;
- affected work item.
