// lib/features/offline/offline_asset_ui.dart
//
// The two UI pieces the built-in ("assets") runners need in offline USB / LAN
// mode (core/offline/offline_asset_results.dart is the data side):
//  * [OfflineStudentPicker] -- group -> student from the roster, replacing the
//    free-text name fields (a result needs a roster `student_id`);
//  * [OfflineAssetSaveState] -- what a result screen does instead of showing a
//    score and queueing for the internet: write the answers to the pack chain /
//    hub and show "Javoblaringiz saqlandi" (no score), or an honest failure with
//    a retry that re-sends the very same payload under the same idempotency key.
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/offline/offline_asset_results.dart';
import '../../shared/theme/app_theme.dart';
import 'offline_saved_screen.dart';

class OfflineStudentPicker extends StatefulWidget {
  /// Null while no student is picked.
  final ValueChanged<OfflineAssetStudent?> onChanged;
  const OfflineStudentPicker({super.key, required this.onChanged});

  @override
  State<OfflineStudentPicker> createState() => _OfflineStudentPickerState();
}

class _OfflineStudentPickerState extends State<OfflineStudentPicker> {
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _group;
  String? _studentId;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final source = offlineContentSource;
    try {
      final g = await api.fetchGroups(source?.schoolCode ?? '',
          schoolId: source?.schoolId);
      if (!mounted) return;
      setState(() {
        _groups = g;
        _loading = false;
      });
    } catch (e) {
      debugPrint('OfflineStudentPicker: groups failed (${e.runtimeType})');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _pickGroup(Map<String, dynamic>? group) async {
    setState(() {
      _group = group;
      _students = [];
      _studentId = null;
      _failed = false;
      _loading = group != null;
    });
    widget.onChanged(null);
    final id = group?['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final s = await api.fetchStudents(id);
      if (!mounted) return;
      setState(() {
        _students = s;
        _loading = false;
      });
    } catch (e) {
      debugPrint('OfflineStudentPicker: students failed (${e.runtimeType})');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _pickStudent(String? id) {
    setState(() => _studentId = id);
    final group = _group;
    Map<String, dynamic>? student;
    for (final s in _students) {
      if (s['id']?.toString() == id) student = s;
    }
    widget.onChanged(student == null || group == null
        ? null
        : OfflineAssetStudent.fromRoster(student, group));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<Map<String, dynamic>>(
        key: const ValueKey('offline_group'),
        isExpanded: true,
        initialValue: _group,
        hint: Text(l10n.selectGroup),
        items: [
          for (final g in _groups)
            DropdownMenuItem(
                value: g, child: Text(g['name']?.toString() ?? '')),
        ],
        onChanged: _loading ? null : _pickGroup,
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('offline_student_${_group?['id']}'),
        isExpanded: true,
        initialValue: _studentId,
        hint: Text(l10n.selectStudent),
        items: [
          for (final s in _students)
            DropdownMenuItem(
                value: s['id']?.toString() ?? '',
                child: Text(s['name']?.toString() ?? '')),
        ],
        onChanged: _students.isEmpty ? null : _pickStudent,
      ),
      if (_loading)
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 2)),
      if (_failed || (_group != null && !_loading && _students.isEmpty))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_failed ? l10n.loadStudentsError : l10n.noStudentsInGroup,
              style: const TextStyle(color: AppColors.err, fontSize: 12)),
        ),
    ]);
  }
}

/// Mix into a result screen's State. Call [saveOfflineAsset] instead of the
/// online enqueue and return [offlineSavedView] from `build` while
/// [offlineSaved] / [offlineFailed] is set.
mixin OfflineAssetSaveState<T extends StatefulWidget> on State<T> {
  bool offlineSaved = false;
  bool offlineFailed = false;

  // Built once: a retry must resend byte-identical content under the same
  // idempotency key (the payload carries "now" and the duration).
  Map<String, dynamic>? _offlinePayload;
  String? _offlineToken;
  VoidCallback? _offlineRetry;

  Future<void> saveOfflineAsset({
    required String testKey,
    required OfflineAssetStudent? student,
    required Map<String, dynamic> Function() buildPayload,
  }) async {
    _offlineRetry = () {
      setState(() => offlineFailed = false);
      saveOfflineAsset(
          testKey: testKey, student: student, buildPayload: buildPayload);
    };
    try {
      final payload = _offlinePayload ??= buildPayload();
      final token = _offlineToken ??= newIdempotencyToken();
      await recordOfflineAssetResult(
          payload: payload, token: token, testKey: testKey, student: student);
      if (!mounted) return;
      setState(() {
        offlineSaved = true;
        offlineFailed = false;
      });
    } catch (e) {
      // Type only: the payload holds a student's answers.
      debugPrint('OfflineAssetSaveState: not saved (${e.runtimeType})');
      if (!mounted) return;
      setState(() {
        offlineSaved = false;
        offlineFailed = true;
      });
    }
  }

  /// Null in normal (online) mode. In offline mode ALWAYS a widget -- the saved
  /// / failed screen, or a spinner while the write is in flight -- so the
  /// runner's own score screen is never built (decision 2: no score offline).
  Widget? offlineGate(String firstName, String lastName) {
    if (!isOfflineContentMode) return null;
    if (offlineSaved || offlineFailed) {
      return offlineSavedView(firstName, lastName);
    }
    return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator()));
  }

  /// "Javoblaringiz saqlandi" (no score) or the honest failure with a retry.
  Widget offlineSavedView(String firstName, String lastName) =>
      OfflineSavedScreen(
        firstName: firstName,
        lastName: lastName,
        onNext: () => context.go('/'),
        onRetry: offlineFailed ? _offlineRetry : null,
      );
}
