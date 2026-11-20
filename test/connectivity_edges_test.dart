import 'dart:io';

import 'package:alochi_monitoring/core/network/connectivity_edges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('linuxHasNetworkManager follows the NetworkManager run dir', () {
    final d = Directory.systemTemp.createTempSync('nm');
    addTearDown(() => d.deleteSync(recursive: true));
    expect(linuxHasNetworkManager(runDir: d.path), isTrue);
    expect(linuxHasNetworkManager(runDir: '${d.path}/missing'), isFalse);
  });

  test('Linux without NetworkManager: empty stream, plugin never touched',
      () async {
    if (!Platform.isLinux) return; // the guard is Linux-only
    expect(await connectivityChanges(linuxHasNm: false).toList(), isEmpty);
  });
}
