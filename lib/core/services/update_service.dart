// lib/core/services/update_service.dart
// Checks a static release-asset manifest (latest-windows.json /
// latest-macos.json) for a newer app version at startup and exposes it as
// UpdateInfo — the login screen renders a persistent top-right badge when
// an update is available. Tapping it downloads and silently installs the
// update (Windows: elevated via PowerShell Start-Process -Verb RunAs,
// since installer.iss requires admin; macOS: DMG swap), falling back to
// openReleasePage() on any failure.
//
// The manifest is uploaded as a GitHub Release *asset* on the 'latest' tag
// by .github/workflows/build-windows.yml / build-macos.yml on every push to
// main, and is fetched via the static release-asset download URL
// (github.com/OWNER/REPO/releases/download/latest/FILENAME), which is
// served through GitHub's CDN redirect — NOT the api.github.com REST API.
// This means it is never subject to GitHub's unauthenticated 60
// requests/hour PER-IP rate limit, which previously caused update checks to
// silently fail for schools sharing one public IP (the old approach polled
// api.github.com/repos/.../releases/tags/latest directly). Because the rate
// limit no longer applies, no client-side throttle/cache is needed either.
// See docs/superpowers/specs/2026-07-11-monitoring-flutter-update-mechanism-design.md
// and docs/superpowers/specs/2026-07-16-monitoring-flutter-update-badge-design.md
// (in the alochi monorepo) for the original link-out-only design — superseded
// by the auto-install behavior below (commit 3f37a0b), which predates a spec.
//
// Production bug (fixed here): computer labs with slow/unreliable internet
// would silently never learn an update existed — a single manifest-fetch
// timeout with no retry, and an unbounded/unretried download stream, meant
// some machines in the same lab stayed on old app versions indefinitely
// while others on better wifi succeeded. Fix: generous timeouts + retry
// with backoff on both the manifest fetch and the download stream (which
// also now detects mid-transfer stalls, not just a slow initial connect),
// a periodic re-check while idle at the login screen so a failed startup
// check gets more chances without a full relaunch, and a visible in-app
// failure signal (SnackBar with a retry action) instead of only a
// silently-opened browser tab.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

/// Timeout for the manifest HTTP GET itself. 20s (not the previous 5s)
/// gives slow lab wifi a real chance to complete a tiny JSON fetch.
const Duration _manifestTimeout = Duration(seconds: 20);

/// Timeout applied between individual byte-stream events while downloading
/// the installer/DMG — this is what catches a stalled/dropped connection
/// mid-transfer, which a connect-only timeout would never see.
const Duration _downloadChunkTimeout = Duration(seconds: 30);

/// Total attempts (initial + retries) for both the manifest fetch and the
/// download transfer.
const int _maxAttempts = 3;

/// Runs [action] up to [attempts] times with linear backoff (3s, 6s, ...)
/// between attempts, returning the first successful result. Rethrows the
/// last error if every attempt fails. A single slow/dropped response on
/// unreliable lab wifi must not be treated as "no update available" or
/// "download impossible" on the first try — it usually just needs another
/// attempt a few seconds later.
Future<T> _withRetry<T>(
  Future<T> Function() action, {
  int attempts = _maxAttempts,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await action();
    } catch (e) {
      lastError = e;
      if (attempt < attempts) {
        await Future.delayed(Duration(seconds: 3 * attempt));
      }
    }
  }
  throw lastError!;
}

/// Downloads [url] to [savePath], retrying the whole transfer from scratch
/// up to [_maxAttempts] times if the connection stalls or drops mid-stream.
/// There is no partial-download resume — a fresh retry of a few-MB
/// installer is cheap enough that resume isn't worth the added complexity.
/// Any partial file from a failed attempt is deleted before the next try so
/// a later successful attempt can't append to/mix with stale bytes.
Future<void> _downloadWithRetry(
  String url,
  String savePath, {
  Function(double)? onProgress,
}) async {
  try {
    await _withRetry(() => _downloadOnce(url, savePath, onProgress));
  } catch (e) {
    // Last-resort fallback: only on macOS, only after all http-based
    // retries are exhausted. curl uses the system's own TLS/network stack
    // (CFNetwork), which is a genuinely different code path from
    // package:http's dart:io HttpClient — if the http path fails for a
    // reason specific to that stack, curl may still succeed. Progress is
    // NOT parsed from curl's output (fragile stderr scraping for no clear
    // benefit here) — the bar just resets to 0% for this final attempt.
    if (!Platform.isMacOS) rethrow;
    final hasCurl = await Process.run('which', ['curl'])
        .then((r) => r.exitCode == 0)
        .catchError((_) => false);
    if (!hasCurl) rethrow;
    onProgress?.call(0.0);
    final result = await Process.run('curl', [
      '-L',
      '-f',
      '--connect-timeout',
      '25',
      '-o',
      savePath,
      url,
    ]);
    if (result.exitCode != 0) {
      throw HttpException(
        'HTTP download failed ($e); curl fallback also failed '
        '(exit ${result.exitCode}): ${result.stderr}',
      );
    }
    onProgress?.call(1.0);
  }
}

