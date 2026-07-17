// lib/core/services/update_service.dart
// Checks GitHub Releases for a newer app version at startup and exposes it
// as UpdateInfo — the login screen renders a persistent top-right badge
// when an update is available. Link-out only, no auto-install.
// See docs/superpowers/specs/2026-07-11-monitoring-flutter-update-mechanism-design.md
// and docs/superpowers/specs/2026-07-16-monitoring-flutter-update-badge-design.md
// (in the alochi monorepo) for the full design rationale.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

final RegExp _setupExePattern =
    RegExp(r'^AlochiMonitoring-(\d+)\.(\d+)\.(\d+)-Setup\.exe$');

/// True if [remote] is strictly newer than [local] (both "X.Y.Z" strings).
/// Numeric comparison, not string comparison — "1.0.9" vs "1.0.10" must
/// compare correctly. Returns false (not an error) for malformed input,
/// since this only gates whether to show the update badge.
bool isNewerVersion(String remote, String local) {
  final r = _parseVersionParts(remote);
  final l = _parseVersionParts(local);
  if (r == null || l == null) return false;
  for (var i = 0; i < 3; i++) {
    if (r[i] != l[i]) return r[i] > l[i];
  }
  return false;
}

/// Extracts the highest version among AlochiMonitoring-X.Y.Z-Setup.exe
/// assets in a GitHub release's `assets` list (raw JSON, already decoded).
/// The 'latest' release accumulates old Setup.exe assets over time (never
/// deleted), so this MUST scan all matches and pick the max — not the first.
/// Returns null if no matching asset is found.
String? maxSetupExeVersion(List<dynamic> assets) {
  List<int>? best;
  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = asset['name'];
    if (name is! String) continue;
    final match = _setupExePattern.firstMatch(name);
    if (match == null) continue;
    final parts = [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
    if (best == null || _compareParts(parts, best) > 0) {
      best = parts;
    }
  }
  if (best == null) return null;
  return '${best[0]}.${best[1]}.${best[2]}';
}

List<int>? _parseVersionParts(String version) {
  final segments = version.split('.');
  if (segments.length < 3) return null;
  final parts = <int>[];
  for (var i = 0; i < 3; i++) {
    final n = int.tryParse(segments[i]);
    if (n == null) return null;
    parts.add(n);
  }
  return parts;
}

int _compareParts(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}

/// Result of a successful update check: a newer version exists.
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
  });
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _releaseApiUrl =
      'https://api.github.com/repos/rusthype/alochi-monitoring/releases/tags/latest';
  static const String _releasePageUrl =
      'https://github.com/rusthype/alochi-monitoring/releases/tag/latest';

  /// Checks for a newer release once. Any failure (offline, GitHub API rate
  /// limit, malformed JSON) is swallowed silently, matching
  /// HeartbeatService's error-handling pattern
  /// (lib/core/services/heartbeat_service.dart:62-71) — never throws, never
  /// blocks app startup. Returns null when no update is available or the
  /// check failed; callers must treat both cases identically (no badge).
  Future<UpdateInfo?> fetchUpdateInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final resp = await http
          .get(Uri.parse(_releaseApiUrl))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;
      final assets = decoded['assets'];
      if (assets is! List) return null;

      final latestVersion = maxSetupExeVersion(assets);
      if (latestVersion == null) return null;
      if (!isNewerVersion(latestVersion, currentVersion)) return null;

      String? downloadUrl;
      final expectedName = 'AlochiMonitoring-$latestVersion-Setup.exe';
      for (final asset in assets) {
        if (asset is Map && asset['name'] == expectedName) {
          downloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      if (downloadUrl == null) return null;

      return UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        downloadUrl: downloadUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads the update installer and executes it silently, then exits the app.
  /// Falls back to opening the release page on any failure.
  Future<void> downloadAndInstallUpdate(UpdateInfo info, {Function(double)? onProgress}) async {
    try {
      if (!Platform.isWindows) {
        // Auto-install is currently only supported on Windows
        await openReleasePage();
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}\\AlochiMonitoring-Setup-${info.latestVersion}.exe';
      final file = File(savePath);

      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final response = await http.Client().send(request);
      
      if (response.statusCode != 200) {
        await openReleasePage();
        return;
      }
      
      final contentLength = response.contentLength;
      int downloaded = 0;
      
      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength != null && onProgress != null) {
          onProgress(downloaded / contentLength);
        }
      }
      await sink.close();

      // Launch installer
      // InnoSetup supports /SILENT (shows progress) or /VERYSILENT (no UI)
      // /CLOSEAPPLICATIONS will close the current running app so it can overwrite
      await Process.start(savePath, ['/SILENT', '/CLOSEAPPLICATIONS']);
      
      exit(0);
    } catch (_) {
      await openReleasePage();
    }
  }

  /// Opens the GitHub release page in the system browser so the user can
  /// download the new installer/DMG themselves.
  Future<void> openReleasePage() async {
    try {
      await launchUrl(
        Uri.parse(_releasePageUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Swallowed
    }
  }
}
