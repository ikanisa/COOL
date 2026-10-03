# Privacy and compliance notes: Rwanda release scope

These are engineering controls and open review points, not a legal clearance. The current release is Rwanda-only MoMo group contributions; historical bank-transfer claims and data paths must not be presented as current capabilities.

- Public and member surfaces must not expose phone numbers, raw SMS, full payer identity, Admin identifiers, or another member's records.
- Collect receives only newly arriving likely MoMo receipt SMS after explicit Android consent. It does not read SMS history, send SMS, collect a MoMo PIN/OTP, or store mobile-money account credentials.
- Raw receipt evidence is protected separately, cannot be selected by ordinary app roles, and requires an explicit capability, reason and audit event to reveal. Candidate evidence is not settlement confirmation.
- Notifications contain status information but never raw evidence, credentials, PINs, OTPs or provider secrets.
- Session, native secure-cache, browser cache, account switch, consent revocation and deletion behavior need physical-device and browser verification. Preserve legally required financial evidence under an approved retention schedule rather than asserting blanket deletion.
- Record actual processors, hosting/backup/log/AI locations, transfer basis, registration and incident-reportability decisions with the responsible privacy/legal owners. The repo alone cannot establish these approvals.
- Verify Play/App Store privacy labels, customer disclosures and reviewer access against the exact enabled Rwanda features and current signed build.