Future<void> _downloadOnce(
  String url,
  String savePath,
  Function(double)? onProgress,
) async {
  final file = File(savePath);
  if (await file.exists()) {
    try {
      await file.delete();
    } catch (_) {}
  }

  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url))
      ..followRedirects = true
      ..maxRedirects = 10;
    final response =
        await client.send(request).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException(
        'Update download failed with status ${response.statusCode}',
      );
    }

    final contentLength = response.contentLength;
    var downloaded = 0;
    // Throttled: raw network chunks can arrive far more than once per
    // frame, and each onProgress call triggers a setState in the caller —
    // forwarding every chunk was flooding the UI thread with rebuilds
    // (the actual cause of the reported interface lag, not download
    // speed). Emit at most 10x/sec, plus always the final 100%.
    var lastEmit = 0.0;
    var lastEmitTime = DateTime.fromMillisecondsSinceEpoch(0);
    final sink = file.openWrite();
    try {
      await for (final chunk
          in response.stream.timeout(_downloadChunkTimeout)) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength != null && onProgress != null) {
          final progress = downloaded / contentLength;
          final now = DateTime.now();
          if (progress - lastEmit >= 0.01 ||
              now.difference(lastEmitTime).inMilliseconds >= 100 ||
              progress >= 1.0) {
            lastEmit = progress;
            lastEmitTime = now;
            onProgress(progress);
          }
        }
      }
    } finally {
      await sink.close();
    }
  } finally {
    client.close();
  }
}

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

/// Result of an install attempt. On the success path the app has already
/// called `exit(0)` and relaunched itself (Windows) or handed off to a
/// detached script (macOS) — so `UpdateResult.success()` is only ever
/// theoretically reachable, same as the `Future<bool> => true` path it
/// replaces. [error] carries the actual exception text so the UI can show
/// something more useful than a generic failure message.
class UpdateResult {
  final bool success;
  final String? error;
  const UpdateResult.success()
      : success = true,
        error = null;
  const UpdateResult.failed(this.error) : success = false;
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _manifestUrlWindows =
      'https://github.com/rusthype/alochi-monitoring/releases/download/latest/latest-windows.json';
  static const String _manifestUrlMacOS =
      'https://github.com/rusthype/alochi-monitoring/releases/download/latest/latest-macos.json';
  static const String _releasePageUrl =
      'https://github.com/rusthype/alochi-monitoring/releases/tag/latest';

  Timer? _recheckTimer;

  /// Checks the static release-asset manifest, retrying up to [_maxAttempts]
  /// times (20s timeout per attempt, linear backoff) before giving up — see
  /// [_withRetry]. Any failure that survives all attempts (offline, non-200,
  /// malformed JSON) is swallowed silently, matching HeartbeatService's
  /// error-handling pattern (lib/core/services/heartbeat_service.dart:62-71)
  /// — never throws, never blocks app startup. Returns null when no update
  /// is available or the check ultimately failed; callers must treat both
  /// cases identically (no badge). Combine with [startPeriodicRecheck] for
  /// callers that stay on-screen long enough to benefit from a later retry
  /// beyond this method's own attempts.
  Future<UpdateInfo?> fetchUpdateInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final manifestUrl =
          Platform.isMacOS ? _manifestUrlMacOS : _manifestUrlWindows;
      final resp = await _withRetry(
        () => http.get(Uri.parse(manifestUrl)).timeout(_manifestTimeout),
      );
      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;

      final latestVersion = decoded['version'];
      final downloadUrl = decoded['url'];
      if (latestVersion is! String || downloadUrl is! String) return null;

      if (!isNewerVersion(latestVersion, currentVersion)) return null;

