import { ApiError, digest, integer, rows, stableJson, uuid } from "./core.js";
import { historySnapshot } from "./member_history_sql.js";

const exactLimit = 9007199254740991n;
const fail = (status, code, message) => {
  throw new ApiError(status, code, message);
};
const unavailable = () => fail(503, "history_unavailable", "History is unavailable.");
const changed = () => fail(409, "history_changed", "History changed. Refresh before continuing.");
const fields = new Set([
  "p_contract_version",
  "p_collection_id",
  "p_query",
  "p_sort",
  "p_cursor",
  "p_limit",
  "p_from",
  "p_before",
]);
const paymentOrders = {
  newest: "l.posted_at DESC,p.id ASC",
  oldest: "l.posted_at ASC,p.id ASC",
  highest: "p.amount_minor DESC,l.posted_at DESC,p.id ASC",
  lowest: "p.amount_minor ASC,l.posted_at DESC,p.id ASC",
};

function historySort(body) {
  const sort = body.p_sort ?? "newest";
  if (typeof sort !== "string" || !Object.hasOwn(paymentOrders, sort)) {
    fail(400, "invalid_sort", "Invalid history sort.");
  }
  return sort;
}
const numeric = (value) => {
  if (typeof value !== "string" || !/^-?\d+$/.test(value)) unavailable();
  const n = BigInt(value);
  if (n > exactLimit || n < -exactLimit) unavailable();
  return Number(n);
};
function instant(value) {
  if (value === undefined || value === null) return null;
  if (
    typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) ||
    !Number.isFinite(Date.parse(value)) || new Date(value).toISOString() !== value
  ) {
    fail(400, "invalid_history_range", "Use a canonical UTC timestamp for the history range.");
  }
  return value;
}

// A financial event is a retained ledger entry, not the mutable current status
// of its payment. Compensating entries remain visible beside their original.
export async function memberHistoryPage(body, env, actor) {
  if (Object.keys(body).some((key) => !fields.has(key)) || body.p_contract_version !== 2) {
    fail(400, "invalid_history_query", "Use the supported history contract.");
  }
  const selected = body.p_collection_id == null
    ? null
    : uuid(body.p_collection_id, "collection_id");
  if (
    body.p_query !== undefined &&
    (typeof body.p_query !== "string" || body.p_query.length > 80 ||
      /[\u0000-\u001f\u007f]/.test(body.p_query))
  ) {
    fail(400, "invalid_query", "Invalid history search.");
  }
  const search = (body.p_query ?? "").trim(), sort = historySort(body);
  const from = instant(body.p_from), before = instant(body.p_before);
  if (from !== null && before !== null && from >= before) {
    fail(400, "invalid_history_range", "The end must follow the start.");
  }
  const limit = integer(body.p_limit ?? 50, "limit", 1, 50), cursor = body.p_cursor ?? null;
  if (
    cursor !== null &&
    (typeof cursor !== "object" || Array.isArray(cursor) ||
      Object.keys(cursor).sort().join(",") !== "after,revision" ||
      typeof cursor.revision !== "string" || !/^[a-f0-9]{32}$/.test(cursor.revision))
  ) changed();
  if (cursor !== null) uuid(cursor.after, "cursor");
  const literal = "%" + search.replace(/[\\%_]/g, "\\$&") + "%",
    collectId = /^#?[0-9]{6}$/.test(search) ? search.replace(/^#/, "") : null;
  let snapshot;
  try {
    snapshot = await historySnapshot(env, actor, {
      selected,
      search,
      sort,
      from,
      before,
      literal,
      collectId,
      cursor,
      limit,
    });
  } catch (error) {
    if (/session_changed|permission_denied/.test(String(error?.message))) {
      fail(403, "session_changed", "Verify your sign-in before continuing.");
    }
    if (["22007", "22008", "22003"].includes(error?.code)) unavailable();
    throw error;
  }
  if (
    !snapshot || snapshot.principal !== actor.userId || snapshot.session_id !== actor.sessionId ||
    snapshot.versions_valid !== true ||
    snapshot.totals?.valid_instants !== true || !Array.isArray(snapshot.items) ||
    snapshot.items.length > limit + 1
  ) unavailable();
  const revision = (await digest(
    stableJson({
      contract_version: 2,
      subject: actor.userId,
      session: actor.sessionId,
      query: { collection_id: selected, search, sort, from, before },
      versions: snapshot.versions,
    }),
  )).slice(0, 32);
  if (
    cursor &&
    (cursor.revision !== revision || !snapshot.anchor_found || snapshot.items.length === 0)
  ) changed();
  const total = numeric(snapshot.totals.total_count),
    credit = numeric(snapshot.totals.credit),
    debit = numeric(snapshot.totals.debit),
    ownCredit = numeric(snapshot.totals.own_credit),
    ownDebit = numeric(snapshot.totals.own_debit);
  if (
    [total, credit, debit, ownCredit, ownDebit].some((n) => n < 0) || ownCredit > credit ||
    ownDebit > debit
  ) unavailable();
  const items = snapshot.items.slice(0, limit).map((row) => {
    if (
      !Number.isSafeInteger(row.amount_minor) || row.amount_minor === 0 || row.currency !== "RWF" ||
      row.rail !== "rwanda_momo" ||
      typeof row.is_current_user_contribution !== "boolean" ||
      !["contribution", "reversal", "correction"].includes(row.entry_kind) ||
      (row.entry_kind === "contribution"
        ? (row.amount_minor < 0 || row.reverses_entry_id !== null)
        : (row.amount_minor > 0 || typeof row.reverses_entry_id !== "string"))
    ) {
      unavailable();
    }
    return { ...row, provider_confirmation: false, settlement_status: "not_asserted" };
  });
  return {
    contract_version: 2,
    contribution_basis: "reconciled_evidence_entries",
    items,
    total_count: total,
    totals: { RWF: credit - debit },
    own_totals: { RWF: ownCredit - ownDebit },
    credit_totals: { RWF: credit },
    debit_totals: { RWF: debit },
    own_credit_totals: { RWF: ownCredit },
    own_debit_totals: { RWF: ownDebit },
    own_collection_ids: snapshot.totals.own_collection_ids,
    revision,
    next_cursor: snapshot.items.length > limit ? { revision, after: items.at(-1).entry_id } : null,
  };
}

