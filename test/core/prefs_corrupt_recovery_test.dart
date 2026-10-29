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

  List<File> backups() => tmp
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('shared_preferences.json.corrupt-'))
      .toList();

  test('F35: at most 3 .corrupt backups are kept, the newest ones', () async {
    for (final ts in [1000, 2000, 3000]) {
      File('${file.path}.corrupt-$ts').writeAsStringSync('old $ts');
    }
    file.writeAsStringSync('{"app_locale": "ru", "x": ["A'); // torn

    await loadPrefsWithFallback(
      load: pluginLoad,
      retryDelay: Duration.zero,
      locatePrefsFile: () async => file,
    );

    final names = backups().map((f) => f.path.split('.corrupt-').last).toSet();
    expect(names.length, 3);
    expect(names.contains('1000'), isFalse, reason: 'oldest dropped');
    expect(names.containsAll(['2000', '3000']), isTrue);
    // The just-quarantined torn file is one of the three.
    expect(backups().any((f) => f.readAsStringSync().contains('"x"')), isTrue);
  });

  test('F35: valid JSON with unreadable (null) values keeps the readable '
      'entries, backs up the original and loads', () async {
    file.writeAsStringSync(
        '{"app_locale": "ru", "bad": null, "roster_done_x": ["A"]}');

    final prefs = await loadPrefsWithFallback(
      load: pluginLoad,
      retryDelay: Duration.zero,
      locatePrefsFile: () async => file,
    );

    expect(prefs.getString('app_locale'), 'ru'); // not lost
    expect(prefs.getStringList('roster_done_x'), ['A']);
    expect(backups(), hasLength(1));
    expect(backups().single.readAsStringSync(), contains('"bad": null'));
    final onDisk = jsonDecode(file.readAsStringSync()) as Map;
    expect(onDisk.containsKey('bad'), isFalse);
    expect(onDisk['app_locale'], 'ru');
  });
}
