// lib/core/db/credential_cache.dart
// Login/parolni lokal saqlash — offline login uchun

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class CredentialCache {
  static const _keyCredentials = 'cached_credentials';
  static const _keySession     = 'cached_session';

  /// Login va parolni saqlaydi (lokal, offline login uchun)
  static Future<void> saveCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCredentials, jsonEncode({
      'username': username,
      'password': password,
      'saved_at': DateTime.now().toIso8601String(),
    }));
  }

  /// Oxirgi muvaffaqiyatli sessiyani saqlaydi
  static Future<void> saveSession(StudentSession session, String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySession, jsonEncode({
      'token':        session.token,
      'student_id':   session.studentId,
      'student_name': session.studentName,
      'variant':      session.variant,
      'grade':        session.grade,
      'group_name':   session.groupName,
      'username':     username,
      'password':     password,
      'saved_at':     DateTime.now().toIso8601String(),
    }));
  }

  /// Saqlangan login/parolni qaytaradi
  static Future<Map<String, String>?> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCredentials);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return {
      'username': data['username'] as String,
      'password': data['password'] as String,
    };
  }

  /// Offline rejimda oxirgi sessiyani qaytaradi
  static Future<StudentSession?> loadOfflineSession(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySession);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;

    // Login/parol bir xil bo'lsa offline sessiya beradi
    if (data['username'] != username || data['password'] != password) return null;

    return StudentSession(
      token:       data['token'] as String,
      studentId:   data['student_id'] as String,
      studentName: data['student_name'] as String,
      variant:     data['variant'] as int,
      grade:       data['grade'] as int,
      groupName:   data['group_name'] as String?,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCredentials);
    await prefs.remove(_keySession);
  }
}
