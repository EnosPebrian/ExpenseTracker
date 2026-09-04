# Telegram Security

## Trust boundaries

`telegram-connection` requires a signed-in Supabase user and resolves authority
from `auth.uid()`. `telegram-webhook` has JWT verification disabled only for
that function and compares `X-Telegram-Bot-Api-Secret-Token` against the server
secret before parsing payloads. The bot token and service-role key remain
server-only. Logs and responses must not contain secrets or token-bearing URLs.

Only private chats where numeric `from.id == chat.id` are accepted. Usernames,
names, phone numbers, captions, and supplied book/member IDs are never identity
authority. Groups, supergroups, channels, bot/anonymous senders, and arbitrary
URL messages are ignored.

## Pairing

The app requests a 24-byte cryptographically random, URL-safe token. The
plaintext `/link` command is returned once and held only in UI memory. Postgres
stores only SHA-256 bytes. Tokens expire after ten minutes, are single-use,
and new issuance revokes the previous outstanding token. Pairing attempts are
limited to ten per Telegram identity per hour.

Linking locks and consumes the token atomically, validates the mapped active
membership, and creates one active private identity connection. Disconnect
revokes the connection and pending token without removing membership, Inbox
rows, or financial data. Every attachment revalidates membership; loss of
membership rejects the source and revokes the connection.

## Data and abuse controls

`update_id` is the primary key for delivery idempotency. Events retain only
minimal operational fields and a sanitized error code, never full webhook JSON.
Authenticated clients cannot read tokens or events; connection state is limited
to the owning active member. Source limits are enforced before download and
after download. Magic bytes are authoritative over extension. The gateway
accepts at most 10 attachment events/hour and 50/day/connection before any file
download or extraction call.

The privileged Inbox RPC derives household and member solely from the validated
connection. It enforces null account/final identity and inserts existing
BETA-08G/G1 entities atomically. It has no SQL path to create transactions.
