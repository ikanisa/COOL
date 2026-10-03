set search_path=public,extensions,auth;set timezone='UTC';
select revision from collect_receipt_operations.policy;