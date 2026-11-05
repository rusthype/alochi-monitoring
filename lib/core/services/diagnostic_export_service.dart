/// Generates one self-contained, print-ready HTML "passport" per diagnostic
/// history record for the offline ZIP-export feature. Deliberately
/// independent from `HtmlService.generateResultHtml` (used by the
/// unrelated monitoring test flow, which has real per-topic data this
/// diagnostic-kiosk flow never captures — see plan Context).
///
/// Every record here has a math_score/english_score pair that is either
/// BOTH present (raw correct-count out of `kDiagnosticSubjectMax`, once the
/// backend has scored the attempt) or BOTH null (the attempt is still
/// sitting in the local offline queue, never reached the server — the
/// PRIMARY reason this export feature exists). No per-topic/per-question
/// data exists anywhere in this flow, so no topic-breakdown section is
/// generated — fabricating one would be dishonest.
library;

import 'dart:convert' show HtmlEscape, HtmlEscapeMode;
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../db/offline_queue.dart';
import '../offline/atomic_file.dart';

/// How many exports of one school (same label, same folder) are kept; older
/// ones are pruned after each successful save so names+scores don't pile up.
const int kExportKeepPerSchool = 5;

/// Flat max question count per fixed-variant diagnostic subject (both
/// math and english) — backend `apps/diagnostic/fixed_variant.py`'s
/// `QUESTIONS_PER_VARIANT = 30`, confirmed by
/// `tests_fixed_variant.py::test_fixed_variant_attempt_reports_flat_30_max_for_both_subjects`
/// (`max_math=30, max_english=30`).
const int kDiagnosticSubjectMax = 30;

class DiagnosticExportService {
  DiagnosticExportService._();

  static String generateStudentPassportHtml(
    Map<String, dynamic> record, {
    required AppLocalizations l10n,
  }) {
    final rawName = (record['student_name'] ?? '').toString();
    // Everything interpolated into the HTML (title included) is escaped.
    final studentName = _esc(rawName);
    final initial = _esc(_initial(rawName));
    final classLabel = _esc((record['class_label'] ?? '').toString());
    final school = _esc((record['school'] ?? '').toString());
    final dateStr = _formatDate(record['date_taken'] as int?);
    final mathScore = record['math_score'] as int?;
    final englishScore = record['english_score'] as int?;

    if (mathScore == null && englishScore == null) {
      return _pendingHtml(
        l10n: l10n,
        studentName: studentName,
        initial: initial,
        classLabel: classLabel,
        school: school,
        dateStr: dateStr,
      );
    }
    return _sentHtml(
      l10n: l10n,
      studentName: studentName,
      initial: initial,
      classLabel: classLabel,
      school: school,
      dateStr: dateStr,
      mathScore: mathScore ?? 0,
      englishScore: englishScore ?? 0,
      isLocalEstimate: record['_local_estimate'] == true,
    );
  }

  static String _formatDate(int? epochMs) {
    if (epochMs == null) return '-';
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  static const _html = HtmlEscape(HtmlEscapeMode.element);
  static String _esc(String v) => _html.convert(v);

  static String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }

  static const _headStyle = '''
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Plus Jakarta Sans',sans-serif;background:#fff;color:#111;font-size:13px;line-height:1.5;padding:24px}@media print{@page{margin:12mm 14mm}body{padding:0}}</style>''';

  static const _fontLink =
      "<link href='https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap' rel='stylesheet'>";

