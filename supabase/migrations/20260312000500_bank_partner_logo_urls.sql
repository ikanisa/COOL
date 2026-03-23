-- Persist official logo URLs for bank partners so the backend contract carries
-- the same brand identity metadata used by the Flutter app.

update public.partners
set
  logo_url = 'https://www.urwegofinance.com/wp-content/uploads/2024/04/Urwego-Finance-1.png',
  updated_at = now()
where slug = 'urwego';
update public.partners
set
  logo_url = 'https://equitygroupholdings.com/wp-content/uploads/2019/07/cropped-equity-bank-logo-300x195.png',
  updated_at = now()
where slug = 'equity';