      return UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        downloadUrl: downloadUrl,
      );
    } catch (e) {
      debugPrint(
          'UpdateService.fetchUpdateInfo: check failed after retries: $e');
      return null;
    }
  }

  /// Starts re-checking the manifest every [interval] while the caller
  /// stays idle on-screen (e.g. sitting at the login/catalog screen between
  /// test sessions). A machine whose very first check failed — even after
  /// [fetchUpdateInfo]'s own internal retries — gets another chance without
  /// needing a full app relaunch, which in practice is often the only thing
  /// that would otherwise trigger a re-check. [onUpdateFound] is only
  /// invoked when a newer version is actually found. Safe to call more than
  /// once; each call replaces any previously running timer. Callers must
  /// pair this with [stopPeriodicRecheck] (e.g. in `State.dispose()`).
  void startPeriodicRecheck(
    void Function(UpdateInfo info) onUpdateFound, {
    Duration interval = const Duration(minutes: 30),
  }) {
    _recheckTimer?.cancel();
    _recheckTimer = Timer.periodic(interval, (_) async {
      final info = await fetchUpdateInfo();
      if (info != null) onUpdateFound(info);
    });
  }

  /// Stops any timer started by [startPeriodicRecheck]. No-op if none is
  /// running.
  void stopPeriodicRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = null;
  }

  /// Downloads the update installer and executes it silently, then exits
  /// the app. Returns `true` only in the (practically unreachable, since a
  /// successful install calls [exit]) success path; returns `false` when
  /// auto-install failed after retries and the release page was opened as
  /// a fallback — callers should surface a visible in-app failure signal
  /// (e.g. a SnackBar with a retry action) in that case rather than relying
  /// solely on the silently-opened browser tab.
  Future<UpdateResult> downloadAndInstallUpdate(UpdateInfo info,
      {Function(double)? onProgress}) async {
    try {
      if (Platform.isMacOS) {
        return await _updateMacOS(info, onProgress);
      }

      if (!Platform.isWindows) {
        // Auto-install is currently only supported on Windows and macOS —
        // no automatic browser open here anymore; the caller (UI) decides
        // whether/when to offer an explicit "open in browser" action.
        return const UpdateResult.failed(
          'Auto-install is not supported on this platform',
        );
      }

      final tempDir = await getTemporaryDirectory();
      final savePath =
          '${tempDir.path}\\AlochiMonitoring-Setup-${info.latestVersion}.exe';

      // Retries the whole transfer (up to _maxAttempts times) on a stalled
      // or dropped connection — see _downloadWithRetry. Throws on final
      // failure, caught by the outer catch below which falls back to
      // openReleasePage() and reports failure to the caller.
      await _downloadWithRetry(info.downloadUrl, savePath,
          onProgress: onProgress);

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
    } catch (e) {
      debugPrint('UpdateService.downloadAndInstallUpdate (Windows) error: $e');
      await _logUpdateFailure('windows-download-or-install', e);
      return UpdateResult.failed(e.toString());
    }
  }

  /// macOS install path: download the DMG, mount/copy/unmount via a shell
  /// script, relaunch. Wrapped in its own try/catch (previously missing —
  /// a bare exception here would have propagated up and only been caught by
  /// [downloadAndInstallUpdate]'s outer handler with no macOS-specific
  /// logging) so failures are logged with which step failed and reported
  /// back to the caller as `false` rather than only being visible via the
  /// browser-fallback tab.
  Future<UpdateResult> _updateMacOS(
      UpdateInfo info, Function(double)? onProgress) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dmgPath = '${tempDir.path}/AlochiMonitoring-Update.dmg';

      // Retries the whole transfer (up to _maxAttempts times) on a stalled
      // or dropped connection — see _downloadWithRetry.
      await _downloadWithRetry(info.downloadUrl, dmgPath,
          onProgress: onProgress);

      // Create a shell script to mount, copy, unmount, and relaunch.
      // Every step that can fail is checked explicitly and logged: silently
      // continuing after a failed rm/cp would leave the OLD app in place (a
      // failed `rm -rf` leaves the old .app directory sitting there, which
      // makes the following `cp -R` copy INTO it as a nested subdirectory
      // instead of replacing it — no error, just a wrong result) and then
      // `open -a` would relaunch that stale app while looking like success.
      // On any failure we fall back to openReleasePage(), matching the
      // fallback philosophy used everywhere else in this file. Note this
      // script runs detached AFTER this Dart process has already called
      // exit(0) below, so a failure at this stage (as opposed to the
      // network download above) can only surface via its own browser
      // fallback and log file, not via the in-app retry banner.
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
    } catch (e) {
      debugPrint('UpdateService._updateMacOS error: $e');
      await _logUpdateFailure('macos-download-or-install', e);
      return UpdateResult.failed(e.toString());
    }
  }

  /// Persists the actual exception behind a failed download/install so the
  /// next occurrence is diagnosable — [debugPrint] alone is invisible in a
  /// release build with no attached console, which previously left the
  /// generic "check your internet" SnackBar as the only trace of a failure.
  /// Shares the same log file the macOS post-install script already writes
  /// to ($HOME/Library/Logs/AlochiMonitoringUpdate.log via
  /// getApplicationSupportDirectory, cross-platform). Never throws — a
  /// logging failure must not mask the original error.
  Future<void> _logUpdateFailure(String stage, Object error) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logFile = File('${dir.path}/AlochiMonitoringUpdate.log');
      await logFile.writeAsString(
        '${DateTime.now().toIso8601String()} [$stage] $error\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never throw and mask the original failure.
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
