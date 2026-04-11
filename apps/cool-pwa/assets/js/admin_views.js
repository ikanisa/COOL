function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function ensureAuthGate() {
  let gate = document.querySelector('[data-admin-auth-gate]');
  if (gate) {
    return gate;
  }

  gate = document.createElement('div');
  gate.className = 'admin-auth-gate hidden';
  gate.setAttribute('data-admin-auth-gate', '');
  document.body.appendChild(gate);
  return gate;
}

export function renderAuthGate({ authState, otpState, onSendCode, onVerifyCode, onSignOut }) {
  const gate = ensureAuthGate();

  if (!authState.live || authState.authorized) {
    gate.classList.add('hidden');
    document.body.classList.remove('admin-auth-locked');
    return;
  }

  document.body.classList.add('admin-auth-locked');
  gate.classList.remove('hidden');

  const helperMessage = escapeHtml(
    otpState.error ||
      authState.message ||
      'Enter your admin WhatsApp number to receive a verification code.',
  );

  if (authState.authenticated && !authState.authorized) {
    gate.innerHTML = `
      <div class="admin-auth-card card">
        <span class="eyebrow">Admin access blocked</span>
        <h2>COOL Admin refused this account</h2>
        <p class="section-caption">${helperMessage}</p>
        <div class="stack">
          <div class="list-item">
            <div class="list-item-header">
              <strong>${escapeHtml(authState.user?.fullName || authState.user?.phone || 'Authenticated account')}</strong>
              <span class="status-pill error">No access</span>
            </div>
            <p>Only accounts with active COOL admin assignments can open this PWA.</p>
          </div>
        </div>
        <div class="button-row">
          <button class="button" type="button" data-admin-signout>Use another account</button>
        </div>
      </div>
    `;
    gate.querySelector('[data-admin-signout]')?.addEventListener('click', () =>
      onSignOut({ preservePhone: false, suppressReload: true }),
    );
    return;
  }

  // ── Not-admin-phone rejection: show contact card ──────────────
  const isNotAdminPhone = otpState.errorCode === 'NOT_ADMIN_PHONE';
  if (isNotAdminPhone) {
    const whatsappUrl = 'https://wa.me/250795588248?text=' +
      encodeURIComponent('Hello, I would like to request COOL Admin access. My phone number is ' + (otpState.phone || ''));
    gate.innerHTML = `
      <div class="admin-auth-card card">
        <span class="eyebrow" style="background:color-mix(in srgb, var(--danger) 18%, var(--card-surface));color:var(--danger)">Access Denied</span>
        <h2>Admin access required</h2>
        <p class="section-caption">This phone number is not registered as a COOL admin. Contact an existing admin to request access.</p>
        <a href="${whatsappUrl}" target="_blank" rel="noopener noreferrer" class="admin-contact-link" style="display:flex;align-items:center;gap:var(--space-3);padding:var(--space-4);border-radius:var(--radius-md);background:color-mix(in srgb, #25D366 12%, var(--card-surface));text-decoration:none;transition:transform var(--transition);">
          <svg width="36" height="36" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" style="flex-shrink:0">
            <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347z" fill="#25D366"/>
            <path d="M12 2C6.477 2 2 6.477 2 12c0 1.89.525 3.66 1.438 5.168L2 22l4.932-1.412A9.953 9.953 0 0012 22c5.523 0 10-4.477 10-10S17.523 2 12 2zm0 18a7.96 7.96 0 01-4.103-1.132l-.294-.175-3.048.873.814-2.976-.192-.304A7.963 7.963 0 014 12c0-4.411 3.589-8 8-8s8 3.589 8 8-3.589 8-8 8z" fill="#25D366"/>
          </svg>
          <div style="display:grid;gap:2px">
            <strong style="color:var(--primary-text);font-size:0.95rem">Request access via WhatsApp</strong>
            <span style="color:var(--secondary-text);font-size:0.85rem">Message the platform admin directly</span>
          </div>
        </a>
        <div class="button-row">
          <button class="secondary-button" type="button" data-admin-retry-phone>Try a different number</button>
        </div>
      </div>
    `;
    gate.querySelector('[data-admin-retry-phone]')?.addEventListener('click', () => {
      otpState.error = null;
      otpState.errorCode = null;
      onSignOut({ preservePhone: false, suppressReload: true });
    });
    return;
  }

  const isCodeStep = otpState.step === 'code';
  gate.innerHTML = `
    <div class="admin-auth-card card">
      <span class="eyebrow">COOL Admin</span>
      <h2>${isCodeStep ? 'Enter the verification code' : 'Admin Sign In'}</h2>
      <p class="section-caption">${helperMessage}</p>
      ${
        isCodeStep
          ? `
            <form class="form-grid" data-admin-code-form>
              <div class="field full">
                <label for="admin-otp-code">Verification code</label>
                <input id="admin-otp-code" name="code" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6" required>
                <small>Code sent to ${escapeHtml(otpState.phone || 'the admin phone number')} via WhatsApp.</small>
              </div>
              <div class="button-row">
                <button class="button" type="submit">${otpState.isLoading ? 'Verifying…' : 'Verify and open admin'}</button>
                <button class="secondary-button" type="button" data-admin-reset-auth>Use a different phone</button>
              </div>
            </form>
          `
          : `
            <form class="form-grid" data-admin-phone-form>
              <div class="field full">
                <label for="admin-phone">WhatsApp phone number</label>
                <input id="admin-phone" name="phone" type="tel" autocomplete="tel" placeholder="+250788…" value="${escapeHtml(otpState.phone || '')}" required>
                <small>Only registered admin numbers can sign in. A verification code will be sent via WhatsApp.</small>
              </div>
              <div class="button-row">
                <button class="button" type="submit">${otpState.isLoading ? 'Sending…' : 'Send verification code'}</button>
              </div>
            </form>
          `
      }
    </div>
  `;

  gate.querySelector('[data-admin-phone-form]')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const phone = new FormData(event.currentTarget).get('phone')?.toString().trim() || '';
    await onSendCode(phone);
  });

  gate.querySelector('[data-admin-code-form]')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const code = new FormData(event.currentTarget).get('code')?.toString().trim() || '';
    await onVerifyCode(code);
  });

  gate.querySelector('[data-admin-reset-auth]')?.addEventListener('click', () =>
    onSignOut({ preservePhone: false, suppressReload: true }),
  );
}

