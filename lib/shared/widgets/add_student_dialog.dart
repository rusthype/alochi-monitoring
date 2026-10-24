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
import '../../core/offline/offline_errors.dart' show kClassWithoutTests;
import '../../core/models/add_student.dart';
import '../theme/app_theme.dart';
import '../utils/form_input_formatters.dart';

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
  final _birthCtrl = TextEditingController();
  final _lastFocus = FocusNode();
  final _firstFocus = FocusNode();
  final _parentFocus = FocusNode();

  /// One per dialog open == one per add attempt (stable across retries).
  final String _tempId = AddStudentDraft.newTempId();

  bool _loading = false;
  String? _error;
  SimilarStudentsException? _similar;
  bool _autoValidate = false;

  /// Field-level errors from a 400 (`invalid_name` / `invalid_parent_fio`),
  /// cleared as soon as the proctor edits that field.
  String? _srvNameError;
  String? _srvParentError;
  String? _srvBirthError;

  @override
  void dispose() {
    _lastCtrl.dispose();
    _firstCtrl.dispose();
    _parentCtrl.dispose();
    _birthCtrl.dispose();
    _lastFocus.dispose();
    _firstFocus.dispose();
    _parentFocus.dispose();
    super.dispose();
  }

  AddStudentDraft get _draft => AddStudentDraft(
        firstName: normalizeStudentName(_firstCtrl.text),
        lastName: normalizeStudentName(_lastCtrl.text),
        birthDate: checkBirthDate(_birthCtrl.text).date,
        parentFio: normalizeStudentName(_parentCtrl.text),
        clientTempId: _tempId,
      );

  String? _nameValidator(String? v, AppLocalizations l10n) {
    switch (validateStudentName(v ?? '')) {
      case null:
        return _srvNameError;
      case StudentNameError.required:
        return l10n.addStudentRequired;
      case StudentNameError.length:
        return l10n.addStudentNameLength;
      case StudentNameError.chars:
        return l10n.addStudentNameChars;
    }
  }

  String? _parentValidator(String? v, AppLocalizations l10n) =>
      isValidParentFio(v ?? '')
          ? _srvParentError
          : l10n.addStudentParentFioChars;

  String? _birthValidator(String? v, AppLocalizations l10n) {
    switch (checkBirthDate(v ?? '').error) {
      case null:
        return _srvBirthError;
      case BirthDateError.incomplete:
        // Don't nag while the date is still being typed; submit catches it.
        return _autoValidate ? l10n.addStudentBirthDateIncomplete : null;
      case BirthDateError.invalid:
        return l10n.addStudentErrInvalidBirthDate;
      case BirthDateError.future:
        return l10n.addStudentBirthDateFuture;
      case BirthDateError.tooOld:
        return l10n.addStudentBirthDateTooOld;
    }
  }

  String _errorText(Object e, AppLocalizations l10n) {
    if (e is AddStudentRejectedException) return l10n.addStudentErrRejected;
    if (e is PendingLimitException) {
      return e.isGroup
          ? l10n.addStudentErrPendingLimitGroup
          : l10n.addStudentErrPendingLimit;
    }
    if (e is ApiException) {
      if (e.statusCode == 429) return l10n.addStudentErrThrottled;
      if (isAddEndpointMissing(e)) return l10n.addStudentErrUnsupported;
      switch (e.code) {
        case 'invalid_group':
          return l10n.addStudentErrInvalidGroup;
        case kClassWithoutTests:
          return l10n.diagnosticClassWithoutTests;
        case 'invalid_class':
          return l10n.addStudentErrInvalidClass;
        case 'duplicate_student':
          return l10n.addStudentErrDuplicate;
        case 'pending_limit':
          return l10n.addStudentErrPendingLimit;
        case 'invalid_client_temp_id':
          // Never expected (the client always sends new:<uuid>) - log it.
          debugPrint('AddStudentDialog: invalid_client_temp_id for $_tempId');
          return l10n.addStudentErrGeneric;
      }
      // Unmapped status/code (incl. network ApiException(0)): never show the
      // raw server/exception text.
      debugPrint('AddStudentDialog unmapped error: ${e.statusCode} ${e.code}');
    }
    return l10n.addStudentErrGeneric;
  }

  /// 400 field codes -> inline errors on the form (back from "Bu shumi?").
  bool _showFieldError(Object e, AppLocalizations l10n) {
    if (e is! ApiException) return false;
    if (e.code != 'invalid_name' &&
        e.code != 'invalid_parent_fio' &&
        e.code != 'invalid_birth_date') {
      return false;
    }
    setState(() {
      _loading = false;
      _similar = null;
      _error = null;
      _autoValidate = true;
      if (e.code == 'invalid_name') {
        _srvNameError = l10n.addStudentErrInvalidName;
      } else if (e.code == 'invalid_birth_date') {
        _srvBirthError = l10n.addStudentErrInvalidBirthDate;
      } else {
        _srvParentError = l10n.addStudentParentFioChars;
      }
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _formKey.currentState?.validate());
    return true;
  }

  Future<void> _submit(
      {bool confirmNew = false, OtherClassMatch? transferFrom}) async {
    if (_loading) return;
    final l10n = AppLocalizations.of(context)!;
    if (!confirmNew) {
      setState(() => _autoValidate = true);
      if (!(_formKey.currentState?.validate() ?? false)) return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _srvNameError = null;
      _srvParentError = null;
      _srvBirthError = null;
    });
    try {
      final draft = transferFrom == null
          ? _draft
          : _draft.withTransferClaim(TransferClaim.fromMatch(transferFrom));
      final result = await widget.onSubmit(draft, confirmNew: confirmNew);
      if (!mounted) return;
      Navigator.of(context).pop(AddStudentCreated(result));
    } on SimilarStudentsException catch (e) {
      if (!mounted) return;
      if (e.candidates.isEmpty && e.otherClassMatches.isEmpty) {
        // Server asked for confirmation but sent nobody to show: nothing to
        // pick, so proceed as "other child".
        setState(() => _loading = false);
        return _submit(confirmNew: true);
      }
      setState(() {
        _loading = false;
        _similar = e;
      });
    } catch (e) {
      debugPrint('AddStudentDialog submit error: $e');
      if (!mounted) return;
      if (_showFieldError(e, l10n)) return;
      setState(() {
        _loading = false;
        _error = _errorText(e, l10n);
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final typed = checkBirthDate(_birthCtrl.text).date;
    final picked = await showDatePicker(
      context: context,
      initialDate: typed ?? DateTime(today.year - 10, today.month, today.day),
      firstDate: kBirthDateMin,
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null && mounted) {
      _srvBirthError = null;
      _birthCtrl.text = formatBirthDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final similar = _similar;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: similar == null
                ? _buildForm(l10n)
                : _buildCandidates(l10n, similar),
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
            inputFormatters: [
              const TitleCaseNameFormatter(),
              LengthLimitingTextInputFormatter(80),
            ],
            decoration: InputDecoration(labelText: l10n.addStudentLastName),
            onChanged: (_) => _srvNameError = null,
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
            inputFormatters: [
              const TitleCaseNameFormatter(),
              LengthLimitingTextInputFormatter(80),
            ],
            decoration: InputDecoration(labelText: l10n.addStudentFirstName),
            onChanged: (_) => _srvNameError = null,
            validator: (v) => _nameValidator(v, l10n),
            onFieldSubmitted: (_) => _parentFocus.requestFocus(),
          ),
          const SizedBox(height: 14),
          // Optional: birth date, typed as KK.OO.YYYY (calendar is secondary).
          TextFormField(
            key: const Key('addStudentBirthDate'),
            controller: _birthCtrl,
            enabled: !_loading,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            inputFormatters: const [BirthDateMaskFormatter()],
            decoration: InputDecoration(
              labelText: l10n.addStudentBirthDate,
              hintText: l10n.addStudentBirthDateHint,
              suffixIcon: IconButton(
                key: const Key('addStudentBirthDatePick'),
                tooltip: l10n.addStudentPickDate,
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                onPressed: _loading ? null : _pickDate,
              ),
            ),
            onChanged: (_) => _srvBirthError = null,
            validator: (v) => _birthValidator(v, l10n),
            onFieldSubmitted: (_) => _parentFocus.requestFocus(),
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
              const TitleCaseNameFormatter(),
              LengthLimitingTextInputFormatter(kParentFioMaxLength)
            ],
            decoration: InputDecoration(labelText: l10n.addStudentParentFio),
            onChanged: (_) => _srvParentError = null,
            validator: (v) => _parentValidator(v, l10n),
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

  Widget _buildCandidates(AppLocalizations l10n, SimilarStudentsException sim) {
    final candidates = sim.candidates;
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
        if (candidates.isNotEmpty) ...[
          Text(l10n.addStudentSimilarBody,
              style: const TextStyle(fontSize: 14, color: AppColors.ink2)),
          const SizedBox(height: 16),
        ],
        for (final c in candidates) ...[
          _CandidateTile(
            candidate: c,
            subtitle: [
              // class_label ("4-A") already says the grade: show one or the other.
              if (c.groupName.isNotEmpty)
                c.groupName
              else if (c.grade > 0)
                l10n.gradeClass(c.grade),
            ].join(' · '),
            enabled: !_loading,
            onTap: () => Navigator.of(context).pop(AddStudentUseExisting(c)),
          ),
          const SizedBox(height: 8),
        ],
        if (sim.otherClassMatches.isNotEmpty)
          _OtherClassWarning(
            key: const Key('addStudentOtherClassWarning'),
            lines: [
              for (final m in sim.otherClassMatches)
                l10n.addStudentOtherClassMatch(m.name, m.classLabel),
            ],
          ),
        for (var i = 0; i < sim.otherClassMatches.length; i++) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: Key('addStudentTransferClaim_$i'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            onPressed: _loading
                ? null
                : () => _submit(
                    confirmNew: true, transferFrom: sim.otherClassMatches[i]),
            child: Text(
              sim.otherClassMatches.length > 1
                  ? '${l10n.addStudentTransferYes} - ${sim.otherClassMatches[i].classLabel}'
                  : l10n.addStudentTransferYes,
              textAlign: TextAlign.center,
            ),
          ),
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
                    _similar = null;
                    _error = null;
                  }),
          child: Text(l10n.backBtn),
        ),
      ],
    );
  }
}

/// Informational: the same name exists in ANOTHER class (no choice offered).
class _OtherClassWarning extends StatelessWidget {
  final List<String> lines;
  const _OtherClassWarning({super.key, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warnMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.amberDark, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in lines)
                  Text(l,
                      style:
                          const TextStyle(color: AppColors.ink1, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
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
