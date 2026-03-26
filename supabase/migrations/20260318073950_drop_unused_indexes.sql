-- ============================================================
-- QA FIX: Drop 92 unused indexes (0 scans since creation)
-- These impose write overhead with no read benefit.
-- Re-create any if needed after monitoring query patterns.
-- ============================================================

-- user_fcm_tokens
DROP INDEX IF EXISTS public.idx_fcm_tokens_user_id;
DROP INDEX IF EXISTS public.idx_fcm_tokens_token;

-- rs_fan_memberships
DROP INDEX IF EXISTS public.idx_rs_fan_memberships_user;

-- rs_fan_clubs
DROP INDEX IF EXISTS public.idx_rs_fan_clubs_partner;

-- rs_shop_orders
DROP INDEX IF EXISTS public.idx_rs_shop_orders_partner;
DROP INDEX IF EXISTS public.idx_rs_shop_orders_user;
DROP INDEX IF EXISTS public.idx_rs_shop_orders_momo_reference;
DROP INDEX IF EXISTS public.idx_rs_shop_orders_referral_invite;

-- groups
DROP INDEX IF EXISTS public.idx_groups_institution_id;
DROP INDEX IF EXISTS public.idx_groups_bank_partner_id;
DROP INDEX IF EXISTS public.idx_groups_creator_id;

-- cool_activities
DROP INDEX IF EXISTS public.idx_cool_activities_active;

-- admin_role_assignments
DROP INDEX IF EXISTS public.idx_admin_role_assignments_granted_by;
DROP INDEX IF EXISTS public.idx_admin_role_assignments_partner_scope_id;

-- ai_content
DROP INDEX IF EXISTS public.idx_ai_content_created_by;
DROP INDEX IF EXISTS public.idx_ai_content_reviewed_by;
DROP INDEX IF EXISTS public.idx_ai_content_country;

-- ai_content_generation_config
DROP INDEX IF EXISTS public.idx_ai_content_gen_config_updated_by;

-- bank_baskets
DROP INDEX IF EXISTS public.idx_bank_baskets_group_id;
DROP INDEX IF EXISTS public.idx_bank_baskets_partner_id;

-- bank_loans
DROP INDEX IF EXISTS public.idx_bank_loans_group_id;
DROP INDEX IF EXISTS public.idx_bank_loans_member_user_id;
DROP INDEX IF EXISTS public.idx_bank_loans_partner_id;

-- rs_tickets
DROP INDEX IF EXISTS public.idx_rs_tickets_user;
DROP INDEX IF EXISTS public.idx_rs_tickets_match;
DROP INDEX IF EXISTS public.idx_rs_tickets_momo_reference;
DROP INDEX IF EXISTS public.idx_rs_tickets_referral_invite;

-- cool_status
DROP INDEX IF EXISTS public.idx_cool_status_active_season;

-- rs_initiative_contributions
DROP INDEX IF EXISTS public.idx_rs_initiative_contributions_momo_reference;
DROP INDEX IF EXISTS public.idx_rs_initiative_contributions_user_id;
DROP INDEX IF EXISTS public.idx_rs_initiative_contributions_referral_invite;

-- referral_invites
DROP INDEX IF EXISTS public.idx_referral_invites_activated_by;
DROP INDEX IF EXISTS public.idx_referral_invites_opened_by;
DROP INDEX IF EXISTS public.idx_referral_invites_inviter;
DROP INDEX IF EXISTS public.idx_referral_invites_invite_code;

-- rs_achievements
DROP INDEX IF EXISTS public.idx_rs_achievements_partner_id;

-- momo_sms_raw
DROP INDEX IF EXISTS public.idx_momo_sms_raw_parse_status;
DROP INDEX IF EXISTS public.idx_momo_sms_raw_received_at;

-- group_contributions
DROP INDEX IF EXISTS public.idx_contributions_user;

-- momo_sms_parsed
DROP INDEX IF EXISTS public.idx_momo_sms_parsed_momo_tx_id;
DROP INDEX IF EXISTS public.idx_momo_sms_parsed_tx_datetime;
DROP INDEX IF EXISTS public.idx_momo_sms_parsed_category;

