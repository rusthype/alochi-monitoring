// Extracted pack images are per-pack and must not outlive their session.
import 'dart:io';

import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;

  setUp(() {
    support = Directory.systemTemp.createTempSync('support_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => support.path);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    support.deleteSync(recursive: true);
  });

  test('media lives in a per-pack folder under offline_store/media', () async {
    final d = await OfflinePackSession.mediaDirFor('pack-1');
    expect(d.path, p.join(support.path, 'offline_store', 'media', 'pack-1'));
  });

  test('cleanup keeps only the named pack; no argument removes everything',
      () async {
    for (final id in ['old-a', 'old-b', 'current']) {
      final d = await OfflinePackSession.mediaDirFor(id);
      await d.create(recursive: true);
      File(p.join(d.path, 'x.jpg')).writeAsBytesSync([1]);
    }
    // stray file from an older flat layout
    File(p.join(support.path, 'offline_store', 'media', 'legacy.jpg'))
        .writeAsBytesSync([1]);

    await OfflinePackSession.cleanupMedia(keepPackUuid: 'current');
    final root = Directory(p.join(support.path, 'offline_store', 'media'));
    expect(
        root.listSync().map((e) => p.basename(e.path)).toList(), ['current']);

    await OfflinePackSession.cleanupMedia();
    expect(root.listSync(), isEmpty);
  });

  test('cleanup with no media folder is a no-op', () async {
    await OfflinePackSession.cleanupMedia();
  });
}
