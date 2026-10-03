with     required_service_function_grants(routine_name) as (
      values
        ('reserve_play_integrity_admission_v1'),
        ('begin_play_integrity_admission_v1'),
        ('complete_play_integrity_admission_v1'),
        ('finish_play_integrity_admission_v1'),
        ('claim_raw_payment_sms_for_parse'),
        ('ingest_raw_payment_sms'),
        ('allocate_parsed_payment_event')
    ),
    missing_service_function_grants as (
      select 'missing service_role function grant: EXECUTE on ' || routine_name as issue
      from required_service_function_grants
      except
      select 'missing service_role function grant: EXECUTE on ' || routine_name
      from information_schema.routine_privileges
      where specific_schema = 'public'
        and grantee = 'service_role'
        and privilege_type = 'EXECUTE'
    ),
    forbidden_function_grants as (
      select 'forbidden function grant: ' || grantee || ' EXECUTE on ' || routine_name as issue
      from information_schema.routine_privileges
      where specific_schema = 'public'
        and privilege_type = 'EXECUTE'
        and (
          (grantee = 'authenticated' and routine_name in (
            'create_group_with_owner',
            'update_collection_profile',
            'get_current_profile', 'ensure_current_profile', 'update_current_profile',
            'admin_grant_user_role', 'admin_revoke_user_role',
            'admin_bootstrap_whatsapp_approval', 'admin_bootstrap_platform_owner'
          ))
          or (grantee = 'service_role' and routine_name = 'check_sms_ingest_rate_limit')
          or (grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
            and routine_name = 'mint_native_action_capability')
        )
    ) select coalesce(jsonb_agg(issue),'[]')from(select issue from missing_service_function_grants union all select issue from forbidden_function_grants)q where issue like '%play_integrity_admission_v1'or issue like '%mint_native_action_capability';
