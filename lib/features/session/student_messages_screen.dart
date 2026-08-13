// lib/features/session/student_messages_screen.dart
//
// "Сообщения" (Messages) screen for the self-login student cabinet — vs
// dark3.jpg. Returns BARE content only (no StudentShell/Scaffold wrap, same
// convention as my_tests_screen.dart/student_results_screen.dart etc.) — the
// wiring step plugs this in as a StatefulShellBranch child.
//
// Data source: GET /api/v1/monitoring/messages/ (api.fetchMessages) — `type`
// has 4 real values (teacher/system/test_assigned/test_reviewed); the
// mockup's 4 filter tabs map onto them as:
//   Все               -> all types
//   От учителей       -> type == 'teacher'
//   Уведомления о тестах -> type in (test_assigned, test_reviewed)
//   Системные         -> type == 'system'
//
// test_assigned/test_reviewed rows are server-synthesized (not real DB
// rows): always `is_read: true` already, and their `id` may not be a real
// UUID (e.g. `synth:...`). PATCH /messages/<id>/read/ only exists for real
// stored rows, so "Отметить как прочитанное" only shows for
// `_Message.isReal` (type teacher/system) — see [_Message.isReal].
//
// Deliberately NOT built (no real data/endpoint backing them, per this
// codebase's never-fabricate policy): the mockup's "Полезные ссылки" detail
// footer and the list's "Показать ещё" pagination control (the backend
// already returns the full ≤50-row list in one call, so there is nothing to
// page through).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
import '../../core/session/logout.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/student_palette.dart';
import '../../shared/widgets/student_kpi_tile.dart';
import '../../shared/widgets/student_shell.dart' show kStudentBranchPaths;

enum _Filter { all, teacher, tests, system }

enum _Sort { newest, oldest }

class _Message {
  final String id;
  final String type; // teacher | system | test_assigned | test_reviewed
  final String title;
  final String body;
  final bool isRead;
  final DateTime? createdAt;
  final String? relatedTestKey;

  const _Message({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    required this.relatedTestKey,
  });

  /// Only teacher/system rows are real stored `StudentMessage` rows with a
  /// PATCH-able id — test_assigned/test_reviewed are synthesized per-request
  /// and already always read.
  bool get isReal => type == 'teacher' || type == 'system';

  factory _Message.fromJson(Map<String, dynamic> j) => _Message(
        id: j['id']?.toString() ?? '',
        type: j['type']?.toString() ?? 'system',
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        isRead: j['is_read'] == true,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
        relatedTestKey: (j['related_test_key'] as String?)?.trim().isEmpty ==
                true
            ? null
            : j['related_test_key'] as String?,
      );

  _Message copyWith({bool? isRead}) => _Message(
        id: id,
        type: type,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        relatedTestKey: relatedTestKey,
      );
}

class _TypeStyle {
  final IconData icon;
  final Color fg;
  final Color bg;
  final String Function(AppLocalizations) tagLabel;
  const _TypeStyle(this.icon, this.fg, this.bg, this.tagLabel);
}

_TypeStyle _styleFor(String type) {
  switch (type) {
    case 'teacher':
      return _TypeStyle(Icons.person_rounded, AppColors.violet,
          AppColors.violetMuted, (l10n) => l10n.messagesTypeTeacher);
    case 'test_assigned':
      return _TypeStyle(Icons.assignment_rounded, AppColors.success,
          AppColors.successMuted, (l10n) => l10n.messagesTypeTest);
    case 'test_reviewed':
      return _TypeStyle(Icons.check_circle_rounded, AppColors.success,
          AppColors.successMuted, (l10n) => l10n.messagesTypeTest);
    default: // system
      return _TypeStyle(Icons.settings_rounded, AppColors.secondary,
          AppColors.secondaryMuted, (l10n) => l10n.messagesTypeSystem);
  }
}

