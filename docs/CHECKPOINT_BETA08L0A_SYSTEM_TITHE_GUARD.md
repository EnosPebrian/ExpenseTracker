# BETA-08L0A System Tithe Server Guard

Date: 2026-09-08

Verdict: **PASS**. The mixed-client server invariant is deployed to the private
hosted project. BETA-08L client and payment-tracker work has not begun.

## Frozen identity and invariant

System Tithe identity is exactly:

```text
UUIDv5(book_id, "system-category:tithe")
```

The PostgreSQL helper delegates to the already-installed
`extensions.uuid_generate_v5(uuid,text)` implementation. Fixed vectors match
the standard/Dart-compatible UUIDv5 outputs:

| Book UUID | Canonical category UUID |
| --- | --- |
| `00000000-0000-0000-0000-000000000000` | `974e8a60-8e63-5615-a4fd-b8acb4ecfec5` |
| `11111111-1111-1111-1111-111111111111` | `2a753de7-0888-5d83-ab12-de274b13c6f0` |
| `a2000000-0000-0000-0000-000000000001` | `2daf63af-1d0b-539b-be96-174948bb8ed0` |

Only this identity is protected. A random-ID custom category named `Tithe`
remains ordinary and editable/deletable.

A valid canonical row must have name `Tithe`, stored category type `expense`,
and `deleted_at IS NULL`. The `BEFORE INSERT OR UPDATE OR DELETE` trigger:

- rejects malformed canonical inserts;
- rejects canonical ID, household, name, type, soft-delete, and hard-delete
  changes;
- rejects changing an ordinary row into the canonical identity;
- allows metadata-only updates such as version, device, and timestamp changes;
- applies to direct writes, normal sync, conflict resolution, initial upload,
  old clients, and ordinary service-role application writes.

The helper and trigger function are `SECURITY INVOKER`, use a fixed empty
search path, and are not directly executable by `PUBLIC`, `anon`, or
`authenticated`. Category RLS and all four existing policies are unchanged.

## Migration and data preservation

- Migration:
  `20260907233238_beta08l0a_system_tithe_category_guard.sql`
- Hosted project: `jylclfebdeaywfdwabph`
- Dry run: exactly the one BETA-08L0A migration pending.
- Push: PASS.
- Final hosted history includes `20260907233238`.
- No tables, columns, category rows, or other business rows were created or
  rewritten.
- Pre/post counts: users 2, books 1, memberships 2, accounts 3, categories 6,
  transactions 27, budgets 8.

SQLite remains **26** and encrypted backup remains **v5**.

## Recovery point

The pre-push logical recovery point is outside the repository:

`C:\Users\enosp\PilgrimTrackerBackups\pre-beta08l0a-20260908-064543`

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `roles.sql` | 431 | `0DECD601FAA70260A3A31E8CE63208CC4A4C1F99921BC6F3ED4FAF1CD980DA3A` |
| `schema.sql` | 163197 | `5D462BC0103A9FDDDD387B7E773A49A97146C4645D51E74D363B3C189BE6AE5E` |
| `data.sql` | 133957 | `8ED0D3657A1926A403392B7F09E03E5667A55ADC87623B6BD03DCE69B4F24710` |
| `history_schema.sql` | 887 | `18B99FBBB3EC9FBB964BB255A56171329ACD99B6977ECE2ADDD89FDF5AA5105B` |
| `history_data.sql` | 148847 | `1458C7D57C4430EF9A6F884A7DB2957FF505A2F7A4006539D38B0DA020FC85BF` |

All five files are present, readable, and non-empty. No credentials or data
contents are recorded here.

## Verification

- Focused pgTAP: 43/43 PASS.
- Fresh `supabase db reset`: PASS through BETA-08L0A.
- Complete pgTAP: 267/267 PASS across 13 files.
- Direct/authenticated malformed writes: rejected.
- Normal sync rename/type/soft-delete/delete mutations: `validation_error`
  with no processed operation persisted.
- Conflict mutation: `validationError` with no processed operation persisted.
- Initial-snapshot malformed canonical insert: rejected.
- Ordinary category insert/update/delete: PASS.
- Hosted helper, trigger, invoker/search-path posture, ACL, RLS, policy count,
  vectors, migration history, and entity counts: PASS.
- Hosted security advisor: no new BETA-08L0A warning; only pre-existing notices
  remain.
- `git diff --check`: PASS; only line-ending conversion warnings were emitted.

Flutter tests, analyzer, and builds were intentionally not rerun because this
milestone changes no Dart or product behavior.

## Scope

No System Tithe category was created. No `SystemCategoryIds`, Tithe page,
payment tracking, CSV, investments, Edge Function, or secret configuration was
implemented. BETA-08L may resume with its server prerequisite in place.

Git finalization is blocked by the pre-existing dirty BETA-08E/F0/G/G1/H/L0/
H1A1 implementation and overlapping documentation. In particular, the hosted
predecessor migration is still untracked, so an L0A-only commit would publish
an incomplete migration chain, while a broad commit would bundle unrelated
work. Nothing was staged, committed, reset, discarded, or pushed.