-- cool_events
DROP INDEX IF EXISTS public.idx_cool_events_user;
DROP INDEX IF EXISTS public.idx_cool_events_type;
DROP INDEX IF EXISTS public.idx_cool_events_campaign;
DROP INDEX IF EXISTS public.idx_cool_events_season;

-- cool_mission_progress
DROP INDEX IF EXISTS public.idx_cool_mission_progress_mission;
DROP INDEX IF EXISTS public.idx_cool_mission_progress_user;

-- momo_reconciliations
DROP INDEX IF EXISTS public.idx_momo_reconciliations_target;

-- rs_shop_products
DROP INDEX IF EXISTS public.idx_rs_shop_products_partner_catalog;

-- users
DROP INDEX IF EXISTS public.idx_users_kyc_document_type;
DROP INDEX IF EXISTS public.idx_users_kyc_extracted_at;
DROP INDEX IF EXISTS public.idx_users_kyc_status;

-- season_memberships
DROP INDEX IF EXISTS public.idx_season_memberships_user;

-- momo_ledger_entries
DROP INDEX IF EXISTS public.idx_momo_ledger_entries_scope;
DROP INDEX IF EXISTS public.idx_momo_ledger_entries_statement;
DROP INDEX IF EXISTS public.idx_momo_ledger_entries_category;

-- momo_parse_attempts
DROP INDEX IF EXISTS public.idx_momo_parse_attempts_user;

-- credit_score_runs
DROP INDEX IF EXISTS public.idx_credit_score_runs_band;

-- admin_audit_log
DROP INDEX IF EXISTS public.idx_admin_audit_log_actor;
DROP INDEX IF EXISTS public.idx_admin_audit_log_action;
DROP INDEX IF EXISTS public.idx_admin_audit_log_created;

-- wallet_pass_events
DROP INDEX IF EXISTS public.idx_wallet_pass_events_user_id;
DROP INDEX IF EXISTS public.idx_wallet_pass_events_pass;

-- pending_transactions
DROP INDEX IF EXISTS public.idx_pending_transactions_user;
DROP INDEX IF EXISTS public.idx_pending_transactions_group;
DROP INDEX IF EXISTS public.idx_pending_transactions_status;
DROP INDEX IF EXISTS public.idx_pending_tx_group_contribution_id;

-- operational_health_events
DROP INDEX IF EXISTS public.idx_operational_health_events_subject;
DROP INDEX IF EXISTS public.idx_operational_health_events_service_time;
DROP INDEX IF EXISTS public.idx_operational_health_events_function_time;
DROP INDEX IF EXISTS public.idx_operational_health_events_user_id;

-- cool_invite_attributions
DROP INDEX IF EXISTS public.idx_cool_invite_inviter;
DROP INDEX IF EXISTS public.idx_cool_invite_invitee;

-- partner_credit_applications
DROP INDEX IF EXISTS public.idx_partner_credit_applications_partner_status;

-- partner_application_handoffs
DROP INDEX IF EXISTS public.idx_partner_application_handoffs_application;
DROP INDEX IF EXISTS public.idx_partner_application_handoffs_user_created;
DROP INDEX IF EXISTS public.idx_partner_app_handoffs_partner_id;

-- quest_progress
DROP INDEX IF EXISTS public.idx_quest_progress_user;

-- referral_conversions
DROP INDEX IF EXISTS public.idx_referral_conversions_inviter;
DROP INDEX IF EXISTS public.idx_referral_conversions_invitee;

-- share_artifacts
DROP INDEX IF EXISTS public.idx_share_artifacts_owner;

-- wallet_passes
DROP INDEX IF EXISTS public.idx_wallet_passes_user;
DROP INDEX IF EXISTS public.idx_wallet_passes_entity;

-- cool_reward_redemptions
DROP INDEX IF EXISTS public.idx_cool_reward_redemptions_reward_id;
DROP INDEX IF EXISTS public.idx_cool_reward_redemptions_user_id;

-- rs_notifications
DROP INDEX IF EXISTS public.idx_rs_notifications_created_by;
DROP INDEX IF EXISTS public.idx_rs_notifications_match_id;

-- otp_rate_events
DROP INDEX IF EXISTS public.idx_otp_rate_events_action_actor_time;
DROP INDEX IF EXISTS public.idx_otp_rate_events_phone_time;
