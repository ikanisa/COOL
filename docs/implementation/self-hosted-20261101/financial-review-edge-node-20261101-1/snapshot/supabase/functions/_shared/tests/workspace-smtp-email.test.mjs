import {wrapFixtureModule} from './helpers/fenced-module.js';
import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {isAbsolute, join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Actual private port with an injected transport. No npm import, real network,
// authentication, SMTP parser, TLS, delivery or hosted compatibility proof.
const root = process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof root === 'string' && isAbsolute(root), 'Provide the coherent actual _shared graph.');
const actual = async name => {if(name==='postgres.js')return import('./helpers/fenced-postgres.js');return wrapFixtureModule(name,await import(pathToFileURL(join(root, name)).href));};
const {createWorkspaceSmtpEmail, WorkspaceSmtpError} = await actual('workspace-smtp-email.js');
const {sendTransactionalEmail} = await actual('domain/email_delivery.js');
const {ApiError} = await actual('domain/core.js');

const SENDER = 'info@ikanisa.com';
const RECIPIENT = 'synthetic.staff@example.invalid';
const PASSWORD = 'synthetic-not-a-real-workspace-app-password';
const DETAIL = 'synthetic private SMTP detail';
const MIME_ID = '<synthetic-operation-0001@ikanisa.com>';
const ENV = {COLLECT_NOTICE_SMTP_PASSWORD: PASSWORD};
const message = () => ({from: {email: SENDER, name: 'Collect'}, to: RECIPIENT,
  subject: 'Collect Admin access approved',
  text: 'Your staff access is approved.\nOpen the ordinary Collect Admin login to request a code.'});
const accepted = extra => ({messageId: MIME_ID, accepted: [RECIPIENT], rejected: [], rejectedErrors: [],
  response: '250 2.0.0 accepted', envelope: {from: SENDER, to: [RECIPIENT]}, ...extra});

function transport(reply = () => accepted()) {
  const constructions = [], sends = [], closes = [];let sendStarted;const sendReady=new Promise(resolve=>{sendStarted=resolve;});
  const createTransport = options => {
    constructions.push(options);
    return {async sendMail(mail) {sends.push(mail);sendStarted(); return reply(mail);}, close() {closes.push(true);}};
  };
  return {createTransport, constructions, sends, closes,sendReady};
}
function safeUnknown(error) {
  assert.ok(error instanceof WorkspaceSmtpError); assert.equal(error.outcome, 'unknown');
  const exposed = String(error) + JSON.stringify(error);
  for (const value of [PASSWORD, DETAIL, RECIPIENT]) assert.equal(exposed.includes(value), false);
  assert.equal(error.code, 'workspace_smtp_unknown');
  return true;
}
function fixedOptions(options) {
  assert.equal(options.host, 'smtp.gmail.com'); assert.equal(options.port, 465);
  assert.equal(options.secure, true); assert.equal(options.pool, false);
  assert.equal(options.logger, false); assert.equal(options.debug, false);
  assert.equal(options.transactionLog, false);
  assert.deepEqual(options.auth, {type: 'login', user: SENDER, pass: PASSWORD});
  assert.equal(options.authMethod, 'LOGIN');
  assert.equal(options.tls.rejectUnauthorized, true); assert.equal(options.tls.servername, 'smtp.gmail.com');
  for (const key of ['connectionTimeout', 'greetingTimeout', 'socketTimeout']) {
    assert.ok(Number.isSafeInteger(options[key]) && options[key] > 0 && options[key] < 10000,
      key + ' must be a finite phase/inactivity limit inside the observational wrapper budget');
  }
  for (const key of ['url', 'service', 'proxy', 'getSocket'])
    assert.equal(Object.hasOwn(options, key), false, 'No alternate destination/downgrade/socket path');
  assert.equal(options.requireTLS, true); assert.equal(options.ignoreTLS, false); assert.equal(options.opportunisticTLS, false);
  assert.equal(options.tls.checkServerIdentity, undefined);
  assert.ok(options.maxRequeues === undefined || options.maxRequeues === 0);
}

