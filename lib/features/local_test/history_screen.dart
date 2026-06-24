import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/db/history_db.dart';
import '../../shared/theme/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await HistoryDb.getHistory();
    if (mounted) {
      setState(() {
        _records = res;
        _loading = false;
      });
    }
  }

  Future<void> _clear() async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Tozalash', style: TextStyle(color: AppColors.ink1)),
        content: const Text("Barcha natijalar tarixi o'chirib yuborilsinmi?",
            style: TextStyle(color: AppColors.ink2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child:
                  const Text("Yo'q", style: TextStyle(color: AppColors.ink3))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text("Ha, o'chirish",
                  style: TextStyle(color: AppColors.err))),
        ],
      ),
    );
    if (conf == true) {
      setState(() => _loading = true);
      await HistoryDb.clearHistory();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        title: const Text('Oflayn Natijalar Tarixi',
            style: TextStyle(
                color: AppColors.ink1,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.ink1),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.err),
              tooltip: 'Tozalash',
              onPressed: _clear,
            )
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brand))
          : _records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_toggle_off_rounded,
                          size: 64,
                          color: AppColors.ink3.withValues(alpha: .5)),
                      const SizedBox(height: 16),
                      const Text("Hozircha tarix yo'q",
                          style:
                              TextStyle(color: AppColors.ink2, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final r = _records[i];
                    final date = DateTime.fromMillisecondsSinceEpoch(
                        r['date_taken'] as int);
                    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(date);
                    final pct = r['total_pct'] as double;
                    final isPass = pct >= 60.0;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: isPass
                                  ? AppColors.ok.withValues(alpha: .1)
                                  : AppColors.err.withValues(alpha: .1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${pct.toInt()}%',
                                style: TextStyle(
                                  color: isPass ? AppColors.ok : AppColors.err,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${r['first_name']} ${r['last_name']}',
                                    style: const TextStyle(
                                        color: AppColors.ink1,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                    'Maktab: ${r['school']} | Sinf/Guruh: ${r['grade_group']}',
                                    style: const TextStyle(
                                        color: AppColors.ink2, fontSize: 12)),
                                const SizedBox(height: 2),
                                Text('Sana: $dateStr',
                                    style: const TextStyle(
                                        color: AppColors.ink3, fontSize: 11)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Mat: ${r['math_score']}',
                                  style: const TextStyle(
                                      color: AppColors.brand,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              Text('Ing: ${r['eng_score']}',
                                  style: const TextStyle(
                                      color: AppColors.ok,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
