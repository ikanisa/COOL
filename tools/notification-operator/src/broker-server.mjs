import net from 'node:net';
import { randomUUID } from 'node:crypto';
import { chmod, lstat, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { hasFreshEmailVerification, need, OperatorError, uuid } from './contract.mjs';
import { OperationJournal } from './private_state.mjs';
import { OperatorClient } from './operator_client.mjs';
import {
  admitBrokerDirectory, BROKER_DESCRIPTOR, BROKER_FORMAT, BROKER_SOCKET, publishBrokerBinding, verifyBrokerBinding,
} from './broker-custody.mjs';
import { brokerRequestId, receiveFrames, safeBrokerError, sendFrame } from './broker-ipc.mjs';

const MANAGE = 'assisted_sms.manage';
const READ = 'assisted_sms.read';
const MAX_CONCURRENT_CALLS = 32;

export class BrokerServer {
  #server;
  #http;
  #client;
  #dir;
  #binding;
  #connections = new Set();
  #closing;

  constructor({ stateDir, http, clock = Date.now }) {
    this.#dir = stateDir;
    this.#http = http;
    this.clock = clock;
  }

  #requireCurrentAuthority(session, permission = MANAGE) {
    const current = this.#http.snapshot();
    need(current && current.epoch === session?.epoch && current.authority === session.authority &&
      current.emailVerifiedAt === session.emailVerifiedAt, 'broker_authority_changed_during_call');
    need(hasFreshEmailVerification(session, this.clock()) && hasFreshEmailVerification(current, this.clock()),
      'fresh_verified_email_required');
    need(current.user.permissions.includes(permission), 'permission_required');
  }

  async start() {
    await admitBrokerDirectory(this.#dir);
    const session = this.#http.snapshot();
    need(hasFreshEmailVerification(session, this.clock()), 'fresh_verified_email_required');
    await this.#http.ensure(session.user.sessionId, MANAGE);
    this.#requireCurrentAuthority(session);

    const journalDir = join(this.#dir, 'operations');
    await mkdir(journalDir, { mode: 0o700 });
    const journal = await new OperationJournal(journalDir).ready();
    this.#client = new OperatorClient({ http: this.#http, journal, clock: this.clock });
    this.#requireCurrentAuthority(session);

    const descriptor = {
      format: BROKER_FORMAT,
      origin: this.#http.origin,
      instance_id: randomUUID(),
      operator_session: session.user.sessionId,
      socket_relative_name: BROKER_SOCKET,
      credentials_persisted: false,
      created_at: new Date(this.clock()).toISOString(),
    };
    await this.#listen();
    this.#binding = await publishBrokerBinding(this.#dir, descriptor);
    this.#requireCurrentAuthority(session);
    return {
      descriptor_path: join(this.#dir, BROKER_DESCRIPTOR),
      descriptor_sha256: this.#binding.digest,
      ...descriptor,
    };
  }

  async #listen() {
    const path = join(this.#dir, BROKER_SOCKET);
    // A stale socket and journal belong to the original broker.
    try {
      await lstat(path);
      throw new OperatorError('existing_socket_refused');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    this.#server = net.createServer(socket => this.#accept(socket));
    await new Promise((resolve, reject) => {
      this.#server.once('error', reject);
      this.#server.listen(BROKER_SOCKET, resolve);
    });
    await chmod(path, 0o600);
  }

  async #requireOriginalBinding() {
    await verifyBrokerBinding(this.#dir, this.#binding);
    need(this.#http.snapshot()?.user.sessionId === this.#binding.descriptor.operator_session,
      'broker_session_replaced');
  }

  #accept(socket) {
    const connection = { greeted: false, active: new Map() };
    this.#connections.add(socket);
    socket.on('error', () => {});
    socket.on('close', () => {
      this.#connections.delete(socket);
      for (const controller of connection.active.values()) controller.abort();
    });
    receiveFrames(socket, value => { void this.#receive(socket, connection, value); }, () => {});
  }

  async #receive(socket, connection, value) {
    let id;
    let controller;
    try {
      id = brokerRequestId(value);
      need(!connection.active.has(id), 'duplicate_ipc_request');
      const descriptor = this.#binding?.descriptor;
      need(descriptor && value.instance_id === descriptor.instance_id &&
        value.operator_session === descriptor.operator_session, 'original_broker_session_required');

      // Reserve the identifier before custody I/O yields to another frame.
      if (value.method === 'call') {
        need(connection.active.size < MAX_CONCURRENT_CALLS, 'ipc_concurrency_limit');
        controller = new AbortController();
        connection.active.set(id, controller);
      }

      await this.#requireOriginalBinding();
      let result;
      if (value.method === 'hello') {
        need(!connection.greeted && !Object.hasOwn(value, 'action') && !Object.hasOwn(value, 'arguments') &&
          !Object.hasOwn(value, 'request_id'), 'invalid_ipc_handshake');
        connection.greeted = true;
        result = {
          ...this.#client.metadata(),
          instance_id: descriptor.instance_id,
          operator_session: descriptor.operator_session,
        };
      } else {
        need(connection.greeted, 'ipc_handshake_required');
        if (value.method === 'cancel') {
          uuid(value.request_id);
          connection.active.get(value.request_id)?.abort();
          result = { cancel_requested: true };
        } else {
          need(controller && typeof value.action === 'string' && !Object.hasOwn(value, 'request_id'),
            'unsupported_ipc_method');
          need(value.arguments?.operator_session === descriptor.operator_session, 'original_broker_session_required');
          need(!socket.destroyed && !controller.signal.aborted, 'request_cancelled');
          await this.#replyToCall(socket, value, controller.signal);
          return;
        }
      }
      sendFrame(socket, { id, ok: true, result });
    } catch (error) {
      if (id && !socket.destroyed) sendFrame(socket, { id, ok: false, error: safeBrokerError(error) });
      else socket.destroy();
    } finally {
      if (controller) connection.active.delete(id);
    }
  }

  async #replyToCall(socket, { id, action, arguments: args }, signal) {
    const permission = action === 'list_pending' ? READ : MANAGE;
    // Recovery may settle missing proof through GET while retaining original journal authority.
    if (action === 'get_operation' && this.#http.snapshot()?.proofState !== 'available') {
      await this.#http.ensure(args.operator_session, permission, { signal });
      await this.#requireOriginalBinding();
      need(!signal.aborted, 'request_cancelled');
    }
    const authority = this.#http.snapshot();
    const result = await this.#client.call(action, args, { signal });
    await this.#requireOriginalBinding();
    need(!signal.aborted, 'request_cancelled');
    this.#requireCurrentAuthority(authority, permission);
    // First-use permits exist only in this response.
    if (result?.may_send === true && !(Date.parse(result.manual_handoff?.valid_until) > this.clock())) {
      throw new OperatorError('handoff_expired', { unknown: true });
    }
    sendFrame(socket, { id, ok: true, result });
  }

  close() {
    this.#closing ??= this.#stop();
    return this.#closing;
  }

  async #stop() {
    for (const socket of this.#connections) socket.destroy();
    if (this.#server) await new Promise(resolve => this.#server.close(resolve));
    this.#http.clear();
  }
}
