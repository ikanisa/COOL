import {AdminRequestError, type AdminClientConfig, type AdminRequestOptions, type AuthoritySnapshot, type JsonObject} from './contracts';
import {admitRequest, requestHeaders, requestNeedsCaptcha, requireRequestAuthority, validateAdminConfig, withCaptcha} from './requestPolicy';
import {acceptedCsrf, decodeResponse} from './responses';
import {fetchAdminResponse} from './transport';

export {AdminRequestError} from './contracts';
export type {AdminBackend, AdminClientConfig, AdminRequestOptions, AdminRequest, AuthoritySnapshot, JsonObject} from './contracts';

interface OwnedResponse {
  isCurrent: () => boolean;
  receiveCsrf?: (token: string | null) => void;
}

/** Cookie transport: never stores bearer/session tokens or automatically retries. */
export class AdminApiClient {
  readonly config: AdminClientConfig;
  private readonly authority: () => AuthoritySnapshot;
  private readonly setCsrf: (token: string | null) => void;
  private readonly onUnauthorized: () => void;
  private readonly fetchImpl: typeof fetch;

  constructor(
    config: AdminClientConfig,
    authority: () => AuthoritySnapshot,
    setCsrf: (token: string | null) => void,
    onUnauthorized: () => void,
  ) {
    validateAdminConfig(config);
    this.config = config;
    this.authority = authority;
    this.setCsrf = setCsrf;
    this.onUnauthorized = onUnauthorized;
    // Native Window.fetch can reject an unbound/class-method receiver.
    this.fetchImpl = config.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  readonly request = async (path: string, options: AdminRequestOptions = {}, owner?: OwnedResponse): Promise<JsonObject> => {
    const admitted = admitRequest(this.config, path, options);
    const {target, method, mutation, authenticated, checksCredentials} = admitted;
    const before = this.authority();
    requireRequestAuthority(this.config, admitted, before);

    const body = requestNeedsCaptcha(this.config, path, admitted) ? await withCaptcha(this.config, options.body) : options.body;
    const current = () => {
      const now = this.authority();
      return now.epoch === before.epoch && (!authenticated || now.key === before.key) && (owner?.isCurrent() ?? true);
    };
    if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.');

    const headers = requestHeaders(this.config, path, options, admitted, before);
    const {response, raw} = await fetchAdminResponse(this.fetchImpl, target, {
      method, headers, body,
    }, {
      signal: options.signal,
      mutation,
      readUnauthorizedBody: checksCredentials,
      timeoutMs: this.config.deadlineMs ?? 30_000,
      maxResponseBytes: this.config.maxResponseBytes ?? 2_097_152,
    });
    if (!current()) throw new AdminRequestError('Your session changed. Reopen this page before continuing.', {outcomeUnknown: mutation});
    const result = decodeResponse(response, raw, path, options, admitted, () => this.onUnauthorized());
    const token = acceptedCsrf(this.config.backend, path, result, mutation);
    if (token !== undefined) (owner?.receiveCsrf ?? this.setCsrf)(token);
    return result;
  };
}
