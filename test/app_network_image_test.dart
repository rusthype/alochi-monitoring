import 'package:alochi_monitoring/shared/widgets/app_network_image.dart';
import 'package:flutter/material.dart';
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
