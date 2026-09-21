-- Settlement evidence is synchronized through versioned updates/tombstones.
-- Physical deletion is intentionally unavailable to ordinary clients.
revoke delete on table public.brokerage_settlements from authenticated;
