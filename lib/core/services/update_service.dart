// lib/core/services/update_service.dart
// Checks GitHub Releases for a newer app version at startup and exposes it
// as UpdateInfo — the login screen renders a persistent top-right badge
// when an update is available. Tapping it downloads and silently installs
// the update (Windows: elevated via PowerShell Start-Process -Verb RunAs,
// since installer.iss requires admin; macOS: DMG swap), falling back to
// openReleasePage() on any failure.
// See docs/superpowers/specs/2026-07-11-monitoring-flutter-update-mechanism-design.md
// and docs/superpowers/specs/2026-07-16-monitoring-flutter-update-badge-design.md
// (in the alochi monorepo) for the original link-out-only design — superseded
// by the auto-install behavior below (commit 3f37a0b), which predates a spec.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

/// Encodes [s] as UTF-16LE bytes, the format PowerShell's -EncodedCommand
/// expects to be base64'd. Used to pass the installer launch script without
/// any string-interpolation quoting/escaping pitfalls around the file path.
Uint8List _utf16LEBytes(String s) {
  final bytes = Uint8List(s.length * 2);
  for (var i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    bytes[i * 2] = code & 0xFF;
    bytes[i * 2 + 1] = (code >> 8) & 0xFF;
  }
  return bytes;
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
      final expectedExeName = 'AlochiMonitoring-$latestVersion-Setup.exe';
      
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'].toString();
        if (Platform.isMacOS) {
          if (name.endsWith('.dmg')) {
            downloadUrl = asset['browser_download_url'] as String?;
            break;
          }
        } else {
          if (name == expectedExeName) {
            downloadUrl = asset['browser_download_url'] as String?;
            break;
          }
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
      if (Platform.isMacOS) {
        await _updateMacOS(info, onProgress);
        return;
      }
      
      if (!Platform.isWindows) {
        // Auto-install is currently only supported on Windows and macOS
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

      // Launch installer with UAC elevation.
      // InnoSetup's installer.iss has PrivilegesRequired=admin, so the
      // compiled Setup.exe requires elevation to run. Process.start() uses
      // CreateProcess under the hood, which does not reliably surface the
      // UAC consent prompt (it either fails with ERROR_ELEVATION_REQUIRED,
      // or silently succeeds only if UAC happens to be disabled). Instead,
      // shell out to PowerShell's Start-Process -Verb RunAs, which is the
      // standard way to get Windows to show the UAC prompt from a
      // non-elevated parent and to wait for the elevated child to finish.
      //
      // InnoSetup supports /SILENT (shows progress) or /VERYSILENT (no UI)
      // /CLOSEAPPLICATIONS will close the current running app so it can overwrite
      final exePath = Platform.resolvedExecutable;
      final psScript = '''
try {
  \$p = Start-Process -FilePath "$savePath" -ArgumentList "/SILENT","/CLOSEAPPLICATIONS" -Verb RunAs -Wait -PassThru
  if (\$p.ExitCode -eq 0) {
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$exePath"
  }
  exit \$p.ExitCode
} catch {
  exit 1
}
''';
      final encoded = base64Encode(_utf16LEBytes(psScript));
      // Bounded wait: if the UAC prompt never gets a response (user AFK,
      // minimized, on another virtual desktop), Process.run's Future would
      // otherwise never resolve, leaving the login screen's update badge
      // stuck forever. 3 minutes covers realistic UAC reaction time + the
      // installer's file copy while still failing closed into the
      // openReleasePage() fallback if nothing happens.
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
      ).timeout(
        const Duration(minutes: 3),
        onTimeout: () => ProcessResult(
          -1,
          -1,
          '',
          'timed out waiting for elevated installer',
        ),
      );

      if (result.exitCode != 0) {
        throw Exception(
          'Windows installer failed or was cancelled (exit code ${result.exitCode})',
        );
      }

      exit(0);
    } catch (_) {
      await openReleasePage();
    }
  }

  Future<void> _updateMacOS(UpdateInfo info, Function(double)? onProgress) async {
    final tempDir = await getTemporaryDirectory();
    final dmgPath = '${tempDir.path}/AlochiMonitoring-Update.dmg';

    // Download DMG
    final request = http.Request('GET', Uri.parse(info.downloadUrl));
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      await openReleasePage();
      return;
    }

    final contentLength = response.contentLength;
    int downloaded = 0;
    final sink = File(dmgPath).openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloaded += chunk.length;
      if (contentLength != null && onProgress != null) {
        onProgress(downloaded / contentLength);
      }
    }
    await sink.close();

    // Create a shell script to mount, copy, unmount, and relaunch.
    // Every step that can fail is checked explicitly and logged: silently
    // continuing after a failed rm/cp would leave the OLD app in place (a
    // failed `rm -rf` leaves the old .app directory sitting there, which
    // makes the following `cp -R` copy INTO it as a nested subdirectory
    // instead of replacing it — no error, just a wrong result) and then
    // `open -a` would relaunch that stale app while looking like success.
    // On any failure we fall back to openReleasePage(), matching the
    // fallback philosophy used everywhere else in this file.
    final scriptPath = '${tempDir.path}/update.sh';
    final script = '''#!/bin/bash
LOG="\$HOME/Library/Logs/AlochiMonitoringUpdate.log"
sleep 2
MOUNT_PATH=\$(hdiutil attach "$dmgPath" -nobrowse | grep -o '/Volumes/.*' | tail -1 | xargs)
if [ -z "\$MOUNT_PATH" ]; then
    echo "\$(date): hdiutil attach failed to produce a mount path" >> "\$LOG"
    open "$_releasePageUrl"
    exit 1
fi
if ! rm -rf "/Applications/alochi_monitoring.app"; then
    echo "\$(date): rm -rf of old app failed" >> "\$LOG"
    hdiutil detach "\$MOUNT_PATH" -force
    open "$_releasePageUrl"
    exit 1
fi
if ! cp -R "\$MOUNT_PATH/alochi_monitoring.app" "/Applications/"; then
    echo "\$(date): cp -R of new app failed" >> "\$LOG"
    hdiutil detach "\$MOUNT_PATH" -force
    open "$_releasePageUrl"
    exit 1
fi
hdiutil detach "\$MOUNT_PATH" -force
open -a "/Applications/alochi_monitoring.app"
''';
    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);

    await Process.start(scriptPath, [], mode: ProcessStartMode.detached);
    exit(0);
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
