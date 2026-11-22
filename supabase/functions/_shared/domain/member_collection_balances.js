import { ApiError, rows } from "./core.js";

export async function listMemberCollectionBalances(env, actor) {
  // Authority, all group totals and supporter counts share one MVCC snapshot.
  // SQL NUMERIC aggregates travel as decimal strings until exact-range checks.
  const list = await rows(
    env,
    `WITH authority AS MATERIALIZED(SELECT private.assert_actor() AS principal),
   groups AS MATERIALIZED(SELECT m.collection_id FROM app.memberships m CROSS JOIN authority a
    WHERE m.user_id=a.principal AND a.principal=? AND api.current_session_id()=? AND m.active=1),
   members AS(SELECT l.collection_id,l.member_id,sum(l.amount_minor) AS balance
    FROM app.ledger_entries l JOIN groups g ON g.collection_id=l.collection_id GROUP BY l.collection_id,l.member_id)
   SELECT g.collection_id,coalesce(sum(m.balance),0)::text AS total,
    coalesce(sum(m.balance) FILTER(WHERE m.member_id=?),0)::text AS own,
    count(m.collection_id) FILTER(WHERE m.balance>0)::text AS supporters
   FROM groups g LEFT JOIN members m ON m.collection_id=g.collection_id GROUP BY g.collection_id ORDER BY g.collection_id`,
    actor.userId,
    actor.sessionId,
    actor.userId,
  );
  const exact = (value) => {
    if (typeof value !== "string" || !/^\d+$/.test(value) || BigInt(value) > 9007199254740991n) {
      throw new ApiError(503, "balance_unavailable", "Balances are unavailable.");
    }
    return Number(value);
  };
  return {
    handled: true,
    value: list.map((row) => ({
      collection_id: row.collection_id,
      currency: "RWF",
      balances: [{
        currency: "RWF",
        amount_raised_minor: exact(row.total),
        current_user_balance_minor: exact(row.own),
      }],
      supporter_count: exact(row.supporters),
    })),
  };
}
