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
import 'package:alochi_monitoring/l10n/app_localizations.dart';
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
  ///
  /// Nullable: entry points that only know the school (e.g. the
  /// "Boshqa maktablar" picker in the pre-login bottom sheet, 2026-07-12)
  /// have no pre-selected test to fall back to. In that case a guruhsiz
  /// school (no groups) is shown as an error instead of being routed
  /// straight to StudentEntryScreen.
  final CatalogEntry? fallbackEntry;

  const GroupSelectScreen({
    super.key,
    required this.schoolCode,
    required this.schoolLabel,
    this.fallbackEntry,
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
        final fallback = widget.fallbackEntry;
        // testKey bo'sh bo'lsa — bu login_screen'dagi "Boshqa maktablar"
        // school-picker'idan kelgan sintetik CatalogEntry (2026-07-12),
        // haqiqiy test emas, hech qachon yuklab/ishga tushirib bo'lmaydi.
        if (fallback == null || fallback.testKey.isEmpty) {
          // Pre-known test yo'q (masalan school-picker orqali kirilgan) —
          // bora oladigan joy yo'q, xato holatini ko'rsatamiz.
          setState(() {
            _loadingGroups = false;
            _err = "Bu maktab uchun testlar topilmadi";
          });
          return;
        }
        // Guruhsiz maktab — filtrlash uchun hech narsa yo'q, hozirgidek
        // to'g'ridan o'quvchi ekraniga o'tamiz (group_id yuborilmaydi).
        _goToStudentEntry(fallback, null);
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
      // Yangi testlar ro'yxat boshida chiqishi uchun yangi-birinchi tartib
      // (backend updated_at bo'yicha; null bo'lsa oxiriga tushadi).
      entries.sort((a, b) =>
          (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
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
    Navigator.of(context).push(
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
      body: Stack(
        children: [
          // Background noise could be added here if we had an asset, but we'll stick to AppColors.bg

          // Main Content
          Positioned.fill(
            child: _loadingGroups
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    key: const PageStorageKey('group_select_scroll'),
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 100,
                      bottom: 80,
                      left: 16,
                      right: 16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth:
                                768), // Max width from mockup 3xl approx 768
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_err != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.errorMuted,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: AppColors.error
                                          .withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_rounded,
                                        color: AppColors.error, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _err!,
                                        style: const TextStyle(
                                            color: AppColors.error,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            if (_groups.isEmpty)
                              // _err != null bo'lsa, yuqoridagi xato bandida
                              // sabab allaqachon ko'rsatilgan — ikkinchi marta
                              // umumiy "Guruhlar topilmadi" matnini takrorlamaymiz.
                              if (_err == null)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 40),
                                    child: Text(AppLocalizations.of(context)!.groupsNotFound, style: const TextStyle(fontSize: 16, color: AppColors.ink3)),
                                  ),
                                )
                              else
                                const SizedBox.shrink()
                            else ...[
                              // Section 1: Guruhni tanlang
                              _buildStepIndicator('Qadam 1', active: true),
                              const SizedBox(height: 12),
                              Text(
                                AppLocalizations.of(context)!.selectGroup,
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                  color: AppColors.ink1,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: _groups.map(_buildGroupPill).toList(),
                              ),
                            ],
                            if (_selectedGroup != null) ...[
                              const SizedBox(height: 48),
                              // Section 2: Testni tanlang
                              _buildStepIndicator('Qadam 2', active: false),
                              const SizedBox(height: 12),
                              Text(
                                AppLocalizations.of(context)!.selectTest,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                  color: AppColors.ink1,
                                ),
                              ),
                              const SizedBox(height: 24),

                              if (_loadingCatalog)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 32),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              else if (_catalog.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 32),
                                  child: Text(
                                    AppLocalizations.of(context)!.testsNotFoundForGroup,
                                    style: const TextStyle(fontSize: 15, color: AppColors.ink3),
                                  ),
                                )
                              else
                                ..._catalog.map(_buildTestCard),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
          ),

          // Floating Navbar
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: Center(
              child: _DoubleBezel(
                padding: const EdgeInsets.all(6),
                borderRadius: 100,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Back Button
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            color: Colors.transparent, // expand tap area
                            child: Row(
                              children: [
                                _HoverableBackButtonIcon(),
                                const SizedBox(width: 8),
                                Text(
                                  AppLocalizations.of(context)!.backBtn,
                                  style: const TextStyle(
                                    color: AppColors.brand,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                      Text(
                        AppLocalizations.of(context)!.appTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.ink1,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 48),
                      const SizedBox(width: 40), // spacer to balance "Ortga"
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(String text, {bool active = true}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.brand : AppColors.gray200,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            color: AppColors.ink3,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupPill(Map<String, dynamic> group) {
    final isSelected = _selectedGroup == group;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: () => _selectGroup(group),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brand : AppColors.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: isSelected ? AppColors.brand : AppColors.border,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: AppColors.brand.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (group['display'] ?? group['name'] ?? '').toString(),
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.ink1,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestCard(CatalogEntry entry) {
    final downloaded = entry.status == CatalogStatus.cached ||
        entry.status == CatalogStatus.cachedOnly ||
        entry.status == CatalogStatus.updatable;
    final isLocked =
        entry.lockedUntil != null && entry.lockedUntil!.isAfter(DateTime.now());
    final isDownloading = _downloadingKeys.contains(entry.testKey);

    if (!downloaded) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _DoubleBezel(
          child: Container(
            color: AppColors.gray50.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gray700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.brand),
                        const SizedBox(width: 6),
                        Text(
                          AppLocalizations.of(context)!.notDownloaded,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand),
                        ),
                      ],
                    ),
                  ],
                ),
                isDownloading
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.brand)),
                      )
                    : _HoverableDownloadButton(
                        onPressed: () => _downloadEntry(entry),
                      ),
              ],
            ),
          ),
        ),
      );
    }

    if (isLocked) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Opacity(
          opacity: 0.6,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.5,
              0.5,
              0.5,
              0,
              0,
              0.5,
              0.5,
              0.5,
              0,
              0,
              0.5,
              0.5,
              0.5,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: _DoubleBezel(
              child: Container(
                color: AppColors.gray50,
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.gray700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.lock_rounded, size: 16, color: AppColors.error),
                            const SizedBox(width: 6),
                            Text(
                              AppLocalizations.of(context)!.stillLocked,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.error),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.gray100,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.lock_rounded,
                          color: AppColors.ink3, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _HoverableTestCard(
      entry: entry,
      onTap: () => _goToStudentEntry(entry, _selectedGroup),
    );
  }
}

