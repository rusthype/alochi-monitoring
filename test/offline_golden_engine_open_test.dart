// Regression: the golden pack's test must be OPENABLE by the engine.
// The fixture once used variant key "A"; runner_dispatch picks a variant with
// `int.tryParse(key) ?? 1`, so "A" -> 1 -> sectionsForVariant("1") was empty
// and the engine showed "test data not found". Real tests use numeric keys.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dir = 'test/fixtures/offline';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
      'golden pack test has non-empty sections for the production-picked variant',
      () async {
    final tmp = Directory.systemTemp.createTempSync('golden_engine_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    addTearDown(() async {
      OfflinePackSession.close();
      await OfflineQueue.resetForTest();
    });

    final keys = OfflineKeys(
      signingPem: File('$_dir/test_signing_public.pem').readAsStringSync(),
      resultsPem: File('$_dir/test_results_public.pem').readAsStringSync(),
    );
    final media = Directory(p.join(tmp.path, 'media'))..createSync();
    final pack = await PackLoader(keys: keys).open(
        File('$_dir/golden.alochipack').readAsBytesSync(), '12345678',
        mediaDir: media);
    await OfflinePackSession.open(pack, media);

    final data = await api.fetchTest('golden_test_1');
    expect(data, isNotNull);

    // Same derivation as runner_dispatch::_pickRandomVariant.
    final variantKeys =
        (data!['variants'] as Map).keys.map((k) => k.toString()).toList();
    expect(variantKeys, isNotEmpty);
    final picked = int.tryParse(variantKeys.first) ?? 1;

    final sections = TestSpec.fromJson(data).sectionsForVariant('$picked');
    expect(sections.map((s) => s.name), ['Vocabulary', 'Reading']);
    expect(sections.first.questions.length, 3);
    expect(sections.last.readingContainer, isNotNull);
  });
}
