begin isolation level serializable;
set local collect.legacy_bank_scheduler_qa='isolated_clone';
select collect_hybrid.verify_legacy_bank_scheduler_retirement();
commit;
