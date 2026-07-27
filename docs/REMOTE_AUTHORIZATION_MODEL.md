# Remote Authorization Model

## Identity boundaries

Pilgrim Tracker keeps four separate concepts:

- `LocalProfile`: device preferences and local onboarding state.
- `HouseholdMember`: a person represented inside a local financial book.
- Supabase Auth user: a remotely verified application identity.
- `book_memberships`: authorization joining an Auth user to a remote book.

Selecting an active local member does not authenticate that person. Signing in
does not claim a book. The authenticated user receives access only through an
active remote membership.

## Authorization boundary

Every application-owned Supabase table has RLS enabled. Access follows:

```text
auth.uid() -> active book_membership -> permitted book_id -> permitted rows
```

Active members can read and write financial mirror rows in their own books.
Only active owners manage books, memberships, and invitations. Policies deny
anonymous and cross-book access, and triggers prevent moving an existing
financial row to another book. A trigger prevents deleting or demoting the
final active owner.

## Linking and invitations

`link_local_household` creates the remote book with the same UUID as the local
book and creates the caller's owner membership. It is idempotent and rejects a
book UUID already controlled by an unrelated owner. The returned link instant
and Auth-user mapping are persisted locally without transferring finance.

The `create-book-invitation` Edge Function validates the caller JWT, delegates
authorization and idempotent invitation creation to
`create_book_invitation`, and uses a server-only credential only for Auth email
delivery. Registered users can discover an existing pending invitation after
sign-in. `accept_book_invitation` derives identity and verified email from the
JWT, rejects mismatches or inactive invitations, and creates at most one active
membership.

## BETA-04 boundary

The remote `accounts`, `categories`, `projects`, `transactions`, and
`asset_definitions` tables plus `app_changes.sequence` establish the server
contract for BETA-04. BETA-03 does not upload, download, merge, or reconcile
any financial record. Continue using one primary device.
