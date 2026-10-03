-- heartbeat-held
begin;set local role service_role;select set_config('request.jwt.claims','{"role":"service_role"}',true);select public.gateway_heartbeat_v1('b02f7194-816a-4dc5-beb8-64e9d34324ce','d9b118a1-3add-42bb-bc22-3b895bcbba92','b901c8b77dd05fceb8f0520b7469a0d507bd120ee281cb063e7ce4b8bdbe0d75','{"sms_permission": false, "network": "offline", "telephony": "unknown", "sim_selected": false, "sim_revision_sha256": null, "local_pause": true, "reported_at": "2026-09-30T22:48:01.013Z"}'::jsonb);select 'HEARTBEAT_HELD';
-- heartbeat-held
commit;select 'HEARTBEAT_DONE';
-- read-authority-held
begin;set local role authenticated;select set_config('request.jwt.claims','{"sub": "99780000-0000-4000-8000-000000000001", "session_id": "99780000-0000-4000-8000-000000010001", "role": "authenticated", "aal": "aal1", "exp": 1790812081}',true);select public.admin_list_gateway_devices_v1();select 'READ_HELD';
-- grant-revocation-wait
begin;update public.admin_user_roles set revoked_at=clock_timestamp()where user_id='99780000-0000-4000-8000-000000000001';commit;select 'REVOKE_DONE';
-- read-authority-held
commit;select 'READ_DONE';
-- heartbeat-held
rollback;\q
-- read-authority-held
rollback;\q
-- grant-revocation-wait
rollback;\q
