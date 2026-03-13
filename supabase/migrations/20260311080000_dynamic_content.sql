-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC CONTENT MIGRATION (fully idempotent for re-run safety)
-- Creates tables for admin-managed content that was previously hardcoded
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1) partner_services ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.partner_services (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id  UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  subtitle    TEXT,
  emoji       TEXT DEFAULT '📋',
  category    TEXT DEFAULT 'general',
  details     JSONB DEFAULT '[]'::jsonb,
  cta_label   TEXT,
  cta_action  TEXT,
  country     TEXT DEFAULT 'RW',
  sort_order  INT DEFAULT 0,
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_services_partner ON public.partner_services(partner_id);
CREATE INDEX IF NOT EXISTS idx_partner_services_country ON public.partner_services(country);

ALTER TABLE public.partner_services ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='partner_services' AND policyname='Public read partner_services') THEN
    CREATE POLICY "Public read partner_services" ON public.partner_services FOR SELECT USING (true);
  END IF;
END $$;

-- ─── 2) supported_countries ──────────────────────────────────────────────
-- Table already exists from prior migration; add missing columns.

CREATE TABLE IF NOT EXISTS public.supported_countries (
  iso_code               TEXT PRIMARY KEY,
  dial_code              TEXT NOT NULL,
  country_name           TEXT NOT NULL,
  flag_emoji             TEXT DEFAULT '🏳️',
  currency_code          TEXT NOT NULL,
  currency_name          TEXT,
  momo_ussd_template     TEXT NOT NULL,
  momo_code_ussd_template TEXT,
  momo_provider_id       TEXT,
  is_active              BOOLEAN DEFAULT true,
  sort_order             INT DEFAULT 0,
  created_at             TIMESTAMPTZ DEFAULT now(),
  updated_at             TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.supported_countries ADD COLUMN IF NOT EXISTS default_lat DOUBLE PRECISION;
ALTER TABLE public.supported_countries ADD COLUMN IF NOT EXISTS default_lng DOUBLE PRECISION;
ALTER TABLE public.supported_countries ADD COLUMN IF NOT EXISTS sort_order INT DEFAULT 0;

ALTER TABLE public.supported_countries ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='supported_countries' AND policyname='Public read supported_countries') THEN
    CREATE POLICY "Public read supported_countries" ON public.supported_countries FOR SELECT USING (true);
  END IF;
END $$;

-- ─── 3) quick_actions ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.quick_actions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL,
  subtitle    TEXT,
  emoji       TEXT DEFAULT '⚡',
  route       TEXT NOT NULL,
  country     TEXT,
  sort_order  INT DEFAULT 0,
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.quick_actions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='quick_actions' AND policyname='Public read quick_actions') THEN
    CREATE POLICY "Public read quick_actions" ON public.quick_actions FOR SELECT USING (true);
  END IF;
END $$;

-- ─── 4) vehicle_types ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.vehicle_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  label       TEXT NOT NULL,
  value       TEXT NOT NULL UNIQUE,
  emoji       TEXT DEFAULT '🚘',
  country     TEXT,
  sort_order  INT DEFAULT 0,
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.vehicle_types ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='vehicle_types' AND policyname='Public read vehicle_types') THEN
    CREATE POLICY "Public read vehicle_types" ON public.vehicle_types FOR SELECT USING (true);
  END IF;
END $$;

-- ─── 5) app_config ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.app_config (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  description TEXT,
  country     TEXT,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='app_config' AND policyname='Public read app_config') THEN
    CREATE POLICY "Public read app_config" ON public.app_config FOR SELECT USING (true);
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- UPDATED_AT TRIGGERS (idempotent: drop + create)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_partner_services_updated ON public.partner_services;
CREATE TRIGGER trg_partner_services_updated
  BEFORE UPDATE ON public.partner_services
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_supported_countries_updated ON public.supported_countries;
CREATE TRIGGER trg_supported_countries_updated
  BEFORE UPDATE ON public.supported_countries
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_quick_actions_updated ON public.quick_actions;
CREATE TRIGGER trg_quick_actions_updated
  BEFORE UPDATE ON public.quick_actions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_vehicle_types_updated ON public.vehicle_types;
