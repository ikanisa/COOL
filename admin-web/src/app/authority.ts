import {workspaceAuthorityFields} from '../session/sessionAuthority';
import type {AdminUser} from '../session/sessionResponses';

/** A renewed email proof is checked separately and is not a new actor/session. */
export function featureAuthorityKey(epoch: number, user: AdminUser): string {
  return JSON.stringify([epoch, ...workspaceAuthorityFields(user)]);
}
