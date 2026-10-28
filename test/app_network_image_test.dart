import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:alochi_monitoring/shared/widgets/app_network_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty URL reserves the requested image slot', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AppNetworkImage(
          url: ' ',
          height: 120,
          width: 90,
        ),
      ),
    );

    final box = tester.widget<SizedBox>(find.byType(SizedBox));
    expect(box.height, 120);
    expect(box.width, 90);
  });

  testWidgets('a stored file that does not decode is deleted and the network '
      'image takes over (not an empty box)', (tester) async {
    final dir = Directory.systemTemp.createTempSync('ani_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final url = MonitoringApi.fixImageUrl('https://api.alochi.org/m/q1.png');
    // PNG signature + junk: passes the store's sniff, fails the image codec.
    // CachedNetworkImage's cache manager asks path_provider for directories.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dir.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null));
    final store = TestImageStore(
        root: Directory('${dir.path}/imgs'),
        client: MockClient((_) async => http.Response.bytes(
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 9, 9], 200)));
    TestImageStore.instanceForTest = store;
    await tester.runAsync(() async {
      await store.init();
      await store.fetch(url);
    });
    final file = store.cachedFile(url)!;

    await tester.pumpWidget(MaterialApp(
        home: AppNetworkImage(url: url, width: 100, height: 100)));
    expect(find.byType(CachedNetworkImage), findsNothing); // stored shown
    // Real IO + codec failure need real time between pumps.
    for (var i = 0; i < 30 && file.existsSync(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pump();

    expect(file.existsSync(), isFalse);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    TestImageStore.instanceForTest = TestImageStore();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  // NOTE: a widget test that drives AppNetworkImage into its real
  // CachedNetworkImage error state (to exercise the Task 3 tap-to-retry
  // affordance end-to-end) was attempted here and removed — confirmed
  // empirically (with and without path_provider mocked, per the pattern in
  // diagnostic_offline_resume_test.dart) that AlochiImageCacheManager's
  // underlying sqflite-backed JsonCacheInfoRepository never resolves under
  // plain `flutter test` (no sqflite plugin channel registered, and unlike
  // AttemptStore's crypto path there is no sqflite_common_ffi wiring in
  // production code to fall back to here) — the image just stays in its
  // loading state forever instead of throwing, so the error branch is
  // unreachable from a widget test without mocking the sqflite method
  // channel wholesale. Not attempted — same class of suite-hang risk this
  // repo already avoids elsewhere. The retry affordance's onTap wiring
  // (`removeFile` + `setState(() => _retryNonce++)`) was verified by
  // reading app_network_image.dart directly instead.
}