String _senderLabel(AppLocalizations l10n, String type) {
  switch (type) {
    case 'teacher':
      return l10n.messagesSenderTeacher;
    case 'test_assigned':
    case 'test_reviewed':
      return l10n.messagesSenderTestSystem;
    default:
      return l10n.messagesSenderSystem;
  }
}

String _formatTimestamp(AppLocalizations l10n, DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  final now = DateTime.now();
  final isToday = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday = local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day;
  final time = DateFormat('HH:mm').format(local);
  if (isToday) return '${l10n.messagesToday}, $time';
  if (isYesterday) return '${l10n.messagesYesterday}, $time';
  return '${DateFormat('dd.MM.yyyy').format(local)}, $time';
}

BoxDecoration _cardDecoration(StudentPalette pal) => BoxDecoration(
      color: pal.surface,
      borderRadius: AppRadii.roundedXl,
      border: Border.all(color: pal.border),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3)),
      ],
    );

class StudentMessagesScreen extends StatefulWidget {
  final StudentSession session;
  const StudentMessagesScreen({super.key, required this.session});

  @override
  State<StudentMessagesScreen> createState() => _StudentMessagesScreenState();
}

class _StudentMessagesScreenState extends State<StudentMessagesScreen> {
  bool _loading = true;
  List<_Message>? _messages;
  String? _selectedId;
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.newest;
  String _query = '';
  final Set<String> _pendingReadIds = {};
  final Set<String> _startingKeys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final raw = await api.fetchMessages(authToken: widget.session.token);
    if (!mounted) return;
    setState(() {
      _messages = raw.map(_Message.fromJson).toList();
      _loading = false;
    });
  }

  List<_Message> get _filtered {
    final all = _messages ?? const <_Message>[];
    var list = all.where((m) {
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.teacher:
          return m.type == 'teacher';
        case _Filter.tests:
          return m.type == 'test_assigned' || m.type == 'test_reviewed';
        case _Filter.system:
          return m.type == 'system';
      }
    }).toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((m) =>
              m.title.toLowerCase().contains(q) ||
              m.body.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return _sort == _Sort.newest ? bd.compareTo(ad) : ad.compareTo(bd);
    });
    return list;
  }

  _Message? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final m in _messages ?? const <_Message>[]) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _markRead(_Message m) async {
    if (!m.isReal || m.isRead || _pendingReadIds.contains(m.id)) return;
    setState(() {
      _pendingReadIds.add(m.id);
      _messages = _messages!
          .map((x) => x.id == m.id ? x.copyWith(isRead: true) : x)
          .toList();
    });
    try {
      await api.markMessageRead(
          authToken: widget.session.token, messageId: m.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = _messages!
            .map((x) => x.id == m.id ? x.copyWith(isRead: false) : x)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.messagesMarkReadError),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _pendingReadIds.remove(m.id));
    }
  }

  Future<void> _markAllRead() async {
    final unread =
        (_messages ?? const <_Message>[]).where((m) => m.isReal && !m.isRead);
    for (final m in unread.toList()) {
      await _markRead(m);
    }
  }

  /// Same fetchTest -> pick variant -> clear kiosk session -> push
  /// /engine_host flow as my_tests_screen.dart's `_startTest`.
  Future<void> _goToTest(String testKey) async {
    if (_startingKeys.contains(testKey)) return;
    setState(() => _startingKeys.add(testKey));
    Map<String, dynamic>? data;
    try {
      data = await api.fetchTest(testKey, authToken: widget.session.token);
    } finally {
      if (mounted) setState(() => _startingKeys.remove(testKey));
    }
    if (!mounted) return;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.loadFailed)),
      );
      return;
    }

    final blob = (data['test_data'] is Map)
        ? Map<String, dynamic>.from(data['test_data'] as Map)
        : data;
    final variants = blob['variants'];
    int variant = 1;
    if (variants is Map && variants.isNotEmpty) {
      final keys = variants.keys.map((k) => k.toString()).toList()..shuffle();
      variant = int.tryParse(keys.first) ?? 1;
    }

    final nameParts = widget.session.studentName.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    await clearStudentSession();
    if (!mounted) return;
    await GoRouter.of(context).push('/engine_host', extra: {
      'testData': data,
      'variant': variant,
      'firstName': firstName,
      'lastName': lastName,
      'school': widget.session.schoolCode,
      'group': widget.session.groupName,
      'grade': widget.session.grade,
      'studentId': widget.session.studentId,
    });
    if (!mounted) return;
    goToLoginReplacingStack(context);
  }

  void _goToSettings() {
    StatefulNavigationShell.of(context)
        .goBranch(kStudentBranchPaths.indexOf('/settings'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: pal.ink3, size: 28),
            const SizedBox(height: 12),
            Text(l10n.loadFailed,
                style: AppTextStyles.bodyMedium.copyWith(color: pal.ink2)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: Text(l10n.retryCheck)),
          ],
        ),
      );
    }

    final all = _messages!;
    final unreadCount = all.where((m) => !m.isRead).length;
    final newTestsCount = all.where((m) => m.type == 'test_assigned').length;
    final reviewedCount = all.where((m) => m.type == 'test_reviewed').length;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Banner(unreadCount: unreadCount, newTestsCount: newTestsCount, reviewedCount: reviewedCount),
            const SizedBox(height: 16),
            _FilterBar(
              filter: _filter,
              sort: _sort,
              onFilterChanged: (v) => setState(() => _filter = v),
              onQueryChanged: (v) => setState(() => _query = v),
              onSortChanged: (v) => setState(() => _sort = v),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1100;
              final medium = constraints.maxWidth >= 760;
              final list = _MessageList(
                messages: _filtered,
                selectedId: _selectedId,
                onSelect: (m) {
                  setState(() => _selectedId = m.id);
                  _markRead(m); // opening a message marks it read, same as the mockup's selected row already showing read state
                },
              );
              final detail = _DetailPane(
                message: _selected,
                starting: _selected != null && _startingKeys.contains(_selected!.relatedTestKey),
                onGoToTest: _selected?.relatedTestKey != null
                    ? () => _goToTest(_selected!.relatedTestKey!)
                    : null,
                onMarkRead: _selected != null && _selected!.isReal && !_selected!.isRead
                    ? () => _markRead(_selected!)
                    : null,
              );
              final quickActions = _QuickActionsPanel(
                systemUnreadCount:
                    all.where((m) => m.type == 'system' && !m.isRead).length,
                onMarkAllRead: _markAllRead,
                onNotificationSettings: _goToSettings,
              );

              if (!medium) {
                return Column(children: [
                  SizedBox(height: 420, child: list),
                  const SizedBox(height: 16),
                  detail,
                  const SizedBox(height: 16),
                  quickActions,
                ]);
              }
              if (!wide) {
                return SizedBox(
                  height: 620,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 2, child: list),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: detail),
                    ],
                  ),
                );
              }
              return SizedBox(
                height: 620,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: list),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: detail),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: quickActions),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final int unreadCount;
  final int newTestsCount;
  final int reviewedCount;
  const _Banner(
      {required this.unreadCount,
      required this.newTestsCount,
      required this.reviewedCount});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.secondaryMuted,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: AppColors.amberBorder),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.mark_email_unread_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.messagesBannerTitle,
                        style: AppTextStyles.titleMedium
                            .copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(l10n.messagesBannerSubtitle,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.ink2)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(
            width: 220,
            child: KpiTile(
              icon: Icons.mail_rounded,
              iconColor: AppColors.violet,
              iconBg: AppColors.violetMuted,
              label: l10n.messagesKpiUnreadLabel,
              value: '$unreadCount',
            ),
          ),
          SizedBox(
            width: 220,
            child: KpiTile(
              icon: Icons.assignment_rounded,
              iconColor: AppColors.success,
              iconBg: AppColors.successMuted,
              label: l10n.messagesKpiNewTestsLabel,
              value: '$newTestsCount',
            ),
          ),
          SizedBox(
            width: 220,
            child: KpiTile(
              icon: Icons.verified_rounded,
              iconColor: AppColors.amberDark,
              iconBg: AppColors.amberBorder,
              label: l10n.messagesKpiReviewedLabel,
              value: '$reviewedCount',
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final _Filter filter;
  final _Sort sort;
  final ValueChanged<_Filter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_Sort> onSortChanged;

  const _FilterBar({
    required this.filter,
    required this.sort,
    required this.onFilterChanged,
    required this.onQueryChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final tabs = <_Filter, String>{
      _Filter.all: l10n.messagesFilterAll,
      _Filter.teacher: l10n.messagesFilterTeacher,
      _Filter.tests: l10n.messagesFilterTests,
      _Filter.system: l10n.messagesFilterSystem,
    };
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final e in tabs.entries) _tab(pal, e.key, e.value),
        SizedBox(
          width: 240,
          height: 42,
          child: TextField(
            onChanged: onQueryChanged,
            style: AppTextStyles.bodyMedium.copyWith(color: pal.ink1),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: pal.ink3),
              hintText: l10n.messagesSearchHint,
              hintStyle: AppTextStyles.bodyMedium.copyWith(color: pal.ink3),
              filled: true,
              fillColor: pal.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: pal.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: pal.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.secondary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: pal.border),
          ),
          alignment: Alignment.center,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<_Sort>(
              value: sort,
              isDense: true,
              icon: Icon(Icons.unfold_more_rounded, size: 16, color: pal.ink3),
              style: AppTextStyles.labelMedium.copyWith(color: pal.ink1),
              dropdownColor: pal.surface,
              items: [
                DropdownMenuItem(value: _Sort.newest, child: Text(l10n.sortNewestFirst)),
                DropdownMenuItem(value: _Sort.oldest, child: Text(l10n.sortOldestFirst)),
              ],
              onChanged: (v) {
                if (v != null) onSortChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _tab(StudentPalette pal, _Filter value, String label) {
    final active = filter == value;
    return GestureDetector(
      onTap: () => onFilterChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.secondaryMuted : pal.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.secondary : pal.border),
        ),
        child: Text(label,
            style: AppTextStyles.labelMedium.copyWith(
                color: active ? AppColors.secondary : pal.ink2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<_Message> messages;
  final String? selectedId;
  final ValueChanged<_Message> onSelect;
  const _MessageList(
      {required this.messages, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Container(
      decoration: _cardDecoration(pal),
      clipBehavior: Clip.antiAlias,
      child: messages.isEmpty
          ? Center(
              child: Text(l10n.messagesEmptyListTitle,
                  style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: messages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final m = messages[i];
                final style = _styleFor(m.type);
                final selected = m.id == selectedId;
                return InkWell(
                  onTap: () => onSelect(m),
                  borderRadius: AppRadii.roundedMd,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.secondaryMuted : Colors.transparent,
                      borderRadius: AppRadii.roundedMd,
                      border: selected
                          ? Border.all(color: AppColors.secondary.withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: style.bg, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Icon(style.icon, color: style.fg, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(m.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.bodyLarge.copyWith(
                                            color: pal.ink1,
                                            fontWeight:
                                                m.isRead ? FontWeight.w600 : FontWeight.w800)),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(_formatTimestamp(l10n, m.createdAt),
                                      style: AppTextStyles.caption.copyWith(color: pal.ink3)),
                                  if (!m.isRead) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                          color: AppColors.secondary, shape: BoxShape.circle),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(m.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyMedium.copyWith(color: pal.ink2)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: style.bg, borderRadius: AppRadii.roundedFull),
                                child: Text(style.tagLabel(l10n),
                                    style: AppTextStyles.caption
                                        .copyWith(color: style.fg, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _DetailPane extends StatelessWidget {
  final _Message? message;
  final bool starting;
  final VoidCallback? onGoToTest;
  final VoidCallback? onMarkRead;
  const _DetailPane(
      {required this.message,
      required this.starting,
      required this.onGoToTest,
      required this.onMarkRead});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final m = message;
    if (m == null) {
      return Container(
        decoration: _cardDecoration(pal),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_outlined, color: pal.ink3, size: 40),
            const SizedBox(height: 12),
            Text(l10n.messagesNoSelectionTitle,
                style: AppTextStyles.titleMedium.copyWith(color: pal.ink1)),
            const SizedBox(height: 6),
            Text(l10n.messagesNoSelectionSubtitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3)),
          ],
        ),
      );
    }
    final style = _styleFor(m.type);
    return Container(
      decoration: _cardDecoration(pal),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: style.bg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(style.icon, color: style.fg, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title,
                          style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(_formatTimestamp(l10n, m.createdAt),
                          style: AppTextStyles.caption.copyWith(color: pal.ink3)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('${l10n.messagesSenderLabel}: ',
                    style: AppTextStyles.labelMedium.copyWith(color: pal.ink3)),
                Text(_senderLabel(l10n, m.type),
                    style: AppTextStyles.labelMedium.copyWith(color: pal.ink2)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration:
                      BoxDecoration(color: style.bg, borderRadius: AppRadii.roundedFull),
                  child: Text(style.tagLabel(l10n),
                      style: AppTextStyles.caption
                          .copyWith(color: style.fg, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(m.body, style: AppTextStyles.bodyLarge.copyWith(color: pal.ink1, height: 1.6)),
            if (m.type == 'test_assigned') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: AppColors.successMuted,
                  borderRadius: AppRadii.roundedMd,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_rounded, color: AppColors.success, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(l10n.messagesTipAssigned,
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (onGoToTest != null)
                  FilledButton.icon(
                    onPressed: starting ? null : onGoToTest,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
                    icon: starting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(l10n.messagesGoToTestButton),
                  ),
                if (onMarkRead != null)
                  OutlinedButton(
                    onPressed: onMarkRead,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.secondary,
                        side: const BorderSide(color: AppColors.secondary)),
                    child: Text(l10n.messagesMarkReadButton),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsPanel extends StatelessWidget {
  final int systemUnreadCount;
  final VoidCallback onMarkAllRead;
  final VoidCallback onNotificationSettings;
  const _QuickActionsPanel({
    required this.systemUnreadCount,
    required this.onMarkAllRead,
    required this.onNotificationSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: _cardDecoration(pal),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.messagesQuickActionsTitle,
                  style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _actionRow(pal, Icons.mark_email_read_rounded, AppColors.secondary,
                  l10n.messagesMarkAllReadTitle, l10n.messagesMarkAllReadSubtitle, onMarkAllRead),
              const SizedBox(height: 10),
              _actionRow(pal, Icons.notifications_active_rounded, AppColors.violet,
                  l10n.messagesNotificationSettingsTitle,
                  l10n.messagesNotificationSettingsSubtitle, onNotificationSettings),
              const SizedBox(height: 10),
              _actionRow(
                  pal,
                  Icons.archive_rounded,
                  AppColors.blue,
                  l10n.messagesArchiveTitle,
                  l10n.messagesArchiveSubtitle,
                  () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.comingSoon)))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: _cardDecoration(pal),
          padding: const EdgeInsets.all(20),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, color: pal.ink3, size: 36),
              const SizedBox(height: 10),
              Text(
                  systemUnreadCount > 0
                      ? l10n.messagesSystemUnreadCount(systemUnreadCount)
                      : l10n.messagesSystemEmptyTitle,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge.copyWith(color: pal.ink1, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(l10n.messagesSystemEmptySubtitle,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(color: pal.ink3)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionRow(StudentPalette pal, IconData icon, Color color, String title,
      String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.roundedMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTextStyles.labelLarge.copyWith(color: pal.ink1)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(color: pal.ink3)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: pal.ink3, size: 18),
          ],
        ),
      ),
    );
  }
}
