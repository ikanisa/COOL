import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/app_access_service.dart';
import '../../core/services/contacts_service.dart';
import '../../core/theme/app_colors.dart';
import 'cool_skeleton.dart';

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
    this.subtitle,
  });

  final bool multiSelect;
  final void Function(List<SimpleContact> selected) onSelected;
  final AppAccessService appAccessService;
  final String? title;
  final String? subtitle;

  /// Show the contact picker as a modal bottom sheet.
  ///
  /// Returns the selected contacts (empty if cancelled).
  static Future<List<SimpleContact>> show(
    BuildContext context, {
    required AppAccessService appAccessService,
    bool multiSelect = false,
    String? title,
    String? subtitle,
  }) async {
    final result = await showModalBottomSheet<List<SimpleContact>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ContactPickerSheet._(
        multiSelect: multiSelect,
        title: title,
        subtitle: subtitle,
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
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle + header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.contacts_rounded,
                      size: 22,
                      color: AppColors.text2,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title ??
                                (widget.multiSelect
                                    ? 'Invite from Contacts'
                                    : 'Share via Contact'),
                            style: GoogleFonts.dmSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle!,
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: AppColors.text3,
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
                const SizedBox(height: 14),

                // ── Search bar ──
                if (!_permissionDenied && !_permanentlyDenied && _error == null)
                  Semantics(
                    textField: true,
                    label: 'Search contacts',
                    hint:
                        'Double tap to search by contact name or phone number',
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearch,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.text,
                      ),
                      cursorColor: AppColors.accent,
                      decoration: InputDecoration(
                        hintText: 'Search by name or phone…',
                        hintStyle: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: AppColors.text3,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.text3,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: AppColors.surface2,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // ── Body ──
          Flexible(child: _buildBody()),

          // ── Bottom safe area ──
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // Loading state
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: CoolSkeletonList(itemCount: 3),
      );
    }

    // Permanently denied
    if (_permanentlyDenied) {
      return _PermissionState(
        icon: Icons.lock_rounded,
        title: 'Contacts access denied',
        message:
            'You\'ve permanently denied contacts access. Open Settings to allow Cool to read your contacts.',
        actionLabel: 'Open Settings',
        onAction: _openContactsSettings,
      );
    }

    if (_accessDisabledInApp) {
      return _PermissionState(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Contacts are off in COOL',
        message:
            'Contacts access is currently disabled from Profile settings, so invite and share flows stay blocked until you turn it back on.',
        actionLabel: 'Enable Contacts',
        onAction: _enableContactsAccess,
      );
    }

    // Denied
    if (_permissionDenied) {
      return _PermissionState(
        icon: Icons.contacts_rounded,
        title: 'Contacts access needed',
        message:
            'Cool needs access to your contacts to invite friends or share content.',
        actionLabel: 'Allow Access',
        onAction: _loadContacts,
      );
    }

    // Error
    if (_error != null) {
      return _PermissionState(
        icon: Icons.warning_amber_rounded,
        title: 'Something went wrong',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _loadContacts,
      );
    }

    // Empty state
    if (_filtered.isEmpty) {
      final isSearching = _searchController.text.trim().isNotEmpty;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Center(
          child: Text(
            isSearching
                ? 'No contacts match "${_searchController.text.trim()}"'
                : 'No contacts with phone numbers found.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text3),
          ),
        ),
      );
    }

    // Contact list
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : AppColors.surface2,
                borderRadius: BorderRadius.circular(21),
              ),
              alignment: Alignment.center,
              child: Text(
                contact.initials,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppColors.accent : AppColors.text2,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + phone
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayName,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    contact.phones.first,
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),

            // Checkbox or chevron
            if (showCheckbox)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? AppColors.accent : AppColors.border2,
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
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.text3,
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
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.text2),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text3,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                actionLabel,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Done ($count)',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
