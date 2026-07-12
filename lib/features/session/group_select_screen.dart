// lib/features/session/group_select_screen.dart
//
// Step 2 of the session flow: maktab+PIN → **guruh tanlash** → o'sha
// guruh test katalogi → o'quvchi → boshlash (2026-07-11 reorder).
//
// Loads the confirmed school's groups. Once a group is picked, the test
// catalog is re-fetched scoped to that group's id (`?group_id=`) so two
// groups sharing one school never see (or accidentally start) each
// other's assigned test.
//
// Guruhsiz maktab (fetchGroups returns empty): falls back to the
// [fallbackEntry] the caller already had selected and skips straight to
// StudentEntryScreen — group_id is never sent, the catalog behaves
// exactly as before this reorder (backward compatible, offline/kiosk
// flow untouched).
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/services/test_catalog_service.dart';
import '../../shared/theme/app_theme.dart';
import 'student_entry_screen.dart';
import 'test_session.dart';

class GroupSelectScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolLabel;

  /// The test the user originally tapped to start this flow. Used as a
  /// fallback when the school has no groups (nothing to filter by) and
  /// kept as the initial pick if it's still relevant after group scoping.
  final CatalogEntry fallbackEntry;

  const GroupSelectScreen({
    super.key,
    required this.schoolCode,
    required this.schoolLabel,
    required this.fallbackEntry,
  });

  @override
  State<GroupSelectScreen> createState() => _GroupSelectScreenState();
}

class _GroupSelectScreenState extends State<GroupSelectScreen> {
  bool _loadingGroups = true;
  List<Map<String, dynamic>> _groups = [];
  Map<String, dynamic>? _selectedGroup;

  bool _loadingCatalog = false;
  List<CatalogEntry> _catalog = [];
  String? _err;
  final Set<String> _downloadingKeys = {};

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final g = await api.fetchGroups(widget.schoolCode);
      if (!mounted) return;
      if (g.isEmpty) {
        // Guruhsiz maktab — filtrlash uchun hech narsa yo'q, hozirgidek
        // to'g'ridan o'quvchi ekraniga o'tamiz (group_id yuborilmaydi).
        _goToStudentEntry(widget.fallbackEntry, null);
        return;
      }
      setState(() {
        _groups = g;
        _loadingGroups = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingGroups = false;
        _err = "Guruhlarni yuklab bo'lmadi";
      });
    }
  }

  Future<void> _selectGroup(Map<String, dynamic> group) async {
    final groupId = (group['id'] ?? '').toString();
    setState(() {
      _selectedGroup = group;
      _loadingCatalog = true;
      _catalog = [];
      _err = null;
    });
    try {
      // Guruh o'zgarganda katalog har doim tarmoqdan qayta yuklanadi —
      // TestCatalogService.refresh() natijani keshlamaydi, shu bilan
      // guruh bo'yicha invalidatsiya avtomatik ta'minlanadi.
      final entries = await testCatalogService.refresh(
        groupId: groupId.isEmpty ? null : groupId,
        schoolCode: widget.schoolCode,
      );
      if (!mounted) return;
      setState(() {
        _catalog = entries;
        _loadingCatalog = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCatalog = false;
        _err = "Testlar ro'yxatini yuklab bo'lmadi";
      });
    }
  }

  /// Guruh kontekstida (group_id ma'lum bo'lganda) testni yuklab, keshga
  /// saqlaydi — S-001: detail fetch guruh scoping bilan bog'lanishi kerak,
  /// shuning uchun bu yerdagi yuklash har doim `_selectedGroup`ning id'sini
  /// uzatadi (guruhsiz maktab bu ekranga umuman kirmaydi — _loadGroups() da
  /// to'g'ridan StudentEntryScreen'ga o'tkaziladi).
  Future<void> _downloadEntry(CatalogEntry entry) async {
    final groupId = (_selectedGroup?['id'] ?? '').toString();
    setState(() => _downloadingKeys.add(entry.testKey));
    try {
      await testCatalogService.download(
        entry.testKey,
        groupId: groupId.isEmpty ? null : groupId,
        schoolCode: widget.schoolCode,
      );
    } catch (e) {
      debugPrint('GroupSelectScreen: download(${entry.testKey}) error: $e');
    }
    if (!mounted) return;
    setState(() => _downloadingKeys.remove(entry.testKey));
    // Holatni yangilash uchun shu guruh katalogini qayta yuklaymiz —
    // muvaffaqiyatli yuklangan test "Boshlash"ga aylanadi.
    if (_selectedGroup != null) {
      await _selectGroup(_selectedGroup!);
    }
  }

  void _goToStudentEntry(CatalogEntry entry, Map<String, dynamic>? group) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'student_entry'),
        builder: (_) => StudentEntryScreen(
          session: TestSession.fromEntry(
            entry,
            schoolCode: widget.schoolCode,
            schoolLabel: widget.schoolLabel,
          ),
          preselectedGroup: group,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Guruhni tanlang', style: AppTextStyles.titleMedium),
      ),
      body: _loadingGroups
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_err != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.err.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_rounded,
                                color: AppColors.err, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _err!,
                                style: const TextStyle(
                                    color: AppColors.err, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_groups.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('Guruhlar topilmadi'),
                        ),
                      )
                    else ...[
                      const Text('Guruhni tanlang',
                          style: AppTextStyles.labelLarge),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _groups.map((group) {
                          final selected = _selectedGroup == group;
                          return GestureDetector(
                            onTap: () => _selectGroup(group),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.secondary
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.secondary
                                      : AppColors.border,
                                ),
                              ),
                              child: Text(
                                (group['display'] ?? group['name'] ?? '')
                                    .toString(),
                                style: AppTextStyles.labelLarge.copyWith(
                                  color:
                                      selected ? Colors.white : AppColors.ink1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (_selectedGroup != null) ...[
                      const SizedBox(height: 24),
                      const Text('Testni tanlang',
                          style: AppTextStyles.labelLarge),
                      const SizedBox(height: 10),
                      if (_loadingCatalog)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_catalog.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Bu guruh uchun test topilmadi'),
                        )
                      else
                        ..._catalog.map(_testTile),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _testTile(CatalogEntry entry) {
    final downloaded = entry.status == CatalogStatus.cached ||
        entry.status == CatalogStatus.cachedOnly ||
        entry.status == CatalogStatus.updatable;
    final isLocked = entry.lockedUntil != null &&
        entry.lockedUntil!.isAfter(DateTime.now());
    final isDownloading = _downloadingKeys.contains(entry.testKey);

    // Yuklanmagan test — shu yerdayoq (guruh ma'lum bo'lgan holatda)
    // yuklab olish imkonini beramiz, group_id bilan (S-001).
    if (!downloaded) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text(
            entry.title,
            style:
                AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text("Yuklab olinmagan",
              style: TextStyle(color: AppColors.ink3, fontSize: 12)),
          trailing: isDownloading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: () => _downloadEntry(entry),
                  child: const Text('Yuklash'),
                ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          entry.title,
          style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: isLocked
            ? const Text('Hali qulflangan',
                style: TextStyle(color: AppColors.primary, fontSize: 12))
            : null,
        trailing: const Icon(Icons.chevron_right_rounded),
        enabled: !isLocked,
        onTap: isLocked ? null : () => _goToStudentEntry(entry, _selectedGroup),
      ),
    );
  }
}
