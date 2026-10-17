// lib/core/offline/lan_diagnostic_api.dart
//
// The offline diagnostic adapter (OfflineDiagnosticKioskApi) with the hub as
// the content source. The adapter reads roster + questions synchronously, so
// the first call of every entry point makes sure the one-shot snapshot from
// `GET /diagnostics` is loaded. Answers still go through
// [LanClientSession.recordResult] (the hub outbox) — nothing is scored here.
import 'offline_diagnostic_api.dart';
import 'lan_client_session.dart';

class LanDiagnosticKioskApi extends OfflineDiagnosticKioskApi {
  LanDiagnosticKioskApi(LanClientSession super.session);

  LanClientSession get _lan => session as LanClientSession;

  @override
  Future<(List<Map<String, dynamic>>, bool)> listSchools() async {
    await _lan.loadDiagnosticSnapshot();
    return super.listSchools();
  }

  @override
  Future<(List<Map<String, dynamic>>, bool)> listClasses(
      String schoolId) async {
    await _lan.loadDiagnosticSnapshot();
    return super.listClasses(schoolId);
  }

  @override
  Future<(List<Map<String, dynamic>>, bool)> listStudents(
      String schoolId, String classLabel) async {
    await _lan.loadDiagnosticSnapshot();
    return super.listStudents(schoolId, classLabel);
  }

  @override
  Future<Map<String, dynamic>> availableSubjects(int grade,
      {String language = 'uz'}) async {
    await _lan.loadDiagnosticSnapshot();
    return super.availableSubjects(grade, language: language);
  }

  @override
  Future<Map<String, dynamic>> startAttempt({
    required String attemptId,
    required String subject,
  }) async {
    await _lan.loadDiagnosticSnapshot();
    return super.startAttempt(attemptId: attemptId, subject: subject);
  }

  @override
  Future<Map<String, dynamic>> finishAttempt({
    required String attemptId,
    required List<Map<String, dynamic>> answers,
    List<String>? flaggedQuestionIds,
    int? generation,
  }) async {
    await _lan.loadDiagnosticSnapshot();
    return super.finishAttempt(
        attemptId: attemptId,
        answers: answers,
        flaggedQuestionIds: flaggedQuestionIds,
        generation: generation);
  }
}
