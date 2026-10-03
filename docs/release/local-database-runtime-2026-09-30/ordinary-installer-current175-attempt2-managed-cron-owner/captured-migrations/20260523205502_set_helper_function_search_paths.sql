-- Supabase security advisor 0011: helper/trigger functions should not inherit
-- caller-controlled search_path.

alter function public.mask_phone(text) set search_path = public;
alter function public._admin_row(uuid, text, text, text, text, timestamptz, jsonb) set search_path = public;
alter function public.normalize_slug(text) set search_path = public;
alter function public.touch_updated_at() set search_path = public;
alter function public.generate_public_id() set search_path = public;
alter function public.generate_contribution_code() set search_path = public;
alter function public.prevent_client_admin_escalation() set search_path = public, auth;
alter function public.prevent_ledger_mutation() set search_path = public;
