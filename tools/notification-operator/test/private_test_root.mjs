import {mkdtemp,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

// Journals and Unix sockets require a real private local filesystem. The
// checkout may live on a recovery volume without native permission semantics.
export async function privateTestRoot() {
  const parent=await realpath(tmpdir());
  return realpath(await mkdtemp(join(parent,'collect-operator-test-')));
}