export function renderSessionToolbar({ authState, onSignOut }) {
  const toolbar = document.querySelector('.toolbar');
  if (!toolbar) {
    return;
  }

  let slot = toolbar.querySelector('[data-admin-session-tools]');
  if (!authState.live || !authState.authorized) {
    slot?.remove();
    return;
  }

  if (!slot) {
    slot = document.createElement('div');
    slot.setAttribute('data-admin-session-tools', '');
    slot.className = 'toolbar-session';
    toolbar.prepend(slot);
  }

  const roleLabel = authState.access?.hasPlatformAccess ? 'Platform admin' : 'Scoped admin';
  slot.innerHTML = `
    <span class="status-pill install">${escapeHtml(roleLabel)}</span>
    <span class="status-pill">${escapeHtml(authState.user?.fullName || authState.user?.phone || authState.user?.id || 'Admin')}</span>
    <button class="ghost-button" type="button" data-admin-signout-toolbar>Sign out</button>
  `;

  slot.querySelector('[data-admin-signout-toolbar]')?.addEventListener('click', () => onSignOut());
}

export function renderRouteRestriction(message) {
  const main = document.getElementById('main');
  if (!main) {
    return;
  }

  let banner = main.querySelector('[data-route-restriction]');
  if (!banner) {
    banner = document.createElement('section');
    banner.className = 'surface-panel card';
    banner.setAttribute('data-route-restriction', '');
    main.prepend(banner);
  }

  banner.innerHTML = `
    <div class="list-item-header">
      <strong>Route access is restricted</strong>
      <span class="status-pill error">Blocked</span>
    </div>
    <p class="section-caption">${escapeHtml(message)}</p>
  `;
}

export function clearRouteRestriction() {
  document.querySelector('[data-route-restriction]')?.remove();
}

