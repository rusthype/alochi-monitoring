import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/main.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const AlochiMonitoringApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(AlochiMonitoringApp), findsOneWidget);
  });
}
