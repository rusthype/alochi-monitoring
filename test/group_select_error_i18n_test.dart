import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/features/session/group_select_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoGroupsApi extends MonitoringApi {
  @override
  Future<List<Map<String, dynamic>>> fetchGroups(String schoolCode,
          {String? schoolId}) async =>
      [];
}

class _FailingGroupsApi extends MonitoringApi {
  @override
  Future<List<Map<String, dynamic>>> fetchGroups(String schoolCode,
          {String? schoolId}) async =>
      throw Exception('boom');
}

Widget _app(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const GroupSelectScreen(schoolCode: '1', schoolLabel: 'School 1'),
    );

void main() {
  late MonitoringApi savedApi;
  setUp(() => savedApi = api);
  tearDown(() => api = savedApi);

  for (final (name, fake, locale, expected) in [
    (
      'no tests, ru',
      _NoGroupsApi(),
      const Locale('ru'),
      'Для этой школы тесты не найдены'
    ),
    (
      'no tests, uz',
      _NoGroupsApi(),
      const Locale('uz'),
      'Bu maktab uchun testlar topilmadi'
    ),
    (
      'groups load failed, ru',
      _FailingGroupsApi(),
      const Locale('ru'),
      'Не удалось загрузить группы'
    ),
    (
      'groups load failed, uz',
      _FailingGroupsApi(),
      const Locale('uz'),
      "Guruhlarni yuklab bo'lmadi"
    ),
  ]) {
    testWidgets('error text follows app locale: $name', (tester) async {
      api = fake;
      await tester.pumpWidget(_app(locale));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
    });
  }

  testWidgets('error text re-renders when locale changes', (tester) async {
    api = _NoGroupsApi();
    await tester.pumpWidget(_app(const Locale('uz')));
    await tester.pumpAndSettle();
    expect(find.text('Bu maktab uchun testlar topilmadi'), findsOneWidget);
    await tester.pumpWidget(_app(const Locale('ru')));
    await tester.pumpAndSettle();
    expect(find.text('Для этой школы тесты не найдены'), findsOneWidget);
  });
}
