import { keys, need, OperatorError, uuid } from './contract.mjs';

const MAX_LINE = 65536;

export function receiveFrames(socket, onMessage, onFailure) {
  const decoder = new TextDecoder('utf8', { fatal: true });
  let pending = Buffer.alloc(0);
  let ended = false;

  function fail(error) {
    ended = true;
    onFailure(error);
    socket.destroy();
  }

  socket.on('data', chunk => {
    if (ended) return;
    try {
      pending = Buffer.concat([pending, chunk]);
      need(pending.length <= MAX_LINE, 'ipc_message_too_large');
      for (let index; (index = pending.indexOf(10)) >= 0;) {
        const line = pending.subarray(0, index);
        pending = pending.subarray(index + 1);
        need(line.length > 0, 'invalid_ipc_frame');
        let value;
        try {
          value = JSON.parse(decoder.decode(line));
        } catch {
          throw new OperatorError('invalid_ipc_json');
        }
        onMessage(value);
      }
    } catch (error) {
      fail(error);
    }
  });

  socket.on('end', () => {
    if (!ended && pending.length > 0) fail(new OperatorError('incomplete_ipc_frame'));
  });
}

export function sendFrame(socket, value) {
  need(!socket.destroyed, 'ipc_disconnected');
  socket.write(JSON.stringify(value) + '\n');
}

export function brokerRequestId(value) {
  keys(value, ['id', 'instance_id', 'operator_session', 'method'], ['action', 'arguments', 'request_id']);
  return uuid(value.id);
}

export function validateBrokerResponse(value) {
  keys(value, ['id', 'ok'], value?.ok === true ? ['result'] : ['error']);
  uuid(value.id);
  need(typeof value.ok === 'boolean' && Object.hasOwn(value, value.ok ? 'result' : 'error'), 'invalid_ipc_response');
  if (!value.ok) {
    keys(value.error, ['code', 'outcome_unknown']);
    need(typeof value.error.code === 'string' && /^[a-z_]{1,100}$/.test(value.error.code) &&
      typeof value.error.outcome_unknown === 'boolean', 'invalid_ipc_error');
  }
  return value;
}

export function safeBrokerError(error) {
  const known = error instanceof OperatorError;
  return {
    code: known ? error.code : 'local_transport_failed',
    outcome_unknown: known && error.outcomeUnknown,
  };
}
