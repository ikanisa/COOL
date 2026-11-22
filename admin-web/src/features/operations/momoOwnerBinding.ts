import {z} from 'zod';
import {sha256Text} from '../core/pendingAttempt';

const digest = z.string().regex(/^[a-f0-9]{64}$/);
const owner = z.object({
  version: z.literal(1),
  request_key: z.string().regex(/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/),
  principal_sha256: digest,
}).strict();
const ownerAndSource = owner.extend({source_sha256: digest});

interface OwnerBindingContext {
  principalId: string;
  storage?: Storage;
}

type OwnerBinding =
  | {kind: 'missing' | 'foreign'}
  | {kind: 'valid'; sourceSha256: string | null};

/** The tab's original storage keys and v1 envelope also cover predecessor requests. */
export function momoOwnerBinding<Context extends OwnerBindingContext>(
  name: (context: Context) => string,
  check: (context: Context) => void,
  invalidMessage: string,
  bindsSource = false,
) {
  function storage(context: Context) {
    return context.storage ?? sessionStorage;
  }

  async function principal(context: Context) {
    const hash = await sha256Text(`collect-momo-principal-v1:${context.principalId}`);
    check(context);
    return hash;
  }

  async function read(context: Context, requestKey: string): Promise<OwnerBinding> {
    check(context);
    let raw: string | null;
    try {
      raw = storage(context).getItem(name(context));
    } catch (error) {
      throw new Error(invalidMessage, {cause: error});
    }
    if (raw === null) return {kind: 'missing'};
    if (raw.length > 1000) throw new Error(invalidMessage);
    let value: unknown;
    try {
      value = JSON.parse(raw);
    } catch (error) {
      throw new Error(invalidMessage, {cause: error});
    }
    const saved = bindsSource ? ownerAndSource.parse(value) : {...owner.parse(value), source_sha256: null};
    if (saved.request_key !== requestKey) throw new Error(invalidMessage);
    return saved.principal_sha256 === await principal(context)
      ? {kind: 'valid', sourceSha256: saved.source_sha256}
      : {kind: 'foreign'};
  }

  async function retain(context: Context, requestKey: string, sourceSha256?: string) {
    if ((await read(context, requestKey)).kind !== 'missing') throw new Error(invalidMessage);
    const binding = {version: 1, request_key: requestKey, principal_sha256: await principal(context)};
    const raw = JSON.stringify(bindsSource ? ownerAndSource.parse({...binding, source_sha256: sourceSha256}) : owner.parse(binding));
    check(context);
    try {
      const store = storage(context), key = name(context);
      if (store.getItem(key) !== null) throw new Error(invalidMessage);
      store.setItem(key, raw);
      if (store.getItem(key) !== raw) throw new Error(invalidMessage);
    } catch (error) {
      throw new Error(invalidMessage, {cause: error});
    }
    check(context);
  }

  async function clear(context: Context, requestKey: string) {
    const saved = await read(context, requestKey);
    if (saved.kind === 'foreign') throw new Error(invalidMessage);
    if (saved.kind === 'missing') return;
    check(context);
    try {
      const store = storage(context), key = name(context);
      store.removeItem(key);
      if (store.getItem(key) !== null) throw new Error(invalidMessage);
    } catch (error) {
      throw new Error(invalidMessage, {cause: error});
    }
  }

  return {read, retain, clear};
}
