import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

import '../../features/combined/combined_screen.dart';
import '../../features/local_test/history_screen.dart';
import '../../features/local_test/local_grade_screen.dart';

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const CommandPalette(),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Populated in didChangeDependencies() — AppLocalizations isn't available
  // yet at field-initializer/initState time.
  List<Map<String, String>> _allRoutes = [];
  List<Map<String, String>> _filtered = [];

  Widget? _extraFor(String route) {
    switch (route) {
      case '/history':
        return const HistoryScreen();
      case '/local_grade':
        return const LocalGradeScreen();
      case '/combined':
        return const CombinedScreen();
      default:
        return null;
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = _allRoutes;
      } else {
        _filtered = _allRoutes
            .where((r) => r['title']!.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    _allRoutes = [
      {'title': l10n.homePage, 'route': '/'},
      {'title': l10n.commandHistoryTitle, 'route': '/history'},
      {'title': l10n.commandLocalGradeTitle, 'route': '/local_grade'},
      {'title': l10n.commandCombinedTitle, 'route': '/combined'},
    ];
    _applyFilter();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        height: 400,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              focusNode: _focusNode,
              autofocus: true,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.searchOrCommandHint,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: (val) {
                if (_filtered.isNotEmpty) {
                  context.pop();
                  final route = _filtered.first['route']!;
                  context.push(route, extra: _extraFor(route));
                }
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final item = _filtered[index];
                  return ListTile(
                    title: Text(item['title']!),
                    leading: const Icon(Icons.keyboard_arrow_right),
                    onTap: () {
                      context.pop();
                      final route = item['route']!;
                      context.push(route, extra: _extraFor(route));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
