// test/update_service_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/services/update_service.dart';

void main() {
  group('isNewerVersion', () {
    test('numeric comparison, not string comparison', () {
      expect(isNewerVersion('1.0.45', '1.0.44'), true);
      // String comparison would wrongly say "1.0.9" > "1.0.10" is false-negative
      // in the other direction too — this must be numeric.
      expect(isNewerVersion('1.0.9', '1.0.10'), false);
      expect(isNewerVersion('1.0.10', '1.0.9'), true);
    });

    test('equal versions are not "newer"', () {
      expect(isNewerVersion('1.0.44', '1.0.44'), false);
    });

    test('malformed version strings return false, never throw', () {
      expect(isNewerVersion('not-a-version', '1.0.44'), false);
      expect(isNewerVersion('1.0.45', 'not-a-version'), false);
      expect(isNewerVersion('', ''), false);
    });
  });

  const goodUrl =
      'https://github.com/rusthype/alochi-monitoring/releases/download/latest/Setup.exe';

  group('isAllowedUpdateUrl (F23 host pin)', () {
    test('only https on github.com', () {
      expect(isAllowedUpdateUrl(goodUrl), isTrue);
      expect(isAllowedUpdateUrl('https://GitHub.com/x/y.exe'), isTrue);
    });
    test('other hosts, lookalikes, http and garbage are refused', () {
      expect(isAllowedUpdateUrl('http://github.com/x.exe'), isFalse);
      expect(isAllowedUpdateUrl('https://evil.example/x.exe'), isFalse);
      expect(isAllowedUpdateUrl('https://github.com.evil.example/x.exe'),
          isFalse);
      expect(isAllowedUpdateUrl('https://github.com@evil.example/x.exe'),
          isFalse);
      expect(isAllowedUpdateUrl('https://api.alochi.org/downloads/x.exe'),
          isFalse);
      expect(isAllowedUpdateUrl('ftp://github.com/x.exe'), isFalse);
      expect(isAllowedUpdateUrl('not a url'), isFalse);
      expect(isAllowedUpdateUrl(''), isFalse);
    });
  });

  group('parseUpdateManifest', () {
    test('old manifest without a hash still parses (sha256 null)', () {
      final info = parseUpdateManifest(
          {'version': '1.0.50', 'pub_date': 'x', 'url': goodUrl}, '1.0.49');
      expect(info, isNotNull);
      expect(info!.sha256, isNull);
      expect(info.downloadUrl, goodUrl);
    });
    test('carries sha256 or installer_sha256 through', () {
      expect(
          parseUpdateManifest(
                  {'version': '1.0.50', 'url': goodUrl, 'sha256': 'AB'},
                  '1.0.49')!
              .sha256,
          'AB');
      expect(
          parseUpdateManifest({
            'version': '1.0.50',
            'url': goodUrl,
            'installer_sha256': 'CD'
          }, '1.0.49')!
              .sha256,
          'CD');
    });
    test('disallowed host, not newer or malformed manifests give null', () {
      expect(
          parseUpdateManifest(
              {'version': '1.0.50', 'url': 'https://evil.example/x.exe'},
              '1.0.49'),
          isNull);
      expect(parseUpdateManifest({'version': '1.0.49', 'url': goodUrl}, '1.0.49'),
          isNull);
      expect(parseUpdateManifest({'version': 5, 'url': goodUrl}, '1.0.49'),
          isNull);
      expect(parseUpdateManifest([], '1.0.49'), isNull);
    });
  });

  group('downloadVerified (F23 hash + cleanup)', () {
    late Directory tmp;
    late String path;
    var downloads = 0;
    final bytes = utf8.encode('fake installer bytes');
    final goodHex = crypto.sha256.convert(bytes).toString();

    UpdateInfo info({String url = goodUrl, String? sha}) => UpdateInfo(
        latestVersion: '1.0.50',
        currentVersion: '1.0.49',
        downloadUrl: url,
        sha256: sha);

    Future<void> fakeDownload(String url, String savePath,
        {Function(double)? onProgress}) async {
      downloads++;
      await File(savePath).writeAsBytes(bytes);
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('upd_');
      path = '${tmp.path}/Setup.exe';
      downloads = 0;
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('matching hash (upper case) keeps the file', () async {
      await downloadVerified(info(sha: goodHex.toUpperCase()), path,
          download: fakeDownload);
      expect(File(path).existsSync(), isTrue);
    });

    test('sha256: prefix is accepted', () async {
      await downloadVerified(info(sha: 'sha256:$goodHex'), path,
          download: fakeDownload);
      expect(File(path).existsSync(), isTrue);
    });

    test('mismatch deletes the file and refuses', () async {
      await expectLater(
          downloadVerified(info(sha: 'a' * 64), path, download: fakeDownload),
          throwsA(isA<UpdateIntegrityException>()));
      expect(File(path).existsSync(), isFalse);
    });

    test('no hash in the manifest: behaves as before (file kept)', () async {
      await downloadVerified(info(), path, download: fakeDownload);
      expect(File(path).existsSync(), isTrue);
      await downloadVerified(info(sha: '  '), path, download: fakeDownload);
      expect(File(path).existsSync(), isTrue);
    });

    test('malformed hash fails closed before anything is downloaded', () async {
      await expectLater(
          downloadVerified(info(sha: 'zzz'), path, download: fakeDownload),
          throwsA(isA<UpdateIntegrityException>()));
      expect(downloads, 0);
      expect(File(path).existsSync(), isFalse);
    });

    test('disallowed host is refused without downloading', () async {
      await expectLater(
          downloadVerified(info(url: 'https://evil.example/Setup.exe'), path,
              download: fakeDownload),
          throwsA(isA<UpdateIntegrityException>()));
      expect(downloads, 0);
    });

    test('a failed transfer leaves no partial file', () async {
      await expectLater(
          downloadVerified(info(), path,
              download: (url, savePath, {onProgress}) async {
            await File(savePath).writeAsBytes([1, 2, 3]);
            throw const SocketException('dropped');
          }),
          throwsA(isA<SocketException>()));
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('runBounded (F23 timeout kills the child)', () {
    test('returns the exit code of a process that finishes', () async {
      final p = _FakeProcess()..finish(0);
      expect(await runBounded(() async => p, const Duration(seconds: 1)), 0);
      expect(p.killed, isFalse);
    });

    test('a process that never exits is killed and reported as -1', () async {
      final p = _FakeProcess();
      final code =
          await runBounded(() async => p, const Duration(milliseconds: 50));
      expect(code, -1);
      expect(p.killed, isTrue);
    });
  });
}

class _FakeProcess implements Process {
  final _exit = Completer<int>();
  bool killed = false;
  void finish(int code) => _exit.complete(code);
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  int get pid => 1;
  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();
  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();
  @override
  IOSink get stdin => throw UnimplementedError();
}
