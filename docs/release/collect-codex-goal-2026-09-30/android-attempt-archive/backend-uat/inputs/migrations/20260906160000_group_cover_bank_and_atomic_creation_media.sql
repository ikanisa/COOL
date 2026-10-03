begin;
-- Atomic group appearance persistence. Existing attested creation, consent,
-- geography, ownership and public-group controls remain authoritative.

create function public.validate_collect_group_cover_reference()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.cover_image_url is null or new.cover_image_url not like 'collect-cover:%' then
    return new;
  end if;
  if new.cover_image_url <> all(array[
    'collect-cover:rw-01-neighbourhood-ikimina:v1',
    'collect-cover:rw-02-women-savings-circle:v1',
    'collect-cover:rw-03-young-professionals-goal:v1',
    'collect-cover:rw-04-market-traders-stock:v1',
    'collect-cover:rw-05-moto-riders-shared-goal:v1',
    'collect-cover:rw-06-farmers-season-inputs:v1',
    'collect-cover:rw-07-family-home-goal:v1',
    'collect-cover:rw-08-craft-cooperative-tools:v1',
    'collect-cover:rw-09-wedding-committee:v2',
    'collect-cover:rw-10-gusaba-gukwa-gathering:v2',
    'collect-cover:rw-11-wedding-attire-preparation:v2',
    'collect-cover:rw-12-wedding-reception-table:v2',
    'collect-cover:rw-13-new-home-wedding-gift:v2',
    'collect-cover:rw-14-wedding-day-family:v2',
    'collect-cover:rw-15-church-community-offering:v1',
    'collect-cover:rw-16-church-building-project:v1',
    'collect-cover:rw-17-choir-shared-equipment:v1',
    'collect-cover:rw-18-muslim-community-giving:v1',
    'collect-cover:rw-19-ramadan-community-meal:v1',
    'collect-cover:rw-20-community-giving-parcels:v1',
    'collect-cover:rw-21-bereavement-support:v1',
    'collect-cover:rw-22-medical-care-support:v1',
    'collect-cover:rw-23-health-cover-contribution:v1',
    'collect-cover:rw-24-neighbours-recovery-support:v1',
    'collect-cover:rw-25-family-everyday-support:v1',
    'collect-cover:rw-26-welcoming-new-baby:v1',
    'collect-cover:rw-27-school-supplies:v1',
    'collect-cover:rw-28-school-meal-support:v1',
    'collect-cover:rw-29-higher-study-support:v1',
    'collect-cover:rw-30-youth-skills-training:v1',
    'collect-cover:rw-31-umuganda-project-tools:v1',
    'collect-cover:rw-32-shared-water-point:v1',
    'collect-cover:rw-33-community-hall-improvement:v1',
    'collect-cover:rw-34-tree-planting-neighbours:v1',
    'collect-cover:rw-35-football-fan-community:v1',
    'collect-cover:rw-36-local-team-equipment:v1',
    'collect-cover:rw-37-away-match-travel:v1',
    'collect-cover:rw-38-cultural-troupe-rehearsal:v1',
    'collect-cover:rw-39-diaspora-family-connection:v1',
    'collect-cover:rw-40-diaspora-community-project:v1',
    'collect-cover:rw-41-buri-munsi:v1',
    'collect-cover:rw-42-gikundiro:v1',
    'collect-cover:rw-43-church-congregation:v1',
    'collect-cover:rw-44-football-fans-matchday:v1'
  ]::text[]) then
    raise exception 'Unknown group cover or version' using errcode = '22023';
  end if;
  if new.cover_image_url in ('collect-cover:rw-41-buri-munsi:v1', 'collect-cover:rw-42-gikundiro:v1')
     and not (coalesce(new.is_platform_sponsored, false)
       and coalesce(new.public_status::text, '') = 'public_approved'
       and ((new.slug = 'buri-munsi' and new.cover_image_url = 'collect-cover:rw-41-buri-munsi:v1')
         or (new.slug = 'gikundiro' and new.cover_image_url = 'collect-cover:rw-42-gikundiro:v1'))) then
    raise exception 'This cover is reserved for its approved public group' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_collect_group_cover_reference() from public, anon, authenticated;
create trigger validate_collect_group_cover_reference
before insert or update of cover_image_url on public.collections
for each row execute function public.validate_collect_group_cover_reference();

-- Appearance is an owner-editable cosmetic value. The existing capability
-- continues to bind the unchanged group/receiver payload; no new device
-- capability, visibility input, receiver update or financial action is added.
-- Both creation and media write roll back on any error, including consumption
-- of the existing one-use native capability.
create function public.create_private_group_with_owner_media_attested(
  group_name text,
  group_description text,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text,
  group_collection_type text,
  group_category_subtype text,
  group_purpose_label text,
  native_capability uuid,
  group_image_url text default null,
  group_accent_color_hex text default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  created_group_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if group_accent_color_hex is not null and group_accent_color_hex !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Invalid group colour' using errcode = '22023';
  end if;
  if octet_length(coalesce(group_image_url, '')) > 7340032 then
    raise exception 'Choose a smaller group photo' using errcode = '22023';
  end if;
  created_group_id := public.create_private_group_with_owner_attested(
    group_name, group_description, receiver_momo_number,
    receiver_momo_number_hash, receiver_label, group_collection_type,
    group_category_subtype, group_purpose_label, native_capability
  );
  update public.collections
  set cover_image_url = nullif(trim(group_image_url), ''),
      accent_color_hex = nullif(trim(group_accent_color_hex), '')
  where id = created_group_id and creator_user_id = auth.uid();
  if not found then raise exception 'Group owner could not be verified'; end if;
  return created_group_id;
end;
$$;
revoke all on function public.create_private_group_with_owner_media_attested(
  text, text, text, text, text, text, text, text, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.create_private_group_with_owner_media_attested(
  text, text, text, text, text, text, text, text, uuid, text, text
) to authenticated;

-- No existing group photos or named public-group records are rewritten.
notify pgrst, 'reload schema';
commit;