test('actual workspace SMTP port validation and acceptance boundary', {concurrency: false}, async t => {
  await t.test('fixed implicit-TLS options and closed message produce only a correlation ID after positive DATA acceptance', async () => {
    const stub = transport(), binding = createWorkspaceSmtpEmail(ENV, stub);
    assert.equal(binding.provider, 'workspace_smtp_v1');
    assert.deepEqual(await binding.send(message()), {messageId: MIME_ID});
    assert.equal(stub.constructions.length, 1); fixedOptions(stub.constructions[0]);
    assert.equal(stub.sends.length, 1); const mail = stub.sends[0];
    assert.deepEqual(mail.envelope, {from: SENDER, to: [RECIPIENT]});
    assert.deepEqual(mail.from, {name: 'Collect', address: SENDER});
    assert.deepEqual(mail.to, {address: RECIPIENT});
    assert.equal(mail.subject, message().subject); assert.equal(mail.text, message().text);
    for (const key of ['auth', 'attachments', 'headers', 'cc', 'bcc', 'replyTo', 'raw']) assert.equal(Object.hasOwn(mail, key), false);
  });
  for (const [name, env] of [
    ['absent', {}], ['empty password', {...ENV, COLLECT_NOTICE_SMTP_PASSWORD: ''}],
    ['whitespace password', {...ENV, COLLECT_NOTICE_SMTP_PASSWORD: '  '}],
    ['conflicting sender', {...ENV, AUTH_EMAIL_FROM: 'other@example.invalid'}],
    ['HTTP URL configured', {...ENV, TRANSACTIONAL_EMAIL_URL: 'https://relay.synthetic.invalid/send'}],
    ['HTTP token configured', {...ENV, TRANSACTIONAL_EMAIL_TOKEN: 'synthetic-relay-token'}],
  ]) await t.test(name + ' stays non-sendable before transport construction', () => {
    const stub = transport();
    assert.throws(() => createWorkspaceSmtpEmail(env, stub), error => {
      assert.ok(error instanceof WorkspaceSmtpError); assert.equal(error.code, 'workspace_smtp_unavailable');
      assert.equal(error.outcome, 'unavailable'); assert.equal((String(error) + JSON.stringify(error)).includes(PASSWORD), false); return true;
    });
    assert.equal(stub.constructions.length, 0);
  });
  const invalidMessages = [
    ['recipient list', {to: RECIPIENT + ',other@example.invalid'}],
    ['recipient display name', {to: 'Name <' + RECIPIENT + '>'}],
    ['recipient array', {to: [RECIPIENT]}],
    ['recipient NUL', {to: 'synthetic\u0000@example.invalid'}],
    ['recipient C1', {to: 'synthetic\u0085@example.invalid'}],
    ['recipient header injection', {to: RECIPIENT + '\r\nBcc: other@example.invalid'}],
    ['wrong sender', {from: {email: 'other@example.invalid', name: 'Collect'}}],
    ['sender name control', {from: {email: SENDER, name: 'Collect\nInjected'}}],
    ['sender name override', {from: {email: SENDER, name: 'Unapproved Product'}}],
    ['subject CRLF', {subject: 'Approved\r\nBcc: other@example.invalid'}],
    ['subject NUL', {subject: 'Approved\u0000'}], ['subject C1', {subject: 'Approved\u0085'}],
    ['text CR', {text: 'Approved\rInjected'}], ['text NUL', {text: 'Approved\u0000'}],
    ['text TAB', {text: 'Approved\tInjected'}], ['text C1', {text: 'Approved\u0085'}],
    ['HTML control', {html: '<p>Approved\rInjected</p>'}],
    ['attachments', {attachments: []}], ['custom headers', {headers: {'X-Extra': 'value'}}],
    ['envelope override', {envelope: {to: ['other@example.invalid']}}],
    ['message auth', {auth: {user: 'other', pass: 'synthetic'}}],
    ['file content', {text: {path: '/synthetic/not-read'}}],
  ];
  for (const [name, changes] of invalidMessages) await t.test(name + ' never reaches sendMail', async () => {
    const stub = transport(), binding = createWorkspaceSmtpEmail(ENV, stub);
    await assert.rejects(binding.send({...message(), ...changes}), error => {
      assert.ok(error instanceof WorkspaceSmtpError);
      const exposed = String(error) + JSON.stringify(error);
      for (const value of [PASSWORD, RECIPIENT]) assert.equal(exposed.includes(value), false);
      return true;
    });
    assert.equal(stub.sends.length, 0);
  });
  for (const [name, result] of [
    ['generated MIME ID alone', {messageId: MIME_ID}],
    ['DATA invitation is not acceptance', accepted({response: '354 send data'})],
    ['negative final DATA reply', accepted({response: '550 5.7.1 refused'})],
    ['missing final reply', accepted({response: undefined})],
    ['no accepted recipient', accepted({accepted: []})],
    ['different accepted recipient', accepted({accepted: ['other@example.invalid']})],
    ['extra accepted recipient', accepted({accepted: [RECIPIENT, 'other@example.invalid']})],
    ['rejected recipient present', accepted({rejected: [RECIPIENT]})],
    ['rejected error present', accepted({rejectedErrors: [new Error(DETAIL)]})],
    ['generic error present', accepted({errors: [new Error(DETAIL)]})],
    ['pending recipient present', accepted({pending: [RECIPIENT]})],
    ['wrong envelope sender', accepted({envelope: {from: 'other@example.invalid', to: [RECIPIENT]}})],
    ['wrong envelope target', accepted({envelope: {from: SENDER, to: ['other@example.invalid']}})],
    ['extra envelope target', accepted({envelope: {from: SENDER, to: [RECIPIENT, 'other@example.invalid']}})],
    ['unsafe MIME ID', accepted({messageId: '<unsafe\u0000@ikanisa.com>'})],
  ]) await t.test(name + ' is unknown after one send without retry', async () => {
    const stub = transport(() => result), binding = createWorkspaceSmtpEmail(ENV, stub);
    await assert.rejects(binding.send(message()), safeUnknown); assert.equal(stub.sends.length, 1);
  });
  await t.test('raw provider errors are sanitized and no automatic second attempt occurs', async () => {
    const stub = transport(() => {throw Object.assign(new Error(DETAIL + ' ' + PASSWORD + ' ' + RECIPIENT),
      {code: 'ETIMEDOUT', response: DETAIL, command: 'DATA'});});
    const binding = createWorkspaceSmtpEmail(ENV, stub);
    await assert.rejects(binding.send(message()), safeUnknown); assert.equal(stub.sends.length, 1);
  });
  await t.test('the actual wrapper timeout is observational; a late SMTP effect causes no second send or result upgrade', async () => {
    let resolveSend;
    const pending = new Promise(resolve => {resolveSend = resolve;});
    const stub = transport(() => pending), actualBinding = createWorkspaceSmtpEmail(ENV, stub);
    let actualCompletion;
    const binding = {provider: actualBinding.provider, send(mail) {
      actualCompletion = actualBinding.send(mail); return actualCompletion;
    }};
    const previousSet = globalThis.setTimeout, previousClear = globalThis.clearTimeout;
    const timers = [], cleared = [];
    globalThis.setTimeout = (callback, milliseconds, ...args) => {
      if(milliseconds!==10000)return previousSet(callback,milliseconds,...args);const timer = {callback: () => callback(...args), milliseconds}; timers.push(timer); return timer;
    };
    globalThis.clearTimeout = timer => {if(timers.includes(timer))cleared.push(timer);else previousClear(timer);};
    try {
      const observed = sendTransactionalEmail({AUTH_EMAIL: binding, AUTH_EMAIL_FROM: SENDER},
        {to: RECIPIENT, subject: message().subject, text: message().text});
      await stub.sendReady;
      assert.equal(stub.sends.length, 1); assert.equal(timers.length, 1); assert.equal(timers[0].milliseconds, 10000);
      timers[0].callback();
      await assert.rejects(observed, error => error instanceof ApiError && error.status === 503 && error.code === 'email_unavailable');
      assert.equal(stub.closes.length, 0, 'Observation timeout did not settle the still-pending port send');
      resolveSend(accepted()); assert.deepEqual(await actualCompletion, {messageId: MIME_ID});
      await assert.rejects(observed, error => error instanceof ApiError && error.code === 'email_unavailable');
      assert.equal(stub.sends.length, 1); assert.equal(stub.closes.length, 1); assert.deepEqual(cleared, timers);
    } finally {
      resolveSend(accepted()); globalThis.setTimeout = previousSet; globalThis.clearTimeout = previousClear;
    }
  });
});
