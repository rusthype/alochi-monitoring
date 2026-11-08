import 'dart:async';

import 'package:alochi_monitoring/core/services/update_service.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/update_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// HEAD stand-in: MockClient derives contentLength from the (empty) body, so a
/// tiny BaseClient reports the length explicitly.
class FakeHeadClient extends http.BaseClient {
  final Future<int?> Function(http.BaseRequest) onHead;
  FakeHeadClient(this.onHead);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final len = await onHead(request);
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200,
        contentLength: len);
  }
}

final _info = UpdateInfo(
  latestVersion: '1.0.171',
  currentVersion: '1.0.170',
  downloadUrl: 'https://github.com/rusthype/alochi-monitoring/x.exe',
  releasedAt: DateTime(2026, 11, 8),
);

Widget _host({
  bool compact = false,
  UpdateInfo? info,
  UpdateInstallFn? install,
  VoidCallback? onSkipped,
  VoidCallback? onNotes,
  Future<int?> Function(UpdateInfo)? sizeLoader,
}) {
  return MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topRight,
        child: UpdatePill(
          info: info ?? _info,
          compact: compact,
          surface: Colors.white,
          border: const Color(0xFFE5E7EB),
          ink1: Colors.black,
          ink2: Colors.grey,
          hoverFill: const Color(0xFFFFF1E6),
          install: install,
          sizeLoader: sizeLoader ?? (_) async => 39946240, // 38.1 MB
          onSkipped: onSkipped,
          onOpenReleaseNotes: onNotes,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openPopover(WidgetTester t) async {
    await t.tap(find.text('Доступна новая версия'));
    await t.pumpAndSettle();
  }

  testWidgets('pill tap opens popover with version/size/date/buttons',
      (t) async {
    await t.pumpWidget(_host());
    expect(find.text('Доступно обновление'), findsNothing);
    await openPopover(t);
    expect(find.text('Доступно обновление'), findsOneWidget);
    expect(find.text('v1.0.171'), findsOneWidget);
    expect(find.text('38.1 МБ'), findsOneWidget);
    expect(find.text('08.11.2026'), findsOneWidget);
    expect(find.text('Пропустить'), findsOneWidget);
    expect(find.text('Позже'), findsOneWidget);
    expect(find.text('Установить и перезапустить'), findsOneWidget);
    expect(find.text('Что нового'), findsOneWidget);
  });

  group('size row is instant', () {
    final never = Completer<int?>();
    Future<int?> pending(UpdateInfo _) => never.future;

    testWidgets('manifest size shows on the first frame, no ellipsis',
        (t) async {
      final sized = UpdateInfo(
        latestVersion: '1.0.171',
        currentVersion: '1.0.170',
        downloadUrl: _info.downloadUrl,
        releasedAt: DateTime(2026, 11, 8),
        sizeBytes: 39946240,
      );
      await t.pumpWidget(_host(info: sized, sizeLoader: pending));
      await t.tap(find.text('Доступна новая версия'));
      await t.pump(); // exactly one frame
      expect(find.text('38.1 МБ'), findsOneWidget);
      expect(find.text('…'), findsNothing);
    });

    testWidgets('prefetched cache shows on the first frame', (t) async {
      final svc = UpdateService.instance;
      svc.resetSizeCache();
      addTearDown(() {
        svc.resetSizeCache();
        svc.sizeClientFactory = http.Client.new;
      });
      await t.pumpWidget(_host(sizeLoader: pending)); // pill built first
      svc.sizeClientFactory = () => FakeHeadClient((_) async => 39946240);
      await t.runAsync(() => svc.fetchInstallerSize(_info)); // prefetch lands
      await t.tap(find.text('Доступна новая версия'));
      await t.pump();
      expect(find.text('38.1 МБ'), findsOneWidget);
      expect(find.text('…'), findsNothing);
    });

    testWidgets('failure leaves the size row hidden', (t) async {
      final c = Completer<int?>();
      await t.pumpWidget(_host(sizeLoader: (_) => c.future));
      await t.tap(find.text('Доступна новая версия'));
      await t.pump();
      expect(find.text('…'), findsOneWidget); // lazy fetch in flight
      c.complete(null);
      await t.pumpAndSettle();
      expect(find.text('…'), findsNothing);
      expect(find.text('Размер'), findsNothing);
    });
  });

  testWidgets('Later, outside tap and Esc close the popover', (t) async {
    await t.pumpWidget(_host());
    await openPopover(t);
    await t.tap(find.text('Позже'));
    await t.pumpAndSettle();
    expect(find.text('Доступно обновление'), findsNothing);

    await openPopover(t);
    await t.tapAt(const Offset(10, 500));
    await t.pumpAndSettle();
    expect(find.text('Доступно обновление'), findsNothing);

    await openPopover(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Доступно обновление'), findsNothing);
  });

  testWidgets('release notes row calls the notes callback', (t) async {
    var opened = 0;
    await t.pumpWidget(_host(onNotes: () => opened++));
    await openPopover(t);
    await t.tap(find.text('Что нового'));
    expect(opened, 1);
  });

  testWidgets('Skip persists the version and reports it', (t) async {
    var skipped = 0;
    await t.pumpWidget(_host(onSkipped: () => skipped++));
    await openPopover(t);
    await t.tap(find.text('Пропустить'));
    await t.pumpAndSettle();
    expect(skipped, 1);
    expect(find.text('Доступно обновление'), findsNothing);
    expect(await UpdateService.instance.isVersionSkipped('1.0.171'), isTrue);
    // A newer version is not skipped.
    expect(await UpdateService.instance.isVersionSkipped('1.0.172'), isFalse);
  });

  testWidgets('Install shows download pill with percent, then error + retry',
      (t) async {
    final results = <Completer<UpdateResult>>[];
    void Function(double)? progress;
    var browser = 0;
    await t.pumpWidget(_host(
        onNotes: () => browser++,
        install: (info, {onProgress}) {
          progress = onProgress;
          final c = Completer<UpdateResult>();
          results.add(c);
          return c.future;
        }));
    await openPopover(t);
    await t.tap(find.text('Установить и перезапустить'));
    await t.pump();

    expect(find.text('Доступна новая версия'), findsNothing);
    expect(find.text('Скачивание: 0%'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    progress!(0.2);
    await t.pump();
    expect(find.text('Скачивание: 20%'), findsOneWidget);

    results.first.complete(const UpdateResult.failed(null));
    await t.pumpAndSettle();
    expect(
        find.textContaining('Не удалось загрузить обновление'), findsOneWidget);
    expect(find.text('Открыть в браузере'), findsOneWidget);
    await t.tap(find.text('Открыть в браузере'));
    expect(browser, 1);
    await t.pumpAndSettle();
    await t.tap(find.byType(UpdatePill)); // reopen the error popover
    await t.pumpAndSettle();

    await t.tap(find.text('Повторить'));
    await t.pump();
    expect(results, hasLength(2));
    expect(find.text('Скачивание: 0%'), findsOneWidget);
  });

  BoxDecoration pillDecoration(WidgetTester t) => t
      .widget<AnimatedContainer>(find.descendant(
          of: find.byType(UpdatePill),
          matching: find.byType(AnimatedContainer)))
      .decoration! as BoxDecoration;

  testWidgets('update pill is a full stadium (radius >= height / 2)',
      (t) async {
    await t.pumpWidget(_host());
    final r = (pillDecoration(t).borderRadius! as BorderRadius).topLeft.x;
    final h = t.getSize(find.byType(AnimatedContainer)).height;
    expect(r, greaterThanOrEqualTo(h / 2));
  });

  testWidgets('compact update pill is a circle', (t) async {
    await t.pumpWidget(_host(compact: true));
    final size = t.getSize(find.byType(AnimatedContainer));
    expect(size.width, size.height);
    final r = (pillDecoration(t).borderRadius! as BorderRadius).topLeft.x;
    expect(r, greaterThanOrEqualTo(size.height / 2));
  });

  testWidgets('download capsule keeps a constant size 0..100%', (t) async {
    void Function(double)? progress;
    await t.pumpWidget(_host(install: (info, {onProgress}) {
      progress = onProgress;
      return Completer<UpdateResult>().future;
    }));
    final updateHeight = t.getSize(find.byType(AnimatedContainer)).height;
    await openPopover(t);
    await t.tap(find.text('Установить и перезапустить'));
    await t.pump();

    final capsule = find.descendant(
        of: find.byType(UpdatePill), matching: find.byType(Container));
    final ring = find.byType(CircularProgressIndicator);
    Size size() => t.getSize(capsule.first);
    final w0 = size();
    final ring0 = t.getTopLeft(ring);
    expect(w0.height, updateHeight);
    for (final p in [0.09, 0.10, 0.99, 1.0]) {
      progress!(p);
      await t.pump();
      expect(size(), w0, reason: 'size changed at $p');
      expect(t.getTopLeft(ring), ring0, reason: 'ring moved at $p');
    }
    expect(find.text('Скачивание: 100%'), findsOneWidget);
  });
}
