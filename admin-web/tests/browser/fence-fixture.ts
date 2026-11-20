import {withPendingFence, type FenceContext} from '../../src/features/operations/pendingFence';

if (!['localhost', '127.0.0.1', '[::1]'].includes(location.hostname)) throw new Error('Loopback fixture only.');
const context: FenceContext = {identity: {id: 'synthetic-actor', sessionId: 'synthetic-session', email: 'fixture@example.test',
  role: 'admin', permissions: ['sms.manage'], expiresAt: '2099-01-01T00:00:00.000Z'}, family: 'sms-fixture', resourceId: 'synthetic-record', isCurrent: () => true};
const tab = new URLSearchParams(location.search).get('tab');
const ownKey = tab === 'a' ? 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' : 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const status = document.getElementById('status')!;
let observedRevision = '', ownedKey = '';
function show(message: string) {status.textContent = message;}
function action(name: string, work: () => Promise<void>) {
  document.getElementById(name)!.addEventListener('click', () => {void work().catch(() => show('Blocked: shared recovery is unavailable or changed.'));});
}
action('observe', () => withPendingFence(context, async access => {
  const state = access.read(); observedRevision = state.revision; ownedKey = state.kind === 'owned' ? state.requestKey : '';
  show(state.kind === 'owned' ? `Owned ${state.requestKey}` : state.kind === 'empty' ? 'Empty' : 'Foreign request');
}));
action('reserve', () => withPendingFence(context, async access => {
  access.reserve(ownKey, observedRevision); ownedKey = ownKey; show(`Reserved ${ownKey}`);
}));
action('hold', () => withPendingFence(context, async access => {
  access.reserve(ownKey, observedRevision); ownedKey = ownKey; show(`Holding ${ownKey}`);
  await new Promise<void>(() => undefined); // Closing this synthetic tab releases its browser lock.
}));
action('complete', () => withPendingFence(context, async access => {access.clear(ownedKey); show('Completed');}));
