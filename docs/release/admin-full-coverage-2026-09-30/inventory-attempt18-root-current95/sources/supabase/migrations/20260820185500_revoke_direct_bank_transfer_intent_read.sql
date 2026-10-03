-- Keep member reads on the owner-bound RPC only. The table policy remains as
-- defense in depth, but authenticated callers must not receive a direct table
-- grant that bypasses the governed API surface.
revoke select on public.bank_transfer_intents from authenticated;