CREATE TRIGGER trg_vehicle_types_updated
  BEFORE UPDATE ON public.vehicle_types
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_app_config_updated ON public.app_config;
CREATE TRIGGER trg_app_config_updated
  BEFORE UPDATE ON public.app_config
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ═══════════════════════════════════════════════════════════════════════════
-- SEED DATA (all use ON CONFLICT DO NOTHING for idempotency)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Quick Actions ───────────────────────────────────────────────────────

INSERT INTO public.quick_actions (title, subtitle, emoji, route, sort_order) VALUES
  ('Groups',   'Savings and invites', '👥', '/groups',   0),
  ('MoMo',     'USSD and sync',       '📲', '/momo',     1),
  ('Partners', 'Rayon and clubs',     '💙', '/partners', 2),
  ('Mobility', 'Drivers and trips',   '🛺', '/mobility', 3)
ON CONFLICT DO NOTHING;

-- ─── Vehicle Types ───────────────────────────────────────────────────────

INSERT INTO public.vehicle_types (label, value, emoji, sort_order) VALUES
  ('All',       'All',    '🔍', 0),
  ('🛺 Moto',   'Moto',   '🛺', 1),
  ('🚗 Cab',    'Cab',    '🚗', 2),
  ('🚛 Truck',  'Truck',  '🚛', 3),
  ('🚐 Liffan', 'Liffan', '🚐', 4)
ON CONFLICT DO NOTHING;

-- ─── App Config ──────────────────────────────────────────────────────────

INSERT INTO public.app_config (key, value, description) VALUES
  ('support_whatsapp',        '250795588248',      'Primary WhatsApp support number'),
  ('credit_grade_excellent',  '80',                'Minimum score for Excellent grade'),
  ('credit_grade_good',       '60',                'Minimum score for Good Standing grade'),
  ('credit_grade_building',   '40',                'Minimum score for Building grade')
ON CONFLICT DO NOTHING;

INSERT INTO public.app_config (key, value, description, country) VALUES
  ('default_map_lat', '-1.9441', 'Default map center latitude', 'RW'),
  ('default_map_lng', '30.0619', 'Default map center longitude', 'RW')
ON CONFLICT DO NOTHING;

-- ─── Supported Countries (update existing rows with new columns) ─────────
-- Rows already seeded by migration 20260310170000; keep the Rwanda map default.

UPDATE public.supported_countries SET default_lat = -1.9441, default_lng = 30.0619, sort_order = 0 WHERE iso_code = 'RW';


-- ─── Partner Services (seed for existing partners) ───────────────────────

-- Urwego Finance services
INSERT INTO public.partner_services (partner_id, title, subtitle, emoji, category, details, cta_label, cta_action, sort_order)
SELECT p.id, s.title, s.subtitle, s.emoji, s.category, s.details::jsonb, s.cta_label, s.cta_action, s.sort_order
FROM public.partners p
CROSS JOIN (VALUES
  ('Group Savings', '48 groups custodied by Urwego Finance', '👥', 'savings',
   '[{"label":"Total RWF Held","value":"3.2M","icon":"💎"},{"label":"Active Groups","value":"48","icon":"📊"},{"label":"Insurance","value":"Covered","icon":"🛡️"}]',
   'View My Groups', 'route:/groups', 0),
  ('Group Expansion Loan', '12% APR · 12 months · Up to 5M', '📈', 'loan',
   '[{"label":"APR","value":"12%","icon":"📊"},{"label":"Term","value":"12 months","icon":"📅"},{"label":"Max Amount","value":"5M RWF","icon":"💰"}]',
   'Apply via USSD *525#', 'ussd:*525#', 1),
  ('Member Emergency Loan', '8% APR · 6 months · Up to 500K', '🆘', 'loan',
   '[{"label":"APR","value":"8%","icon":"📊"},{"label":"Term","value":"6 months","icon":"📅"},{"label":"Max Amount","value":"500K RWF","icon":"💰"}]',
   'Apply via USSD *525#', 'ussd:*525#', 2),
  ('Agri-Business Loan', '10% APR · 18 months · Up to 3M', '🌾', 'loan',
   '[{"label":"APR","value":"10%","icon":"📊"},{"label":"Term","value":"18 months","icon":"📅"},{"label":"Max Amount","value":"3M RWF","icon":"💰"}]',
   'Apply via USSD *525#', 'ussd:*525#', 3),
  ('Open a Bank Account', 'Link your savings group to a real bank account', '🏧', 'account',
   '[{"label":"Minimum Deposit","value":"5,000 RWF","icon":"💵"},{"label":"Monthly Fee","value":"Free","icon":"✨"},{"label":"Debit Card","value":"Included","icon":"💳"}]',
   'Open via USSD *525#', 'ussd:*525#', 4)
) AS s(title, subtitle, emoji, category, details, cta_label, cta_action, sort_order)
WHERE p.slug = 'urwego'
  AND NOT EXISTS (SELECT 1 FROM public.partner_services ps WHERE ps.partner_id = p.id);