  static String _pendingHtml({
    required AppLocalizations l10n,
    required String studentName,
    required String initial,
    required String classLabel,
    required String school,
    required String dateStr,
  }) {
    return '''
<!DOCTYPE html><html lang='${l10n.localeName}'><head><meta charset='UTF-8'><title>A'lochi — $studentName</title>
$_fontLink
$_headStyle
</head><body><div style='max-width:640px;margin:0 auto'>
  <div style='display:flex;align-items:center;justify-content:space-between;border-bottom:2.5px solid #111;padding-bottom:10px;margin-bottom:16px'>
    <div style='font-size:11px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:#555'>${l10n.diagnosticPassportHeader}</div>
    <div style='font-size:10px;color:#888'>$dateStr</div>
  </div>
  <div style='display:flex;align-items:center;gap:18px;background:#f7f7f7;border-radius:12px;padding:16px 20px;margin-bottom:16px'>
    <div style='width:54px;height:54px;border-radius:50%;background:#111;color:#fff;display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:900;flex-shrink:0'>$initial</div>
    <div style='flex:1'>
      <div style='font-size:20px;font-weight:800;margin-bottom:5px'>$studentName</div>
      <div style='display:flex;gap:16px;font-size:12px;color:#555'><span>$classLabel</span><span>$school</span></div>
    </div>
  </div>
  <div style='background:#FEF2F2;border:1.5px solid #DC2626;border-radius:12px;padding:18px 20px'>
    <div style='font-size:13px;font-weight:800;color:#DC2626;margin-bottom:6px'>${l10n.exportPendingTitle}</div>
    <div style='font-size:12px;color:#7f1d1d;line-height:1.7'>${l10n.exportPendingBody}</div>
  </div>
  <div style='border-top:1px solid #eee;padding-top:8px;margin-top:18px;display:flex;justify-content:space-between;font-size:10px;color:#bbb'>
    <span>${l10n.exportFooterBrand}</span>
    <span>$school · $classLabel · $dateStr</span>
  </div>
</div></body></html>
''';
  }

