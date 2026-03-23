import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/app_access_service.dart';
import '../../core/services/contacts_service.dart';
import '../../core/theme/cool_foundations.dart';
import 'cool_skeleton.dart';
import '../../core/l10n/l10n.dart';

/// A modal bottom sheet that lets users pick contacts from their phone.
///
/// Supports multi-select (for group invites) and single-select (for sharing).
/// Handles permission denied / permanently denied states with "Open Settings".
class ContactPickerSheet extends StatefulWidget {
  const ContactPickerSheet._({
    required this.multiSelect,
    required this.onSelected,
    required this.appAccessService,
    this.title,
    this.message,
  });

  final bool multiSelect;
  final void Function(List<SimpleContact> selected) onSelected;
  final AppAccessService appAccessService;
  final String? title;
  final String? message;

  /// Show the contact picker as a modal bottom sheet.
  ///
  /// Returns the selected contacts (empty if cancelled).
  static Future<List<SimpleContact>> show(
    BuildContext context, {
    required AppAccessService appAccessService,
    bool multiSelect = false,
    String? title,
    String? subtitle,
    String? message,
  }) async {
    final result = await showModalBottomSheet<List<SimpleContact>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ContactPickerSheet._(
        multiSelect: multiSelect,
        title: title,
        message: subtitle ?? message,
        appAccessService: appAccessService,
        onSelected: (contacts) => Navigator.of(context).pop(contacts),
      ),
    );
    return result ?? const [];
  }

  @override
  State<ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<ContactPickerSheet>
    with WidgetsBindingObserver {
  final _service = const ContactsService();
  late final AppAccessService _appAccessService = widget.appAccessService;
  final _searchController = TextEditingController();
  final _selected = <String>{};

  List<SimpleContact>? _allContacts;
  List<SimpleContact> _filtered = [];
  bool _isLoading = true;
  bool _accessDisabledInApp = false;
  bool _permissionDenied = false;
  bool _permanentlyDenied = false;
  String? _error;
  bool _refreshOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadContacts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_refreshOnResume) {
      return;
    }
    _refreshOnResume = false;
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _accessDisabledInApp = false;
      _permissionDenied = false;
      _permanentlyDenied = false;
    });

    final access = await _appAccessService.getSnapshot(
      AppAccessPermission.contacts,
    );
    if (access.kind == AppAccessStateKind.disabledInApp) {
      setState(() {
        _isLoading = false;
        _accessDisabledInApp = true;
      });
      return;
    }

    // Check current permission status before requesting — show rationale first
    // if the user hasn't been asked yet, matching camera & location UX.
    final currentStatus = await Permission.contacts.status;

    if (currentStatus.isPermanentlyDenied) {
      setState(() {
        _isLoading = false;
        _permanentlyDenied = true;
      });
      return;
    }

    if (currentStatus.isDenied) {
      // First time or previously denied (but not permanently): show rationale
      // instead of immediately firing the system dialog.
      setState(() {
        _isLoading = false;
        _permissionDenied = true;
      });
      return;
    }

    if (!currentStatus.isGranted) {
      // This case should ideally be covered by isDenied/isUndetermined,
      // but handles other non-granted states like restricted/limited.
      setState(() {
        _isLoading = false;
        _permissionDenied = true;
      });
      return;
    }

    // Permission already granted — fetch contacts directly.
    try {
      final contacts = await _service.fetchContacts();
      setState(() {
        _allContacts = contacts;
        _filtered = contacts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Could not load contacts.';
      });
    }
  }

  Future<void> _requestContactsPermission() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

    final status = await _service.requestPermission();

    if (status.isPermanentlyDenied) {
      setState(() {
        _isLoading = false;
        _permanentlyDenied = true;
      });
      return;
    }

    if (!status.isGranted) {
      setState(() {
        _isLoading = false;
        _permissionDenied = true;
      });
      return;
    }

    // Permission granted — reload contacts
    await _loadContacts();
  }

  Future<void> _enableContactsAccess() async {
    final snapshot = await _appAccessService.enableAndRequest(
      AppAccessPermission.contacts,
    );
    if (!mounted) {
      return;
    }
    if (snapshot.kind == AppAccessStateKind.blockedInSystem) {
      setState(() {
        _isLoading = false;
        _accessDisabledInApp = false;
        _permanentlyDenied = true;
      });
      return;
    }
    await _loadContacts();
  }

  Future<void> _openContactsSettings() async {
    _refreshOnResume = true;
    final opened = await openAppSettings();
    if (!mounted) {
      return;
    }
    if (!opened) {
      _refreshOnResume = false;
      setState(() => _error = 'Could not open contacts settings.');
    }
  }

  void _onSearch(String query) {
    if (_allContacts == null) return;
    setState(() {
      if (query.trim().isEmpty) {
        _filtered = _allContacts!;
      } else {
        final q = query.trim().toLowerCase();
        _filtered = _allContacts!.where((c) {
          if (c.displayName.toLowerCase().contains(q)) return true;
          return c.phones.any(
            (p) => p.replaceAll(RegExp(r'[\s\-\(\)+]'), '').contains(q),
          );
        }).toList();
      }
    });
  }

  void _toggleContact(SimpleContact contact) {
    if (widget.multiSelect) {
      setState(() {
        if (_selected.contains(contact.id)) {
          _selected.remove(contact.id);
        } else {
          _selected.add(contact.id);
        }
      });
    } else {
      widget.onSelected([contact]);
    }
  }

  void _confirmSelection() {
    if (_allContacts == null || _selected.isEmpty) return;
    final chosen = _allContacts!
        .where((c) => _selected.contains(c.id))
        .toList();
    widget.onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final effectiveSubtitle = widget.message;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radii.lg)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle + header ──
          Padding(
            padding: EdgeInsets.fromLTRB(
              space.x5 + 2,
              space.x2 + 4,
              space.x5 + 2,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                SizedBox(height: space.x4),
                Row(
                  children: [
                    Icon(
                      Icons.contacts_rounded,
                      size: 22,
                      color: colors.secondaryText,
                    ),
                    SizedBox(width: space.x2 + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title ??
                                (widget.multiSelect
                                    ? 'Invite from Contacts'
                                    : 'Share via Contact'),
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.primaryText,
                            ),
                          ),
                          if (effectiveSubtitle != null) ...[
                            SizedBox(height: space.x1 / 2),
                            Text(
                              effectiveSubtitle,
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: colors.tertiaryText,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.multiSelect && _selected.isNotEmpty)
                      _DoneButton(
                        count: _selected.length,
                        onTap: _confirmSelection,
                      ),
                  ],
                ),
                SizedBox(height: space.x3 + 2),

                // ── Search bar ──
                if (!_permissionDenied && !_permanentlyDenied && _error == null)
                  Semantics(
                    textField: true,
                    label: context.l10n.searchContacts,
                    hint: 'Search name or phone',
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearch,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.primaryText,
                      ),
                      cursorColor: colors.accent,
                      decoration: InputDecoration(
                        hintText: 'Search by name or phone',
                        hintStyle: textTheme.bodySmall?.copyWith(
                          color: colors.tertiaryText,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: colors.tertiaryText,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: colors.inputSurface,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: space.x3 + 2,
                          vertical: space.x2 + 2,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(radii.sm),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                SizedBox(height: space.x2),
              ],
            ),
          ),

          // ── Body ──
          Flexible(child: _buildBody()),

          // ── Bottom safe area ──
          SizedBox(height: MediaQuery.paddingOf(context).bottom + space.x2),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final text = context.coolText;
    final space = context.coolSpace;

    // Loading state
    if (_isLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: space.x10 - 4),
        child: const CoolSkeletonList(itemCount: 3),
      );
    }

    // Permanently denied
    if (_permanentlyDenied) {
      return _PermissionState(
        icon: Icons.lock_rounded,
        title: 'Contacts access denied',
        message: 'You\'ve permanently denied contacts',
        actionLabel: 'Open Settings',
        action: _openContactsSettings,
      );
    }

    if (_accessDisabledInApp) {
      return _PermissionState(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Contacts are off in',
        message: 'Contacts access is currently',
        actionLabel: 'Enable Contacts',
        action: _enableContactsAccess,
      );
    }

    // Denied
    if (_permissionDenied) {
      return _PermissionState(
        icon: Icons.contacts_rounded,
        title: 'Contacts access needed',
        message: 'Cool needs access to',
        actionLabel: 'Allow Access',
        action: _requestContactsPermission,
      );
    }

    // Error
    if (_error != null) {
      return _PermissionState(
        icon: Icons.warning_amber_rounded,
        title: 'Something went wrong',
        message: _error!,
        actionLabel: 'Retry',
        action: _loadContacts,
      );
    }

    // Empty state
    if (_filtered.isEmpty) {
      final isSearching = _searchController.text.trim().isNotEmpty;
      return Padding(
        padding: EdgeInsets.symmetric(vertical: space.x9, horizontal: space.x6),
        child: Center(
          child: Text(
            isSearching
                ? 'No contacts match "${_searchController.text.trim()}"'
                : 'No contacts with phone numbers found.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: colors.tertiaryText),
          ),
        ),
      );
    }

    // Contact list
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: space.x4),
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final contact = _filtered[index];
        final isSelected = _selected.contains(contact.id);

        return _ContactTile(
          contact: contact,
          isSelected: isSelected,
          showCheckbox: widget.multiSelect,
          onTap: () => _toggleContact(contact),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Contact tile
// ═══════════════════════════════════════════════════════════════════════════

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.isSelected,
    required this.showCheckbox,
    required this.onTap,
  });

  final SimpleContact contact;
  final bool isSelected;
  final bool showCheckbox;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: space.x2 + 2,
          horizontal: space.x1,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.accent.withValues(alpha: 0.15)
                    : colors.inputSurface,
                borderRadius: BorderRadius.circular(21),
              ),
              alignment: Alignment.center,
              child: Text(
                contact.initials,
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? colors.accent : colors.secondaryText,
                ),
              ),
            ),
            SizedBox(width: space.x3),

            // Name + phone
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayName,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: space.x1 / 4),
                  Text(
                    contact.phones.first,
                    style: text.mono(
                      textTheme.labelSmall,
                      fontWeight: FontWeight.w400,
                      color: colors.tertiaryText,
                    ),
                  ),
                ],
              ),
            ),

            // Checkbox or chevron
            if (showCheckbox)
              AnimatedContainer(
                duration: CoolMotion.quick,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(radii.sm / 2.5),
                  border: Border.all(
                    color: isSelected ? colors.accent : colors.borderStrong,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: colors.tertiaryText,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Permission state
// ═══════════════════════════════════════════════════════════════════════════

class _PermissionState extends StatelessWidget {
  const _PermissionState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: space.x8,
        horizontal: space.x7 - 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: colors.secondaryText),
          SizedBox(height: space.x3 + 2),
          Text(
            title,
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          SizedBox(height: space.x2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.tertiaryText,
              height: 1.5,
            ),
          ),
          SizedBox(height: space.x5),
          GestureDetector(
            onTap: action,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: space.x6,
                vertical: space.x3,
              ),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(radii.sm),
              ),
              child: Text(
                actionLabel,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.accentForeground,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Done button (multi-select mode)
// ═══════════════════════════════════════════════════════════════════════════

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: space.x4, vertical: space.x2),
        decoration: BoxDecoration(
          color: colors.accent,
          borderRadius: BorderRadius.circular(radii.pill),
        ),
        child: Text(
          'Done ($count)',
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.accentForeground,
          ),
        ),
      ),
    );
  }
}