export async function readMemberHistory(body, env, actor) {
  if (body.p_contract_version === 2) return await memberHistoryPage(body, env, actor);
  if (body.p_contract_version !== undefined && body.p_contract_version !== 1) {
    throw new ApiError(400, "invalid_history_query", "Use the supported history contract.");
  }
  const selected = body.p_collection_id == null
    ? null
    : uuid(body.p_collection_id, "collection_id");
  const search = typeof body.p_query === "string" ? body.p_query.trim() : "";
  if (search.length > 80) throw new ApiError(400, "invalid_query", "Invalid history search.");
  const order = paymentOrders[historySort(body)];
  const limit = integer(body.p_limit ?? 50, "limit", 1, 50);
  const list = await rows(
    env,
    `SELECT p.id AS payment_id,p.collection_id,p.amount_minor,p.currency,p.rail,l.posted_at,p.payer_display_name AS supporter_label,CASE WHEN p.member_id=? THEN 1 ELSE 0 END AS own,p.revision FROM payments p JOIN ledger_entries l ON l.payment_id=p.id AND l.kind='contribution' JOIN memberships m ON m.collection_id=p.collection_id WHERE m.user_id=? AND m.active=1 AND p.status IN ('recorded','reconciled','confirmed') AND (? IS NULL OR p.collection_id=?) AND (?='' OR p.payer_display_name LIKE ? OR p.id=?) ORDER BY ${order} LIMIT 10001`,
    actor.userId,
    actor.userId,
    selected,
    selected,
    search,
    "%" + search + "%",
    search,
  );
  if (list.length > 10000) {
    throw new ApiError(
      400,
      "history_filter_required",
      "Choose a group or narrow the history search.",
    );
  }
  const revision =
    (await digest(stableJson(list.map((r) => [r.payment_id, r.revision, r.amount_minor])))).slice(
      0,
      32,
    );
  let start = 0;
  const cursor = body.p_cursor;
  if (cursor) {
    if (cursor.revision !== revision || typeof cursor.after !== "string") {
      throw new ApiError(409, "history_changed", "History changed. Refresh before continuing.");
    }
    start = list.findIndex((r) => r.payment_id === cursor.after) + 1;
    if (start === 0) {
      throw new ApiError(409, "history_changed", "History changed. Refresh before continuing.");
    }
  }
  const total = list.reduce((s, r) => s + r.amount_minor, 0),
    own = list.reduce((s, r) => s + (r.own ? r.amount_minor : 0), 0);
  if (!Number.isSafeInteger(total) || !Number.isSafeInteger(own)) {
    throw new ApiError(503, "history_unavailable", "History is unavailable.");
  }
  const window = list.slice(start, start + limit);
  return {
    items: window.map(({ own, revision, ...r }) => ({
      ...r,
      is_current_user_contribution: own === 1,
    })),
    total_count: list.length,
    totals: { RWF: total },
    own_totals: { RWF: own },
    own_collection_ids: [...new Set(list.filter((r) => r.own).map((r) => r.collection_id))],
    revision,
    next_cursor: start + window.length < list.length
      ? { revision, after: window.at(-1).payment_id }
      : null,
  };
}
