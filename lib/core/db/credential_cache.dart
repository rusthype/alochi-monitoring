// lib/core/db/credential_cache.dart
// Login/parolni xavfsiz saqlash — offline login uchun
// Windows DPAPI orqali shifrlangan (flutter_secure_storage)

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';

class CredentialCache {
  static const _storage = FlutterSecureStorage(
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );

  static const _keyUsername = 'cc_username';
  static const _keyPassword = 'cc_password';
  static const _keyToken = 'cc_token';
  static const _keyStudentId = 'cc_student_id';
  static const _keyStudentName = 'cc_student_name';
  static const _keyVariant = 'cc_variant';
  static const _keyGrade = 'cc_grade';
  static const _keyGroupName = 'cc_group_name';

  static Future<void> saveCredentials(String username, String password) async {
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
  }

  static Future<void> saveSession(
      StudentSession session, String username, String password) async {
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyToken, value: session.token);
    await _storage.write(key: _keyStudentId, value: session.studentId);
    await _storage.write(key: _keyStudentName, value: session.studentName);
    await _storage.write(key: _keyVariant, value: session.variant?.toString());
    await _storage.write(key: _keyGrade, value: session.grade?.toString());
    await _storage.write(key: _keyGroupName, value: session.groupName ?? '');
  }

  static Future<Map<String, String>?> loadCredentials() async {
    final username = await _storage.read(key: _keyUsername);
    final password = await _storage.read(key: _keyPassword);
    if (username == null || password == null) return null;
    return {'username': username, 'password': password};
  }

  static Future<StudentSession?> loadOfflineSession(
      String username, String password) async {
    final savedUsername = await _storage.read(key: _keyUsername);
    final savedPassword = await _storage.read(key: _keyPassword);
    // Login/parol bir xil bo'lsa offline sessiya beradi
    if (savedUsername != username || savedPassword != password) return null;

    final token = await _storage.read(key: _keyToken);
    final studentId = await _storage.read(key: _keyStudentId);
    final studentName = await _storage.read(key: _keyStudentName);
    final variant = await _storage.read(key: _keyVariant);
    final grade = await _storage.read(key: _keyGrade);
    final groupName = await _storage.read(key: _keyGroupName);

    if (token == null || studentId == null || studentName == null) return null;

    return StudentSession(
      token: token,
      studentId: studentId,
      studentName: studentName,
      variant: int.tryParse(variant ?? ''),
      grade: int.tryParse(grade ?? ''),
      groupName: (groupName?.isEmpty ?? true) ? null : groupName,
    );
  }

  static Future<void> clear() async {
    await _storage.deleteAll();
  }
}
