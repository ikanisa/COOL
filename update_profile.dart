import 'dart:io';

void main() {
  final file = File('lib/features/profile/screens/profile_screen.dart');
  var content = file.readAsStringSync();

  // 1. Remove ProfileFactsCard
  content = content.replaceFirst(RegExp(r'ProfileFactsCard\([\s\S]*?\]\s*,\s*\),\s*const SizedBox\(height: 14\),'), '');

  // 2. Change preferenceRows to remove app access and support
  content = content.replaceFirst(r'''
    final preferenceRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.admin_panel_settings_outlined,
        label: l10n.profileAppAccess,
        value: l10n.profileManageAction,
        onTap: _showAppAccessSheet,
      ),
      ProfileSettingsRow(
        icon: Icons.notifications_outlined,
        label: l10n.notificationsLabel,
        trailing: ProfileNotificationToggle(
          value: profile.notificationsEnabled,
          isLoading: notificationSettings.isLoading,
          onChanged: _toggleNotifications,
        ),
        showArrow: false,
      ),
      ProfileSettingsRow(
        icon: Icons.help_outline_rounded,
        label: l10n.supportLabel,
        value: l10n.whatsapp,
        onTap: _openSupportWhatsApp,
      ),
    ];''', r'''
    final supportAndAccessRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.help_outline_rounded,
        label: l10n.supportLabel,
        value: l10n.whatsapp,
        onTap: _openSupportWhatsApp,
      ),
      ProfileSettingsRow(
        icon: Icons.admin_panel_settings_outlined,
        label: l10n.profileAppAccess,
        value: l10n.profileManageAction,
        onTap: _showAppAccessSheet,
      ),
    ];
    final preferenceRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.notifications_outlined,
        label: l10n.notificationsLabel,
        trailing: ProfileNotificationToggle(
          value: profile.notificationsEnabled,
          isLoading: notificationSettings.isLoading,
          onChanged: _toggleNotifications,
        ),
        showArrow: false,
      ),
    ];''');

  // 3. Merge setupItems and moneyRows into account
  content = content.replaceFirst(r'''
                    ProfileSettingsSection(
                      title: l10n.profileSetupTitle,
                      rows: profile.setupItems
                          .map((item) {
                            final onTap = switch (item.id) {
                              'account' => () => context.push(
                                AppRoutes.registerLocation(
                                  phone: authState.user?.phone,
                                ),
                              ),
                              'wallet' => () => _showMomoEditSheet(profile),
                              'official_identity' =>
                                () => _showOfficialIdentitySheet(profile),
                              'travel_role' => () => _showTravelRoleSheet(
                                profile,
                              ),
                              _ => null,
                            };

                            return ProfileSettingsRow(
                              icon: switch (item.id) {
                                'wallet' =>
                                  Icons.account_balance_wallet_outlined,
                                'official_identity' =>
                                  Icons.verified_user_outlined,
                                'travel_role' => Icons.swap_horiz_rounded,
                                _ => Icons.badge_outlined,
                              },
                              label: item.label,
                              onTap: onTap,
                              showArrow: onTap != null,
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 14),
                    ProfileSettingsSection(
                      title: l10n.moneySectionTitle,
                      rows: moneyRows,
                    ),''', r'''
                    ProfileSettingsSection(
                      title: l10n.account,
                      rows: [
                        ...profile.setupItems.map((item) {
                          final onTap = switch (item.id) {
                            'account' => () => context.push(
                              AppRoutes.registerLocation(
                                phone: authState.user?.phone,
                              ),
                            ),
                            'wallet' => () => _showMomoEditSheet(profile),
                            'official_identity' =>
                              () => _showOfficialIdentitySheet(profile),
                            'travel_role' => () => _showTravelRoleSheet(
                              profile,
                            ),
                            _ => null,
                          };

                          return ProfileSettingsRow(
                            icon: switch (item.id) {
                              'wallet' =>
                                Icons.account_balance_wallet_outlined,
                              'official_identity' =>
                                Icons.verified_user_outlined,
                              'travel_role' => Icons.swap_horiz_rounded,
                              _ => Icons.badge_outlined,
                            },
                            label: item.label,
                            onTap: onTap,
                            showArrow: onTap != null,
                          );
                        }),
                        ...moneyRows,
                      ],
                    ),''');

  // 4. Add supportAndAccessRows below preferenceRows
  content = content.replaceFirst(r'''
                    ProfileSettingsSection(
                      title: l10n.preferencesSectionTitle,
                      rows: preferenceRows,
                    ),''', r'''
                    ProfileSettingsSection(
                      title: l10n.preferencesSectionTitle,
                      rows: preferenceRows,
                    ),
                    const SizedBox(height: 14),
                    ProfileSettingsSection(
                      title: l10n.supportLabel,
                      rows: supportAndAccessRows,
                    ),''');

  file.writeAsStringSync(content);
}
