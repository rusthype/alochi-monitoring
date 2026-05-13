import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AlochiMonitoringApp());
    expect(find.byType(AlochiMonitoringApp), findsOneWidget);
  });
}
