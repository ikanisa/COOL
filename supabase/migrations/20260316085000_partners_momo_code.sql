-- Add momo_code column to partners table
ALTER TABLE public.partners ADD COLUMN IF NOT EXISTS momo_code text;

COMMENT ON COLUMN public.partners.momo_code IS
  'MoMo payment code for the partner (used for USSD payments in Rwanda).';
