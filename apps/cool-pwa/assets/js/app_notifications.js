export function initializeNotificationControls({
  state,
  dbGetAll,
  dbPutRecord,
  trackEvent,
  recordSuccessMoment,
  refreshDerivedUi,
  showToast,
}) {
  document.querySelectorAll('[data-enable-notifications]').forEach((button) => {
    button.addEventListener('click', async () => {
      if (!('Notification' in window)) {
        showToast('This browser does not support notifications.');
        return;
      }

      if (Notification.permission === 'granted') {
        showToast('Notifications are already enabled.');
        await updateNotificationStatus();
        return;
      }

      await trackEvent('notification_permission_requested');
      const permission = await Notification.requestPermission();
      await trackEvent('notification_permission_result', { permission });

      if (permission === 'granted') {
        await recordSuccessMoment('notifications_enabled');
        showToast('Notifications enabled.');
        await updateNotificationStatus();
      } else {
        showToast('Notifications remain disabled.');
      }
    });
  });

  document.querySelectorAll('[data-demo-notification]').forEach((button) => {
    button.addEventListener('click', async () => {
      const notification = {
        title: 'COOL sync completed',
        body: 'Your queued finance updates are now secure and current.',
        tag: 'cool-demo-sync',
        icon: '/assets/icons/Icon-192.png',
        badge: '/assets/icons/Icon-192.png',
        data: { route: '/notifications/' },
        actions: [
          { action: 'open-notifications', title: 'View alerts' },
          { action: 'open-home', title: 'Go home' },
        ],
      };

      await dbPutRecord('notifications', {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        title: notification.title,
        body: notification.body,
        unread: true,
      });
      await refreshDerivedUi();

      if (Notification.permission === 'granted' && state.registration) {
        try {
          await state.registration.showNotification(
            notification.title,
            notification,
          );
          await trackEvent('demo_notification_shown');
          return;
        } catch (error) {
          await trackEvent('demo_notification_display_failed', {
            message: String(error),
          });
        }
      }

      await trackEvent('demo_notification_saved_in_app', {
        permission: 'Notification' in window
          ? Notification.permission
          : 'unsupported',
        registrationReady: Boolean(state.registration),
      });
      showToast('Alert saved in-app. Enable notifications for system delivery.');
    });
  });

  if (window.location.pathname.startsWith('/notifications')) {
    void markNotificationsRead({ dbGetAll, dbPutRecord });
  }

  void updateNotificationStatus();
}

export async function updateBadge({ dbGetAll }, explicitCount = null) {
  const count = explicitCount ??
    (await dbGetAll('notifications')).filter((entry) => entry.unread).length;

  if ('setAppBadge' in navigator) {
    if (count > 0) {
      await navigator.setAppBadge(count);
    } else {
      await navigator.clearAppBadge();
    }
  }

  document.querySelectorAll('[data-badge-count]').forEach((node) => {
    node.textContent = String(count);
  });
}

async function updateNotificationStatus() {
  document.querySelectorAll('[data-notification-status]').forEach((node) => {
    if (!('Notification' in window)) {
      node.textContent = 'Unsupported';
      node.className = 'status-pill error';
      return;
    }

    const permission = Notification.permission;
    node.textContent = permission === 'granted'
      ? 'Enabled'
      : permission === 'denied'
        ? 'Blocked'
        : 'Not enabled';
    node.className = `status-pill ${
      permission === 'granted'
        ? 'online'
        : permission === 'denied'
          ? 'error'
          : 'offline'
    }`;
  });
}

async function markNotificationsRead({ dbGetAll, dbPutRecord }) {
  const notifications = await dbGetAll('notifications');
  const unread = notifications.filter((entry) => entry.unread);
  await Promise.all(
    unread.map((entry) =>
      dbPutRecord('notifications', { ...entry, unread: false })
    ),
  );
  await updateBadge({ dbGetAll }, 0);
}