-- Radiant Insurance services
INSERT INTO public.partner_services (partner_id, title, subtitle, emoji, category, details, cta_label, cta_action, sort_order)
SELECT p.id, s.title, s.subtitle, s.emoji, s.category, s.details::jsonb, s.cta_label, s.cta_action, s.sort_order
FROM public.partners p
CROSS JOIN (VALUES
  ('Group Savings Insurance', 'Protect your group''s pooled funds', '👥', 'insurance',
   '[{"label":"Coverage","value":"Up to 10M RWF","icon":"💎"},{"label":"Premium","value":"0.5% / month","icon":"📊"},{"label":"Claims","value":"48h turnaround","icon":"⚡"}]',
   'Chat about this cover', 'whatsapp', 0),
  ('Member Protection Plan', 'Individual coverage for group members', '🫶', 'insurance',
   '[{"label":"Life Cover","value":"5M RWF","icon":"❤️"},{"label":"Health","value":"Inpatient + Outpatient","icon":"🏥"},{"label":"Premium","value":"2,500 RWF / month","icon":"💰"}]',
   'Chat about this cover', 'whatsapp', 1),
  ('Agri-Insurance', 'Crop and livestock coverage for farming groups', '🌾', 'insurance',
   '[{"label":"Crop Cover","value":"Seasonal","icon":"🌱"},{"label":"Livestock","value":"Per animal","icon":"🐄"},{"label":"Weather Index","value":"Included","icon":"🌤️"}]',
   'Chat about this cover', 'whatsapp', 2)
) AS s(title, subtitle, emoji, category, details, cta_label, cta_action, sort_order)
WHERE p.slug = 'radiant'
  AND NOT EXISTS (SELECT 1 FROM public.partner_services ps WHERE ps.partner_id = p.id);

-- PRISMA services
INSERT INTO public.partner_services (partner_id, title, subtitle, emoji, category, details, cta_label, cta_action, sort_order)
SELECT p.id, s.title, s.subtitle, s.emoji, s.category, s.details::jsonb, s.cta_label, s.cta_action, s.sort_order
FROM public.partners p
CROSS JOIN (VALUES
  ('Accounting', 'Bookkeeping, financial statements, payroll',          '📒', 'service', '[]', 'Chat about this service', 'whatsapp', 0),
  ('Tax',        'RRA compliance, VAT, income tax, tax planning',       '🧾', 'service', '[]', 'Chat about this service', 'whatsapp', 1),
  ('Audit',      'Statutory audit, internal audit, due diligence',      '🔍', 'service', '[]', 'Chat about this service', 'whatsapp', 2),
  ('Legal',      'Corporate law, contracts, regulatory compliance',     '⚖️', 'service', '[]', 'Chat about this service', 'whatsapp', 3),
  ('Advisory',   'Business strategy, M&A, restructuring',              '💡', 'service', '[]', 'Chat about this service', 'whatsapp', 4)
) AS s(title, subtitle, emoji, category, details, cta_label, cta_action, sort_order)
WHERE p.slug = 'prisma'
  AND NOT EXISTS (SELECT 1 FROM public.partner_services ps WHERE ps.partner_id = p.id);
