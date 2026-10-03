create or replace function enqueue_notification_event(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_collection_id uuid default null,
  p_deep_link text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_id uuid;
  preference_enabled boolean;
begin
  if p_type = 'contribution_confirmed' then
    select coalesce(contribution_confirmations, true)
    into preference_enabled
    from notification_preferences
    where user_id = p_user_id;
  elsif p_type = 'payment_reminder' then
    select coalesce(payment_reminders, true)
    into preference_enabled
    from notification_preferences
    where user_id = p_user_id;
  elsif p_type = 'group_update' then
    select coalesce(group_updates, true)
    into preference_enabled
    from notification_preferences
    where user_id = p_user_id;
  elsif p_type = 'security_notice' then
    select coalesce(security_notices, true)
    into preference_enabled
    from notification_preferences
    where user_id = p_user_id;
  else
    raise exception 'invalid_notification_type';
  end if;

  if coalesce(preference_enabled, true) = false then
    return null;
  end if;

  insert into notification_events (
    user_id,
    collection_id,
    type,
    title,
    body,
    deep_link
  )
  values (
    p_user_id,
    p_collection_id,
    p_type,
    p_title,
    p_body,
    p_deep_link
  )
  returning id into inserted_id;

  return inserted_id;
end;
$$;

revoke execute on function enqueue_notification_event(uuid, text, text, text, uuid, text)
from anon, authenticated;
grant execute on function enqueue_notification_event(uuid, text, text, text, uuid, text)
to service_role;
