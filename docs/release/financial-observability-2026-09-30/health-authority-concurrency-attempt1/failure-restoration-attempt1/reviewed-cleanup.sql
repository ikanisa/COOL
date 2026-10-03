begin;
do $$ begin
 if exists(select 1 from collect_hybrid.member_records where id::text like '99670000-%' and xmin::text not in ('3285','3286','3287','3290','3291','3292','3295','3296','3299','3302','3303','3304','3305','3308','3309','3310')) then raise exception 'Unattributed synthetic member';end if;
 if (select count(*) from public.app_realtime_events where xmin::text in ('3285','3286','3287','3290','3291','3292','3295','3296','3299','3302','3303','3304','3305','3308','3309','3310'))<>37 then raise exception 'Unexpected realtime fixture rows';end if;
end $$;
select 'CLEANUP_XID:'||pg_current_xact_id();
delete from collect_hybrid.member_records where id::text like '99670000-%' and xmin::text in ('3285','3286','3287','3290','3291','3292','3295','3296','3299','3302','3303','3304','3305','3308','3309','3310');
delete from public.app_realtime_events where xmin::text in ('3285','3286','3287','3290','3291','3292','3295','3296','3299','3302','3303','3304','3305','3308','3309','3310') or xmin::text=pg_current_xact_id()::text;
commit;