  static String _sentHtml({
    required AppLocalizations l10n,
    required String studentName,
    required String initial,
    required String classLabel,
    required String school,
    required String dateStr,
    required int mathScore,
    required int englishScore,
    bool isLocalEstimate = false,
  }) {
    final mathPct = (mathScore * 100 / kDiagnosticSubjectMax).round();
    final engPct = (englishScore * 100 / kDiagnosticSubjectMax).round();
    final totalOk = mathScore + englishScore;
    const totalMax = kDiagnosticSubjectMax * 2;
    final totalErr = totalMax - totalOk;
    final pct = (totalOk * 100 / totalMax).round();

    String verdict;
    String verdictColor;
    if (pct >= 80) {
      verdict = l10n.exportVerdictExcellent;
      verdictColor = '#10B981';
    } else if (pct >= 60) {
      verdict = l10n.exportVerdictGood;
      verdictColor = '#F97316';
    } else {
      verdict = l10n.exportVerdictNeedsPractice;
      verdictColor = '#EF4444';
    }

    String subjColor(int p) => p >= 60 ? '#10B981' : '#EF4444';

    final String summary;
    if (pct >= 80) {
      summary = l10n.exportSummaryHigh(studentName, pct);
    } else if (pct >= 60) {
      summary = l10n.exportSummaryMid(studentName, pct);
    } else {
      summary = l10n.exportSummaryLow(studentName, pct);
    }

    // The only real per-subject signal available (no per-topic data exists
    // for this flow — see plan Context) is which of the two subjects
    // scored lower; the weaker one gets more days in the generic plan.
    final mathIsWeaker = mathPct <= engPct;
    final firstFocus =
        mathIsWeaker ? l10n.exportMathExercises : l10n.exportEnglishExercises;
    final secondFocus =
        mathIsWeaker ? l10n.exportEnglishExercises : l10n.exportMathExercises;

    return '''
<!DOCTYPE html><html lang='${l10n.localeName}'><head><meta charset='UTF-8'><title>A'lochi — $studentName</title>
$_fontLink
$_headStyle
</head><body><div style='max-width:720px;margin:0 auto'>
  <div style='display:flex;align-items:center;justify-content:space-between;border-bottom:2.5px solid #111;padding-bottom:10px;margin-bottom:16px'>
    <div style='font-size:11px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:#555'>${l10n.diagnosticPassportHeader}</div>
    <div style='font-size:10px;color:#888'>$dateStr</div>
  </div>
  ${isLocalEstimate ? "<div style='background:#FFF7ED;border:1.5px solid #F97316;border-radius:10px;padding:10px 16px;margin-bottom:14px;font-size:11px;font-weight:700;color:#9A3412'>${l10n.exportLocalEstimateBanner}</div>" : ''}
  <div style='display:flex;align-items:center;gap:18px;background:#f7f7f7;border-radius:12px;padding:16px 20px;margin-bottom:16px'>
    <div style='width:54px;height:54px;border-radius:50%;background:#111;color:#fff;display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:900;flex-shrink:0'>$initial</div>
    <div style='flex:1'>
      <div style='font-size:20px;font-weight:800;margin-bottom:5px'>$studentName</div>
      <div style='display:flex;gap:16px;font-size:12px;color:#555'><span>$classLabel</span><span>$school</span></div>
    </div>
    <div style='background:#111;color:#fff;border-radius:12px;padding:14px 22px;text-align:center'>
      <div style='font-size:32px;font-weight:900;line-height:1;margin-bottom:3px;color:$verdictColor'>$pct%</div>
      <div style='font-size:10px;opacity:.6;text-transform:uppercase'>$verdict</div>
    </div>
  </div>
  <div style='display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:16px'>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#10B981'>$totalOk</div><div style='font-size:11px;color:#888;margin-top:2px'>${l10n.correctAnswerLabelPdf}</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#EF4444'>$totalErr</div><div style='font-size:11px;color:#888;margin-top:2px'>${l10n.wrongAnswerLabelPdf}</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#F97316'>$totalMax</div><div style='font-size:11px;color:#888;margin-top:2px'>${l10n.totalQuestionsCountLabel}</div></div>
  </div>
  <div style='display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:16px'>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#111'>$mathScore/$kDiagnosticSubjectMax</div><div style='font-size:11px;color:#888;margin-top:2px'>${l10n.mathSubjectFull}</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#111'>$englishScore/$kDiagnosticSubjectMax</div><div style='font-size:11px;color:#888;margin-top:2px'>${l10n.englishSubjectFull}</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:${subjColor(mathPct)}'>$mathPct%</div><div style='font-size:11px;color:#888;margin-top:2px'>${l10n.htmlMathPercentLabel}</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:${subjColor(engPct)}'>$engPct%</div><div style='font-size:11px;color:#888;margin-top:2px'>${l10n.htmlEnglishPercentLabel}</div></div>
  </div>
  <div style='display:grid;grid-template-columns:1fr 1fr;gap:14px'>
    <div>
      <div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.8px;color:#888;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px'>${l10n.fourteenDayPlanHeader}</div>
      <div style='padding-left:14px;border-left:2.5px solid #eee'>
        <div style='margin-bottom:10px'><div style='font-size:9px;font-weight:700;color:#F97316;text-transform:uppercase'>${l10n.exportDays1to4}</div><div style='font-size:12px;font-weight:700;margin-top:2px'>$firstFocus</div><div style='font-size:11px;color:#888'>${l10n.exportDailyPractice1520Msg}</div></div>
        <div style='margin-bottom:10px'><div style='font-size:9px;font-weight:700;color:#2563EB;text-transform:uppercase'>${l10n.exportDays5to7}</div><div style='font-size:12px;font-weight:700;margin-top:2px'>$secondFocus</div><div style='font-size:11px;color:#888'>${l10n.exportDailyPractice1520Msg}</div></div>
        <div style='margin-bottom:10px'><div style='font-size:9px;font-weight:700;color:#10B981;text-transform:uppercase'>${l10n.dayRange8_11}</div><div style='font-size:12px;font-weight:700;margin-top:2px'>${l10n.mixedExercisesTopic}</div><div style='font-size:11px;color:#888'>${l10n.exportReviewBothSubjectsMsg}</div></div>
        <div><div style='font-size:9px;font-weight:700;color:#888;text-transform:uppercase'>${l10n.dayRange12_14}</div><div style='font-size:12px;font-weight:700;margin-top:2px'>${l10n.controlTestTopic}</div><div style='font-size:11px;color:#888'>${l10n.compareResultsMsg}</div></div>
      </div>
    </div>
    <div>
      <div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.8px;color:#888;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px'>${l10n.aiSummaryHeader}</div>
      <div style='background:#111;color:#fff;border-radius:10px;padding:13px 15px;margin-bottom:12px'>
        <div style='font-size:9px;opacity:.4;text-transform:uppercase;letter-spacing:.6px;margin-bottom:6px'>${l10n.alochiAiLabel}</div>
        <div style='font-size:12px;line-height:1.75;opacity:.88'>$summary</div>
      </div>
      <div style='background:#f7f7f7;border-radius:10px;padding:12px 14px'>
        <div style='font-size:11px;font-weight:700;margin-bottom:5px'>${l10n.forParentsLabel}</div>
        <div style='font-size:11px;color:#444;line-height:1.8'>${l10n.exportParentTipsText.replaceAll('\n', '<br>')}</div>
      </div>
    </div>
  </div>
  <div style='border-top:1px solid #eee;padding-top:8px;margin-top:18px;display:flex;justify-content:space-between;font-size:10px;color:#bbb'>
    <span>${l10n.exportFooterBrand}</span>
    <span>$school · $classLabel · $dateStr</span>
  </div>
</div></body></html>
''';
  }

