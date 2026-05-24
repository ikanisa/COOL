# Privacy And Compliance Notes

Privacy defaults:

- Public profile identity defaults to anonymous or pseudonymous.
- Public views never expose phone number, MOMO number, raw SMS, legal identity, balances, or account numbers.
- Public profile avatar URLs are hidden unless the user has chosen display-name identity.
- Collection cover images are safe public presentation assets and should be moderated before public directory approval.
- Raw SMS is stored because audit and re-parse workflows need it, but RLS restricts access.
- Phone and MOMO numbers are hashed where matching can use hashes.

Compliance TODOs before production:

- Rwanda data protection review for SMS content, retention, and subject access.
- Financial/regulatory review confirming Collect is a transparency and recordkeeping tool, not a money transmitter.
- Google Play restricted SMS permission approval if production SMS ingestion is desired.
- WhatsApp Cloud API template approval for authentication messages.
- Operational support policy for platform admin access to raw SMS during disputes.
