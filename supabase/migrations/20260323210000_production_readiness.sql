-- ════════════════════════════════════════════════════════════════
-- Production Readiness Migration
-- Fixes: RLS gaps, duplicate triggers, missing updated_at, FK indexes
-- ════════════════════════════════════════════════════════════════

-- ─── 1. RLS POLICY GAPS ─────────────────────────────────────────
-- biopay_embeddings: backend-only table (service_role via edge functions)
-- RLS is ON but zero policies → fully locked. Add explicit deny for safety docs.
DROP POLICY IF EXISTS "biopay_embeddings_deny_anon" ON public.biopay_embeddings;
CREATE POLICY "biopay_embeddings_deny_anon"
  ON public.biopay_embeddings FOR ALL TO anon USING (false);
DROP POLICY IF EXISTS "biopay_embeddings_deny_authenticated" ON public.biopay_embeddings;
CREATE POLICY "biopay_embeddings_deny_authenticated"
  ON public.biopay_embeddings FOR ALL TO authenticated USING (false);
DROP POLICY IF EXISTS "biopay_embeddings_service_role" ON public.biopay_embeddings;
CREATE POLICY "biopay_embeddings_service_role"
  ON public.biopay_embeddings FOR ALL TO service_role USING (true) WITH CHECK (true);

-- biopay_match_rate_events: backend-only rate limit tracking
DROP POLICY IF EXISTS "biopay_match_rate_events_deny_anon" ON public.biopay_match_rate_events;
CREATE POLICY "biopay_match_rate_events_deny_anon"
  ON public.biopay_match_rate_events FOR ALL TO anon USING (false);
DROP POLICY IF EXISTS "biopay_match_rate_events_deny_authenticated" ON public.biopay_match_rate_events;
CREATE POLICY "biopay_match_rate_events_deny_authenticated"
  ON public.biopay_match_rate_events FOR ALL TO authenticated USING (false);
DROP POLICY IF EXISTS "biopay_match_rate_events_service_role" ON public.biopay_match_rate_events;
CREATE POLICY "biopay_match_rate_events_service_role"
  ON public.biopay_match_rate_events FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─── 2. DROP DUPLICATE AUDIT TRIGGERS ───────────────────────────
-- Keep trg_audit_* (log_admin_mutation), drop old audit_* (trigger_admin_audit_log)
DROP TRIGGER IF EXISTS audit_admin_role_assignments ON public.admin_role_assignments;
DROP TRIGGER IF EXISTS audit_app_config ON public.app_config;
DROP TRIGGER IF EXISTS audit_partner_services ON public.partner_services;
DROP TRIGGER IF EXISTS audit_partners ON public.partners;
DROP TRIGGER IF EXISTS audit_quick_actions ON public.quick_actions;

-- Replace the missing audit trigger on admin_role_assignments with log_admin_mutation
DROP TRIGGER IF EXISTS trg_audit_admin_role_assignments ON public.admin_role_assignments;
CREATE TRIGGER trg_audit_admin_role_assignments
  AFTER INSERT OR UPDATE OR DELETE ON public.admin_role_assignments
  FOR EACH ROW EXECUTE FUNCTION log_admin_mutation();

-- Drop the orphaned trigger function (no more callers)
DROP FUNCTION IF EXISTS public.trigger_admin_audit_log() CASCADE;


-- ─── 3. MISSING updated_at TRIGGERS ─────────────────────────────
-- All use the existing set_updated_at() function

DROP TRIGGER IF EXISTS trg_ai_content_generation_config_set_updated_at ON public.ai_content_generation_config;
CREATE TRIGGER trg_ai_content_generation_config_set_updated_at
  BEFORE UPDATE ON public.ai_content_generation_config
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_bank_baskets_set_updated_at ON public.bank_baskets;
CREATE TRIGGER trg_bank_baskets_set_updated_at
  BEFORE UPDATE ON public.bank_baskets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_bank_loans_set_updated_at ON public.bank_loans;
