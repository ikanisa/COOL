import { ApiError, digest, first, id, integer, now, rows, stableJson, uuid } from "./core.js";
import { mutation, retainedResponse } from "./mutations.js";
import { groupFor } from "./groups.js";
import {
  boundCreationReceipt,
  contributionIntentJson as intentJson,
  normalizeContributionSender,
} from "./contribution_intent_dto.js";
import { memberIntentSnapshot } from "./member_intent_sql.js";

function restoreOriginalSender(row, sessionId) {
  // Only the immutable, exact create receipt can supply this binding. A later
  // profile value or an unverified database projection is not original evidence.
  const raw = row.creation_response_json;
  if (
    row.originating_session_id === sessionId && typeof raw === "string" && raw.length <= 8192 &&
    new TextEncoder().encode(raw).length <= 8192
  ) {
    try {
      const hash = JSON.parse(raw)?.sender_phone_hash;
      if (boundCreationReceipt(row, hash)) return { ...row, sender_phone_hash: hash };
    } catch { /* An unavailable receipt leaves this historical intent non-actionable. */ }
  }
  return { ...row, sender_phone_hash: "" };
}
function intentConfirmation(intent, actor, evidence) {
  if (!evidence?.payment_id) {
    return { ...intentJson(intent), confirmation_status: "awaiting_confirmation" };
  }
  return {
    ...intentJson(intent),
    confirmation_status: evidence.payment_status === "reversed"
      ? "reversed"
      : evidence.contribution_entry_id && evidence.payment_member_id === actor.userId
      ? "credited"
      : "payment_received",
    payment_id: evidence.payment_id,
    contribution_entry_id: evidence.contribution_entry_id ?? null,
    credited_amount_rwf: evidence.credited_amount_rwf ?? null,
    posted_at: evidence.posted_at ?? null,
    provider_transaction_reference: evidence.provider_transaction_reference ?? null,
    provider_transaction_at: evidence.provider_transaction_at ?? null,
    balance_after_contribution_rwf: evidence.balance_after_contribution_rwf ?? null,
    group_balance_after_contribution_rwf: evidence.group_balance_after_contribution_rwf ?? null,
  };
}
async function legacyIntentConfirmation(env, intent, actor) {
  const linked = await first(
    env,
    `SELECT p.id,p.status,p.member_id,p.amount_minor,l.id AS entry_id,l.posted_at
 FROM payments p LEFT JOIN ledger_entries l ON l.payment_id=p.id AND l.kind='contribution'
 WHERE p.intent_id=? AND (p.member_id=? OR EXISTS(SELECT 1 FROM momo_financial_links f WHERE f.payment_id=p.id AND f.beneficiary_member_id=?))`,
    intent.id,
    actor.userId,
    actor.userId,
  );
  if (!linked) return intentConfirmation(intent, actor, null);
  const snapshot = linked.entry_id
    ? await first(
      env,
      "SELECT * FROM contribution_posting_snapshots WHERE ledger_entry_id=?",
      linked.entry_id,
    )
    : null;
  const reference = await first(
    env,
    `SELECT t.provider_transaction_id,t.transaction_at FROM momo_financial_links f JOIN momo_transactions t ON t.id=f.transaction_id WHERE f.payment_id=?`,
    linked.id,
  );
  return intentConfirmation(intent, actor, {
    payment_id: linked.id,
    payment_status: linked.status,
    payment_member_id: linked.member_id,
    contribution_entry_id: linked.entry_id,
    credited_amount_rwf: linked.entry_id ? linked.amount_minor : null,
    posted_at: linked.posted_at,
    provider_transaction_reference: reference?.provider_transaction_id,
    provider_transaction_at: reference?.transaction_at,
    balance_after_contribution_rwf: snapshot?.member_balance_after_minor,
    group_balance_after_contribution_rwf: snapshot?.group_balance_after_minor,
  });
}

