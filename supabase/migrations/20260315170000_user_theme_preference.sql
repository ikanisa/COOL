-- Add theme preference columns to public.users
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS theme_preference text DEFAULT 'system',
ADD COLUMN IF NOT EXISTS theme_preference_updated_at timestamptz DEFAULT now();

-- Update existing rows to have the current timestamp if the column was just added
UPDATE public.users
SET theme_preference_updated_at = now()
WHERE theme_preference_updated_at IS NULL;