CREATE TRIGGER trg_bank_loans_set_updated_at
  BEFORE UPDATE ON public.bank_loans
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_cool_activities_set_updated_at ON public.cool_activities;
CREATE TRIGGER trg_cool_activities_set_updated_at
  BEFORE UPDATE ON public.cool_activities
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_cool_mission_progress_set_updated_at ON public.cool_mission_progress;
CREATE TRIGGER trg_cool_mission_progress_set_updated_at
  BEFORE UPDATE ON public.cool_mission_progress
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_cool_status_set_updated_at ON public.cool_status;
CREATE TRIGGER trg_cool_status_set_updated_at
  BEFORE UPDATE ON public.cool_status
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_nexus_opportunities_set_updated_at ON public.nexus_opportunities;
CREATE TRIGGER trg_nexus_opportunities_set_updated_at
  BEFORE UPDATE ON public.nexus_opportunities
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_special_products_set_updated_at ON public.special_products;
CREATE TRIGGER trg_special_products_set_updated_at
  BEFORE UPDATE ON public.special_products
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_user_fcm_tokens_set_updated_at ON public.user_fcm_tokens;
CREATE TRIGGER trg_user_fcm_tokens_set_updated_at
  BEFORE UPDATE ON public.user_fcm_tokens
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ─── 4. MISSING FK INDEXES ──────────────────────────────────────

-- admin_audit_log
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_actor_id
  ON public.admin_audit_log (actor_id);

-- admin_role_assignments
CREATE INDEX IF NOT EXISTS idx_admin_role_assignments_granted_by
  ON public.admin_role_assignments (granted_by);

-- ai_content
CREATE INDEX IF NOT EXISTS idx_ai_content_created_by
  ON public.ai_content (created_by);
CREATE INDEX IF NOT EXISTS idx_ai_content_reviewed_by
  ON public.ai_content (reviewed_by);

-- ai_content_generation_config
CREATE INDEX IF NOT EXISTS idx_ai_content_generation_config_updated_by
  ON public.ai_content_generation_config (updated_by);

-- bank_baskets
CREATE INDEX IF NOT EXISTS idx_bank_baskets_group_id
  ON public.bank_baskets (group_id);
CREATE INDEX IF NOT EXISTS idx_bank_baskets_partner_id
  ON public.bank_baskets (partner_id);

-- bank_loans
CREATE INDEX IF NOT EXISTS idx_bank_loans_group_id
  ON public.bank_loans (group_id);
CREATE INDEX IF NOT EXISTS idx_bank_loans_member_user_id
  ON public.bank_loans (member_user_id);
CREATE INDEX IF NOT EXISTS idx_bank_loans_partner_id
  ON public.bank_loans (partner_id);

-- biopay_enrollment_audits
CREATE INDEX IF NOT EXISTS idx_biopay_enrollment_audits_profile_id
  ON public.biopay_enrollment_audits (profile_id);

-- biopay_match_events
CREATE INDEX IF NOT EXISTS idx_biopay_match_events_matched_profile_id
  ON public.biopay_match_events (matched_profile_id);

-- biopay_revocations
CREATE INDEX IF NOT EXISTS idx_biopay_revocations_profile_id
  ON public.biopay_revocations (profile_id);

-- cool_reward_redemptions
CREATE INDEX IF NOT EXISTS idx_cool_reward_redemptions_reward_id
  ON public.cool_reward_redemptions (reward_id);
CREATE INDEX IF NOT EXISTS idx_cool_reward_redemptions_user_id
  ON public.cool_reward_redemptions (user_id);

-- cool_status
CREATE INDEX IF NOT EXISTS idx_cool_status_active_season_id
  ON public.cool_status (active_season_id);

-- groups
CREATE INDEX IF NOT EXISTS idx_groups_bank_partner_id
  ON public.groups (bank_partner_id);
