// lib/features/result/result_screen.dart
//
// Math+English flow, shown right after the student finishes. The student must
// NOT see their score/percentage/levels/wrong answers, so this renders the
// same thank-you screen the diagnostic flow uses. The result was already
// submitted (or queued offline) by TestScreen before navigating here.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/db/credential_cache.dart';
import '../../core/models/models.dart';
import '../../core/sync/sync_service.dart';
import '../diagnostic/screens/diagnostic_finished_screen.dart';

class ResultScreen extends StatefulWidget {
  final StudentSession session;
  final TestPackage package;
  final TestResult result;
  final bool synced;
  final int xpEarned;
  final List<dynamic> wrongAnswers;
  const ResultScreen(
      {super.key,
      required this.session,
      required this.package,
      required this.result,
      required this.synced,
      this.xpEarned = 0,
      this.wrongAnswers = const []});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    SyncService.instance.flushNow().catchError((Object e) {
      debugPrint('ResultScreen flushNow error: $e');
    });
  }

  /// Same action the old "Keyingi talaba" button had: wipe the saved
  /// credentials so the next student can't see the previous login/password,
  /// then pop back to the student entry screen. Also runs on the 15s
  /// auto-return, which the old screen did not have.
  Future<void> _next() async {
    await CredentialCache.clear();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DiagnosticFinishedScreen(
      studentName: widget.session.studentName,
      title: AppLocalizations.of(context)!.testFinishedTitle,
      returnLabel: AppLocalizations.of(context)!.nextStudent,
      onReturn: _next,
    );
  }
}
