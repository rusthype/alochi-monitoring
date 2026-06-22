// lib/features/test/confirm_screen.dart
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import 'test_screen.dart';

class ConfirmScreen extends StatefulWidget {
  final StudentSession session;
  final TestPackage package;
  const ConfirmScreen(
      {super.key, required this.session, required this.package});
  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _start() async {
    final variant = widget.session.variant;
    if (variant == null) {
      setState(() => _error = 'Faol imtihon topilmadi yoki muddati tugagan');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final questions = await api.getQuestions(widget.package.id, variant);
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => TestScreen(
                  session: widget.session,
                  package: widget.package,
                  questions: questions)));
    } on ApiException catch (e) {
      setState(() {
        _error = e.statusCode == 403
            ? 'Faol imtihon topilmadi yoki muddati tugagan'
            : e.message;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Yuklanmadi. Qayta urinib ko\'ring.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final p = widget.package;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.brandLight,
                    child: Text(
                        s.studentName.isNotEmpty ? s.studentName[0] : 'T',
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brand)),
                  ),
                  const SizedBox(height: 16),
                  const Text("Salom!", style: TextStyle(color: AppColors.ink2)),
                  const SizedBox(height: 4),
                  Text(s.studentName,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (s.grade != null)
                          _chip('${s.grade}-sinf', Icons.school_outlined),
                        if (s.variant != null)
                          _chip('Variant ${s.variant}', Icons.numbers_outlined),
                        if (s.groupName != null)
                          _chip(s.groupName!, Icons.group_outlined),
                      ]),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(children: [
                      Text(p.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 14),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _stat(
                                '${p.mathCount}', 'Matematika', AppColors.math),
                            Container(
                                width: 1, height: 36, color: AppColors.border),
                            _stat(
                                '${p.engCount}', 'Ingliz tili', AppColors.eng),
                            Container(
                                width: 1, height: 36, color: AppColors.border),
                            _stat('${p.totalCount}', 'Jami', AppColors.brand),
                          ]),
                    ]),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style:
                            const TextStyle(color: AppColors.err, fontSize: 13),
                        textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _start,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow),
                    label: const Text('Testni boshlash'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Orqaga',
                        style: TextStyle(color: AppColors.ink2)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.ink2),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ]),
      );

  Widget _stat(String val, String label, Color color) => Column(children: [
        Text(val,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.ink2)),
      ]);
}
