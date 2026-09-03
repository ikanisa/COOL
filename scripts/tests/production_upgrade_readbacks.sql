-- Isolated production-copy check only. Caller verifies network/RAM isolation.
-- All fixture accounts, sessions, role approvals and groups roll back.
BEGIN;
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_setting('collect.recovery_drill',true) IS DISTINCT FROM 'production-archive-v1'
     OR current_setting('listen_addresses')<>'' OR current_setting('cron.launch_active_jobs')<>'off'
     OR current_setting('pg_net.database_name')<>'template1' OR current_setting('pg_net.batch_size')<>'0' THEN
    RAISE EXCEPTION 'Dedicated isolated recovery cluster required; never execute on production';
  END IF;
END $$;
CREATE FUNCTION pg_temp.assert_true(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS NOT TRUE THEN RAISE EXCEPTION 'Readback assertion failed: %',label; END IF; END $$;
DO $$
DECLARE r record; payload jsonb; page jsonb; history jsonb; keys text[]; checked integer:=0;
BEGIN
  FOR r IN SELECT id,public_id FROM public.profiles ORDER BY id LOOP
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',r.id,'role','authenticated')::text,true);
    SET LOCAL ROLE authenticated;
    payload:=public.get_current_member_profile();
    SELECT array_agg(key ORDER BY key) INTO keys FROM jsonb_object_keys(payload) key;
    PERFORM pg_temp.assert_true(keys=ARRAY['country_code','currency_code','id','momo_number','momo_provider','public_id','revolut_account','revolut_link','whatsapp_phone'], 'exact nine-field member profile');
    PERFORM pg_temp.assert_true(payload->>'id'=r.id::text AND payload->>'public_id'=r.public_id::text,'numeric member identity preserved');
    PERFORM pg_temp.assert_true(payload->>'public_id' ~ '^[0-9]{6}$','six digit ID');
    page:=public.list_current_member_history_page();
    history:=public.list_current_member_payment_history();
    PERFORM pg_temp.assert_true((page->>'total_count')::integer=jsonb_array_length(history),'bounded and legacy history totals agree');
    PERFORM pg_temp.assert_true(jsonb_typeof(page->'items')='array' AND jsonb_typeof(page->'totals')='object','bounded history types');
    PERFORM pg_temp.assert_true(jsonb_typeof(public.list_current_member_recent_intents()->'items')='array','recent intents contract');
    PERFORM pg_temp.assert_true(jsonb_typeof(public.list_current_member_collection_balances())='array','collection currency balances');
    PERFORM pg_temp.assert_true(NOT public.has_admin_permission('overview.read'),'unapproved legacy member cannot use platform Admin');
    RESET ROLE;
    checked:=checked+1;
  END LOOP;
  PERFORM pg_temp.assert_true(checked>0,'existing profiles checked');
END $$;

-- Rehearse exactly the owner-selected identity, not an arbitrary legacy Admin.
DO $$
DECLARE selected uuid; count_selected integer; sid uuid:='99430903-0000-4000-8000-000000000001';
BEGIN
  SELECT count(*),min(u.id::text)::uuid INTO count_selected,selected
  FROM auth.users u JOIN public.profiles p ON p.id=u.id
  WHERE regexp_replace(u.phone,'[^0-9]','','g')='250795588248' AND p.public_id='965511'
    AND u.phone_confirmed_at IS NOT NULL AND u.deleted_at IS NULL AND NOT u.is_anonymous
    AND (u.banned_until IS NULL OR u.banned_until<now());
  PERFORM pg_temp.assert_true(count_selected=1,'exact approved operator resolves uniquely');
  PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM auth.sessions WHERE id=sid),'fixture session collision guard');
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  SET LOCAL ROLE service_role;
  PERFORM public.admin_bootstrap_whatsapp_approval(selected,'+250795588248','Local recovery-copy activation rehearsal; rolled back');
  PERFORM public.admin_bootstrap_platform_owner(selected,'Local recovery-copy role rehearsal; rolled back');
  RESET ROLE;
  INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(sid,selected,clock_timestamp(),clock_timestamp());
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',selected,'role','authenticated','session_id',sid)::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_true(public.has_admin_permission('overview.read') AND public.has_admin_permission('admin_users.manage'),'approved combined role with fresh session works');
  PERFORM pg_temp.assert_true(public.admin_current_user()->>'user_id'=selected::text,'Admin identity readback');
  PERFORM pg_temp.assert_true(jsonb_typeof(public.admin_overview())='object','Admin overview loads after activation');
  RESET ROLE;
END $$;

-- A group owner can promote an existing member without platform preapproval.
DO $$
DECLARE owner_id uuid:='99430903-0000-4000-8000-000000000002'; member_id uuid:='99430903-0000-4000-8000-000000000003';
  group_id uuid:='99430903-0000-4000-8000-000000000004'; member_public_id text; result jsonb;
BEGIN
  PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM auth.users WHERE id IN(owner_id,member_id)),'fixture account collision guard');
  INSERT INTO auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
    VALUES(owner_id,'authenticated','authenticated','250788994002',now(),'{}','{}'),
      (member_id,'authenticated','authenticated','250788994003',now(),'{}','{}');
  SELECT public_id INTO member_public_id FROM public.profiles WHERE id=member_id;
  INSERT INTO public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type)
    VALUES(group_id,'isolated-recovery-group',owner_id,'Recovery-only fixture','Other','private','private','other');
  INSERT INTO public.collection_members(collection_id,user_id,role,status)
    VALUES(group_id,owner_id,'owner','active'),(group_id,member_id,'member','active');
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  result:=public.add_group_admin(group_id,member_public_id);
  PERFORM pg_temp.assert_true(result->>'role'='admin' AND result->>'public_id'=member_public_id,'ordinary owner adds group admin');
  PERFORM pg_temp.assert_true(public.add_group_admin(group_id,member_public_id)=result,'promotion retry is idempotent');
  PERFORM pg_temp.assert_true(NOT public.has_admin_permission('overview.read'),'group owner does not gain platform access');
  RESET ROLE;
  PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM collect_admin_access.whatsapp_approvals WHERE user_id IN(owner_id,member_id)),'group roles require no preapproved number');
END $$;
ROLLBACK;
SELECT 'PRODUCTION_COPY_READBACKS_PASS';
