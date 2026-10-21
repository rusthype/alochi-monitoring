// lib/shared/widgets/add_student_dialog.dart
//
// "Bola qo'shish" dialog shared by the monitoring roster
// (student_entry_screen.dart) and the diagnostic roster
// (diagnostic_student_select_screen.dart).
//
// Steps: form -> (loading) -> done | candidates ("Bu shumi?") -> done.
// The dialog never talks to an API itself: the caller passes [onSubmit]
// (monitoring `addStudentOrQueue`, diagnostic `diagnosticKioskApi.addStudent`,
// or a fake in tests). It owns one `client_temp_id` per open dialog so every
// retry — including after a lost response — hits the same server-side request.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart' show ApiException;
import '../../core/models/add_student.dart';
import '../theme/app_theme.dart';

typedef AddStudentSubmit = Future<AddStudentResult>
    Function(AddStudentDraft draft, {required bool confirmNew});

/// What the dialog resolved to.
sealed class AddStudentOutcome {
  const AddStudentOutcome();
}

/// A new (pending) child was created or queued locally.
class AddStudentCreated extends AddStudentOutcome {
  final AddStudentResult result;
  const AddStudentCreated(this.result);
}

/// The proctor picked an existing candidate ("Ha, shu bola"): no request was
/// created, use that student.
class AddStudentUseExisting extends AddStudentOutcome {
  final SimilarStudent student;
  const AddStudentUseExisting(this.student);
}

Future<AddStudentOutcome?> showAddStudentDialog(
  BuildContext context, {
  required AddStudentSubmit onSubmit,
}) {
  return showDialog<AddStudentOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AddStudentDialog(onSubmit: onSubmit),
  );
}

class AddStudentDialog extends StatefulWidget {
  final AddStudentSubmit onSubmit;
  const AddStudentDialog({super.key, required this.onSubmit});

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _lastCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _parentCtrl = TextEditingController();
  final _lastFocus = FocusNode();
  final _firstFocus = FocusNode();
  final _parentFocus = FocusNode();

  /// One per dialog open == one per add attempt (stable across retries).
  final String _tempId = AddStudentDraft.newTempId();

  DateTime? _birthDate;
  bool _loading = false;
  String? _error;
  List<SimilarStudent>? _candidates;
  bool _autoValidate = false;

  @override
  void dispose() {
    _lastCtrl.dispose();
    _firstCtrl.dispose();
    _parentCtrl.dispose();
    _lastFocus.dispose();
    _firstFocus.dispose();
    _parentFocus.dispose();
    super.dispose();
  }

  AddStudentDraft get _draft => AddStudentDraft(
        firstName: normalizeStudentName(_firstCtrl.text),
        lastName: normalizeStudentName(_lastCtrl.text),
        birthDate: _birthDate,
        parentFio: normalizeStudentName(_parentCtrl.text),
        clientTempId: _tempId,
      );

  String? _nameValidator(String? v, AppLocalizations l10n) {
    switch (validateStudentName(v ?? '')) {
      case null:
        return null;
      case StudentNameError.required:
        return l10n.addStudentRequired;
      case StudentNameError.length:
        return l10n.addStudentNameLength;
      case StudentNameError.chars:
        return l10n.addStudentNameChars;
    }
  }

  String _errorText(Object e, AppLocalizations l10n) {
    if (e is ApiException) {
      switch (e.code) {
        case 'invalid_name':
          return l10n.addStudentErrInvalidName;
        case 'invalid_group':
          return l10n.addStudentErrInvalidGroup;
        case 'pending_limit':
          return l10n.addStudentErrPendingLimit;
      }
      return e.message;
    }
    return l10n.addStudentErrGeneric;
  }

