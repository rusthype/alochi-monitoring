// lib/core/sync/sync_service.dart
// Oflayn navbatlarni internet paydo bo'lganda avtomatik yuboruvchi xizmat.
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../db/offline_queue.dart';
import '../db/diagnostic_answer_store.dart';
import '../network/connectivity_service.dart';
import '../../features/diagnostic/data/diagnostic_kiosk_api.dart';

/// Outcome of a single flush attempt — lets a manual "Yuborish" button (e.g.
/// [DiagnosticHistoryScreen]) tell the user what actually happened instead
/// of always going quiet, since [SyncService._flushAll] itself never throws.
enum SyncFlushOutcome { success, nothingPending, noNetwork, busy, error }

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<SignalReading>? _probeSub;
  Timer? _probeDebounce;
  bool? _probeOnline;

  /// Debounce for the probe-driven flush (a flapping link must not cause a
  /// flush storm; `flushing` additionally rejects overlapping flushes).
  @visibleForTesting
  Duration probeDebounce = const Duration(seconds: 2);

  /// Test seam: replaces the real flush on a probe-driven online edge.
  @visibleForTesting
  Future<void> Function()? probeFlushOverride;
  Timer? _timer;

  /// Exposed so UI (e.g. [SyncStatusBadge]) can show a live "syncing" state.
  /// App-lifetime singleton — intentionally never disposed by [dispose].
  final ValueNotifier<bool> flushing = ValueNotifier<bool>(false);
  bool _started = false;
  int _consecutiveFailures = 0;
  // Exponential backoff (self-rescheduling Timer, not Timer.periodic): 10s
  // base, doubling per consecutive failure, capped at 320s (5 min). Resets
  // to _baseInterval as soon as a flush succeeds (_consecutiveFailures back
  // to 0) — see _currentInterval.
  static const Duration _baseInterval = Duration(seconds: 10);
  static const Duration _maxInterval = Duration(seconds: 320);

  void start() {
    if (_started) return;
    _started = true;
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (_hasNetwork(results)) {
        // Cancel whatever backoff tick is pending so connectivity coming
        // back doesn't fire an overlapping second flush once that old timer
        // elapses too — _flushAll's own `flushing` guard would no-op it
        // anyway, but this avoids the redundant attempt entirely.
        _timer?.cancel();
        _flushAll().then((_) => _scheduleNext());
      }
    });
    // The latency probe knows about REAL internet (the interface-level stream
    // above does not): flush immediately on its offline -> online edge.
    _probeSub =
        ConnectivityService.instance.readings.listen(handleProbeReading);
    _flushAll().then((_) => _scheduleNext());
  }

  /// Offline -> online edge detector for [ConnectivityService] readings.
  /// The first reading and `checking` placeholders never trigger a flush.
  @visibleForTesting
  void handleProbeReading(SignalReading r) {
    if (r.checking) return;
    final online = r.tier != SignalTier.none;
    final wasOffline = _probeOnline == false;
    _probeOnline = online;
    if (!online || !wasOffline) return;
    _probeDebounce?.cancel();
    _probeDebounce = Timer(probeDebounce, () {
      _timer?.cancel();
      (probeFlushOverride ?? _flushAll)().then((_) => _scheduleNext());
    });
  }

  void _scheduleNext() {
    if (!_started) return;
    _timer?.cancel();
    _timer = Timer(_currentInterval(), () {
      _flushAll().then((_) => _scheduleNext());
    });
  }

  Duration _currentInterval() {
    if (_consecutiveFailures <= 0) return _baseInterval;
    final shift = _consecutiveFailures.clamp(0, 5);
    final ms = _baseInterval.inMilliseconds * (1 << shift);
    return Duration(
        milliseconds: ms > _maxInterval.inMilliseconds
            ? _maxInterval.inMilliseconds
            : ms);
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
  /// shunchaki keyingi tick'da qayta urinadi.
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
    } on ApiException catch (e) {
      // 409 "Attempt allaqachon yakunlangan": attempt allaqachon
      // kiosk/finish/ bilan yopilgan — javoblar finish payload orqali
      // yetib borgan, qayta yuborish hech qachon o'tmaydi (prod: bitta
      // attempt ~52 marta 409 bilan urildi). Aniq rad etish — qatorlarni
      // sinxronlangan deb belgilab, abadiy qayta urinishni to'xtatamiz.
      if (e.statusCode == 409) {
        await DiagnosticAnswerStore.markSynced(
          attemptId,
          rows.map((r) => r['question_id'] as String).toList(),
        );
        return;
      }
      debugPrint('SyncService._flushDiagnosticAnswers($attemptId) error: $e');
    } catch (e) {
      debugPrint('SyncService._flushDiagnosticAnswers($attemptId) error: $e');
    }
  }

  void dispose() {
    _connSub?.cancel();
    _connSub = null;
    _probeSub?.cancel();
    _probeSub = null;
    _probeDebounce?.cancel();
    _probeDebounce = null;
    _probeOnline = null;
    _timer?.cancel();
    _timer = null;
    _started = false;
  }
}