class _HoverableBackButtonIcon extends StatefulWidget {
  @override
  State<_HoverableBackButtonIcon> createState() =>
      _HoverableBackButtonIconState();
}

class _HoverableBackButtonIconState extends State<_HoverableBackButtonIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.brand : AppColors.brandLight,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.arrow_back_rounded,
          color: _isHovered ? Colors.white : AppColors.brand,
          size: 18,
        ),
      ),
    );
  }
}

class _HoverableDownloadButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _HoverableDownloadButton({required this.onPressed});

  @override
  State<_HoverableDownloadButton> createState() =>
      _HoverableDownloadButtonState();
}

class _HoverableDownloadButtonState extends State<_HoverableDownloadButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            transform: _isHovered
                ? Matrix4.translationValues(0, -2, 0)
                : Matrix4.identity(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _isHovered ? AppColors.brand : Colors.white,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                  color: _isHovered ? AppColors.brand : AppColors.border),
              boxShadow: [
                if (_isHovered)
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                else
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download_rounded,
                    size: 18,
                    color: _isHovered ? Colors.white : AppColors.ink1),
                const SizedBox(width: 8),
                Text(
                AppLocalizations.of(context)!.download,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _isHovered ? Colors.white : AppColors.ink1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverableTestCard extends StatefulWidget {
  final CatalogEntry entry;
  final VoidCallback onTap;

  const _HoverableTestCard({required this.entry, required this.onTap});

  @override
  State<_HoverableTestCard> createState() => _HoverableTestCardState();
}

class _HoverableTestCardState extends State<_HoverableTestCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: widget.onTap,
            child: _DoubleBezel(
              isHovered: _isHovered,
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.entry.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink1,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                        AppLocalizations.of(context)!.ready,
                        style: const TextStyle(fontSize: 13, color: AppColors.ink3, fontWeight: FontWeight.w500),
                      ),
                      ],
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: 40,
                      height: 40,
                      transform: _isHovered
                          ? Matrix4.translationValues(4, 0, 0)
                          : Matrix4.identity(),
                      decoration: BoxDecoration(
                        color:
                            _isHovered ? AppColors.brand : AppColors.brandLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: _isHovered ? Colors.white : AppColors.brand,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DoubleBezel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool isHovered;

  const _DoubleBezel({
    required this.child,
    this.padding = const EdgeInsets.all(6),
    this.borderRadius = 32,
    this.isHovered = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      transform:
          isHovered ? Matrix4.translationValues(0, -4, 0) : Matrix4.identity(),
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          if (isHovered)
            BoxShadow(
              color: AppColors.brand.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 12),
              spreadRadius: -8,
            )
          else
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 24,
              offset: const Offset(0, 4),
              spreadRadius: -4,
            ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(borderRadius - 6),
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