  Future<void> _submit({bool confirmNew = false}) async {
    if (_loading) return;
    final l10n = AppLocalizations.of(context)!;
    if (!confirmNew) {
      setState(() => _autoValidate = true);
      if (!(_formKey.currentState?.validate() ?? false)) return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.onSubmit(_draft, confirmNew: confirmNew);
      if (!mounted) return;
      Navigator.of(context).pop(AddStudentCreated(result));
    } on SimilarStudentsException catch (e) {
      if (!mounted) return;
      if (e.candidates.isEmpty) {
        // Server asked for confirmation but sent nobody to show: nothing to
        // pick, so proceed as "other child".
        setState(() => _loading = false);
        return _submit(confirmNew: true);
      }
      setState(() {
        _loading = false;
        _candidates = e.candidates;
      });
    } catch (e) {
      debugPrint('AddStudentDialog submit error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e, l10n);
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 8),
      firstDate: DateTime(now.year - 25),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final candidates = _candidates;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: candidates == null
                ? _buildForm(l10n)
                : _buildCandidates(l10n, candidates),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    return Form(
      key: _formKey,
      autovalidateMode: _autoValidate
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.addStudentTitle,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink1)),
          const SizedBox(height: 6),
          Text(l10n.addStudentSubtitle,
              style: const TextStyle(fontSize: 14, color: AppColors.ink2)),
          const SizedBox(height: 20),
          TextFormField(
            key: const Key('addStudentLastName'),
            controller: _lastCtrl,
            focusNode: _lastFocus,
            autofocus: true,
            enabled: !_loading,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            decoration: InputDecoration(labelText: l10n.addStudentLastName),
            validator: (v) => _nameValidator(v, l10n),
            onFieldSubmitted: (_) => _firstFocus.requestFocus(),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('addStudentFirstName'),
            controller: _firstCtrl,
            focusNode: _firstFocus,
            enabled: !_loading,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            decoration: InputDecoration(labelText: l10n.addStudentFirstName),
            validator: (v) => _nameValidator(v, l10n),
            onFieldSubmitted: (_) => _parentFocus.requestFocus(),
          ),
          const SizedBox(height: 14),
          // Optional: birth date.
          Semantics(
            button: true,
            label: l10n.addStudentBirthDate,
            child: InkWell(
              key: const Key('addStudentBirthDate'),
              borderRadius: BorderRadius.circular(12),
              onTap: _loading ? null : _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.addStudentBirthDate,
                  suffixIcon: _birthDate == null
                      ? const Icon(Icons.calendar_today_rounded, size: 18)
                      : IconButton(
                          tooltip: l10n.addStudentClearDate,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: _loading
                              ? null
                              : () => setState(() => _birthDate = null),
                        ),
                ),
                child: Text(
                  _birthDate == null ? '' : _fmtDate(_birthDate!),
                  style: const TextStyle(fontSize: 15, color: AppColors.ink1),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Optional: parent F.I.O.
          TextFormField(
            key: const Key('addStudentParentFio'),
            controller: _parentCtrl,
            focusNode: _parentFocus,
            enabled: !_loading,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              LengthLimitingTextInputFormatter(kParentFioMaxLength)
            ],
            decoration: InputDecoration(labelText: l10n.addStudentParentFio),
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _ErrorBanner(text: _error!),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('addStudentCancel'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  onPressed:
                      _loading ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  key: const Key('addStudentSubmit'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  onPressed: _loading ? null : () => _submit(),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(l10n.addStudentSubmit),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCandidates(
      AppLocalizations l10n, List<SimilarStudent> candidates) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.addStudentSimilarTitle,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink1)),
        const SizedBox(height: 6),
        Text(l10n.addStudentSimilarBody,
            style: const TextStyle(fontSize: 14, color: AppColors.ink2)),
        const SizedBox(height: 16),
        for (final c in candidates) ...[
          _CandidateTile(
            candidate: c,
            subtitle: [
              if (c.grade > 0) l10n.gradeClass(c.grade),
              if (c.groupName.isNotEmpty) c.groupName,
            ].join(' · '),
            enabled: !_loading,
            onTap: () => Navigator.of(context).pop(AddStudentUseExisting(c)),
          ),
          const SizedBox(height: 8),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          _ErrorBanner(text: _error!),
        ],
        const SizedBox(height: 14),
        ElevatedButton(
          key: const Key('addStudentNotThem'),
          style:
              ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _loading ? null : () => _submit(confirmNew: true),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(l10n.addStudentSimilarNone),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('addStudentBackToForm'),
          onPressed: _loading
              ? null
              : () => setState(() {
                    _candidates = null;
                    _error = null;
                  }),
          child: Text(l10n.backBtn),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final SimilarStudent candidate;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  const _CandidateTile({
    required this.candidate,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.pageBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(candidate.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink1)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.ink2)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String text;
  const _ErrorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.errorMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                key: const Key('addStudentError'),
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
