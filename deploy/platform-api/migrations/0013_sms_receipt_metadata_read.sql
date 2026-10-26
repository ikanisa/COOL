-- Additive candidate successor after0012. Read metadata only: no raw source,
-- extraction, assisted-SMS access, policy, recipient or transport activation.
INSERT INTO admin_account_role_capabilities(role,permission) VALUES
 ('owner','sms.read'),('admin','sms.read'),('staff','sms.read');

-- Explicit existing-account adoption uses the canonical authentication link,
-- not a mobile/app profile association. Operator-only principals qualify.
-- Revoked/invited accounts, disconnected links and suspended principals do not.
INSERT OR IGNORE INTO admin_grants(user_id,permission,granted_by,granted_at)
 SELECT link.user_id,'sms.read','admin-account:'||account.id,strftime('%Y-%m-%dT%H:%M:%fZ','now')
 FROM admin_users account
 JOIN admin_principal_links link ON link.admin_user_id=account.id
 JOIN users principal ON principal.id=link.user_id
 WHERE account.status='active' AND account.role IN('owner','admin','staff') AND principal.access_status='active';

-- Existing canonical link/role/account lifecycle triggers inherit the new role
-- definition for future active accounts. Runtime still intersects live grants,
-- role definitions, current account/principal/session and issuing origin.
CREATE INDEX sms_receipts_metadata_order ON sms_receipts(created_at DESC,id ASC);
