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

function ensureConfirmDialog() {
  let dialog = document.querySelector('[data-admin-confirm-dialog]');
  if (dialog) {
    return dialog;
  }

  dialog = document.createElement('dialog');
  dialog.className = 'surface-panel';
  dialog.setAttribute('data-admin-confirm-dialog', '');
  document.body.appendChild(dialog);
  return dialog;
}

async function confirmAdminAction({
  title,
  eyebrow = 'Review change',
  description = '',
  body = '',
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  danger = false,
} = {}) {
  const dialog = ensureConfirmDialog();
  if (typeof dialog.showModal !== 'function') {
    return window.confirm([title, description].filter(Boolean).join('\n\n'));
  }

  return await new Promise((resolve) => {
    dialog.innerHTML = `
      <form method="dialog" class="stack">
        <span class="eyebrow">${escapeHtml(eyebrow)}</span>
        <div>
          <h2 class="page-title compact-title">${escapeHtml(title || 'Review admin action')}</h2>
          ${description ? `<p class="section-caption">${escapeHtml(description)}</p>` : ''}
        </div>
        <div class="review-block">
          ${body}
        </div>
        <div class="button-row">
          <button class="${danger ? 'danger-button' : 'button'}" type="submit" value="confirm">${escapeHtml(confirmLabel)}</button>
          <button class="secondary-button" type="submit" value="cancel">${escapeHtml(cancelLabel)}</button>
        </div>
      </form>
    `;

    dialog.addEventListener(
      'close',
      () => resolve(dialog.returnValue === 'confirm'),
      { once: true },
    );
    dialog.showModal();
  });
}

function renderPagination(container, pagination, onPageChange) {
  if (!container) {
    return;
  }

  if (!pagination || pagination.total <= pagination.limit) {
    container.innerHTML = '';
    return;
  }

  container.innerHTML = `
    <div class="pagination-row">
      <span class="meta">Page ${escapeHtml(pagination.page)} of ${escapeHtml(pagination.totalPages)} · ${escapeHtml(pagination.total)} total</span>
      <div class="button-row">
        <button class="secondary-button" type="button" data-page-nav="prev" ${pagination.hasPreviousPage ? '' : 'disabled'}>Previous</button>
        <button class="secondary-button" type="button" data-page-nav="next" ${pagination.hasNextPage ? '' : 'disabled'}>Next</button>
      </div>
    </div>
  `;

  container.querySelector('[data-page-nav="prev"]')?.addEventListener('click', () => {
    if (pagination.hasPreviousPage) {
      onPageChange?.(pagination.page - 1);
    }
  });
  container.querySelector('[data-page-nav="next"]')?.addEventListener('click', () => {
    if (pagination.hasNextPage) {
      onPageChange?.(pagination.page + 1);
    }
  });
}

function setSelectOptions(select, options, { includeBlank = false, selectedValue = '' } = {}) {
  if (!select) {
    return;
  }

  const normalized = Array.isArray(options) ? options : [];
  const optionHtml = [
    includeBlank ? '<option value="">All</option>' : '',
    ...normalized.map((option) => {
      if (typeof option === 'string') {
        return `<option value="${escapeHtml(option)}">${escapeHtml(option)}</option>`;
      }
      return `<option value="${escapeHtml(option.value)}">${escapeHtml(option.label)}</option>`;
    }),
  ].join('');

  select.innerHTML = optionHtml;
  select.value = selectedValue;
}

function setDatalistOptions(datalist, options) {
  if (!datalist) {
    return;
  }
  datalist.innerHTML = (Array.isArray(options) ? options : [])
    .map((option) => `<option value="${escapeHtml(option)}"></option>`)
    .join('');
}

function formatJsonSummary(value) {
  if (value === undefined || value === null || value === '') {
    return 'None';
  }
  const text =
    typeof value === 'string' ? value : JSON.stringify(value, null, 2);
  return text.length > 600 ? `${text.slice(0, 597)}...` : text;
}