  /// Enriches [records] with a best-effort local score estimate for any
  /// still-'pending' row this device's own offline queue has enough data to
  /// self-score — see plan doc Context. [queuedFinishPayloads] is the
  /// already-decrypted contents of `OfflineQueue.peekLocalQueue()` (pure,
  /// no I/O here — the caller does the reading). A record with no matching
  /// or usable queued answer-key data (older app version, different
  /// attempt, wrong `_offlineKind`, or genuinely nothing queued yet) is
  /// returned completely unchanged — this must never invent a score.
  ///
  /// The estimate is deliberately NOT written back to DiagnosticHistoryDb
  /// anywhere in this codebase — it only ever flows into the export ZIP's
  /// HTML (see `_sentHtml`'s `isLocalEstimate` banner), never into the
  /// app's own history list UI (`DiagnosticHistoryScreen._row`).
  static List<Map<String, dynamic>> withLocalEstimates(
    List<Map<String, dynamic>> records,
    List<Map<String, dynamic>> queuedFinishPayloads,
  ) {
    final byAttempt = <String, List<Map<String, dynamic>>>{};
    for (final item in queuedFinishPayloads) {
      if (item['_offlineKind'] != 'diagnostic_finish') continue;
      final attemptId = (item['attempt_id'] ?? '').toString();
      if (attemptId.isEmpty) continue;
      byAttempt.putIfAbsent(attemptId, () => []).add(item);
    }
    return records.map((record) {
      if (record['status'] != 'pending') return record;
      final attemptId = (record['attempt_id'] ?? '').toString();
      final queuedForAttempt = byAttempt[attemptId];
      if (queuedForAttempt == null) return record;
      final estimate = _localScoreFromQueuedFinishes(queuedForAttempt);
      if (estimate == null) return record;
      return {
        ...record,
        // A subject the queue has no estimate for keeps its official (sent)
        // score instead of being overwritten with null.
        'math_score': estimate['math'] ?? record['math_score'],
        'english_score': estimate['english'] ?? record['english_score'],
        '_local_estimate': true,
      };
    }).toList();
  }

