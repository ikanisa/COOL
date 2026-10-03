insert into public.payments(member_record_id,id,collection_id,contributor_user_id,receiver_user_id,
      receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,
      anonymity_choice,contributor_public_id,posted_at,payment_intent_id,parsed_event_id)
      values('99780000-0000-4000-8000-000000040001','99780000-0000-4000-8000-000000050001','99640000-0000-4000-8000-000000020001',null,
      (select creator_user_id from public.collections where id='99640000-0000-4000-8000-000000020001'),
      (select momo_number_hash from public.profiles where id=(select creator_user_id from public.collections where id='99640000-0000-4000-8000-000000020001')),
      100,'SYNTH-CURRENT-RECEIPT-978401','mtn_momo','manual_admin','review',
      'anonymous',null,null,null,null);