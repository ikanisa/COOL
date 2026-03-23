-- Fix audit trigger to support tables without an "id" column (e.g. app_config)

create or replace function public.trigger_admin_audit_log()
returns trigger
language plpgsql
security definer
as $$
declare
  v_target_id text;
  v_old_json jsonb;
  v_new_json jsonb;
begin
  if TG_OP = 'DELETE' or TG_OP = 'UPDATE' then
    v_old_json := to_jsonb(OLD);
  end if;
  
  if TG_OP = 'INSERT' or TG_OP = 'UPDATE' then
    v_new_json := to_jsonb(NEW);
  end if;

  -- Determine the primary key to log from JSON
  if TG_OP = 'DELETE' then
    if TG_TABLE_NAME = 'app_config' then
      v_target_id := (v_old_json->>'key')::text;
    else
      v_target_id := (v_old_json->>'id')::text;
    end if;
  else
    if TG_TABLE_NAME = 'app_config' then
      v_target_id := (v_new_json->>'key')::text;
    else
      v_target_id := (v_new_json->>'id')::text;
    end if;
  end if;

  -- Only log if the actor is an admin
  if exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
    insert into public.admin_audit_log (actor_id, action, target_table, target_id, old_data, new_data)
    values (
      auth.uid(),
      lower(TG_OP),
      TG_TABLE_NAME,
      v_target_id,
      v_old_json,
      v_new_json
    );
  end if;

  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;
create or replace function public.log_admin_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_id text;
  v_old_json jsonb;
  v_new_json jsonb;
BEGIN
  IF TG_OP = 'DELETE' or TG_OP = 'UPDATE' THEN
    v_old_json := to_jsonb(OLD);
  END IF;
  
  IF TG_OP = 'INSERT' or TG_OP = 'UPDATE' THEN
    v_new_json := to_jsonb(NEW);
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF TG_TABLE_NAME = 'app_config' THEN
      v_target_id := (v_old_json->>'key')::text;
    ELSE
      v_target_id := (v_old_json->>'id')::text;
    END IF;
  ELSE
    IF TG_TABLE_NAME = 'app_config' THEN
      v_target_id := (v_new_json->>'key')::text;
    ELSE
      v_target_id := (v_new_json->>'id')::text;
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_table, target_id, new_data)
    VALUES (auth.uid(), 'create', TG_TABLE_NAME, v_target_id, v_new_json);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_table, target_id, old_data, new_data)
    VALUES (auth.uid(), 'update', TG_TABLE_NAME, v_target_id, v_old_json, v_new_json);
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_table, target_id, old_data)
    VALUES (auth.uid(), 'delete', TG_TABLE_NAME, v_target_id, v_old_json);
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;
