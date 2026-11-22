import { requirePort } from './errors.js';
import { canonicalJson, requireRequestId, sha256 } from './values.js';
import { listingFilterIdentity, listingText, normalizeListingQuery, selectListing } from './listing-query.js';
import {
  mapObservationError as mapped,
  OBSERVATION_HASH as HASH,
  observationInteger as int,
  requireObservation as check,
} from './observation-evidence.js';

// The existing SQL function applies the current actor's installation and history grants.
function pageRows(tx, query, limit, offset) {
  return tx.unsafe('SELECT private.burimunsi_observation_page($1,$2,$3,$4) AS result', [
    query,
    'all',
    limit,
    offset,
  ]);
}

function observationItem(value, groupId) {
  check(typeof value.id === 'string' && value.id.length === 36);
  const at = new Date(int(value.createdAt)).toISOString();
  return {
    id: value.id,
    groupId,
    sourceKind: 'observation',
    sourceId: value.id,
    status: 'source_unresolved',
    at,
    financialEffects: 0,
  };
}

// Ordered by evidence retention time. The latest record does not imply phone chronology.
export async function readLatestRetainedObservationId(tx) {
  const rows = await pageRows(tx, '', 1, 0);
  check(rows.length === 1 && HASH.test(rows[0].result?.revision ?? ''));
  const result = rows[0].result, total = int(result.totalCount, 0, 100000);
  check(Array.isArray(result.items) && result.items.length === Math.min(total, 1));
  return result.items.length ? requireRequestId(result.items[0].id) : null;
}

export async function readObservationListing({ groupId, clock, readSnapshot }, actor, query, cursor) {
  requirePort(cursor, ['create', 'read']);
  const listing = normalizeListingQuery('observations', query), { q, limit } = listing;
  if (query.cursor !== undefined) {
    check(typeof query.cursor === 'string' && query.cursor.length > 0, 'invalid_cursor', 400);
  }
  const filterHash = await sha256(
    canonicalJson({ kind: 'own_observations', q, installationId: actor.installationId }),
  );
  try {
    return await readSnapshot(async (tx) => {
      if (listing.advanced) {
        // Reuse the existing security-definer's exact own-installation authority
        // and metadata projection, within one read snapshot. No body is read.
        const first = await pageRows(tx, q, 100, 0);
        check(first.length === 1 && HASH.test(first[0].result?.revision ?? ''));
        const initial = first[0].result, total = int(initial.totalCount, 0, 100000), raw = [...initial.items];
        for (let offset = 100; offset < total; offset += 100) {
          const part = await pageRows(tx, q, 100, offset);
          check(
            part.length === 1 && part[0].result?.revision === initial.revision &&
              part[0].result.totalCount === total && Array.isArray(part[0].result.items),
          );
          raw.push(...part[0].result.items);
        }
        check(raw.length === total);
        const entries = raw.map((value) => {
          const item = observationItem(value, groupId);
          return { item, at: item.at, search: listingText(item.id) };
        });
        const revision = await sha256(canonicalJson({ retained: initial.revision, entries })), now = clock();
        const scope = {
          groupId,
          actorId: actor.id,
          snapshot: revision,
          filterHash: await sha256(
            canonicalJson({
              kind: 'own_observations',
              installationId: actor.installationId,
              ...listingFilterIdentity(listing),
            }),
          ),
          sort: listing.sort,
        };
        const after = query.cursor ? await cursor.read(query.cursor, scope, now) : null;
        const selected = selectListing(entries, 'observations', listing, after, new Date(now).toISOString());
        const nextCursor = selected.after
          ? await cursor.create({ ...scope, after: selected.after, expiresAt: now + 15 * 60 * 1000 })
          : null;
        return {
          items: selected.items,
          totalCount: selected.totalCount,
          nextCursor,
          revision,
          asOf: selected.asOf,
        };
      }
      const first = await pageRows(tx, q, limit, 0);
      check(first.length === 1 && HASH.test(first[0].result?.revision ?? ''));
      const scope = {
        groupId,
        actorId: actor.id,
        snapshot: first[0].result.revision,
        filterHash,
        sort: 'newest',
      };
      const after = query.cursor ? await cursor.read(query.cursor, scope, clock()) : null;
      const offset = after?.offset ?? 0;
      check(Number.isSafeInteger(offset) && offset >= 0 && offset <= 100000, 'invalid_cursor', 400);
      const selected = offset === 0 ? first : await pageRows(tx, q, limit, offset);
      check(selected.length === 1 && selected[0].result?.revision === scope.snapshot);
      const result = selected[0].result, total = int(result.totalCount, 0, 100000), now = clock();
      check(
        Array.isArray(result.items) && result.items.length === Math.max(0, Math.min(limit, total - offset)) &&
          Number.isSafeInteger(now) && now > 0,
      );
      const items = result.items.map((value) => observationItem(value, groupId));
      const nextCursor = offset + items.length < total
        ? await cursor.create({
          ...scope,
          after: { offset: offset + items.length },
          expiresAt: now + 15 * 60 * 1000,
        })
        : null;
      return {
        items,
        totalCount: total,
        nextCursor,
        revision: scope.snapshot,
        asOf: new Date(now).toISOString(),
      };
    });
  } catch (error) {
    throw mapped(error);
  }
}
