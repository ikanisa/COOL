import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/app_access_service.dart';
import '../../core/services/contacts_service.dart';
import '../../core/theme/cool_foundations.dart';
import 'cool_skeleton.dart';
import '../../core/l10n/l10n.dart';

part 'contact_picker_sheet_parts.dart';

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
        _error = context.l10n.contactPickerCouldNotLoadContacts;
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
      setState(
        () => _error = context.l10n.contactPickerCouldNotOpenContactsSettings,
      );
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
                      CoolIcons.contacts,
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
                                    ? context
                                          .l10n
                                          .contactPickerInviteFromContacts
                                    : context.l10n.shareViaContact),
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
                    hint: context.l10n.contactPickerSearchNameOrPhoneHint,
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearch,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.primaryText,
                      ),
                      cursorColor: colors.accent,
                      decoration: InputDecoration(
                        hintText: context.l10n.contactPickerSearchByNameOrPhone,
                        hintStyle: textTheme.bodySmall?.copyWith(
                          color: colors.tertiaryText,
                        ),
                        prefixIcon: Icon(
                          CoolIcons.search,
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
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(radii.sm),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(radii.sm),
                          borderSide: BorderSide.none,
                        ),
                        disabledBorder: OutlineInputBorder(
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
}
