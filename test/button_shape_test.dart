import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/features/auth/login_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/theme/app_theme.dart';
import 'package:alochi_monitoring/shared/widgets/button_shape.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReachableApi extends MonitoringApi {
  @override
  Future<bool> ping() async => true;
}

void main() {
  testWidgets('hover overlay shape matches the chip frame radius',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: BottomChip(
                fill: Colors.white,
                border: Colors.grey,
                height: 42,
                child: TextButton.icon(
                  onPressed: () {},
                  style: bottomChipButtonStyle(foreground: Colors.black),
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text('Oflayn Tarix'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(TextButton)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    final expected = BorderRadius.circular(kChipRadius);
    final shape = tester
        .widget<TextButton>(find.byType(TextButton))
        .style!
        .shape!
        .resolve({WidgetState.hovered}) as RoundedRectangleBorder;
    expect(shape.borderRadius, expected);

    final frame = tester.widget<Container>(find.byType(Container).first);
    expect((frame.decoration! as BoxDecoration).borderRadius, expected);
    expect(frame.clipBehavior, Clip.antiAlias);

    // Button fills the whole chip interior (no inset pill inside the border).
    final chip = tester.getSize(find.byType(BottomChip));
    final button = tester.getSize(find.byType(TextButton));
    expect(button.width, chip.width - 2);
    expect(button.height, chip.height - 2);
  });

  group('login screen buttons', () {
    late MonitoringApi savedApi;
    setUp(() {
      savedApi = api;
      api = _ReachableApi();
    });
    tearDown(() => api = savedApi);

    testWidgets('tabs, Maktablar button and language capsule share shapes',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      addTearDown(() {
        ConnectivityService.instance.dispose();
        tester.view.reset();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            theme: AppTheme.theme,
            locale: const Locale('uz'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LoginScreen(),
          ),
        ),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      // Tabs: ink radius == indicator radius, ink sits in its own Material.
      final chipRadius = BorderRadius.circular(kChipRadius);
      for (final key in ['login-tab-student', 'login-tab-diagnostic']) {
        final tab = find.byKey(ValueKey(key));
        final ink = tester.widget<InkWell>(tab);
        expect(ink.borderRadius, chipRadius);
        expect(ink.onTap, isNotNull);
        await mouse.moveTo(tester.getCenter(tab));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<Material>(
                find.ancestor(of: tab, matching: find.byType(Material)).first,
              )
              .type,
          MaterialType.transparency,
        );
      }
      // Disabled "Testlar / Tez kunda" tab: no tap target, so no overlay.
      final disabled =
          tester.widget<InkWell>(find.byKey(const ValueKey('login-tab-tests')));
      expect(disabled.onTap, isNull);

      // Language capsule: clipped to the capsule's rounded shape and tall
      // enough that the dropdown's InkWell fills it.
      final capsule = find.ancestor(
        of: find.byType(DropdownButton<String>),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).borderRadius != null),
      );
      expect(capsule, findsOneWidget);
      final capsuleBox = tester.widget<Container>(capsule);
      expect((capsuleBox.decoration! as BoxDecoration).borderRadius,
          BorderRadius.circular(kControlRadius));
      expect(capsuleBox.clipBehavior, Clip.antiAlias);
      await mouse.moveTo(tester.getCenter(capsule));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      // Diagnostic tab shows the big outlined "Maktablar" button.
      await tester.tap(find.byKey(const ValueKey('login-tab-diagnostic')));
      await tester.pump(const Duration(milliseconds: 400));
      final schools = find.widgetWithIcon(OutlinedButton, Icons.school_rounded);
      expect(schools, findsOneWidget);
      final shape = tester
          .widget<OutlinedButton>(schools)
          .style!
          .shape!
          .resolve({WidgetState.hovered}) as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(kControlRadius));
      await mouse.moveTo(tester.getCenter(schools));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });
}
