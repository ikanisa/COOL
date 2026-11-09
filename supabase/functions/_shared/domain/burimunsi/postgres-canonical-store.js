import {requirePort,requireThat} from './errors.js';
import {automaticWork} from './automatic-work.js';
import {requireId,requireRequestId,requireAmount,canonicalJson,normalizePhone} from './values.js';
import {authorize,matchExistingMember} from './policy.js';
import {pgInteger} from './postgres-values.js';

const OPS=new Set(['burimunsi.allocate','burimunsi.enroll','burimunsi.membership']);
const HASH=/^[a-f0-9]{64}$/;
const exact=(v,min=0)=>pgInteger(v,{minimum:min,code:'canonical_record_invalid'});
const clone=v=>JSON.parse(canonicalJson(v));
const fullPhone=value=>{try{return normalizePhone(value);}catch{return null;}};

/** Concrete transaction/read/idempotency adapter, NOT a substitute ledger writer.
 * commands receives the SAME admitted SQL transaction and must call the shared
 * Collect commands. identities must read authoritative, effective-dated proofs.
 * Missing bridges fail at construction; there is no memory or SQL-write fallback.
 */
export class PostgresCanonicalStore {
  constructor({authority,commands,identities,jobs,clock=()=>Date.now()}) {
    requirePort(authority,['write','session']);requireId(authority.groupId);
    requirePort(commands,['postContribution','createDirectMember','setMembershipActive','enqueueEligibleRematch']);
    requirePort(identities,['policy','members','verified']);requirePort(jobs,['assertPostingLease']);
    Object.assign(this,{authority,commands,identities,jobs,clock});this.groupId=authority.groupId;
  }
  inCanonicalTransaction(fn) {
    return this.authority.write(async sql=>{
      requirePort(sql,['unsafe']);const group=this.groupId;
      const scope=g=>requireThat(g===group,'access_denied',403);
      // Private scope is locked BEFORE jobs, receipts, identities or memberships.
      const s=(await sql.unsafe(`SELECT collection_id,receiving_account_id,enabled,version
        FROM private.burimunsi_scopes WHERE collection_id=$1 FOR UPDATE`,[group]))[0];
      requireThat(s?.enabled===true&&s.collection_id===group,'scope_unavailable',503);
      requireId(s.receiving_account_id);exact(s.version,1);
      let open=true;
      const ensure=()=>requireThat(open,'transaction_closed',503);
      const actors=new Map(),authorizations=new Map();
      const loadReceipt=async(id,g)=>{
        ensure();scope(g);requireId(id);
        const rows=await sql.unsafe(`SELECT t.*,x.collection_id,x.source_binding_id,x.source_binding_version,
          x.policy_version AS scope_policy_version,p.member_id,p.status AS payment_status
          FROM private.burimunsi_transaction_scopes x
          JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
          LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id
          LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
          WHERE x.collection_id=$1 AND x.receiving_account_id=$2 AND t.id=$3 FOR UPDATE OF x,t`,[group,s.receiving_account_id,id]);
        requireThat(rows.length<=1,'canonical_record_invalid',503);if(!rows.length)return null;
        const r=rows[0];requireThat(r.id===id&&r.collection_id===group&&r.receiving_account_id===s.receiving_account_id&&r.currency==='RWF'&&r.event_kind==='incoming_receipt','canonical_record_invalid',503);
        const conflict=exact(r.has_conflict);requireThat(conflict===0||conflict===1,'canonical_record_invalid',503);
        const state=conflict?'conflict':r.payment_status==='reversed'?'reversed':
          ['reconciled','confirmed','corrected'].includes(r.payment_status)?'posted':r.allocation_state==='unallocated'?'unallocated':'processing';
        const receipt={id:r.id,groupId:group,receivingAccountId:r.receiving_account_id,version:exact(r.version,1),
          amountRwf:requireAmount(exact(r.amount_minor,1)),currency:'RWF',state,hasConflict:conflict===1,
          memberId:r.member_id??null,at:r.transaction_at,fullPayerPhone:fullPhone(r.payer_identifier),
          originalPayerName:r.payer_name??null,providerTransactionId:r.provider_transaction_id??null,
          sourceBindingId:r.source_binding_id,sourceBindingVersion:exact(r.source_binding_version,1)};
        return clone(receipt);
      };
      const loadMember=async(id,g)=>{
        ensure();scope(g);requireId(id);
        const rows=await sql.unsafe(`SELECT u.id,m.collection_id,m.active,m.revision,u.access_status
          FROM app.memberships m JOIN app.users u ON u.id=m.user_id
          WHERE m.collection_id=$1 AND m.user_id=$2 FOR UPDATE OF m,u`,[group,id]);
        requireThat(rows.length<=1,'canonical_record_invalid',503);if(!rows.length)return null;
        const r=rows[0];requireThat(r.id===id&&r.collection_id===group,'canonical_record_invalid',503);
        const active=exact(r.active);requireThat(active===0||active===1,'canonical_record_invalid',503);
        const member={id,groupId:group,active:active===1,eligible:r.access_status==='active',version:exact(r.revision,1)};
        return clone(member);
      };
      const reloadActor=async sessionId=>{
        ensure();requireRequestId(sessionId);const actor=await this.authority.session(sql,{id:sessionId});
        if(actor){requireThat(actor.groupId===group&&actor.sessionId===sessionId,'session_unavailable',401);actors.set(actor.id,clone(actor));}
        return actor;
      };
      const checkActor=async(cmd,capability)=>{
        const actor=await reloadActor(cmd.sessionId);authorize(actor,group,capability,{now:this.clock()});
        requireThat(actor.id===cmd.actorId,'session_unavailable',401);return actor;
      };
      const readCanonicalResult=async transactionId=>{
        ensure();requireId(transactionId);
        const rows=await sql.unsafe(`SELECT t.id AS transaction_id,t.amount_minor AS source_amount,t.currency AS source_currency,t.has_conflict,
          t.event_kind,t.allocation_state,p.evidence_id AS payment_evidence_id,l.evidence_id AS entry_evidence_id,
          EXISTS(SELECT 1 FROM app.ledger_entries compensation WHERE compensation.reverses_entry_id=l.id) AS has_compensation,
          p.id AS payment_id,p.member_id,p.amount_minor,p.currency,p.status,
          f.beneficiary_member_id AS link_member_id,p.rail,
          l.id AS ledger_entry_id,l.amount_minor AS entry_amount,l.currency AS entry_currency,
          s.member_balance_after_minor,s.group_balance_after_minor
          FROM private.burimunsi_transaction_scopes x JOIN app.momo_transactions t ON t.id=x.transaction_id
          JOIN app.momo_financial_links f ON f.transaction_id=t.id
          JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
          JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=p.collection_id
            AND l.member_id=p.member_id AND l.kind='contribution'
          JOIN app.contribution_posting_snapshots s ON s.ledger_entry_id=l.id AND s.payment_id=p.id
          WHERE x.collection_id=$1 AND x.receiving_account_id=$2 AND t.receiving_account_id=x.receiving_account_id AND t.id=$3`,[group,s.receiving_account_id,transactionId]);
        requireThat(rows.length===1,'canonical_writer_contract_violation',503);const r=rows[0];
        const amount=exact(r.source_amount,1);
        requireThat(r.transaction_id===transactionId&&exact(r.has_conflict)===0&&
          ['reconciled','confirmed'].includes(r.status)&&r.event_kind==='incoming_receipt'&&r.allocation_state==='linked'&&
          r.has_compensation===false&&r.payment_evidence_id===r.entry_evidence_id&&r.link_member_id===r.member_id&&r.rail==='rwanda_momo'&&r.source_currency==='RWF'&&r.currency==='RWF'&&r.entry_currency==='RWF'&&
          exact(r.amount_minor,1)===amount&&exact(r.entry_amount,1)===amount,'canonical_writer_contract_violation',503);
        // A correction/reversal needs its own supported projection. Never report the
        // original contribution snapshot as a current successful posting.
        requireId(r.payment_id);requireId(r.payment_evidence_id);requireId(r.member_id);requireId(r.ledger_entry_id);
        return {transactionId,memberId:r.member_id,amountRwf:amount,currency:'RWF',ledgerEntryId:r.ledger_entry_id,
          memberBalanceRwf:exact(r.member_balance_after_minor),groupBalanceRwf:exact(r.group_balance_after_minor)};
      };
      const derivePostingCommand=async input=>{
          // Copy before the first await. Caller objects cannot retarget a plan.
          let cmd=clone(input);
          ensure();scope(cmd.groupId);requireRequestId(cmd.requestId);requireId(cmd.receiptId);requireId(cmd.memberId);
          // Re-read instead of trusting mutated objects returned to callers.
          const receipt=await loadReceipt(cmd.receiptId,group);
          requireThat(receipt&&!receipt.hasConflict&&receipt.state==='unallocated'&&receipt.version===cmd.expectedVersion,'transaction_changed',409);
          const member=await loadMember(cmd.memberId,group);
          requireThat(member?.active&&member.eligible,'member_unavailable',409);
          let actor=null;
          if(cmd.mode==='exception'){
            requireThat(typeof cmd.reason==='string'&&cmd.reason.trim().length>=8&&cmd.reason.length<=500&&!/[\u0000-\u001f\u007f]/.test(cmd.reason),'identification_note_required');
            actor=await checkActor(cmd,'payments.allocate');
          }
          else {
            requireThat(cmd.mode==='automatic','invalid_allocation_mode',503);
            cmd={...cmd,work:automaticWork(cmd.work)};
            if(cmd.work.kind==='rematch')requireThat(cmd.work.memberId===cmd.memberId&&cmd.work.policyVersion===cmd.policyVersion,'identity_changed',409);
            const admitted=authorizations.get(cmd.receiptId);
            requireThat(admitted?.requestId===cmd.requestId&&canonicalJson(admitted.work)===canonicalJson(cmd.work),'automatic_work_required',503);
            await this.jobs.assertPostingLease(sql,{groupId:group,transactionId:cmd.receiptId,requestId:cmd.requestId,work:cmd.work});
            const policy=await this.identities.policy(sql,group);
            const match=matchExistingMember(receipt,await this.identities.members(sql,group),await this.identities.verified(sql,group),policy);
            requireThat(match.kind==='matched'&&match.memberId===cmd.memberId&&match.policyVersion===cmd.policyVersion&&
              canonicalJson(match.identityIds)===canonicalJson(cmd.identityIds),'identity_changed',409);
          }
          ensure();return clone({...cmd,receipt:clone(receipt),member:clone(member),actor});
      };
      const ops={
        reloadActor,lockReceipt:loadReceipt,lockMember:loadMember,readCanonicalResult,
        retainedCommand:async(g,actorId,requestId)=>{
          ensure();scope(g);requireRequestId(actorId);requireRequestId(requestId);
          requireThat(actors.has(actorId),'session_unavailable',401);
          const rows=await sql.unsafe(`SELECT session_id,operation,fingerprint,response FROM private.burimunsi_command_receipts
            WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid FOR UPDATE`,[g,actorId,requestId]);
          requireThat(rows.length<=1,'canonical_record_invalid',503);const r=rows[0];if(!r)return null;
          requireThat(OPS.has(r.operation)&&HASH.test(r.fingerprint)&&r.response&&typeof r.response==='object'&&!Array.isArray(r.response),'canonical_record_invalid',503);
          return {sessionId:r.session_id,operation:r.operation,fingerprint:r.fingerprint,response:clone(r.response)};
        },
        retainCommand:async cmd=>{
          ensure();scope(cmd.groupId);requireRequestId(cmd.actorId);requireRequestId(cmd.sessionId);requireRequestId(cmd.requestId);
          requireThat(OPS.has(cmd.operation)&&HASH.test(cmd.fingerprint)&&actors.get(cmd.actorId)?.sessionId===cmd.sessionId,'invalid_command_receipt',503);
          const response=clone(cmd.response);
          requireThat(response&&typeof response==='object'&&!Array.isArray(response)&&new TextEncoder().encode(canonicalJson(response)).length<=65536,'invalid_command_receipt',503);
          await checkActor(cmd,cmd.operation==='burimunsi.allocate'?'payments.allocate':'members.enroll');
          // Plain INSERT: an unexpected duplicate aborts the entire transaction.
          // postgres.js infers JSONB; pass the object, never a pre-stringified JSON string.
          await sql.unsafe(`INSERT INTO private.burimunsi_command_receipts
            (collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at)
            VALUES($1,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7::jsonb,$8)`,
            [group,cmd.actorId,cmd.requestId,cmd.sessionId,cmd.operation,cmd.fingerprint,response,this.clock()]);
        },
        loadApprovedPolicy:async g=>{ensure();scope(g);return this.identities.policy(sql,g);},
        listEligibleMembers:async g=>{ensure();scope(g);return this.identities.members(sql,g);},
        listVerifiedIdentities:async g=>{ensure();scope(g);return this.identities.verified(sql,g);},
        assertAutomaticAdmission:async cmd=>{
          ensure();scope(cmd.groupId);requireId(cmd.transactionId);requireRequestId(cmd.requestId);
          cmd={...cmd,work:automaticWork(cmd.work)};
          await this.jobs.assertPostingLease(sql,cmd);
          authorizations.set(cmd.transactionId,{requestId:cmd.requestId,work:clone(cmd.work)});
        },
        retainAutomaticOutcome:async cmd=>{
          ensure();scope(cmd.groupId);requireId(cmd.transactionId);requireRequestId(cmd.requestId);
          const work=automaticWork(cmd.work);
          requireThat(work.kind==='rematch','automatic_work_required',503);
          const admitted=authorizations.get(cmd.transactionId);
          requireThat(admitted?.requestId===cmd.requestId&&canonicalJson(admitted.work)===canonicalJson(work),'automatic_work_required',503);
          requirePort(this.jobs,['retainAutomaticOutcome']);
          return this.jobs.retainAutomaticOutcome(sql,{...clone(cmd),work});
        },
        // Both planning and posting rederive authoritative facts on the same
        // admitted SQL connection. Planning has no financial/storage side effect.
        planCanonicalContribution:async cmd=>derivePostingCommand(cmd),
        postCanonicalContribution:async(input,planned=null)=>{
          const expected=planned===null?null:clone(planned);
          const cmd=await derivePostingCommand(input),{receipt,actor}=cmd;
          requireThat(expected===null||canonicalJson(cmd)===canonicalJson(expected),'posting_plan_changed',409);
          await this.commands.postContribution(sql,cmd);
          ensure();
          // The shared writer's claimed result is not proof. Read canonical rows.
          const result=await readCanonicalResult(cmd.receiptId);
          requireThat(result.memberId===cmd.memberId&&result.amountRwf===receipt.amountRwf,'canonical_writer_contract_violation',503);
          if(actor)await checkActor(cmd,'payments.allocate');
          else await this.jobs.assertPostingLease(sql,{groupId:group,transactionId:cmd.receiptId,requestId:cmd.requestId,work:cmd.work});
          return result;
        },
        createDirectMember:async cmd=>{
          ensure();scope(cmd.groupId);const actor=await checkActor(cmd,'members.enroll');
          const result=await this.commands.createDirectMember(sql,{...clone(cmd),actor});
          await checkActor(cmd,'members.enroll');return result;
        },
        setMembershipActive:async cmd=>{
          ensure();scope(cmd.groupId);const actor=await checkActor(cmd,'members.enroll');
          const result=await this.commands.setMembershipActive(sql,{...clone(cmd),actor});
          await checkActor(cmd,'members.enroll');return result;
        },
        enqueueEligibleRematch:async cmd=>{ensure();scope(cmd.groupId);return this.commands.enqueueEligibleRematch(sql,clone(cmd));}
      };
      try{return await fn(Object.freeze(ops));}finally{open=false;}
    });
  }
}