CREATE INDEX IF NOT EXISTS idx_groups_creator_id
  ON public.groups (creator_id);

-- momo_parse_attempts
CREATE INDEX IF NOT EXISTS idx_momo_parse_attempts_user_id
  ON public.momo_parse_attempts (user_id);

-- momo_sms_sender_inventory_resolutions
CREATE INDEX IF NOT EXISTS idx_momo_sms_sender_inv_res_resolved_by
  ON public.momo_sms_sender_inventory_resolutions (resolved_by);

-- operational_health_events
CREATE INDEX IF NOT EXISTS idx_operational_health_events_user_id
  ON public.operational_health_events (user_id);

-- partner_application_handoffs
CREATE INDEX IF NOT EXISTS idx_partner_application_handoffs_application_id
  ON public.partner_application_handoffs (application_id);
CREATE INDEX IF NOT EXISTS idx_partner_application_handoffs_partner_id
  ON public.partner_application_handoffs (partner_id);
CREATE INDEX IF NOT EXISTS idx_partner_application_handoffs_user_id
  ON public.partner_application_handoffs (user_id);

-- partner_credit_applications
CREATE INDEX IF NOT EXISTS idx_partner_credit_applications_partner_id
  ON public.partner_credit_applications (partner_id);

-- pending_transactions
CREATE INDEX IF NOT EXISTS idx_pending_transactions_group_contribution_id
  ON public.pending_transactions (group_contribution_id);
CREATE INDEX IF NOT EXISTS idx_pending_transactions_group_id
  ON public.pending_transactions (group_id);

-- referral_conversions
CREATE INDEX IF NOT EXISTS idx_referral_conversions_inviter_id
  ON public.referral_conversions (inviter_id);

-- referral_invites
CREATE INDEX IF NOT EXISTS idx_referral_invites_activated_by_user_id
  ON public.referral_invites (activated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_referral_invites_inviter_id
  ON public.referral_invites (inviter_id);
CREATE INDEX IF NOT EXISTS idx_referral_invites_opened_by_user_id
  ON public.referral_invites (opened_by_user_id);

-- rs_initiative_contributions
CREATE INDEX IF NOT EXISTS idx_rs_initiative_contributions_referral_invite_id
  ON public.rs_initiative_contributions (referral_invite_id);
CREATE INDEX IF NOT EXISTS idx_rs_initiative_contributions_user_id
  ON public.rs_initiative_contributions (user_id);

-- rs_notifications
CREATE INDEX IF NOT EXISTS idx_rs_notifications_created_by
  ON public.rs_notifications (created_by);
CREATE INDEX IF NOT EXISTS idx_rs_notifications_match_id
  ON public.rs_notifications (match_id);

-- rs_shop_orders
CREATE INDEX IF NOT EXISTS idx_rs_shop_orders_partner_id
  ON public.rs_shop_orders (partner_id);
CREATE INDEX IF NOT EXISTS idx_rs_shop_orders_referral_invite_id
  ON public.rs_shop_orders (referral_invite_id);

-- rs_tickets
CREATE INDEX IF NOT EXISTS idx_rs_tickets_match_id
  ON public.rs_tickets (match_id);
CREATE INDEX IF NOT EXISTS idx_rs_tickets_referral_invite_id
  ON public.rs_tickets (referral_invite_id);

-- share_artifacts
CREATE INDEX IF NOT EXISTS idx_share_artifacts_owner_user_id
  ON public.share_artifacts (owner_user_id);

-- wallet_pass_events
CREATE INDEX IF NOT EXISTS idx_wallet_pass_events_user_id
  ON public.wallet_pass_events (user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_pass_events_wallet_pass_id
  ON public.wallet_pass_events (wallet_pass_id);

-- wallet_passes
CREATE INDEX IF NOT EXISTS idx_wallet_passes_user_id
  ON public.wallet_passes (user_id);
