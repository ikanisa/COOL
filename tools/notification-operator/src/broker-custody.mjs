import { lstat } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { hash, keys, need, ORIGINS, sha, uuid } from './contract.mjs';
import { privateDirectory, privateRead, privateWrite } from './private_state.mjs';

export const BROKER_SOCKET = 'operator.sock';
export const BROKER_DESCRIPTOR = 'broker.json';
export const BROKER_FORMAT = 'collect.operator.session-broker.v1';

const decoder = new TextDecoder('utf8', { fatal: true });

function sameFile(a, b) {
  return a.dev === b.dev && a.ino === b.ino && a.size === b.size &&
    a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs && a.mode === b.mode;
}

async function readPrivateSocket(dir) {
  const stat = await lstat(join(dir, BROKER_SOCKET));
  need(stat.isSocket() && !stat.isSymbolicLink() && stat.uid === process.getuid() &&
    (stat.mode & 0o077) === 0, 'private_owned_socket_required');
  return stat;
}

export async function readConfig(path, expectedSha) {
  hash(expectedSha);
  await privateDirectory(dirname(path));
  const { raw } = await privateRead(path);
  need(sha(raw) === expectedSha, 'reviewed_configuration_digest_required');
  const value = JSON.parse(decoder.decode(raw));
  keys(value, ['format', 'enabled', 'origin']);
  need(value.format === 'collect.operator.client-config.v1' && value.enabled === true &&
    ORIGINS.includes(value.origin), 'independently_approved_configuration_required');
  return value;
}

export async function admitBrokerDirectory(dir) {
  await privateDirectory(dir);
  need(process.cwd() === dir, 'private_socket_working_directory_required');
}

export async function publishBrokerBinding(dir, descriptor) {
  const socketIdentity = await readPrivateSocket(dir);
  const path = join(dir, BROKER_DESCRIPTOR);
  const digest = await privateWrite(path, descriptor);
  const { raw, stat: descriptorIdentity } = await privateRead(path);
  need(sha(raw) === digest, 'broker_descriptor_replaced');
  return { descriptor, digest, descriptorIdentity, socketIdentity };
}

export async function readBrokerBinding(dir, expectedSha) {
  const { raw, stat: descriptorIdentity } = await privateRead(join(dir, BROKER_DESCRIPTOR));
  need(sha(raw) === expectedSha, 'reviewed_broker_descriptor_required');
  const descriptor = JSON.parse(decoder.decode(raw));
  keys(descriptor, [
    'format', 'origin', 'instance_id', 'operator_session', 'socket_relative_name', 'credentials_persisted', 'created_at',
  ]);
  need(descriptor.format === BROKER_FORMAT && ORIGINS.includes(descriptor.origin) &&
    descriptor.socket_relative_name === BROKER_SOCKET && descriptor.credentials_persisted === false,
    'invalid_broker_descriptor');
  uuid(descriptor.instance_id);
  uuid(descriptor.operator_session);
  const socketIdentity = await readPrivateSocket(dir);
  return { descriptor, digest: expectedSha, descriptorIdentity, socketIdentity };
}

export async function verifyBrokerBinding(dir, binding) {
  await privateDirectory(dir);
  const { raw, stat } = await privateRead(join(dir, BROKER_DESCRIPTOR));
  need(sameFile(stat, binding.descriptorIdentity) && sha(raw) === binding.digest, 'broker_descriptor_replaced');
  need(sameFile(await readPrivateSocket(dir), binding.socketIdentity), 'broker_socket_replaced');
}
