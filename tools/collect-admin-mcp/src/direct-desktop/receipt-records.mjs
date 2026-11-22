import { digest, fail, operationKey, PREPARE_SCHEMA, validate } from './contract.mjs';
import { immutable } from './execution-state.mjs';

export function findTicket(tx, ticketId) {
  const ticket = tx.get('tickets', ticketId);
  if (!ticket) fail('ticket_not_found');
  if (ticket.fingerprint !== digest({ source: ticket.source, recipient: ticket.recipient, message: ticket.message, checks: ticket.checks, policy_hash: ticket.policy_hash }) ||
      ticket.id !== `ticket_${ticket.fingerprint}` || ticket.operation_key !== operationKey(ticket.source)) fail('journal_corrupt');
  validate(PREPARE_SCHEMA, { source: ticket.source, recipient: ticket.recipient, message: ticket.message, checks: ticket.checks }, 'journal_corrupt');
  if (tx.get('jobs', ticket.operation_key)?.ticket_id !== ticketId) fail('ticket_superseded');
  return immutable(ticket);
}

export function findAttempt(tx, id) {
  const attempt = tx.all('attempts').find(value => value.id === id);
  if (!attempt) fail('attempt_not_found');
  const ticket = findTicket(tx, attempt.ticket_id);
  if (attempt.operation_key !== ticket.operation_key || !['DISPATCH_ARMED', 'OUTGOING_OBSERVED', 'FAILED_NO_SEND', 'OUTCOME_UNKNOWN'].includes(attempt.state)) fail('journal_corrupt');
  return { attempt: immutable(attempt), ticket };
}
