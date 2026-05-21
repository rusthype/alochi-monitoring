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
}
