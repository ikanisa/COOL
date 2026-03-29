-- Align the remaining fan-engagement admin write policy with the app's
-- canonical platform-admin check.

drop policy if exists "Admins can manage polls" on public.rs_match_polls;
create policy "Admins can manage polls"
  on public.rs_match_polls for all
  using (public.is_admin_user())
  with check (public.is_admin_user());
