// lib/core/api/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class MonitoringApi {
  static const String _base = 'https://api.alochi.org/api/v1/monitoring';
  static const Duration _timeout = Duration(seconds: 10);
  String? _token;

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final resp = await http.post(
      Uri.parse('$_base$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(_timeout);
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      final msg = data['detail'] ?? data['message'] ?? data.toString();
      throw ApiException(resp.statusCode, msg.toString());
    }
    return data;
  }

  Future<dynamic> _get(String path) async {
    final resp = await http.get(
      Uri.parse('$_base$path'),
      headers: _headers,
    ).timeout(_timeout);
    if (resp.statusCode >= 400) throw ApiException(resp.statusCode, resp.body);
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<StudentSession> login(String username, String password) async {
    final data = await _post('/auth/login/', {'username': username, 'password': password});
    return StudentSession.fromJson(data);
  }

  Future<bool> ping() async {
    try {
      final data = await _get('/ping/') as Map<String, dynamic>;
      return data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<List<TestPackage>> getPackages(int grade) async {
    final data = await _get('/packages/?grade=$grade') as List;
    return data.map((j) => TestPackage.fromJson(j)).toList();
  }

  Future<List<Question>> getQuestions(String packageId, int variant) async {
    final data = await _get('/packages/$packageId/questions/?variant=$variant') as Map<String, dynamic>;
    return (data['questions'] as List).map((j) => Question.fromJson(j)).toList();
  }

  Future<bool> submitResult(TestResult result) async {
    try {
      await _post('/results/', result.toJson());
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 409) return true; // Already submitted
      return false;
    } catch (_) {
      return false;
    }
  }
}

final api = MonitoringApi();
