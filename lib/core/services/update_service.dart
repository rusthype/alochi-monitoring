// lib/core/services/update_service.dart
//
// GitHub Releases API orqali yangi versiyani tekshiradi.
// App ichida banner ko'rsatiladi, update majburiy emas.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _kGithubRepo     = 'rusthype/alochi-monitoring';
const _kLastDismissKey = 'update_dismissed_version';

class ReleaseInfo {
  final String version;    // '1.0.6'
  final String tagName;    // 'v1.0.6'
  final String downloadUrl;
  final String releaseUrl;
  final String publishedAt;
  final String body;

  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.downloadUrl,
    required this.releaseUrl,
    required this.publishedAt,
    required this.body,
  });
}

class UpdateService {
  // Singleton
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  ReleaseInfo? _latest;
  bool _checked = false;

  /// Yangi versiya borligini tekshiradi.
  /// [force] = true bo'lsa dismiss ni ham e'tiborsiz qoldiradi.
  Future<ReleaseInfo?> checkForUpdate({bool force = false}) async {
    if (_checked && !force && _latest == null) return null;
    try {
      final resp = await http.get(
        Uri.parse(
            'https://api.github.com/repos/$_kGithubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latest  = tagName.replaceAll('v', '');

      final info    = await PackageInfo.fromPlatform();
      final current = info.version; // '1.0.6'

      _checked = true;

      if (!_isNewer(latest, current)) return null;

      // Dismiss tekshirish
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_kLastDismissKey) == latest) return null;
      }

      // Installer URL
      final assets = data['assets'] as List? ?? [];
      String downloadUrl = '';
      for (final a in assets) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('-setup.exe') || name.endsWith('.exe')) {
          downloadUrl = a['browser_download_url'] as String? ?? '';
          break;
        }
      }

      _latest = ReleaseInfo(
        version:     latest,
        tagName:     tagName,
        downloadUrl: downloadUrl,
        releaseUrl:  data['html_url'] as String? ?? '',
        publishedAt: (data['published_at'] as String? ?? '').substring(0, 10),
        body:        data['body'] as String? ?? '',
      );
      return _latest;
    } catch (e) {
      debugPrint('[UpdateService] $e');
      return null;
    }
  }

  /// Ushbu versiyani "keyinroq" deb belgilash
  Future<void> dismiss(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastDismissKey, version);
    _latest = null;
  }

  /// GitHub Releases sahifasini ochish
  Future<void> openReleasePage(String url) async {
    final uri = Uri.parse(url.isNotEmpty
        ? url
        : 'https://github.com/$_kGithubRepo/releases/latest');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// Yangi versiyani yuklab o'rnatish (exe)
  Future<void> downloadAndInstall(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // v1.0.7 > v1.0.6 ?
  bool _isNewer(String latest, String current) {
    final l = _parts(latest);
    final c = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (i >= l.length || i >= c.length) break;
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  List<int> _parts(String v) =>
      v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
}
