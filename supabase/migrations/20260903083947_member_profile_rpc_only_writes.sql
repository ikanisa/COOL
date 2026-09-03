begin;

-- Member payment-route changes must pass through
-- update_current_member_profile(). That RPC validates the country/provider
-- pairing, derives the canonical phone hash, clears the inactive rail and
-- writes the required audit event. Legacy column grants allowed an own-row
-- REST or GraphQL update to bypass those invariants.
--
-- Reject a hash that was changed before this cutover and permanently bind
-- every non-null hash to its normalized Rwanda MoMo number. Validation occurs
-- before privileges are revoked, so inconsistent production data aborts the
-- entire transaction instead of being silently trusted or partly migrated.
alter table public.profiles
  add constraint profiles_momo_number_hash_matches check (
    momo_number_hash is null
    or (
      momo_number ~ '^07[2389][0-9]{7}$'
      and momo_number_hash = encode(
        extensions.digest('+250' || substr(momo_number, 2), 'sha256'),
        'hex'
      )
    )
    or (
      momo_number ~ '^\\+2507[2389][0-9]{7}$'
      and momo_number_hash = encode(
        extensions.digest(momo_number, 'sha256'),
        'hex'
      )
    )
  ) not valid;

alter table public.profiles
  validate constraint profiles_momo_number_hash_matches;

-- Table-level and column-level privileges are independent in PostgreSQL, so
-- revoke both forms explicitly. Service-role and function-owner privileges are
-- not changed. The own-row RLS policy remains as defense in depth.
revoke update on table public.profiles from public, anon, authenticated;
revoke update (
  momo_number,
  momo_number_hash,
  momo_pay_code,
  updated_at
) on table public.profiles from public, anon, authenticated;

comment on function public.update_current_member_profile(text, text, text, text, text) is
  'Member-facing profile payment-route edit endpoint. Validates and canonicalizes the selected rail, derives dependent fields, and records an audit event.';

commit;