  /// Sums correct answers per subject from this attempt's queued finish
  /// payloads, comparing each `answers` entry's `selected` display letter
  /// against `_offline_answer_key.answers[question_id]`. Returns null when
  /// no queued row for this attempt carries a usable answer key at all.
  /// An empty `answers` map counts as "no usable key" too — that happens
  /// when the subject was started from a `kiosk/peek/` (dry_run) fallback
  /// package, which never carries `correct_display_letter`, and must not
  /// be scored as a confirmed 0 correct.
  static Map<String, int?>? _localScoreFromQueuedFinishes(
    List<Map<String, dynamic>> queuedForAttempt,
  ) {
    int? mathCorrect;
    int? englishCorrect;
    for (final item in queuedForAttempt) {
      final key = item['_offline_answer_key'];
      final answers = item['answers'];
      if (key is! Map || answers is! List) continue;
      final correctAnswers = key['answers'];
      if (correctAnswers is! Map || correctAnswers.isEmpty) continue;
      final subject = (key['subject'] ?? '').toString();
      var correct = 0;
      for (final a in answers) {
        if (a is! Map) continue;
        final qid = (a['question_id'] ?? '').toString();
        final selected = a['selected'];
        if (correctAnswers.containsKey(qid) &&
            correctAnswers[qid] == selected) {
          correct++;
        }
      }
      if (subject == 'math') {
        mathCorrect = correct;
      } else if (subject == 'english') {
        englishCorrect = correct;
      }
    }
    if (mathCorrect == null && englishCorrect == null) return null;
    return {'math': mathCorrect, 'english': englishCorrect};
  }

