-- Align fan-engagement and home-banner admin policies with the app's
-- canonical platform-admin check, and repair the seeded legacy banner route.

drop policy if exists "Admins can manage predictions" on public.rs_match_predictions;
create policy "Admins can manage predictions"
  on public.rs_match_predictions for all
  using (public.is_admin_user())
  with check (public.is_admin_user());

drop policy if exists "Admins can manage commentary" on public.rs_match_commentary;
create policy "Admins can manage commentary"
  on public.rs_match_commentary for all
  using (public.is_admin_user())
  with check (public.is_admin_user());

drop policy if exists "Admins can manage home banners" on public.rs_home_banners;
create policy "Admins can manage home banners"
  on public.rs_home_banners for all
  using (public.is_admin_user())
  with check (public.is_admin_user());

update public.rs_home_banners
set route = '/registry'
where route = '/rayon/registry';
