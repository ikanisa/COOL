type ServiceAccount = {
  project_id?: string;
  client_email?: string;
  private_key?: string;
};

const tokenUrl = "https://oauth2.googleapis.com/token";
const appCheckScope = "https://www.googleapis.com/auth/firebase";
const grantType = "urn:ietf:params:oauth:grant-type:jwt-bearer";

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

async function buildJwtAssertion(
  serviceAccount: Required<ServiceAccount>,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64urlEncode({ alg: "RS256", typ: "JWT" });
  const payload = base64urlEncode({
    iss: serviceAccount.client_email,
    scope: appCheckScope,
    aud: tokenUrl,
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

function getServiceAccount(): Required<ServiceAccount> {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")?.trim() ||
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT")?.trim();
  if (!raw) {
    throw new Error(
      "FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_SERVICE_ACCOUNT must be set.",
    );
  }

  const parsed = JSON.parse(raw) as ServiceAccount;
  if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
    throw new Error(
      "Firebase service account JSON is missing project_id, client_email, or private_key.",
    );
  }

  return {
    project_id: parsed.project_id,
    client_email: parsed.client_email,
    private_key: parsed.private_key,
  };
}

async function getAccessToken(
  serviceAccount: Required<ServiceAccount>,
): Promise<string> {
  const jwt = await buildJwtAssertion(serviceAccount);
  const response = await fetch(tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:
      `grant_type=${encodeURIComponent(grantType)}&assertion=${encodeURIComponent(jwt)}`,
  });

  if (!response.ok) {
    throw new Error(
      `Firebase OAuth token exchange failed: ${response.status} ${await response.text()}`,
    );
  }

  const data = await response.json() as { access_token?: string };
  if (!data.access_token) {
    throw new Error("Firebase OAuth token exchange returned no access token.");
  }
  return data.access_token;
}

async function readJson(path: string): Promise<Record<string, unknown>> {
  return JSON.parse(await Deno.readTextFile(path)) as Record<string, unknown>;
}

function extractPlistString(contents: string, key: string): string | null {
  const pattern = new RegExp(
    `<key>${key}</key>\\s*<string>([^<]+)</string>`,
    "m",
  );
  const match = pattern.exec(contents);
  return match?.[1]?.trim() || null;
}

async function getAndroidConfig(): Promise<{
  projectNumber: string;
  appId: string;
}> {
  const raw = await readJson("android/app/src/production/google-services.json");
  const projectInfo = (raw.project_info ?? {}) as Record<string, unknown>;
  const projectNumber = Deno.env.get("FIREBASE_PROJECT_NUMBER")?.trim() ||
    String(projectInfo.project_number ?? "").trim();
  const appId = Deno.env.get("FIREBASE_ANDROID_PRODUCTION_APP_ID")?.trim() ||
    String(
      (((raw.client ?? []) as Record<string, unknown>[])[0]?.client_info as
          Record<string, unknown> | undefined)?.mobilesdk_app_id ?? "",
    ).trim();

  if (!projectNumber || !appId) {
    throw new Error(
      "Could not resolve Android Firebase project_number or mobilesdk_app_id.",
    );
  }

  return { projectNumber, appId };
}

async function getIosConfig(): Promise<{
  projectNumber: string;
  appId: string;
}> {
  const plist = await Deno.readTextFile("ios/Runner/GoogleService-Info.plist");
  const projectNumber = Deno.env.get("FIREBASE_PROJECT_NUMBER")?.trim() ||
    extractPlistString(plist, "GCM_SENDER_ID") ||
    "";
  const appId = Deno.env.get("FIREBASE_IOS_PRODUCTION_APP_ID")?.trim() ||
    extractPlistString(plist, "GOOGLE_APP_ID") ||
    "";

  if (!projectNumber || !appId) {
    throw new Error(
      "Could not resolve iOS Firebase GCM_SENDER_ID or GOOGLE_APP_ID.",
    );
  }

  return { projectNumber, appId };
}

async function fetchProviderConfig(
  accessToken: string,
  name: string,
): Promise<Record<string, unknown>> {
  const response = await fetch(
    `https://firebaseappcheck.googleapis.com/v1beta/${name}`,
    {
      headers: { Authorization: `Bearer ${accessToken}` },
    },
  );

  if (!response.ok) {
    throw new Error(
      `App Check config fetch failed for ${name}: ${response.status} ${await response.text()}`,
    );
  }

  return await response.json() as Record<string, unknown>;
}

async function main() {
  const serviceAccount = getServiceAccount();
  const accessToken = await getAccessToken(serviceAccount);
  const android = await getAndroidConfig();

  const androidConfigName =
    `projects/${android.projectNumber}/apps/${android.appId}/playIntegrityConfig`;
  const androidConfig = await fetchProviderConfig(accessToken, androidConfigName);
  console.log("==> verified Firebase App Check Android provider");
  console.log(`    resource: ${androidConfig.name}`);

  const verifyIos = Deno.env.get("COOL_IOS_RELEASE_ENABLED")?.trim() === "1";
  if (!verifyIos) {
    console.log(
      "==> skipping Firebase App Check iOS provider verification " +
        "(COOL_IOS_RELEASE_ENABLED != 1)",
    );
    return;
  }

  const ios = await getIosConfig();
  const iosConfigName =
    `projects/${ios.projectNumber}/apps/${ios.appId}/appAttestConfig`;
  const iosConfig = await fetchProviderConfig(accessToken, iosConfigName);
  console.log("==> verified Firebase App Check iOS provider");
  console.log(`    resource: ${iosConfig.name}`);
}

if (import.meta.main) {
  await main();
}
