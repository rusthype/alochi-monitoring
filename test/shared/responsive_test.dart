import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/shared/utils/responsive.dart';

Future<T> _withHeight<T>(
  WidgetTester tester,
  double height,
  T Function(BuildContext) probe,
) async {
  late T result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: Size(1024, height)),
      child: Builder(
        builder: (context) {
          result = probe(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('isCompact is true under 800 height, false above',
      (tester) async {
    expect(await _withHeight(tester, 700, isCompact), isTrue);
    expect(await _withHeight(tester, 900, isCompact), isFalse);
  });

  testWidgets('clampedMediaHeight respects min/max/mid bounds', (tester) async {
    final tiny = await _withHeight(tester, 100, clampedMediaHeight);
    expect(tiny, greaterThanOrEqualTo(110.0));

    final huge = await _withHeight(tester, 5000, clampedMediaHeight);
    expect(huge, lessThanOrEqualTo(260.0));

    final mid = await _withHeight(tester, 700, clampedMediaHeight);
    expect(mid, greaterThan(110.0));
    expect(mid, lessThan(260.0));
  });
}
