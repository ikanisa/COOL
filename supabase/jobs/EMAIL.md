# Contribution receipt email

The Collect Cloud `collect-email-jobs` Edge Function processes an opted-in
contribution receipt through its separate admission and delivery journal. Its
authorization binds the original dispatch ID, reviewed source, approval, active
profile and a one-message batch limit. The shared application uses the original
dispatch ID to reconcile an uncertain outcome. An SMTP acceptance records
acceptance by the sender.

The function and its synthetic tests are available in `supabase/functions/`.
Cloud scheduler installation for this lane requires a separate reviewed
integration with the current Cloud scheduler and application fence. The main
Cloud jobs scheduler handles its own signed dispatch contract.
