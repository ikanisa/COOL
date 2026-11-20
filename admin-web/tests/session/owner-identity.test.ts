import {afterEach, describe, expect, it, vi} from 'vitest';
import {AdminSessionController, isVerifiedCurrentOwner, parseAdminUser} from '../../src/session/SessionProvider';
import {parseOwnerIdentitySession} from '../../src/session/ownerIdentity';

const principal = '11111111-1111-4111-8111-111111111111', actor = '22222222-2222-4222-8222-222222222222', other = '33333333-3333-4333-8333-333333333333';
const expiry = new Date(Date.now() + 3_600_000).toISOString(), csrf = 'c'.repeat(64), publishableKey = 'sb_publishable_' + 'a'.repeat(32);
const account = {id: actor, principalId: principal, email: 'owner@example.test', role: 'owner', sessionId: 'session-one', permissions: ['overview.read'], assuranceLevel: 1, mfaAt: null, financialModel: 'canonical_evidence_ledger'};
const proof = {schemaVersion: 1, adminId: actor, principalId: principal, email: account.email};
const reply = (value: unknown) => new Response(JSON.stringify(value), {status: 200, headers: {'Content-Type': 'application/json'}});
const controllers: AdminSessionController[] = [];
afterEach(() => {controllers.splice(0).forEach(controller => controller.stop()); sessionStorage.clear();});

describe('Protected owner session proof', () => {
  it('accepts only the exact schema with matching normalized envelope email', () => {
    expect(parseOwnerIdentitySession({ownerIdentity: proof, ownerEmail: account.email})).toEqual(proof);
    expect(parseOwnerIdentitySession({ownerIdentity: {...proof, extra: true}, ownerEmail: account.email})).toBeNull();
    expect(parseOwnerIdentitySession({ownerIdentity: {...proof, email: 'Owner@example.test'}, ownerEmail: 'Owner@example.test'})).toBeNull();
    expect(parseOwnerIdentitySession({ownerIdentity: proof, ownerEmail: 'other@example.test'})).toBeNull();
    expect(parseOwnerIdentitySession({ownerIdentity: null, ownerEmail: null})).toBeNull();
  });
  it('never adopts owner claims from an unauthenticated login result', () => {
    const parsed = parseAdminUser({user: account, expiresAt: expiry, ownerEmail: account.email, ownerIdentity: proof});
    expect(parsed.ownerIdentity).toBeUndefined(); expect(isVerifiedCurrentOwner(parsed)).toBe(false);
  });
  it('preserves a managed text principal through the session refresh and rejects a retargeted owner proof', async () => {
    const firstPrincipal = 'Legacy-Principal-47';
    let currentPrincipal = firstPrincipal;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ?
      reply({user: {...account, principalId: currentPrincipal}, expiresAt: expiry, csrfToken: csrf,
        ownerEmail: account.email, ownerIdentity: {...proof, principalId: firstPrincipal}}) :
      reply({contractVersion: 1, sessionId: account.sessionId, emailVerifiedAt: null}));
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl});
    controllers.push(controller);
    await controller.refresh();
    const original = controller.getSnapshot();
    expect(original.status).toBe('authenticated');
    expect(original.user?.principalId).toBe(firstPrincipal);
    expect(isVerifiedCurrentOwner(original.user!)).toBe(true);
    currentPrincipal = firstPrincipal.toLowerCase();
    await controller.refresh();
    const refreshed = controller.getSnapshot();
    expect(refreshed.status).toBe('authenticated');
    expect(refreshed.user?.principalId).toBe(currentPrincipal);
    expect(isVerifiedCurrentOwner(refreshed.user!)).toBe(false);
    expect(controller.isCurrentAuthority(original.epoch, account.id, account.sessionId)).toBe(false);
  });
  it('rejects invalid database text identities before binding a session', () => {
    for (const principalId of ['', ' leading', 'trailing ', 'a\u0000b', 'a\u0085b', '\ud800', 'a'.repeat(201)]) {
      expect(() => parseAdminUser({user: {...account, principalId}, expiresAt: expiry})).toThrow(/verification/);
    }
    expect(parseAdminUser({user: {...account, principalId: 'équipe-🟩'}, expiresAt: expiry}).principalId).toBe('équipe-🟩');
  });
  it('binds the session proof to all three actor identities and fences later proof changes', async () => {
    let currentOwner = proof;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => String(url).endsWith('/auth/session') ? reply({user: account, expiresAt: expiry, csrfToken: csrf, ownerEmail: currentOwner.email, ownerIdentity: currentOwner}) : reply({contractVersion: 1, sessionId: account.sessionId, emailVerifiedAt: null}));
    const controller = new AdminSessionController({backend: 'supabase', publishableKey, captchaEnabled: false, googleEnabled: false, fetchImpl}); controllers.push(controller);
    await controller.refresh(); const first = controller.getSnapshot(), user = first.user!;
    expect(user.ownerIdentity).toEqual(proof); expect(isVerifiedCurrentOwner(user)).toBe(true);
    expect(isVerifiedCurrentOwner({...user, principalId: other})).toBe(false);
    expect(isVerifiedCurrentOwner({...user, id: other})).toBe(false);
    expect(isVerifiedCurrentOwner({...user, email: 'other@example.test'})).toBe(false);
    expect(isVerifiedCurrentOwner({...user, role: 'admin'})).toBe(false);
    currentOwner = {...proof, adminId: other}; await controller.refresh();
    expect(controller.getSnapshot().epoch).toBeGreaterThan(first.epoch);
    expect(isVerifiedCurrentOwner(controller.getSnapshot().user!)).toBe(false);
    expect(controller.isCurrentAuthority(first.epoch, actor, account.sessionId)).toBe(false);
  });
});