export function renderUsersPanel({ data, onTogglePlatformAccess }) {
  const list = document.getElementById('admin-users-list');
  if (!list) {
    return;
  }

  const filterInput = document.querySelector('[data-user-filter]');
  const users = Array.isArray(data?.users) ? data.users : [];

  const render = () => {
    const query = filterInput?.value?.trim().toLowerCase() || '';
    const filtered = query
      ? users.filter((user) => {
          const haystack = [
            user.display_name,
            user.phone,
            user.public_user_id,
            user.id,
          ]
            .filter(Boolean)
            .join(' ')
            .toLowerCase();
          return haystack.includes(query);
        })
      : users;

    if (!filtered.length) {
      list.innerHTML = `
        <li class="list-item">
          <div class="list-item-header">
            <strong>No matching users</strong>
            <span class="status-pill offline">Empty</span>
          </div>
          <p>Try a different name, phone number, or public user ID.</p>
        </li>
      `;
      return;
    }

    list.innerHTML = filtered
      .slice(0, 24)
      .map((user) => {
        const statusLabel = user.has_platform_access
          ? user.has_legacy_admin
            ? 'Legacy admin'
            : 'Platform admin'
          : user.bank_assignment_count > 0
            ? `Bank admin x${user.bank_assignment_count}`
            : 'User';
        const buttonLabel = user.has_platform_access
          ? 'Revoke platform access'
          : 'Grant platform access';
        const buttonDisabled = user.has_legacy_admin || typeof onTogglePlatformAccess !== 'function' ? 'disabled' : '';

        return `
          <li class="list-item">
            <div class="list-item-header">
              <strong>${escapeHtml(user.display_name)}</strong>
              <span class="status-pill ${user.has_platform_access ? 'online' : user.bank_assignment_count > 0 ? 'syncing' : 'offline'}">${escapeHtml(statusLabel)}</span>
            </div>
            <p>${escapeHtml(user.phone || 'No phone on file')} · ${escapeHtml(user.public_user_id || user.id)}</p>
            <div class="list-actions">
              <button class="secondary-button" type="button" data-toggle-user-admin="${escapeHtml(user.id)}" ${buttonDisabled}>${escapeHtml(buttonLabel)}</button>
              ${
                user.has_legacy_admin
                  ? '<span class="meta">Legacy `users.is_admin` rows are visible here but not revocable from the browser yet.</span>'
                  : ''
              }
            </div>
          </li>
        `;
      })
      .join('');

    list.querySelectorAll('[data-toggle-user-admin]').forEach((button) => {
        button.addEventListener('click', async () => {
        if (typeof onTogglePlatformAccess !== 'function') {
          return;
        }
          const user = users.find((entry) => entry.id === button.getAttribute('data-toggle-user-admin'));
          if (!user) {
            return;
          }
        button.disabled = true;
        try {
          await onTogglePlatformAccess(user);
        } finally {
          button.disabled = false;
        }
      });
    });
  };

  if (filterInput) {
    filterInput.oninput = render;
  }
  render();
}

