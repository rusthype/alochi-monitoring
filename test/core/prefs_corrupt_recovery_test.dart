// Audit wave 2 #2: a torn shared_preferences.json (power cut mid-write) must
// be quarantined and recreated so later launches persist normally, instead of
// the app running on an in-memory store forever.

import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/storage/prefs_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('prefs_corrupt_');
    file = File('${tmp.path}/shared_preferences.json');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Behaves like the desktop plugin: parses the file, throws when it is torn.
  Future<SharedPreferences> pluginLoad() async {
    final raw = file.existsSync() ? file.readAsStringSync() : '';
    final map = raw.isEmpty
        ? <String, Object>{}
        : Map<String, Object>.from(jsonDecode(raw) as Map);
    SharedPreferences.setMockInitialValues(map);
    return SharedPreferences.getInstance();
  }

  test('torn file is renamed to .corrupt-<ts> and prefs load from a fresh file',
      () async {
    file.writeAsStringSync('{"app_locale": "ru", "roster_done_x": ["A'); // torn
    final errors = <Object>[];

    final prefs = await loadPrefsWithFallback(
      load: pluginLoad,
      retryDelay: Duration.zero,
      onFailure: (e, _) => errors.add(e),
      locatePrefsFile: () async => file,
    );

    expect(prefs, isNotNull);
    expect(errors, isNotEmpty);
    final quarantined = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('shared_preferences.json.corrupt-'));
    expect(quarantined, hasLength(1));
    expect(quarantined.single.readAsStringSync(), contains('roster_done_x'));
    expect(file.existsSync(), isFalse); // plugin recreates it on next write
  });

  test('NUL-filled file (typical NTFS power-cut result) is quarantined too',
      () async {
    file.writeAsBytesSync(List<int>.filled(64, 0));
    await loadPrefsWithFallback(
      load: pluginLoad,
      retryDelay: Duration.zero,
      locatePrefsFile: () async => file,
    );
    expect(
        tmp
            .listSync()
            .any((f) => f.path.contains('shared_preferences.json.corrupt-')),
        isTrue);
  });

  test('a healthy file that merely failed to load once is NOT touched',
      () async {
    file.writeAsStringSync('{"app_locale": "ru"}');
    await loadPrefsWithFallback(
      load: () async => throw StateError('locked by antivirus'),
      retryDelay: Duration.zero,
      locatePrefsFile: () async => file,
    );
    expect(file.readAsStringSync(), '{"app_locale": "ru"}');
    expect(tmp.listSync().length, 1);
  });

  test('locator failure keeps the in-memory fallback', () async {
    final prefs = await loadPrefsWithFallback(
      load: () async => throw const FormatException('torn'),
      retryDelay: Duration.zero,
      locatePrefsFile: () async => throw StateError('no path_provider'),
    );
    expect(prefs, isNotNull);
  });
}
