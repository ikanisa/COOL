import { HttpError } from "./auth.ts";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type RequireAppCheckTokenOptions = {
  fetchFn?: typeof fetch;
  getAccessToken?: () => Promise<string>;
  getProjectId?: () => string;
};

const APP_CHECK_HEADER = "X-Firebase-AppCheck";
const APP_CHECK_SCOPE = "https://www.googleapis.com/auth/firebase";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const GRANT_TYPE = "urn:ietf:params:oauth:grant-type:jwt-bearer";

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64urlEncode(obj: Record<string, unknown>): string {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)));
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\\n/g, "")
    .replace(/\n/g, "")
    .trim();

  const binaryDer = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function getServiceAccount(): ServiceAccount {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    throw new HttpError(
      503,
      "Device attestation is not configured on the server.",
    );
  }

  const serviceAccount = JSON.parse(raw) as ServiceAccount;
  if (!serviceAccount.client_email || !serviceAccount.private_key) {
    throw new HttpError(
      503,
      "Device attestation credentials are incomplete on the server.",
    );
  }

  return serviceAccount;
}

function getFirebaseProjectId(): string {
  const serviceAccount = getServiceAccount();
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")?.trim() ||
    serviceAccount.project_id?.trim();

  if (!projectId) {
    throw new HttpError(
      503,
      "Device attestation project configuration is missing.",
    );
  }

  return projectId;
}

async function buildJwtAssertion(
  serviceAccount: ServiceAccount,
  scope: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64urlEncode({ alg: "RS256", typ: "JWT" });
  const payload = base64urlEncode({
    iss: serviceAccount.client_email,
    scope,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  });
  const signingInput = `${header}.${payload}`;
  const key = await importPrivateKey(serviceAccount.private_key);
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(signingInput),
    ),
  );

  return `${signingInput}.${base64url(signature)}`;
}

async function getFirebaseAccessToken(): Promise<string> {
  if (cachedAccessToken && Date.now() < cachedAccessToken.expiresAt - 60_000) {
    return cachedAccessToken.token;
  }

  const serviceAccount = getServiceAccount();
  const jwt = await buildJwtAssertion(serviceAccount, APP_CHECK_SCOPE);
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=${encodeURIComponent(GRANT_TYPE)}&assertion=${
      encodeURIComponent(jwt)
    }`,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new HttpError(
      503,
      `Device attestation token exchange failed: ${response.status} ${errorText}`,
    );
  }

  const data = await response.json();
  cachedAccessToken = {
    token: data.access_token as string,
    expiresAt: Date.now() + Number(data.expires_in ?? 3600) * 1000,
  };

  return cachedAccessToken.token;
}

/**
 * Validates a Firebase App Check token from the request header.
 *
 * This consumes a limited-use token via Firebase's verifyAppCheckToken API,
 * which also enforces replay protection for future uses of the same token.
 *
 * @throws HttpError if the token is missing, invalid, replayed, or if the
 * server is not configured to verify App Check tokens.
 */
export async function requireAppCheckToken(
  request: Request,
  options: RequireAppCheckTokenOptions = {},
): Promise<string> {
  const token = request.headers.get(APP_CHECK_HEADER)?.trim();

  if (!token || token.length === 0) {
    throw new HttpError(
      401,
      "Device attestation required. Please update your app.",
    );
  }

  const fetchFn = options.fetchFn ?? fetch;
  const getAccessToken = options.getAccessToken ?? getFirebaseAccessToken;
  const getProjectId = options.getProjectId ?? getFirebaseProjectId;
  const accessToken = await getAccessToken();
  const projectId = getProjectId();
  const response = await fetchFn(
    `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}:verifyAppCheckToken`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ appCheckToken: token }),
    },
  );

  if (response.status === 403) {
    throw new HttpError(401, "Invalid device attestation token.");
  }

  if (response.status === 400) {
    throw new HttpError(
      503,
      "Device attestation provider is not supported by the verifier.",
    );
  }

  if (!response.ok) {
    const errorText = await response.text();
    throw new HttpError(
      503,
      `Device attestation verification failed: ${response.status} ${errorText}`,
    );
  }

  const data = await response.json() as { alreadyConsumed?: boolean };
  if (data.alreadyConsumed === true) {
    throw new HttpError(409, "Device attestation token already used.");
  }

  return token;
}