export function renderAppConfigPanel({ data, onSaveConfig }) {
  const list = document.getElementById('admin-config-list');
  const form = document.getElementById('config-change-form');
  if (!list || !form) {
    return;
  }

  const entries = Array.isArray(data?.configEntries) ? data.configEntries : [];
  list.innerHTML = entries.length
    ? entries
        .slice(0, 24)
        .map(
          (entry) => `
            <li class="list-item">
              <div class="list-item-header">
                <strong>${escapeHtml(entry.key)}</strong>
                <span class="status-pill ${entry.country ? 'syncing' : 'online'}">${escapeHtml(entry.country || 'Platform')}</span>
              </div>
              <p>${escapeHtml(entry.description || entry.value || 'No description')}</p>
              <span class="meta mono">${escapeHtml(entry.value || '')}</span>
              <div class="list-actions">
                <button class="secondary-button" type="button" data-load-config="${escapeHtml(entry.key)}">Load into form</button>
              </div>
            </li>
          `,
        )
        .join('')
    : `
        <li class="list-item">
          <div class="list-item-header">
            <strong>No app config loaded</strong>
            <span class="status-pill offline">Empty</span>
          </div>
          <p>Create the first runtime config entry from this browser.</p>
        </li>
      `;

  list.querySelectorAll('[data-load-config]').forEach((button) => {
    button.addEventListener('click', () => {
      const key = button.getAttribute('data-load-config');
      const entry = entries.find((item) => item.key === key);
      if (!entry) {
        return;
      }

      form.querySelector('#config-key').value = entry.key || '';
      form.querySelector('#config-scope').value = entry.country || 'platform';
      form.querySelector('#config-value').value = entry.value || '';
      form.querySelector('#config-description').value = entry.description || '';
    });
  });

  const submitButton = form.querySelector('button[type="submit"]');
  if (submitButton) {
    submitButton.disabled = typeof onSaveConfig !== 'function';
  }

  form.onsubmit = async (event) => {
    event.preventDefault();
    if (typeof onSaveConfig !== 'function') {
      return;
    }
    const formData = new FormData(form);
    const scope = formData.get('scope')?.toString().trim() || '';
    const country =
      !scope || scope.toLowerCase() === 'platform' ? null : scope.toUpperCase();
    if (submitButton) {
      submitButton.disabled = true;
    }

    try {
      await onSaveConfig({
        key: formData.get('config_key')?.toString().trim() || '',
        value: formData.get('requested_value')?.toString() || '',
        description: formData.get('description')?.toString().trim() || '',
        country,
      });
    } finally {
      if (submitButton) {
        submitButton.disabled = false;
      }
    }
  };
}

export function renderRolesPanel({ data, onAssignRole, onRevokeRole }) {
  const list = document.getElementById('admin-role-list');
  const form = document.getElementById('role-assignment-form');
  if (!list || !form) {
    return;
  }

  const assignments = Array.isArray(data?.roleAssignments) ? data.roleAssignments : [];
  list.innerHTML = assignments.length
    ? assignments
        .slice(0, 24)
        .map(
          (assignment) => `
            <li class="list-item">
              <div class="list-item-header">
                <strong>${escapeHtml(assignment.user_name || assignment.user_phone || assignment.user_id)}</strong>
                <span class="status-pill ${assignment.role === 'bank' ? 'syncing' : 'online'}">${escapeHtml(assignment.role === 'bank' ? 'Bank' : 'Platform')}</span>
              </div>
              <p>${escapeHtml(assignment.partner_name || 'Global platform scope')}</p>
              <span class="meta">${escapeHtml(assignment.notes || assignment.granted_at || '')}</span>
              <div class="list-actions">
                <button class="secondary-button" type="button" data-revoke-role="${escapeHtml(assignment.id)}" ${typeof onRevokeRole !== 'function' ? 'disabled' : ''}>Revoke</button>
              </div>
            </li>
          `,
        )
        .join('')
    : `
        <li class="list-item">
          <div class="list-item-header">
            <strong>No active role assignments</strong>
            <span class="status-pill offline">Empty</span>
          </div>
          <p>Create a platform or bank admin assignment below.</p>
        </li>
      `;

  list.querySelectorAll('[data-revoke-role]').forEach((button) => {
    button.addEventListener('click', async () => {
      if (typeof onRevokeRole !== 'function') {
        return;
      }
      const assignmentId = button.getAttribute('data-revoke-role');
      button.disabled = true;
      try {
        await onRevokeRole({ assignmentId });
      } finally {
        button.disabled = false;
      }
    });
  });

  const submitButton = form.querySelector('button[type="submit"]');
  if (submitButton) {
    submitButton.disabled = typeof onAssignRole !== 'function';
  }

  form.onsubmit = async (event) => {
    event.preventDefault();
    if (typeof onAssignRole !== 'function') {
      return;
    }
    const formData = new FormData(form);
    const role = formData.get('role')?.toString().trim().toLowerCase() || '';
    const scopeOrReason = formData.get('scope_or_reason')?.toString().trim() || '';
    if (submitButton) {
      submitButton.disabled = true;
    }

    try {
      await onAssignRole({
        targetUserId: formData.get('user_id')?.toString().trim() || '',
        role,
        bankId: role === 'bank' ? scopeOrReason : '',
        notes: role === 'bank' ? '' : scopeOrReason,
      });
    } finally {
      if (submitButton) {
        submitButton.disabled = false;
      }
    }
  };
}
