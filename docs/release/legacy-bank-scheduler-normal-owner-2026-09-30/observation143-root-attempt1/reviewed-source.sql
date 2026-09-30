begin isolation level serializable;
set local collect.legacy_bank_scheduler_qa='isolated_clone';
select collect_hybrid.verify_legacy_bank_scheduler_retirement();
commit;
begin isolation level serializable;
do $$ declare code text; message text; begin
  begin perform collect_hybrid.verify_legacy_bank_scheduler_retirement();
  exception when others then get stacked diagnostics code=returned_sqlstate,message=message_text; end;
  if code is distinct from '55000' or message is distinct from 'bank_scheduler_observation_interval_required' then
    raise exception 'Premature final verification must be rejected'; end if;
end $$;
select jsonb_build_object('premature_verification_rejected',true);
rollback;
