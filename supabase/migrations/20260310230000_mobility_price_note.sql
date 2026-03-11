-- Add optional price note / negotiable field to mobility_trips
ALTER TABLE public.mobility_trips
  ADD COLUMN IF NOT EXISTS price_note text;

COMMENT ON COLUMN public.mobility_trips.price_note IS
  'Optional free-text price note or "Negotiable" tag shown on trip listings.';