  /// File-name-safe form of [v]: no path separators, `..`, control or
  /// Windows-reserved characters (zip entry names are untrusted data).
  static String _safeName(String v) => v
      .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f\x7f]'), '_')
      .replaceAll('..', '_');

  /// Builds the raw ZIP bytes for [records] — pure, no disk I/O, easily
  /// unit-testable. [onProgress] fires once per record, after that
  /// record's HTML has been added to the archive.
  static Uint8List buildZipBytes(
    List<Map<String, dynamic>> records, {
    required AppLocalizations l10n,
    void Function(int done)? onProgress,
  }) {
    final archive = Archive();
    final usedNames = <String>{};
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final html = generateStudentPassportHtml(record, l10n: l10n);
      final attemptId = (record['attempt_id'] ?? '').toString();
      final shortId = _safeName(
          attemptId.length >= 8 ? attemptId.substring(0, 8) : attemptId);
      final studentSlug = _safeName((record['student_name'] ?? 'student')
          .toString()
          .trim()
          .replaceAll(RegExp(r'\s+'), '_'));
      var filename = 'natija_${studentSlug}_$shortId.html';
      // attempt_id is unique per DiagnosticHistoryDb row, but guard
      // against a blank/duplicate attempt_id silently overwriting a
      // previous entry inside the zip.
      var suffix = 1;
      while (!usedNames.add(filename)) {
        filename = 'natija_${studentSlug}_${shortId}_$suffix.html';
        suffix++;
      }
      archive.addFile(ArchiveFile.string(filename, html));
      onProgress?.call(i + 1);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Builds the zip and saves it to the platform Downloads folder (same
  /// fallback chain as `engine_host_screen.dart`'s PDF export — see plan
  /// Context), returning the saved file's path. Does NOT open the file;
  /// the caller decides whether/when to do that (e.g. a SnackBar action).
  static Future<String> exportResultsToZip(
    List<Map<String, dynamic>> records, {
    required AppLocalizations l10n,
    void Function(int done)? onProgress,
    String? schoolLabel,
  }) async {
    final hasPending = records.any((r) => r['status'] == 'pending');
    final queued = hasPending
        ? await OfflineQueue.peekLocalQueue()
        : const <Map<String, dynamic>>[];
    final enrichedRecords = withLocalEstimates(records, queued);
    final zipBytes = buildZipBytes(enrichedRecords,
        l10n: l10n, onProgress: onProgress);

    final now = DateTime.now();

    String? path;
    if (!Platform.isIOS && !Platform.isAndroid) {
      try {
        Directory? dir;
        if (Platform.isMacOS) {
          final home = Platform.environment['HOME'];
          if (home != null) {
            final parts = home.split('/');
            if (parts.length >= 3 && parts[1] == 'Users') {
              dir = Directory('/Users/${parts[2]}/Downloads');
            }
          }
        }
        dir ??= await getDownloadsDirectory();
        if (dir != null) {
          path = await saveZipUnique(dir, zipBytes, now, label: schoolLabel);
        }
      } catch (_) {}
    }
    path ??= await saveZipUnique(
        await getApplicationSupportDirectory(), zipBytes, now,
        label: schoolLabel);
    return path;
  }

  /// Writes [bytes] into [dir] as `alochi_diagnostika_[<label>_]<date>_<HHmmss>.zip`
  /// (temp file + verify + rename, see [writeFileVerified]) and never
  /// overwrites: a taken name gets `-2`, `-3` ... Returns the saved path.
  @visibleForTesting
  static Future<String> saveZipUnique(
      Directory dir, Uint8List bytes, DateTime now, {String? label}) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final tag = _safeName((label ?? '').trim().replaceAll(RegExp(r'\s+'), '_'))
        .replaceAll(RegExp(r'_+'), '_');
    final base = 'alochi_diagnostika_${tag.isEmpty ? '' : '${tag}_'}'
        '${now.year}-${two(now.month)}-'
        '${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    var file = File('${dir.path}/$base.zip');
    for (var n = 2; file.existsSync(); n++) {
      file = File('${dir.path}/$base-$n.zip');
    }
    await writeFileVerified(file, bytes);
    if (tag.isNotEmpty) await _pruneOldExports(dir, tag, file);
    return file.path;
  }

  @visibleForTesting
  static Future<void> defaultDeleteExportFile(File f) => f.delete();

  /// Test seam for the (best-effort) prune delete.
  @visibleForTesting
  static Future<void> Function(File) deleteExportFile = defaultDeleteExportFile;

  /// Deletes all but the newest [kExportKeepPerSchool] exports of [tag] in
  /// [dir]. Matches only the exact names [saveZipUnique] generates, plain
  /// files only (no dirs/symlinks), never [keep]. Best-effort: never throws.
  static Future<void> _pruneOldExports(
      Directory dir, String tag, File keep) async {
    try {
      final re = RegExp('^alochi_diagnostika_${RegExp.escape(tag)}_'
          r'(\d{4}-\d{2}-\d{2}_\d{6})(?:-(\d+))?\.zip$');
      final found = <({File file, String stamp, int n, DateTime mtime})>[];
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final m = re.firstMatch(e.uri.pathSegments.last);
        if (m == null) continue;
        found.add((
          file: e,
          stamp: m.group(1)!,
          n: int.tryParse(m.group(2) ?? '') ?? 1,
          mtime: e.statSync().modified,
        ));
      }
      // Newest first: name timestamp, then -N suffix, then mtime.
      found.sort((a, b) {
        final c = b.stamp.compareTo(a.stamp);
        if (c != 0) return c;
        final d = b.n.compareTo(a.n);
        return d != 0 ? d : b.mtime.compareTo(a.mtime);
      });
      final keepName = keep.uri.pathSegments.last;
      var kept = 0;
      for (final f in found) {
        final isNew = f.file.uri.pathSegments.last == keepName;
        if (isNew || kept < kExportKeepPerSchool) {
          kept++;
          continue;
        }
        try {
          await deleteExportFile(f.file);
        } catch (_) {
          debugPrint('diagnostic export prune: delete failed');
        }
      }
    } catch (_) {
      debugPrint('diagnostic export prune: listing failed');
    }
  }
}
