// This module is only called on the local, socket-only managed-chain fixture.
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';

const retryClass='private:burimunsi_observation_retry_commands';
const smsClass='private:burimunsi_payment_sms_deliveries';
const sha=text=>createHash('sha256').update(text).digest('hex');
const uuidHash=value=>{
  const hex=createHash('md5').update(value).digest('hex');
  return [hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-');
};
const ref=(name,n)=>sha(name+':'+uuidHash('rt-journal-'+n));

export async function installPostingSubjectFixture({owner,admin,entry,commit}) {
  // A drifted predecessor cannot be partially advanced or silently re-granted.
  await owner.query('ALTER FUNCTION private._burimunsi_retention_journal_links_v1(text,text) SECURITY INVOKER');
  try {
    await assert.rejects(commit(entry),{code:'55000',message:'burimunsi_journal_posting_links_precondition'});
  } finally {
    await owner.query('ALTER FUNCTION private._burimunsi_retention_journal_links_v1(text,text) SECURITY DEFINER');
  }
  await commit(entry);
  await assert.rejects(commit(entry),{code:'55000',message:'burimunsi_journal_posting_links_precondition'});
  const {rows:[{privateHelper}]}=await owner.query(`SELECT bool_and(
    NOT has_function_privilege(role,'private._burimunsi_retention_journal_links_v1(text,text)','EXECUTE')
    ) AS "privateHelper" FROM unnest(ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime']) AS roles(role)`);
  assert.equal(privateHelper,true);
  const seed=await readFile(new URL('./fixtures/journal-posting-subjects.sql',import.meta.url),'utf8');
  await admin.query('BEGIN');
  try {
    const relations=[...seed.matchAll(/INSERT INTO ((?:app|private)\.\w+)/g)].map(match=>match[1]);
    await admin.query("SET LOCAL session_replication_role='replica'");
    for (const relation of new Set(relations)) await admin.query('ALTER TABLE '+relation+' DISABLE TRIGGER collect_fence_statement_v1');
    await admin.query(seed);
    for (const relation of new Set(relations)) await admin.query('ALTER TABLE '+relation+' ENABLE ALWAYS TRIGGER collect_fence_statement_v1');
    await admin.query('COMMIT');
  } catch (error) {await admin.query('ROLLBACK');throw error;}
}

async function reviewerSession(owner) {
  const user=randomUUID(),account=randomUUID(),auth=randomUUID(),sid=randomUUID(),publicId=randomUUID();
  const email='rt-reviewer@example.invalid',origin='https://rt-admin.example.invalid',cookie=sha(randomUUID());
  const now=Math.floor(Date.now()/1000),challenge=randomUUID();
  // The archive fixture uses a text sentinel for its synthetic user's public
  // number. Owner onboarding allocates from the actual numeric public-ID space.
  await owner.query("UPDATE app.users SET public_id='949999' WHERE id='synthetic-primary' AND public_id='synthetic-public'");
  await owner.query('SELECT private.collect_initialize_owner($1,$2,$3,$4,$5,$6,$7)',
    [randomUUID(),account,user,email,'pbkdf2-sha256$600000$fixture-only','Synthetic Reviewer','journal-posting-source-fixture']);
  await owner.query('INSERT INTO auth.users(id,email,email_confirmed_at) VALUES($1,$2,now())',[auth,email]);
  await owner.query("INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES($1,$2,'aal1',now()+interval '1 hour')",[sid,auth]);
  await owner.query("INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES($1,$2,'synthetic-reviewer')",[auth,user]);
  await owner.query("INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES($1,$2,'admin',$3,$3,$4)",[sid,user,now,now+3600]);
  await owner.query(`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
    SELECT $1,$2,id,auth_version,$3,$4,$5,$6 FROM app.admin_users WHERE id=$7`,[cookie,publicId,sid,origin,now,now+3600,account]);
  await owner.query("INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext) VALUES($1,$2,$3,'{}')",[cookie,auth,sid]);
  await owner.query("INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at) VALUES($1,'otp',to_timestamp($2))",[sid,now]);
  await owner.query(`INSERT INTO private.supabase_otp_challenges
    (id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
    VALUES($1,$2,'email',$3,'admin',0,$4,$5,1,$6,'accepted')`,[challenge,sha('email:'+email),email,now-1,now+299,now]);
  return {user,context:[account,cookie,origin,publicId],challenge,claims:{sub:auth,session_id:sid,role:'authenticated',
    aal:'aal1',iat:now,exp:now+3600,amr:[{method:'otp',timestamp:now}]}};
}

export async function verifyPostingSubjectRpc({owner,runtime}) {
  const reviewer=await reviewerSession(owner);
  const subjects=['rt-capture','rt-payer','rt-other-payer','rt-dup-capture','rt-dup-payer','rt-actor','rt-allocator','rt-owner',
    'rt-cross-actor','rt-name-only','rt-page','synthetic-primary',reviewer.user];
  const requests=new Map();
  for(const [i,subject] of subjects.entries()) {
    if (subject!=='synthetic-primary' && subject!==reviewer.user) {
      await owner.query(`INSERT INTO app.users(id,email,public_id,created_at,updated_at)
        VALUES($1,$2,$3,now()::text,now()::text)`,[subject,subject+'@example.invalid',String(950000+i)]);
    }
    if (subject==='rt-name-only') await owner.query("UPDATE app.users SET momo_number='+250780070099' WHERE id=$1",[subject]);
    const id=randomUUID();
    await owner.query(`INSERT INTO app.deletion_requests(id,user_id,submission_id,created_at,updated_at)
      VALUES($1,$2,$3,now()::text,now()::text)`,[id,subject,randomUUID()]);
    requests.set(subject,id);
  }
  const {rows:[control]}=await owner.query('SELECT epoch,source_sha256 FROM private.collect_fence_control WHERE singleton');
  const admission=randomUUID(),evidence={captures:0,continuationPages:0,roleLimit:100};
  await runtime.query("SET ROLE collect_runtime; SET collect.edge_verified='true'");
  try {
    const {rows:[{work}]}=await runtime.query("SELECT private.collect_fence_register($1,$2,'http_admin') AS work",[admission,control.source_sha256]);
    await runtime.query(`SELECT set_config('collect.fence_admission_id',$1,false),set_config('collect.fence_epoch',$2,false),
      set_config('collect.fence_source_sha256',$3,false),set_config('request.jwt.claims',$4,false)`,
    [admission,String(work.epoch),control.source_sha256,JSON.stringify(reviewer.claims)]);
    await runtime.query('SELECT private.admin_email_record_initial($1,$2,$3,$4,$5)',[...reviewer.context,reviewer.challenge]);
    const captureStatement='SELECT private.retention_capture_inventory_v2($1,$2,0,$3,100000) AS page';
    const capture=async subject=>{
      const operation=randomUUID();
      const {rows:[{page:first}]}=await runtime.query(captureStatement,[operation,requests.get(subject),control.source_sha256]);
      evidence.captures++;
      const all=[...first.descriptors];
      let page=first;
      while(page.next_page!==null) {
        ({rows:[{page}]}=await runtime.query('SELECT private.retention_inventory_page_v2($1,$2,$3,false) AS page',
          [operation,first.manifest_sha256,page.next_page]));
        evidence.continuationPages++;
        assert.equal(page.manifest_sha256,first.manifest_sha256);
        all.push(...page.descriptors);
      }
      assert.equal(all.length,first.descriptor_count);
      const journals=all.filter(row=>[retryClass,smsClass].includes(row.class_name));
      assert.equal(journals.length,2);
      for(const row of journals) {
        assert.equal(row.status,'unmapped');assert.equal(row.subject_count,null);assert.equal(row.erasure,'blocked');
        const links=row.positive_subject_links;
        assert.equal(links.complete,false);assert.equal(links.missing_matches_prove_absence,false);
        for(const link of links.matches){
          assert.deepEqual(Object.keys(link).sort(),['record_key_sha256','relationship']);
          assert.match(link.record_key_sha256,/^[a-f0-9]{64}$/);
        }
      }
      return {links:Object.fromEntries(journals.map(row=>[row.class_name,row.positive_subject_links])),first};
    };
    await assert.rejects(runtime.query(captureStatement,[randomUUID(),requests.get('rt-payer'),control.source_sha256]),{code:'42501'});
    await runtime.query('BEGIN');
    try {
      await runtime.query('SELECT private.set_admin_email_context($1,$2,$3,$4)',reviewer.context);
      await assert.rejects(runtime.query(captureStatement,[randomUUID(),requests.get(reviewer.user),control.source_sha256]),{code:'42501'});
    } finally {await runtime.query('ROLLBACK');}
    await runtime.query('BEGIN');
    try {
      await runtime.query('SELECT private.set_admin_email_context($1,$2,$3,$4)',reviewer.context);
      const roles=(links,cls,n)=>links[cls].matches.filter(link=>link.record_key_sha256===ref(cls,n)).map(link=>link.relationship);
      const {links:captureLinks}=await capture('rt-capture');
      assert.deepEqual(roles(captureLinks,smsClass,1),['allocation_actor','capture_principal','evidence_owner','posting_actor']);
      assert.deepEqual(roles(captureLinks,retryClass,1),['allocation_actor','evidence_owner','posting_actor','retry_operator']);
      assert.notEqual(ref(smsClass,1),ref(retryClass,1));
      const {links:payer}=await capture('rt-payer');
      assert.deepEqual(payer[retryClass].matches,[{relationship:'canonical_beneficiary',record_key_sha256:ref(retryClass,1)}]);
      assert.deepEqual(roles(payer,smsClass,1),['receipt_recipient']);
      assert.deepEqual((await capture('rt-other-payer')).links[retryClass].matches,
        [{relationship:'canonical_beneficiary',record_key_sha256:ref(retryClass,2)}]);
      assert.equal((await capture('rt-dup-capture')).links[smsClass].matches.length,0);
      assert.equal((await capture('rt-dup-payer')).links[retryClass].matches.length,0);
      for(const [subject,relationship] of [['rt-actor','posting_actor'],['rt-allocator','allocation_actor'],['rt-owner','evidence_owner']]) {
        const {links}=await capture(subject);
        assert.deepEqual(roles(links,smsClass,3),[relationship]);
        assert.equal(links[retryClass].matches.length,0);
      }
      assert.equal((await capture('rt-cross-actor')).links[smsClass].matches.length,0);
      const {links:unknown}=await capture('rt-name-only');
      assert.deepEqual(unknown[retryClass].matches,[]);assert.deepEqual(unknown[smsClass].matches,[]);
      const {links:limited,first:sealed}=await capture('rt-page');
      const repeated=(await runtime.query(captureStatement,[sealed.manifest_id,requests.get('rt-page'),control.source_sha256])).rows[0].page;
      assert.deepEqual(repeated,sealed);
      const ids=[uuidHash('rt-journal-5'),...Array.from({length:25},(_,i)=>uuidHash('rt-limit-'+(i+1)))].sort();
      const roleOrder=['allocation_actor','evidence_owner','posting_actor','retry_operator'];
      const bounded=[{record_key_sha256:sha(retryClass+':00000000-0000-4000-8000-000000000001'),relationship:'retry_operator'},
        ...ids.flatMap(id=>roleOrder.map(relationship=>({record_key_sha256:sha(retryClass+':'+id),relationship})))].slice(0,100);
      assert.equal(limited[retryClass].truncated,true);
      assert.deepEqual(limited[retryClass].matches,bounded);
      const {links:many,first}=await capture('synthetic-primary');
      assert.ok(first.page_count>1);
      assert.equal(many[smsClass].truncated,true);
      const expected=Array.from({length:102},(_,i)=>uuidHash('synthetic-attempt-'+(i+1))).sort()
        .slice(0,100).map(id=>({relationship:'receipt_recipient',record_key_sha256:sha(smsClass+':'+id)}));
      assert.deepEqual(many[smsClass].matches,expected);
      const frames=(await runtime.query(`SELECT current_setting('burimunsi.native_receipt_frame',true) n,
        current_setting('burimunsi.pin_frame',true) p,current_setting('burimunsi.payment_sms_frame',true) s`)).rows[0];
      assert.ok(Object.values(frames).every(v=>!v));
      await runtime.query('COMMIT');
    } catch (error) {await runtime.query('ROLLBACK');throw error;}
    const {rows:[{closed}]}=await runtime.query("SELECT private.collect_fence_close($1,$2,$3,'settled','completed',0,0) AS closed",
      [admission,work.epoch,control.source_sha256]);assert.equal(closed.state,'settled');
  } finally {await runtime.query('RESET ROLE; RESET ALL');}
  return evidence;
}