function findUserSelection(rawValue, users) {
  const value = String(rawValue || '').trim();
  if (!value) {
    return null;
  }

  return (Array.isArray(users) ? users : []).find((user) =>
    [
      user.id,
      user.label,
      user.display_name,
      user.phone,
      user.public_user_id,
    ]
      .filter(Boolean)
      .includes(value),
  ) || null;
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
                <small>If the number is authorized, a verification code will be sent via WhatsApp.</small>
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

export function renderUsersPanel({
  data,
  onTogglePlatformAccess,
  onFilterChange,
  onPageChange,
}) {
  const list = document.getElementById('admin-users-list');
  const form = document.getElementById('user-filter-form');
  const filterInput = document.querySelector('[data-user-filter]');
  const summary = document.querySelector('[data-user-results-summary]');
  const paginationNode = document.querySelector('[data-user-pagination]');
  if (!list) {
    return;
  }

  const users = Array.isArray(data?.users) ? data.users : [];
  const pagination = data?.pagination || null;
  const filters = data?.filters || {};

  if (filterInput) {
    filterInput.value = filters.q || '';
  }
  if (form) {
    form.onsubmit = (event) => {
      event.preventDefault();
      onFilterChange?.({
        q: filterInput?.value || '',
        page: 1,
      });
    };
  }
  const resetUserFilter = form?.querySelector('[data-user-filter-reset]');
  if (resetUserFilter) {
    resetUserFilter.onclick = () => {
      if (filterInput) {
        filterInput.value = '';
      }
      onFilterChange?.({ q: '', page: 1 });
    };
  }

  if (summary && pagination) {
    summary.textContent = pagination.total
      ? `Showing ${users.length} account${users.length === 1 ? '' : 's'} from ${pagination.total} total.`
      : 'No accounts match the current filter.';
  }

  list.innerHTML = users.length
    ? users
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

          return `
            <li class="list-item">
              <div class="list-item-header">
                <strong>${escapeHtml(user.display_name)}</strong>
                <span class="status-pill ${user.has_platform_access ? 'online' : user.bank_assignment_count > 0 ? 'syncing' : 'offline'}">${escapeHtml(statusLabel)}</span>
              </div>
              <p>${escapeHtml(user.phone || 'No phone on file')} · ${escapeHtml(user.public_user_id || user.id)}</p>
              ${
                user.has_legacy_admin
                  ? '<span class="meta">Legacy flag still exists on this account. Revoking from the browser will clear the flag and revoke active sessions.</span>'
                  : ''
              }
              <div class="list-actions">
                <button class="secondary-button" type="button" data-toggle-user-admin="${escapeHtml(user.id)}" ${typeof onTogglePlatformAccess !== 'function' ? 'disabled' : ''}>${escapeHtml(buttonLabel)}</button>
              </div>
            </li>
          `;
        })
        .join('')
    : `
        <li class="list-item">
          <div class="list-item-header">
            <strong>No matching users</strong>
            <span class="status-pill offline">Empty</span>
          </div>
          <p>Try a different name, phone number, or public user ID.</p>
        </li>
      `;

  list.querySelectorAll('[data-toggle-user-admin]').forEach((button) => {
    button.addEventListener('click', async () => {
      if (typeof onTogglePlatformAccess !== 'function') {
        return;
      }
      const user = users.find((entry) => entry.id === button.getAttribute('data-toggle-user-admin'));
      if (!user) {
        return;
      }

      const confirmed = await confirmAdminAction({
        title: user.has_platform_access
          ? 'Revoke platform access'
          : 'Grant platform access',
        description: user.has_platform_access
          ? 'This will remove privileged access and invalidate active admin sessions for the target user.'
          : 'This will grant platform-wide admin access to the selected user.',
        body: `
          <div class="stack">
            <div class="list-item">
              <strong>${escapeHtml(user.display_name)}</strong>
              <span class="meta">${escapeHtml(user.phone || user.public_user_id || user.id)}</span>
            </div>
            ${
              user.has_legacy_admin
                ? '<p class="meta">Legacy admin flag detected. This revoke path will clear the old flag as well as any role assignment.</p>'
                : ''
            }
          </div>
        `,
        confirmLabel: user.has_platform_access ? 'Revoke access' : 'Grant access',
        danger: user.has_platform_access,
      });

      if (!confirmed) {
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

  renderPagination(paginationNode, pagination, onPageChange);
}

export function renderAppConfigPanel({
  data,
  onSaveConfig,
  onFilterChange,
  onPageChange,
}) {
  const list = document.getElementById('admin-config-list');
  const form = document.getElementById('config-change-form');
  const filterForm = document.getElementById('config-filter-form');
  const filterInput = document.querySelector('[data-config-filter]');
  const filterScope = document.querySelector('[data-config-filter-scope]');
  const summary = document.querySelector('[data-config-results-summary]');
  const paginationNode = document.querySelector('[data-config-pagination]');
  if (!list || !form) {
    return;
  }

  const entries = Array.isArray(data?.configEntries) ? data.configEntries : [];
  const pagination = data?.pagination || null;
  const filters = data?.filters || {};
  const configCatalog = data?.configCatalog || { keys: [], scopes: [] };

  setDatalistOptions(
    document.getElementById('config-key-catalog'),
    configCatalog.keys || [],
  );
  setSelectOptions(
    document.getElementById('config-scope'),
    [{ value: 'platform', label: 'Platform' }].concat(
      (configCatalog.scopes || [])
        .filter((scope) => scope && scope.toLowerCase() !== 'platform')
        .map((scope) => ({ value: scope, label: scope })),
    ),
    { selectedValue: form.querySelector('#config-scope')?.value || 'platform' },
  );
  setSelectOptions(
    filterScope,
    [{ value: 'platform', label: 'Platform' }].concat(
      (configCatalog.scopes || [])
        .filter((scope) => scope && scope.toLowerCase() !== 'platform')
        .map((scope) => ({ value: scope, label: scope })),
    ),
    { includeBlank: true, selectedValue: filters.scope || '' },
  );

  if (filterInput) {
    filterInput.value = filters.q || '';
  }
  if (filterForm) {
    filterForm.onsubmit = (event) => {
      event.preventDefault();
      onFilterChange?.({
        q: filterInput?.value || '',
        scope: filterScope?.value || '',
        page: 1,
      });
    };
  }
  const resetConfigFilter = filterForm?.querySelector('[data-config-filter-reset]');
  if (resetConfigFilter) {
    resetConfigFilter.onclick = () => {
      if (filterInput) {
        filterInput.value = '';
      }
      if (filterScope) {
        filterScope.value = '';
      }
      onFilterChange?.({ q: '', scope: '', page: 1 });
    };
  }

  if (summary && pagination) {
    summary.textContent = pagination.total
      ? `Showing ${entries.length} config entr${entries.length === 1 ? 'y' : 'ies'} from ${pagination.total} total.`
      : 'No config entries match the current filter.';
  }

  list.innerHTML = entries.length
    ? entries
        .map((entry) => {
          const loadKey = `${entry.key}::${entry.country || 'platform'}`;
          return `
            <li class="list-item">
              <div class="list-item-header">
                <strong>${escapeHtml(entry.key)}</strong>
                <span class="status-pill ${entry.country ? 'syncing' : 'online'}">${escapeHtml(entry.country || 'Platform')}</span>
              </div>
              <p>${escapeHtml(entry.description || 'No description')}</p>
              <pre class="review-block review-code">${escapeHtml(formatJsonSummary(entry.value || ''))}</pre>
              <div class="list-actions">
                <button class="secondary-button" type="button" data-load-config="${escapeHtml(loadKey)}">Load into form</button>
              </div>
            </li>
          `;
        })
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
      const [key, rawScope] = (button.getAttribute('data-load-config') || '').split('::');
      const entry = entries.find((item) => item.key === key && (item.country || 'platform') === rawScope);
      if (!entry) {
        return;
      }

      form.querySelector('#config-key').value = entry.key || '';
      form.querySelector('#config-scope').value = entry.country || 'platform';
      form.querySelector('#config-value').value = entry.value || '';
      form.querySelector('#config-description').value = entry.description || '';
      form.querySelector('#config-change-reason').focus();
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
    const scope = formData.get('scope')?.toString().trim() || 'platform';
    const country =
      !scope || scope.toLowerCase() === 'platform' ? null : scope.toUpperCase();
    const key = formData.get('config_key')?.toString().trim() || '';
    const payload = {
      key,
      value: formData.get('requested_value')?.toString() || '',
      description: formData.get('description')?.toString().trim() || '',
      country,
      changeReason: formData.get('change_reason')?.toString().trim() || '',
    };
    const existing = entries.find(
      (entry) => entry.key === key && (entry.country || null) === (country || null),
    );

    const confirmed = await confirmAdminAction({
      title: existing ? 'Review config update' : 'Review new config entry',
      description: 'Config writes are immediate and should only be made with a clear operational reason.',
      confirmLabel: existing ? 'Save update' : 'Create entry',
      body: `
        <div class="stack">
          <div class="list-item">
            <strong>${escapeHtml(payload.key || 'Missing key')}</strong>
            <span class="meta">${escapeHtml(country || 'Platform')}</span>
          </div>
          <div class="detail-grid compact-grid">
            <div class="list-item">
              <strong>Current value</strong>
              <pre class="review-code">${escapeHtml(formatJsonSummary(existing?.value || 'None'))}</pre>
            </div>
            <div class="list-item">
              <strong>Requested value</strong>
              <pre class="review-code">${escapeHtml(formatJsonSummary(payload.value || 'None'))}</pre>
            </div>
          </div>
          <div class="list-item">
            <strong>Reason</strong>
            <span class="meta">${escapeHtml(payload.changeReason || 'None provided')}</span>
          </div>
        </div>
      `,
    });

    if (!confirmed) {
      return;
    }

    if (submitButton) {
      submitButton.disabled = true;
    }
    try {
      await onSaveConfig(payload);
    } finally {
      if (submitButton) {
        submitButton.disabled = false;
      }
    }
  };

  renderPagination(paginationNode, pagination, onPageChange);
}

export function renderRolesPanel({ data, onAssignRole, onRevokeRole }) {
  const list = document.getElementById('admin-role-list');
  const form = document.getElementById('role-assignment-form');
  const summary = document.querySelector('[data-role-results-summary]');
  if (!list || !form) {
    return;
  }

  const assignments = Array.isArray(data?.roleAssignments) ? data.roleAssignments : [];
  const users = Array.isArray(data?.assignableUsers) ? data.assignableUsers : [];
  const bankPartners = Array.isArray(data?.bankPartners) ? data.bankPartners : [];
  const userPicker = form.querySelector('#role-user-picker');
  const bankSelect = form.querySelector('#role-bank-scope');
  const roleSelect = form.querySelector('#role-target');
  const reasonField = form.querySelector('#role-reason');

  setDatalistOptions(
    document.getElementById('role-user-catalog'),
    users.map((user) => user.label || user.id),
  );
  setSelectOptions(
    bankSelect,
    bankPartners.map((partner) => ({
      value: partner.id,
      label: partner.name,
    })),
    { includeBlank: true, selectedValue: bankSelect?.value || '' },
  );

  const syncRoleFields = () => {
    const isBankRole = roleSelect?.value === 'bank';
    if (bankSelect) {
      bankSelect.disabled = !isBankRole;
      if (!isBankRole) {
        bankSelect.value = '';
      }
    }
  };
  if (roleSelect) {
    roleSelect.onchange = syncRoleFields;
  }
  syncRoleFields();

  if (summary) {
    summary.textContent = assignments.length
      ? `${assignments.length} active assignment${assignments.length === 1 ? '' : 's'} loaded.`
      : 'No active role assignments.';
  }

  list.innerHTML = assignments.length
    ? assignments
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
      const assignment = assignments.find(
        (entry) => entry.id === button.getAttribute('data-revoke-role'),
      );
      if (!assignment) {
        return;
      }

      const confirmed = await confirmAdminAction({
        title: 'Review role revocation',
        description:
          'Revoking a role immediately removes that workspace from the target user and invalidates live admin sessions.',
        confirmLabel: 'Revoke role',
        danger: true,
        body: `
          <div class="stack">
            <div class="list-item">
              <strong>${escapeHtml(assignment.user_name || assignment.user_phone || assignment.user_id)}</strong>
              <span class="meta">${escapeHtml(assignment.role)}</span>
            </div>
            <div class="list-item">
              <strong>Scope</strong>
              <span class="meta">${escapeHtml(assignment.partner_name || 'Platform-wide')}</span>
            </div>
          </div>
        `,
      });

      if (!confirmed) {
        return;
      }

      button.disabled = true;
      try {
        await onRevokeRole({ assignmentId: assignment.id });
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
    const selectedUser = findUserSelection(
      formData.get('user_picker')?.toString().trim() || '',
      users,
    );
    const bankId = formData.get('bank_id')?.toString().trim() || '';
    const notes = formData.get('change_reason')?.toString().trim() || '';

    if (!selectedUser) {
      userPicker?.focus();
      return;
    }
    if (role === 'bank' && !bankId) {
      bankSelect?.focus();
      return;
    }

    const confirmed = await confirmAdminAction({
      title: 'Review role assignment',
      description: 'Admin roles change what this person can see and do immediately after the mutation succeeds.',
      confirmLabel: 'Assign role',
      body: `
        <div class="stack">
          <div class="list-item">
            <strong>${escapeHtml(selectedUser.display_name)}</strong>
            <span class="meta">${escapeHtml(selectedUser.phone || selectedUser.public_user_id || selectedUser.id)}</span>
          </div>
          <div class="list-item">
            <strong>Requested role</strong>
            <span class="meta">${escapeHtml(role || 'Unknown')}</span>
          </div>
          ${
            role === 'bank'
              ? `
                <div class="list-item">
                  <strong>Bank scope</strong>
                  <span class="meta">${escapeHtml(bankPartners.find((partner) => partner.id === bankId)?.name || bankId || 'Missing')}</span>
                </div>
              `
              : ''
          }
          <div class="list-item">
            <strong>Reason</strong>
            <span class="meta">${escapeHtml(notes || 'None provided')}</span>
          </div>
        </div>
      `,
    });

    if (!confirmed) {
      return;
    }

    if (submitButton) {
      submitButton.disabled = true;
    }
    try {
      await onAssignRole({
        targetUserId: selectedUser.id,
        role,
        bankId: role === 'bank' ? bankId : '',
        notes,
      });
      form.reset();
      syncRoleFields();
      reasonField?.blur();
    } finally {
      if (submitButton) {
        submitButton.disabled = false;
      }
    }
  };
}

export function renderAuditLogPanel({ data, onFilterChange, onPageChange }) {
  const list = document.getElementById('audit-log-list');
  const form = document.getElementById('audit-filter-form');
  const queryInput = document.getElementById('audit-query');
  const actionSelect = document.getElementById('audit-action');
  const tableSelect = document.getElementById('audit-table');
  const summary = document.querySelector('[data-audit-results-summary]');
  const paginationNode = document.querySelector('[data-audit-pagination]');
  if (!list) {
    return;
  }

  const entries = Array.isArray(data?.auditEntries) ? data.auditEntries : [];
  const filters = data?.filters || {};
  const pagination = data?.pagination || null;
  const catalog = data?.auditCatalog || {};

  if (queryInput) {
    queryInput.value = filters.q || '';
  }
  setSelectOptions(
    actionSelect,
    (catalog.actions || []).map((action) => ({ value: action, label: action })),
    { includeBlank: true, selectedValue: filters.action || '' },
  );
  setSelectOptions(
    tableSelect,
    (catalog.tables || []).map((table) => ({ value: table, label: table })),
    { includeBlank: true, selectedValue: filters.table || '' },
  );

  if (form) {
    form.onsubmit = (event) => {
      event.preventDefault();
      onFilterChange?.({
        q: queryInput?.value || '',
        action: actionSelect?.value || '',
        table: tableSelect?.value || '',
        page: 1,
      });
    };
  }
  const resetAuditFilter = form?.querySelector('[data-audit-filter-reset]');
  if (resetAuditFilter) {
    resetAuditFilter.onclick = () => {
      if (queryInput) {
        queryInput.value = '';
      }
      if (actionSelect) {
        actionSelect.value = '';
      }
      if (tableSelect) {
        tableSelect.value = '';
      }
      onFilterChange?.({ q: '', action: '', table: '', page: 1 });
    };
  }

  if (summary && pagination) {
    summary.textContent = pagination.total
      ? `Showing ${entries.length} audit entr${entries.length === 1 ? 'y' : 'ies'} from ${pagination.total} total.`
      : 'No audit evidence matches the current filter.';
  }

  list.innerHTML = entries.length
    ? entries
        .map(
          (entry) => `
            <li class="list-item">
              <div class="list-item-header">
                <strong>${escapeHtml(entry.actor_name || entry.actor_phone || entry.actor_id || 'Unknown actor')}</strong>
                <span class="status-pill ${entry.action === 'delete' ? 'error' : entry.action === 'update' ? 'syncing' : 'online'}">${escapeHtml(entry.action || 'action')}</span>
              </div>
              <p>${escapeHtml([entry.target_table, entry.target_id].filter(Boolean).join(' · ') || 'Tracked admin mutation')}</p>
              ${
                entry.notes
                  ? `<span class="meta">${escapeHtml(entry.notes)}</span>`
                  : ''
              }
              <div class="detail-grid compact-grid">
                <div class="list-item">
                  <strong>Before</strong>
                  <pre class="review-code">${escapeHtml(formatJsonSummary(entry.old_data))}</pre>
                </div>
                <div class="list-item">
                  <strong>After</strong>
                  <pre class="review-code">${escapeHtml(formatJsonSummary(entry.new_data))}</pre>
                </div>
              </div>
              <span class="meta">${escapeHtml(entry.created_at || '')}</span>
            </li>
          `,
        )
        .join('')
    : `
        <li class="list-item">
          <div class="list-item-header">
            <strong>No audit evidence found</strong>
            <span class="status-pill offline">Empty</span>
          </div>
          <p>Change the filters or widen the time window by clearing search terms.</p>
        </li>
      `;

  renderPagination(paginationNode, pagination, onPageChange);
}
