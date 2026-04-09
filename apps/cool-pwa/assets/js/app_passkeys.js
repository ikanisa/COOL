export function initializePasskeyControls({
  settings,
  dbGetAll,
  dbPutRecord,
  dbSet,
  trackEvent,
  recordSuccessMoment,
}) {
  document.querySelectorAll('[data-passkey-register]').forEach((button) => {
    button.addEventListener('click', async () => {
      const statusNode = document.querySelector('[data-passkey-status]');
      try {
        const result = await registerPasskey({ dbPutRecord });
        statusNode.textContent = `Passkey registered for ${result.label}.`;
        await trackEvent('passkey_registered');
        await recordSuccessMoment('passkey_registered');
      } catch (error) {
        statusNode.textContent = `Passkey setup failed: ${String(error)}`;
      }
    });
  });

  document.querySelectorAll('[data-passkey-auth]').forEach((button) => {
    button.addEventListener('click', async () => {
      const statusNode = document.querySelector('[data-passkey-status]');
      try {
        const result = await verifyPasskey({ dbGetAll });
        statusNode.textContent = `Verified with ${result.label}.`;
        await dbSet(
          'settings',
          settings.passkeyLastVerifiedAt,
          new Date().toISOString(),
        );
        await trackEvent('passkey_verified');
      } catch (error) {
        statusNode.textContent = `Verification failed: ${String(error)}`;
      }
    });
  });
}

async function registerPasskey({ dbPutRecord }) {
  if (!window.PublicKeyCredential || !navigator.credentials?.create) {
    throw new Error('Passkeys are unavailable in this browser.');
  }

  const label =
    document.querySelector('[data-passkey-name]')?.value?.trim() ||
    'COOL member';
  const userId = crypto.getRandomValues(new Uint8Array(16));
  const challenge = crypto.getRandomValues(new Uint8Array(32));
  const credential = await navigator.credentials.create({
    publicKey: {
      rp: { name: 'COOL PWA', id: window.location.hostname },
      user: {
        id: userId,
        name: `${label.toLowerCase().replace(/\s+/g, '.')}@cool.app`,
        displayName: label,
      },
      challenge,
      pubKeyCredParams: [
        { type: 'public-key', alg: -7 },
        { type: 'public-key', alg: -257 },
      ],
      timeout: 60_000,
      authenticatorSelection: {
        residentKey: 'preferred',
        userVerification: 'preferred',
      },
      attestation: 'none',
    },
  });

  if (!credential) {
    throw new Error('Browser did not return a credential.');
  }

  const record = {
    id: credential.id,
    rawId: bufferToBase64url(credential.rawId),
    label,
    registeredAt: new Date().toISOString(),
  };
  await dbPutRecord('passkeys', record);
  return record;
}

async function verifyPasskey({ dbGetAll }) {
  const credentials = await dbGetAll('passkeys');
  if (!credentials.length) {
    throw new Error('No passkey is registered yet.');
  }

  const challenge = crypto.getRandomValues(new Uint8Array(32));
  const assertion = await navigator.credentials.get({
    publicKey: {
      challenge,
      userVerification: 'preferred',
      allowCredentials: credentials.map((entry) => ({
        type: 'public-key',
        id: base64urlToBuffer(entry.rawId),
      })),
      timeout: 60_000,
    },
  });

  if (!assertion) {
    throw new Error('Verification was cancelled.');
  }

  return credentials.find((entry) => entry.id === assertion.id) ??
    credentials[0];
}

function bufferToBase64url(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function base64urlToBuffer(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(
    normalized.length + ((4 - normalized.length % 4) % 4),
    '=',
  );
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}