export async function createContributionIntent(operation, body, env, actor) {
  const requestId = uuid(body.p_request_id ?? id(), "request_id");
  const g = await groupFor(env, actor, body.collection ?? body.p_collection_id);
  const amount = integer(body.p_expected_amount_rwf ?? body.amount_minor, "amount", 1);
  if (!g.receiver_momo_number || !["mtn_momo", "airtel_money"].includes(g.receiver_network)) {
    throw new ApiError(409, "route_unavailable", "The group payment route is unavailable.");
  }
  const member = await first(
    env,
    "SELECT momo_number,country_code FROM users WHERE id=?",
    actor.userId,
  );
  const sender = normalizeContributionSender(member?.momo_number);
  if (!sender || member?.country_code !== "RW") {
    throw new ApiError(403, "profile_incomplete", "Complete your MoMo profile first.");
  }
  const senderHash = await digest(sender);
  if (
    typeof body.p_sender_phone_hash !== "string" ||
    !/^([a-f0-9]{64})$/.test(body.p_sender_phone_hash) || body.p_sender_phone_hash !== senderHash
  ) {
    throw new ApiError(
      409,
      "contribution_sender_changed",
      "Refresh your payment details before continuing.",
    );
  }
  const previous = await retainedResponse(env, actor, operation, requestId, body, {
    collectionId: g.id,
  });
  if (previous.found) {
    if (previous.value?.sender_phone_hash !== senderHash) {
      throw new ApiError(
        409,
        "contribution_sender_changed",
        "Refresh your payment details before continuing.",
      );
    }
    return { handled: true, value: previous.value };
  }
  const pending = await first(
    env,
    `SELECT p.*,r.response_json AS creation_response_json FROM payment_intents p LEFT JOIN request_receipts r ON r.user_id=p.member_id AND r.request_id=p.request_id AND r.operation='create_contribution_intent' AND r.session_id=p.originating_session_id AND r.body_sha256=p.request_sha256 WHERE p.member_id=? AND p.collection_id=? AND p.amount_minor=? AND p.originating_session_id=? AND p.status='pending' AND p.expires_at>? ORDER BY p.created_at DESC LIMIT 1`,
    actor.userId,
    g.id,
    amount,
    actor.sessionId,
    now(),
  );
  if (pending) {
    if (!boundCreationReceipt(pending, senderHash)) {
      throw new ApiError(
        409,
        "contribution_sender_changed",
        "Refresh your payment details before continuing.",
      );
    }
    return {
      handled: true,
      value: await mutation(
        env,
        actor,
        operation,
        requestId,
        body,
        intentJson({ ...pending, sender_phone_hash: senderHash }),
        [],
        { collectionId: g.id, expectedCollectionRevision: g.revision },
      ),
    };
  }
  const paymentId = id();
  const created = now();
  const expires = new Date(Date.now() + 900000).toISOString();
  const value = intentJson({
    id: paymentId,
    collection_id: g.id,
    amount_minor: amount,
    currency: "RWF",
    rail: "rwanda_momo",
    status: "pending",
    receiver_momo_number: g.receiver_momo_number,
    network: g.receiver_network,
    receiver_label: g.receiver_display_label,
    sender_phone_hash: senderHash,
    created_at: created,
    expires_at: expires,
    originating_session_id: actor.sessionId,
  });
  const stmt = env.DB.prepare(
    `INSERT INTO payment_intents(id,collection_id,member_id,amount_minor,receiver_momo_number,receiver_network,receiver_label,originating_session_id,created_at,expires_at,request_id,request_sha256) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`,
  ).bind(
    paymentId,
    g.id,
    actor.userId,
    amount,
    g.receiver_momo_number,
    g.receiver_network,
    g.receiver_display_label ?? "",
    actor.sessionId,
    created,
    expires,
    requestId,
    await digest(stableJson(body)),
  );
  return {
    handled: true,
    value: await mutation(env, actor, operation, requestId, body, value, [stmt], {
      collectionId: g.id,
      expectedCollectionRevision: g.revision,
    }),
  };
}

export async function listMemberRecentIntents(body, env, actor) {
  const selected = body.p_intent_id == null ? null : uuid(body.p_intent_id, "intent_id");
  if (typeof env.DB.withLockedReadSnapshot === "function") {
    let observations;
    try {
      observations = await memberIntentSnapshot(env.DB, actor, selected, now());
    } catch (error) {
      if (
        error?.code === "40001" || (error?.code === "42501" && error.message === "session_changed")
      ) {
        throw new ApiError(403, "session_changed", "Verify your sign-in before continuing.");
      }
      throw error;
    }
    if (!observations.length) {
      throw new ApiError(403, "session_changed", "Verify your sign-in before continuing.");
    }
    return {
      handled: true,
      value: {
        items: observations.filter((row) => row.id !== null).map((row) =>
          intentConfirmation(restoreOriginalSender(row, actor.sessionId), actor, row)
        ),
        pending_count: observations[0].pending_count,
      },
    };
  }
  const list = await rows(
    env,
    `SELECT p.*,CASE WHEN length(r.response_json)<=8192 THEN r.response_json ELSE NULL END AS creation_response_json FROM payment_intents p
   LEFT JOIN request_receipts r ON r.user_id=p.member_id AND r.request_id=p.request_id AND r.operation='create_contribution_intent'
    AND r.session_id=p.originating_session_id AND r.body_sha256=p.request_sha256
   WHERE p.member_id=? AND (? IS NULL OR p.id=?) ORDER BY p.created_at DESC,p.id LIMIT 50`,
    actor.userId,
    selected,
    selected,
  );
  const count = await first(
    env,
    `SELECT count(*) AS n FROM payment_intents WHERE member_id=? AND status='pending' AND expires_at>?`,
    actor.userId,
    now(),
  );
  const pipeline = await first(
    env,
    "SELECT name FROM sqlite_master WHERE type='table' AND name='momo_financial_links'",
  );
  const original = list.map((row) => restoreOriginalSender(row, actor.sessionId));
  return {
    handled: true,
    value: {
      items: pipeline
        ? await Promise.all(original.map((row) => legacyIntentConfirmation(env, row, actor)))
        : original.map(intentJson),
      pending_count: count.n,
    },
  };
}
