import net from 'node:net';
import { randomUUID } from 'node:crypto';
import { hash, need, OperatorError } from './contract.mjs';
import { admitBrokerDirectory, BROKER_SOCKET, readBrokerBinding, verifyBrokerBinding } from './broker-custody.mjs';
import { receiveFrames, sendFrame, validateBrokerResponse } from './broker-ipc.mjs';

const RESPONSE_TIMEOUT = 35000;

function connectSocket(socket) {
  return new Promise((resolve, reject) => {
    function connected() {
      socket.off('close', closed);
      resolve();
    }
    function closed() {
      socket.off('connect', connected);
      reject(new OperatorError('broker_connection_failed'));
    }
    socket.once('connect', connected);
    socket.once('close', closed);
  });
}

export class BrokerConnector {
  #dir;
  #expected;
  #binding;
  #socket;
  #pending = new Map();
  #connecting = false;
  #failed = false;
  #hello = null;

  constructor({ stateDir, descriptorSha256 }) {
    this.#dir = stateDir;
    this.#expected = hash(descriptorSha256);
  }

  #requireConnection() {
    need(!this.#failed && this.#socket && !this.#socket.destroyed, 'broker_reconnection_refused');
  }

  async connect() {
    need(!this.#connecting && !this.#socket && !this.#failed, 'broker_reconnection_refused');
    this.#connecting = true;
    try {
      await admitBrokerDirectory(this.#dir);
      this.#binding = await readBrokerBinding(this.#dir, this.#expected);
      need(!this.#failed, 'broker_reconnection_refused');
      const socket = this.#socket = net.createConnection(BROKER_SOCKET);
      socket.on('error', () => this.#fail());
      socket.on('close', () => this.#fail());
      receiveFrames(socket, value => this.#accept(value), () => this.#fail());
      await connectSocket(socket);
      const hello = await this.#request('hello');
      const descriptor = this.#binding.descriptor;
      need(hello.instance_id === descriptor.instance_id && hello.operator_session === descriptor.operator_session &&
        hello.origin === descriptor.origin, 'original_broker_session_required');
      this.#hello = hello;
      return hello;
    } catch (error) {
      if (this.#socket) this.#fail();
      throw error;
    } finally {
      this.#connecting = false;
    }
  }

  metadata() {
    if (this.#hello && !this.#failed) return structuredClone(this.#hello);
    return {
      authentication_state: this.#failed ? 'broker_disconnected' : 'unconfigured',
      operator_session: this.#failed ? this.#binding?.descriptor.operator_session ?? null : null,
      credentials_persisted: false,
      messages_automation: false,
    };
  }

  #accept(value) {
    try {
      const response = validateBrokerResponse(value);
      const pending = this.#pending.get(response.id);
      need(pending, 'unexpected_ipc_response');
      this.#pending.delete(response.id);
      pending.finish();
      if (response.ok) pending.resolve(response.result);
      else pending.reject(new OperatorError(response.error.code, { unknown: response.error.outcome_unknown }));
    } catch {
      this.#fail();
    }
  }

  #fail() {
    this.#failed = true;
    this.#socket?.destroy();
    for (const pending of this.#pending.values()) {
      pending.finish();
      pending.reject(new OperatorError('broker_disconnected_outcome_unknown', { unknown: true }));
    }
    this.#pending.clear();
  }

  #track(id, resolve, reject, cleanup) {
    const timer = setTimeout(() => this.#fail(), RESPONSE_TIMEOUT);
    this.#pending.set(id, {
      resolve, reject,
      finish: () => {
        clearTimeout(timer);
        cleanup?.();
      },
    });
  }

  #send(id, method, extra) {
    const descriptor = this.#binding.descriptor;
    try {
      sendFrame(this.#socket, {
        id,
        instance_id: descriptor.instance_id,
        operator_session: descriptor.operator_session,
        method,
        ...extra,
      });
    } catch {
      this.#fail();
    }
  }

  #cancel(requestId) {
    // Keep both response slots until they settle on this connection.
    const id = randomUUID();
    this.#track(id, () => {}, () => {});
    this.#send(id, 'cancel', { request_id: requestId });
  }

  async #request(method, extra = {}, signal) {
    this.#requireConnection();
    await verifyBrokerBinding(this.#dir, this.#binding);
    this.#requireConnection();
    need(!signal?.aborted, 'request_cancelled');
    const id = randomUUID();
    return new Promise((resolve, reject) => {
      const cancel = () => this.#cancel(id);
      this.#track(id, resolve, reject, () => signal?.removeEventListener('abort', cancel));
      signal?.addEventListener('abort', cancel, { once: true });
      this.#send(id, method, extra);
    });
  }

  async call(action, args, { signal } = {}) {
    need(this.#hello && args?.operator_session === this.#binding.descriptor.operator_session,
      'original_broker_session_required');
    const value = await this.#request('call', { action, arguments: args }, signal);
    await verifyBrokerBinding(this.#dir, this.#binding);
    need(!signal?.aborted, 'request_cancelled');
    return value;
  }

  close() {
    this.#fail();
  }
}
