import 'package:alochi_monitoring/core/theme/app_colors.dart';
import 'package:alochi_monitoring/features/offline/export_done_notice.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _name = '999_00000000000040008000000000000a1_20261023-035206.alochires';
const _file = '/Users/max/Downloads/alochi-offline/$_name';

Widget _host(double width, List<String> files) => MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ExportDoneNotice(
                headline: 'Экспортировано результатов: 5', files: files),
          ),
        ),
      ),
    );

void main() {
  testWidgets('green success notice: headline, file name, folder, actions',
      (tester) async {
    await tester.pumpWidget(_host(360, const [_file]));
    final box = tester.widget<Container>(find.byType(Container).first);
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, AppColors.successMuted);
    expect(find.text('Экспортировано результатов: 5'), findsOneWidget);
    expect(find.text(_name), findsOneWidget);
    expect(find.text('Копировать путь'), findsOneWidget);
    expect(find.text('/Users/max/Downloads/alochi-offline'), findsOneWidget);
  });

  testWidgets('reveal button hidden when the file no longer exists',
      (tester) async {
    await tester.pumpWidget(_host(360, const [_file]));
    expect(find.text('Показать в папке'), findsNothing);
  });

  testWidgets('very long path in a narrow box does not overflow',
      (tester) async {
    final long =
        '/Users/some.very.long.user.name/Downloads/${'deep-folder/' * 8}'
        '$_name';
    await tester.pumpWidget(_host(220, [long, long]));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('…'), findsOneWidget); // folder middle-ellipsis
  });

  testWidgets('copy puts the full path on the clipboard and confirms',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(_host(360, const [_file]));
    await tester.tap(find.text('Копировать путь'));
    await tester.pump();
    expect(copied, _file);
    expect(find.text('Скопировано'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Копировать путь'), findsOneWidget);
  });

  test('middleEllipsis keeps both ends and respects max', () {
    expect(middleEllipsis('short'), 'short');
    final r = middleEllipsis('a' * 30 + 'b' * 30, max: 21);
    expect(r.length, 21);
    expect(r, contains('…'));
    expect(r.startsWith('a'), isTrue);
    expect(r.endsWith('b'), isTrue);
  });
}
