-- Fresh Cloudflare runtime: all outbound notifications use email.
CREATE TRIGGER collect_notification_email_only BEFORE INSERT ON collect_notification_outbox
WHEN NEW.channel!='email'
BEGIN SELECT RAISE(ABORT,'Collect notifications use email only'); END;
CREATE INDEX collect_email_dispatch_queue ON collect_notification_outbox(channel,status,created_at,id);
CREATE TRIGGER collect_email_member_event_state AFTER UPDATE OF status ON collect_notification_outbox
WHEN NEW.status IN ('accepted','uncertain','suppressed','failed_no_send')
BEGIN
  UPDATE member_notification_events SET
    status=CASE NEW.status WHEN 'failed_no_send' THEN 'failed' ELSE NEW.status END,
    sent_at=CASE WHEN NEW.status='accepted' THEN NEW.accepted_at ELSE sent_at END,
    provider_reference=COALESCE(NEW.provider_reference,provider_reference)
  WHERE id=json_extract(NEW.payload_json,'$.member_event_id') AND user_id=NEW.recipient_user_id
    AND status IN ('queued','uncertain');
END;
