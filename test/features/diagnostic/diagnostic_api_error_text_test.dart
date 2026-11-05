// The kiosk API's ApiException.message is Uzbek-only debug text; the three
// diagnostic pickers must show localized ARB text instead (ru must be Russian).
import 'package:alochi_monitoring/core/api/api_client.dart' show ApiException;
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_class_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_school_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_student_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_widgets.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/l10n/app_localizations_ru.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _raw = "Internet aloqasi yo'q.";

Future<void> _pump(WidgetTester tester, Widget screen) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: screen,
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final ru = AppLocalizationsRu();

  testWidgets('school picker shows localized text, not the raw message',
      (tester) async {
    await _pump(
        tester,
        DiagnosticSchoolSelectScreen(
            loadSchools: () async => throw const ApiException(0, _raw)));
    expect(find.text(_raw), findsNothing);
    expect(find.text(ru.connectionError), findsOneWidget);
  });

  testWidgets('student picker shows localized text, not the raw message',
      (tester) async {
    await _pump(
        tester,
        DiagnosticStudentSelectScreen(
          schoolId: 's1',
          schoolName: 'M1',
          classLabel: '4-A',
          language: 'uz',
          listStudentsOverride: (_, __) async =>
              throw const ApiException(429, "Ko'p urinish, biroz kuting"),
        ));
    expect(find.text("Ko'p urinish, biroz kuting"), findsNothing);
    expect(find.text(ru.tooManyAttempts), findsOneWidget);
  });

  testWidgets('class picker shows localized text, not the raw message',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => null);
    await http.runWithClient(
        () => _pump(
            tester,
            const DiagnosticClassSelectScreen(
                schoolId: 'no-cache-school', schoolName: 'M1')),
        () => MockClient((_) async => http.Response('{}', 503)));
    expect(find.text("Server xatosi, keyinroq urinib ko'ring"), findsNothing);
    expect(find.text(ru.serverErrorRetry), findsOneWidget);
  });

  testWidgets('cached-list badge: accurate wording for offline vs server busy',
      (tester) async {
    await _pump(tester, const Scaffold(body: DiagnosticOfflineBadge()));
    expect(find.text(ru.diagnosticOfflineCached), findsOneWidget);
    await _pump(
        tester,
        const Scaffold(body: DiagnosticOfflineBadge(offline: false)));
    expect(find.text(ru.diagnosticServerBusyCached), findsOneWidget);
    expect(find.text(ru.diagnosticOfflineCached), findsNothing);
  });
}
