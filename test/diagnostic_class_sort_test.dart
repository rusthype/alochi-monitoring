import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_class_select_screen.dart';

void main() {
  test('compareClassLabels sorts class labels numerically, not lexicographically', () {
    final labels = ['10-A', '11-B', '1-A', '2-B', '9-A'];
    labels.sort(compareClassLabels);
    expect(labels, ['1-A', '2-B', '9-A', '10-A', '11-B']);
  });
}
