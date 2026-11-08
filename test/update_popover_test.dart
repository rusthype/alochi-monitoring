import 'dart:async';

import 'package:alochi_monitoring/core/services/update_service.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/update_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _info = UpdateInfo(
  latestVersion: '1.0.171',
  currentVersion: '1.0.170',
  downloadUrl: 'https://github.com/rusthype/alochi-monitoring/x.exe',
  releasedAt: DateTime(2026, 11, 8),
);

Widget _host({
  UpdateInfo? info,
  UpdateInstallFn? install,
  VoidCallback? onSkipped,
  VoidCallback? onNotes,
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
          surface: Colors.white,
          border: const Color(0xFFE5E7EB),
          ink1: Colors.black,
          ink2: Colors.grey,
          hoverFill: const Color(0xFFFFF1E6),
          install: install,
          sizeLoader: (_) async => 39946240, // 38.1 MB
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
    await t.pumpWidget(_host(onNotes: () => browser++, install: (info, {onProgress}) {
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
    expect(find.textContaining('Не удалось загрузить обновление'),
        findsOneWidget);
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
}
