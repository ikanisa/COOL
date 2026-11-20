/** Existing Collect person/membership statements shared by Admin and native
 * adapters. These only build statements: callers retain admission, transaction,
 * permission/fresh-email guards, version checks, receipts and audit ownership.
 * Native enrollment creates a Direct beneficiary, never an Auth/operator user.
 */
export function personInsertStatement(db,{id,name,phone,email,memberType,provider,momo,code,status,timestamp}){
 return db.prepare(`INSERT INTO users(id,public_id,full_name,phone,email,member_type,momo_provider,momo_number,momo_pay_code,access_status,created_at,updated_at)
    VALUES(?,(SELECT printf('%06d',min(candidate)) FROM (SELECT 0 AS candidate UNION ALL SELECT CAST(public_id AS INTEGER)+1 FROM users WHERE public_id!='999999') c WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM users WHERE public_id=printf('%06d',candidate))),?,?,?,?,?,?,?,?,?,?)`)
  .bind(id,name,memberType==='app'?phone:null,memberType==='app'?email:null,memberType,provider,momo,code,status,timestamp,timestamp);
}
export function membershipWriteStatement(db,{create,id,groupId,userId,role,active,timestamp}){
 return create?db.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,?,?,?)`).bind(id,groupId,userId,role,active,timestamp):
  db.prepare(`UPDATE memberships SET role=?,active=?,revision=revision+1 WHERE collection_id=? AND user_id=?`).bind(role,active,groupId,userId);
}
