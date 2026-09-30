import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_spacing.dart';
import '../../shared/widgets/collect_state_panels.dart';
import 'admin_roster_import.dart';
import 'admin_roster_models.dart';

/// Business/operator review adaptation using the shared Collect theme, modal,
/// fields and actions. The source receipt never becomes editable input.
class AdminRosterImportDialog extends StatefulWidget {
  const AdminRosterImportDialog({
    required this.draft,
    this.pickFile,
    super.key,
  });
  final AdminRosterDraft draft;
  final Future<PlatformFile?> Function()? pickFile;
  @override
  State<AdminRosterImportDialog> createState() =>
      _AdminRosterImportDialogState();
}

class _AdminRosterImportDialogState extends State<AdminRosterImportDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _reason = TextEditingController();
  final _text = TextEditingController(
    text: 'Member name,MoMo name,MoMo number\n',
  );
  PlatformFile? _file;
  bool _consent = false, _picking = false;
  int _page = 0;
  final Set<int> _visited = {0};
  AdminRosterDraft get draft => widget.draft;
  bool get _ai => const {
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'webp',
  }.contains(_file?.extension?.toLowerCase());
  @override
  void initState() {
    super.initState();
    draft.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (draft.invalidated) {
      _title.clear();
      _reason.clear();
      _text.clear();
      _file = null;
      _consent = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    draft.removeListener(_changed);
    draft.dispose();
    _title.dispose();
    _reason.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final picked = widget.pickFile != null
          ? await widget.pickFile!()
          : (await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: const [
                'csv',
                'txt',
                'xlsx',
                'pdf',
                'png',
                'jpg',
                'jpeg',
                'webp',
              ],
            ));
      if (!mounted) return;
      draft.checkSession();
      if (picked != null) {
        setState(() {
          _file = picked;
          _consent = false;
        });
      }
    } catch (_) {
      if (mounted && !draft.invalidated) {
        setState(
          () => draft.error = 'The file could not be selected. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  bool _valid() => _form.currentState?.validate() ?? false;
  Future<void> _prepare() async {
    if (!_valid()) return;
    await draft.prepare(
      () async => _file == null
          ? AdminRosterUpload.pasted(_text.text)
          : AdminRosterUpload.file(_file!, aiConsent: _consent),
    );
    if (mounted && draft.preview != null) {
      setState(() {
        _page = 0;
        _visited.add(0);
      });
    }
  }

  Future<void> _commit() async {
    if (!_valid()) return;
    final acknowledged = await draft.commit(
      title: _title.text,
      reason: _reason.text,
    );
    if (mounted &&
        acknowledged != null &&
        !draft.invalidated &&
        draft.gateway.isCurrent) {
      draft.discardRecoveryReference();
      Navigator.of(context).pop(acknowledged);
    }
  }

  Future<void> _checkStatus() async {
    final acknowledged = await draft.recoverStatus();
    if (mounted &&
        acknowledged != null &&
        !draft.invalidated &&
        draft.gateway.isCurrent) {
      draft.discardRecoveryReference();
      Navigator.of(context).pop(acknowledged);
    }
  }

  Future<void> _recoverReload() async {
    final result=await draft.recoverReload();
    if(!mounted || draft.invalidated) return;
    _title.text=draft.editorTitle;_reason.text=draft.editorReason;
    _text.clear();_file=null;_consent=false;_visited.clear();_visited.add(0);_page=0;
    if(result!=null && draft.gateway.isCurrent) {draft.discardRecoveryReference();Navigator.of(context).pop(result);}
    else {setState(() {});}
  }

  @override
  Widget build(BuildContext context) {
    if (draft.invalidated) {
      return AlertDialog(
        title: Text(
          draft.errorCode == null ? 'Sign-in changed' : 'Roster unavailable',
        ),
        content: Text(draft.error ?? rosterSessionChanged),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final locked = draft.busy || _picking;
    final receipt = draft.preview;
    final pages = ((draft.rows.length + 24) ~/ 25).clamp(1, 20);
    final canAffirm =
        (draft.canEdit || draft.canReaffirm) &&
        receipt?.isHumanReview == true &&
        !draft.edited &&
        _visited.length == pages;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          draft.mode == 'create'
              ? 'Create assisted group'
              : 'Add reviewed members',
        ),
        content: SizedBox(
          width: 760,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const InfoSecurityBanner(
                  title: 'Private group · review every row',
                  message:
                      'A preview adds no members. Save your review, confirm every row, then submit the complete roster together.',
                ),
                const SizedBox(height: CollectSpacing.x4),
                if(draft.storageWarning!=null) Text(draft.storageWarning!),
                if(draft.reloadAvailable || draft.recovered) OutlinedButton(
                  key:const Key('roster-recover-reload'),
                  onPressed:locked?null:_recoverReload,
                  child:const Text('Check recovery for this sign-in')),
                if(draft.recoveryMessage!=null) Semantics(liveRegion:true,child:Text(draft.recoveryMessage!)),
                if(draft.hasUnsavedRecoveryChanges) const Text('Unsaved recovery changes · save a recovery draft before reloading. Rows, group name and reason are never stored in this browser.'),
                if (draft.mode == 'create') ...[
                  TextFormField(
                    key: const Key('roster-title'),
                    controller: _title,
                    onChanged:(value)=>draft.setEditorMetadata(title:value),
                    enabled: draft.canEdit,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      errorMaxLines: 3,
                    ),
                    validator: (value) =>
                        (value?.trim().length ?? 0) < 3 ||
                            (value?.trim().length ?? 0) > 120
                        ? 'Use 3 to 120 characters.'
                        : null,
                  ),
                  const SizedBox(height: CollectSpacing.x4),
                ],
                TextFormField(
                  key: const Key('roster-reason'),
                  controller: _reason,
                  onChanged:(value)=>draft.setEditorMetadata(reason:value),
                  enabled:
                      draft.canEdit,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    errorMaxLines: 3,
                    helperMaxLines: 4,
                    helperText: 'Required for the review and audit trail.',
                  ),
                  validator: (value) =>
                      (value?.trim().length ?? 0) < 8 ||
                          (value?.trim().length ?? 0) > 500
                      ? 'Use 8 to 500 characters.'
                      : null,
                ),
                const SizedBox(height: CollectSpacing.x4),
                if (receipt == null) ...[
                  TextFormField(
                    key: const Key('roster-source'),
                    controller: _text,
                    enabled: !locked && !draft.sourceLocked && _file == null,
                    minLines: 5,
                    maxLines: 9,
                    decoration: const InputDecoration(
                      labelText: 'Member roster',
                      errorMaxLines: 3,
                      helperMaxLines: 5,
                      helperText:
                          'Member name, registered MoMo name, MoMo number. Up to 500 rows.',
                    ),
                  ),
                  const SizedBox(height: CollectSpacing.x3),
                  Wrap(
                    spacing: CollectSpacing.x2,
                    runSpacing: CollectSpacing.x2,
                    children: [
                      OutlinedButton.icon(
                        onPressed: locked || draft.sourceLocked ? null : _pick,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Choose roster file'),
                      ),
                      if (_file != null)
                        TextButton(
                          onPressed: locked || draft.sourceLocked
                              ? null
                              : () => setState(() {
                                  _file = null;
                                  _consent = false;
                                }),
                          child: const Text('Use pasted list'),
                        ),
                    ],
                  ),
                  if (_file != null)
                    Padding(
                      padding: const EdgeInsets.only(top: CollectSpacing.x2),
                      child: Text(_file!.name),
                    ),
                  if (_ai)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _consent,
                      onChanged: locked || draft.sourceLocked
                          ? null
                          : (value) =>
                                setState(() => _consent = value ?? false),
                      title: const Text('Use OpenAI for this file'),
                      subtitle: const Text(
                        'Send this PDF or image for extraction. Collect retains a source and consent receipt plus extracted and reviewed rows; it does not retain the original file. Review all results before adding members.',
                      ),
                    ),
                  if (_file?.extension?.toLowerCase() == 'xlsx')
                    const Text(
                      'The workbook is retained only for this request. Its original bytes and the text derived by this browser are identified separately; the server does not verify the text against workbook cells.',
                    ),
                ],
                if (receipt != null) ...[
                  _sourceReceipt(context),
                  const SizedBox(height: CollectSpacing.x4),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${receipt.rowCount} rows · ${receipt.readyCount} ready · ${receipt.errorCount} requiring correction',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    draft.edited
                        ? 'Unsaved corrections · save a new review before submitting.'
                        : receipt.isHumanReview
                        ? receipt.canSubmit
                              ? 'Human review saved · revision ${receipt.revisionNumber}'
                              : 'Saved review is unavailable for submission. Discard this draft and start a new import.'
                        : 'Initial preview · human review required',
                  ),
                  const SizedBox(height: CollectSpacing.x3),
                  for (
                    var index = _page * 25;
                    index < draft.rows.length && index < (_page + 1) * 25;
                    index++
                  )
                    _row(context, index),
                  Wrap(
                    spacing: CollectSpacing.x2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: locked || _page == 0
                            ? null
                            : () => setState(() {
                                _page--;
                                _visited.add(_page);
                              }),
                        child: const Text('Previous rows'),
                      ),
                      Semantics(
                        liveRegion: true,
                        child: Text('Page ${_page + 1} of $pages'),
                      ),
                      OutlinedButton(
                        onPressed: locked || _page + 1 >= pages
                            ? null
                            : () => setState(() {
                                _page++;
                                _visited.add(_page);
                              }),
                        child: const Text('Next rows'),
                      ),
                    ],
                  ),
                  const SizedBox(height: CollectSpacing.x3),
                  CheckboxListTile(
                    key: const Key('roster-affirm'),
                    contentPadding: EdgeInsets.zero,
                    value: draft.affirmed,
                    onChanged: canAffirm
                        ? (value) => draft.affirm(value ?? false)
                        : null,
                    title: Text(
                      'I have reviewed all ${draft.rows.length} rows and confirm these members and MoMo identities.',
                    ),
                    subtitle: Text(
                      _visited.length < pages
                          ? 'Visit every page before confirming.'
                          : 'Save the review before confirming. Editing a row requires a new saved review.',
                    ),
                  ),
                ],
                if (draft.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: CollectSpacing.x3),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        draft.error!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(top: CollectSpacing.x3),
                    child: Semantics(
                      liveRegion: true,
                      label: 'Roster request in progress',
                      child: const LinearProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: locked ? null : () {draft.discardRecoveryReference();Navigator.of(context).pop();},
            child: Text(
              draft.commitPending
                  ? 'Discard draft · outcome may be unknown'
                  : 'Discard draft',
            ),
          ),
          if(receipt!=null && draft.gateway.supportsRecovery) OutlinedButton(
            key:const Key('roster-save-recovery'),
            onPressed:draft.canEdit?draft.saveRecoveryDraft:null,
            child:const Text('Save recovery draft')),
          if (receipt == null && (!draft.reloadAvailable || draft.recovered && draft.recoveryMessage==null))
            OutlinedButton(
              onPressed: locked || draft.terminalUploadFailure
                  ? null
                  : _prepare,
              child: Text(
                draft.sourceLocked ? 'Retry preview' : 'Prepare preview',
              ),
            ),
          if (draft.canDiscardPendingReview)
            TextButton(
              onPressed: draft.discardRejectedReview,
              child: const Text('Discard rejected review request'),
            ),
          if (draft.statusRequired)
            OutlinedButton(
              onPressed: draft.canCheckStatus ? _checkStatus : null,
              child: const Text('Check saved import status'),
            ),
          if (receipt != null && !draft.commitPending)
            OutlinedButton(
              onPressed: locked || !draft.canSaveReview
                  ? null
                  : () async {
                      if (_valid()) await draft.saveReview(_reason.text);
                      if (mounted && draft.reviewIssues.isNotEmpty) {
                        setState(
                          () => _page = draft.reviewIssues.keys.first ~/ 25,
                        );
                      }
                    },
              child: Text(
                draft.reviewPending
                    ? 'Retry saved review'
                    : 'Save reviewed rows',
              ),
            ),
          if (receipt != null)
            FilledButton(
              onPressed: !locked && (draft.canCommit || draft.canRetryCommit)
                  ? _commit
                  : null,
              child: Text(
                draft.commitPending
                    ? 'Retry same submission'
                    : draft.mode == 'create'
                    ? 'Create group and add members'
                    : 'Add members',
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceReceipt(BuildContext context) {
    final initial = draft.initialPreview!;
    final source = initial.raw['source_receipt'] as Map;
    return ExpansionTile(
      title: Text(
        initial.processingMethod == 'openai_structured_extraction'
            ? 'Original AI extraction receipt'
            : 'Original source receipt',
      ),
      subtitle: Text('${source['client_filename']} · ${initial.sourceKind}'),
      childrenPadding: const EdgeInsets.all(CollectSpacing.x3),
      children: [
        SelectableText(
          'Source SHA-256: ${initial.sourceSha256}\nImport: ${initial.importId}\nInitial revision: ${initial.revisionId}\nCurrent revision: ${draft.preview!.revisionId}\nParent revision: ${draft.preview!.parentRevisionId ?? 'Initial preview'}\nExpires: ${initial.expiresAt.toLocal()}',
        ),
        if (initial.model != null)
          Text(
            'Extraction model: ${initial.model}\nConsent receipt: ${source['consent_version']}\nExtraction: ${source['extraction_id']}',
          ),
        if (initial.sourceKind == 'xlsx')
          const Text(
            'Workbook bytes recorded; TSV was derived by this browser, not verified against workbook cells by the server.',
          ),
      ],
    );
  }

  Widget _row(BuildContext context, int index) {
    final current = draft.preview!.rows[index];
    final initial = draft.initialPreview!.rows[index];
    return Padding(
      key: ValueKey('roster-row-$index'),
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Row ${index + 1}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (draft.initialPreview!.processingMethod ==
              'openai_structured_extraction')
            Text(
              'Initial extraction confidence: ${(initial.confidence * 100).toStringAsFixed(0)}% · verify against the source',
            ),
          for (final entry in const {
            'member_name': 'Member name',
            'momo_name': 'Registered MoMo name',
            'momo_number': 'MoMo number',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(top: CollectSpacing.x2),
              child: TextFormField(
                key: ValueKey(
                  'roster-${draft.preview!.revisionId}-$index-${entry.key}',
                ),
                initialValue: draft.rows[index][entry.key] as String,
                enabled: draft.canEdit,
                decoration: InputDecoration(
                  labelText: '${entry.value} · row ${index + 1}',
                ),
                keyboardType: entry.key == 'momo_number'
                    ? TextInputType.phone
                    : TextInputType.text,
                onChanged: (value) => draft.edit(index, entry.key, value),
              ),
            ),
          if (draft.reviewIssues[index] != null)
            Text(
              draft.reviewIssues[index]!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          if (current.issues.isNotEmpty && !draft.edited)
            Text(
              current.issues.join(' · '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          const Divider(),
        ],
      ),
    );
  }
}

Future<AdminRosterCommit?> showAdminRosterImport(
  BuildContext context,
  AdminRosterDraft draft,
) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final result = await showDialog<AdminRosterCommit>(
    context: context,
    barrierDismissible: false,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (_) => AdminRosterImportDialog(draft: draft),
  );
  if (previousFocus?.context != null && previousFocus!.canRequestFocus) {
    previousFocus.requestFocus();
  }
  return result;
}
