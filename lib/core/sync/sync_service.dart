// lib/core/sync/sync_service.dart
// Oflayn navbatlarni internet paydo bo'lganda avtomatik yuboruvchi xizmat.
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../db/offline_queue.dart';
import '../db/diagnostic_answer_store.dart';
import '../../features/diagnostic/data/diagnostic_kiosk_api.dart';

/// Outcome of a single flush attempt — lets a manual "Yuborish" button (e.g.
/// [DiagnosticHistoryScreen]) tell the user what actually happened instead
/// of always going quiet, since [SyncService._flushAll] itself never throws.
enum SyncFlushOutcome { success, nothingPending, noNetwork, busy, error }

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _timer;

  /// Exposed so UI (e.g. [SyncStatusBadge]) can show a live "syncing" state.
  /// App-lifetime singleton — intentionally never disposed by [dispose].
  final ValueNotifier<bool> flushing = ValueNotifier<bool>(false);
  bool _started = false;
  int _consecutiveFailures = 0;
  static const Duration _interval = Duration(seconds: 60);

  void start() {
    if (_started) return;
    _started = true;
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (_hasNetwork(results)) _flushAll();
    });
    _timer = Timer.periodic(_interval, (_) => _flushAll());
    _flushAll();
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> flushNow() => _flushAll();

  /// Same flush, but reports what happened — for UI that needs to tell the
  /// user whether their tap actually reached the server (see
  /// diagnostic_history_screen.dart).
  Future<SyncFlushOutcome> flushNowWithResult() => _flushAll();

  Future<SyncFlushOutcome> _flushAll() async {
    if (flushing.value) return SyncFlushOutcome.busy;
    flushing.value = true;
    try {
      // Navbat bo'sh bo'lsa tarmoqqa umuman tegmaymiz (behuda 60s flush yo'q).
      final pending = await OfflineQueue.totalPendingCount();
      final pendingDiagAttempts =
          await DiagnosticAnswerStore.attemptsWithPending();
      if (pending == 0 && pendingDiagAttempts.isEmpty) {
        return SyncFlushOutcome.nothingPending;
      }
      // Haqiqiy internetni 1 ta arzon GET bilan tekshiramiz. Interfeys "ulangan"
      // bo'lsa-da internet yo'q bo'lsa, bu N ta 20s timeout urinishidan saqlaydi.
      if (!await api.ping()) return SyncFlushOutcome.noNetwork;
      if (pending > 0) await api.flushOfflineQueue();
      for (final attemptId in pendingDiagAttempts) {
        await _flushDiagnosticAnswers(attemptId);
      }
      _consecutiveFailures = 0;
      return SyncFlushOutcome.success;
    } catch (e) {
      _consecutiveFailures++;
      debugPrint('SyncService._flushAll error: $e');
      if (_consecutiveFailures >= 5) {
        debugPrint(
            '⚠️ SyncService: $_consecutiveFailures consecutive flush failures — results may not be reaching the server');
      }
      return SyncFlushOutcome.error;
    } finally {
      flushing.value = false;
    }
  }

  /// Bitta attempt'ning hali sinxronlanmagan fixed-variant javoblarini
  /// best-effort sinxronlash — o'z xatolarini yutadi, shunda bitta yomon
  /// attempt hech qachon shu flush tsiklining qolgan qismini yoki undan
  /// yuqoridagi OfflineQueue flush'ini bloklamaydi; sinxronlanmagan qator
  /// shunchaki keyingi 60s tick'da qayta urinadi.
  Future<void> _flushDiagnosticAnswers(String attemptId) async {
    final rows = await DiagnosticAnswerStore.pendingForAttempt(attemptId);
    if (rows.isEmpty) return;
    try {
      await diagnosticKioskApi.syncAnswers(
        attemptId: attemptId,
        answers: rows
            .map((r) => {
                  'question_index': r['question_index'],
                  'question_id': r['question_id'],
                  'selected_option': r['selected_option'],
                  'answered_at': r['answered_at'],
                })
            .toList(),
      );
      await DiagnosticAnswerStore.markSynced(
        attemptId,
        rows.map((r) => r['question_id'] as String).toList(),
      );
    } catch (e) {
      debugPrint('SyncService._flushDiagnosticAnswers($attemptId) error: $e');
    }
  }

  void dispose() {
    _connSub?.cancel();
    _connSub = null;
    _timer?.cancel();
    _timer = null;
    _started = false;
  }
}
