// lib/features/test/question_report_sheet.dart
// Lets a pupil flag a problem with a specific question (wrong answer key,
// broken options, missing image/text, or something else) straight from the
// test-taking screen. Opened by EngineQNum's report icon (see
// core/engine/question_widgets.dart) via TestEngine._openReportSheet
// (core/engine/test_engine.dart), which supplies all student/test context.
//
// Submission is best-effort telemetry, same posture as HeartbeatService's
// session ping: it goes through the existing offline-first queue
// (OfflineQueue.enqueueLocal / SyncService), never a raw direct HTTP call,
// so a report survives a crash/offline session and is delivered once
// connectivity returns — and a failure here must never crash or block the
// test itself.

import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

import '../../core/api/api_client.dart';
import '../../core/db/offline_queue.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/app_colors.dart';

/// Opens the "report a problem with this question" bottom sheet. All
/// student/test context is captured by the caller — this widget only
/// collects the reason (+ comment, required for "other") and enqueues it.
void showQuestionReportSheet(
  BuildContext context, {
  required String testKey,
  required String variant,
  required String slotKey,
  required String questionSnapshot,
  required String studentCode,
  required String studentName,
  required String schoolCode,
  required String sessionId,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuestionReportSheet(
      testKey: testKey,
      variant: variant,
      slotKey: slotKey,
      questionSnapshot: questionSnapshot,
      studentCode: studentCode,
      studentName: studentName,
      schoolCode: schoolCode,
      sessionId: sessionId,
    ),
  );
}

/// Mirrors the backend's frozen `reason` enum exactly
/// (POST /api/v1/monitoring/question-report/).
enum _ReportReason { questionError, wrongOptions, imageTextMissing, other }

extension on _ReportReason {
  String get wireValue => switch (this) {
        _ReportReason.questionError => 'question_error',
        _ReportReason.wrongOptions => 'wrong_options',
        _ReportReason.imageTextMissing => 'image_text_missing',
        _ReportReason.other => 'other',
      };
}

class _QuestionReportSheet extends StatefulWidget {
  final String testKey;
  final String variant;
  final String slotKey;
  final String questionSnapshot;
  final String studentCode;
  final String studentName;
  final String schoolCode;
  final String sessionId;

  const _QuestionReportSheet({
    required this.testKey,
    required this.variant,
    required this.slotKey,
    required this.questionSnapshot,
    required this.studentCode,
    required this.studentName,
    required this.schoolCode,
    required this.sessionId,
  });

  @override
  State<_QuestionReportSheet> createState() => _QuestionReportSheetState();
}

class _QuestionReportSheetState extends State<_QuestionReportSheet> {
  final _commentCtrl = TextEditingController();
  bool _showOtherField = false;
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(_ReportReason reason, {String comment = ''}) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final payload = <String, dynamic>{
      // Internal-only marker read by ApiClient._dispatchLocalQueueItem to
      // route this row to /question-report/ instead of the default
      // /result/ — stripped before either payload leaves the device.
      '_offlineKind': 'question_report',
      'test_key': widget.testKey,
      'variant': widget.variant,
      'slot_key': widget.slotKey,
      'question_snapshot': widget.questionSnapshot,
      'student_code': widget.studentCode,
      'student_name': widget.studentName,
      'school_code': widget.schoolCode,
      'session_id': widget.sessionId,
      'reason': reason.wireValue,
      'comment': comment,
    };

    final l10n = AppLocalizations.of(context)!;
    try {
      final token = newIdempotencyToken();
      await OfflineQueue.enqueueLocal(payload, token);
      // Best-effort immediate delivery attempt — irrelevant if offline,
      // SyncService's periodic flush picks it up later regardless.
      SyncService.instance.flushNow().catchError((e) {
        debugPrint('QuestionReportSheet: flushNow error: $e');
      });
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.questionReportSentMsg),
          backgroundColor: AppColors.mint,
        ));
      }
    } catch (e) {
      debugPrint('QuestionReportSheet: enqueueLocal error: $e');
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.questionReportFailedMsg),
          backgroundColor: AppColors.err,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canSubmitOther = !_submitting && _commentCtrl.text.trim().isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0f172a),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slateDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.flag_outlined, color: AppColors.mint, size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.reportQuestionSheetTitle,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            _ReasonRow(
              label: l10n.reportReasonQuestionError,
              onTap: _submitting
                  ? null
                  : () => _submit(_ReportReason.questionError),
            ),
            _ReasonRow(
              label: l10n.reportReasonWrongOptions,
              onTap: _submitting
                  ? null
                  : () => _submit(_ReportReason.wrongOptions),
            ),
            _ReasonRow(
              label: l10n.reportReasonImageTextMissing,
              onTap: _submitting
                  ? null
                  : () => _submit(_ReportReason.imageTextMissing),
            ),
            _ReasonRow(
              label: l10n.reportReasonOther,
              selected: _showOtherField,
              onTap: _submitting
                  ? null
                  : () => setState(() => _showOtherField = true),
            ),
            if (_showOtherField) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _commentCtrl,
                maxLines: 3,
                autofocus: true,
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: AppColors.muted),
                decoration: InputDecoration(
                  hintText: l10n.reportCommentHint,
                  hintStyle: const TextStyle(color: Color(0xFF64748b)),
                  filled: true,
                  fillColor: const Color(0xFF1e293b),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSubmitOther
                      ? () => _submit(_ReportReason.other,
                          comment: _commentCtrl.text.trim())
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mint,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppColors.slateDark,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    l10n.reportSubmitBtn,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ReasonRow({required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.mint.withValues(alpha: .15)
                : const Color(0xFF1e293b),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.mint : AppColors.slateDark,
            ),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF64748b), size: 18),
          ]),
        ),
      );
}
