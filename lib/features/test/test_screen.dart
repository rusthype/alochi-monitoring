// lib/features/test/test_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../result/result_screen.dart';

class TestScreen extends StatefulWidget {
  final StudentSession session;
  final TestPackage package;
  final List<Question> questions;
  const TestScreen({super.key, required this.session, required this.package, required this.questions});
  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  int _current = 0;
  final Map<int, String> _answers = {};
  bool _submitting = false;

  Question get _q => widget.questions[_current];
  int get _total   => widget.questions.length;
  bool get _isLast => _current == _total - 1;

  void _answer(String choice) {
    setState(() {
      _answers[_current] = choice;
      if (!_isLast) Future.delayed(const Duration(milliseconds: 280), () {
        if (mounted) setState(() => _current++);
      });
    });
  }

  Future<void> _finish() async {
    setState(() => _submitting = true);
    final answered = _answers.length;
    int mathAns = 0, engAns = 0;
    for (int i = 0; i < widget.questions.length; i++) {
      if (!_answers.containsKey(i)) continue;
      if (widget.questions[i].isMath) mathAns++; else engAns++;
    }

    final answersMap = <String, String>{};
    for (int i = 0; i < widget.questions.length; i++) {
      if (_answers.containsKey(i)) answersMap[widget.questions[i].id] = _answers[i]!;
    }

    final result = TestResult(
      packageId: widget.package.id,
      variant:   widget.session.variant,
      mathScore: mathAns,
      engScore:  engAns,
      totalPct:  _total > 0 ? (answered * 100 ~/ _total) : 0,
      answers:   answersMap,
      deviceId:  Platform.isWindows ? 'flutter-windows' : Platform.isMacOS ? 'flutter-mac' : 'flutter-linux',
    );

    final synced = await api.submitResult(result);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => ResultScreen(session: widget.session, package: widget.package, result: result, synced: synced)));
  }

  @override
  Widget build(BuildContext context) {
    final mathCount   = widget.questions.where((q) => q.isMath).length;
    final isMath      = _q.isMath;
    final sectionList = widget.questions.where((q) => q.isMath == isMath).toList();
    final sectionIdx  = sectionList.indexOf(_q) + 1;
    final sectionColor = isMath ? AppColors.math : AppColors.eng;
    final sectionLabel = isMath ? 'Matematika' : 'Ingliz tili';

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyA): () => _answer('a'),
          const SingleActivator(LogicalKeyboardKey.keyB): () => _answer('b'),
          const SingleActivator(LogicalKeyboardKey.keyC): () => _answer('c'),
          const SingleActivator(LogicalKeyboardKey.keyD): () => _answer('d'),
          const SingleActivator(LogicalKeyboardKey.arrowLeft):  () { if (_current > 0) setState(() => _current--); },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () { if (!_isLast) setState(() => _current++); },
        },
        child: Focus(
          autofocus: true,
          child: Column(children: [
            // Topbar
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: sectionColor, borderRadius: BorderRadius.circular(20)),
                  child: Text('$sectionIdx / ${sectionList.length}  $sectionLabel',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const Spacer(),
                Text('${_answers.length} / $_total', style: const TextStyle(color: AppColors.ink2, fontSize: 13)),
                const SizedBox(width: 16),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(120, 40),
                      backgroundColor: _answers.length == _total ? AppColors.brand : AppColors.ink3,
                    ),
                    onPressed: _submitting ? null : _finish,
                    child: _submitting
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Tugatish'),
                  ),
                ),
              ]),
            ),
            LinearProgressIndicator(
              value: _answers.length / _total,
              backgroundColor: AppColors.border,
              color: AppColors.brand,
              minHeight: 3,
            ),
            Expanded(child: Row(children: [
              // Dots sidebar
              Container(
                width: 200,
                color: AppColors.bg,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _section('Matematika', AppColors.math, 0, mathCount),
                    const SizedBox(height: 16),
                    _section('Ingliz tili', AppColors.eng, mathCount, _total),
                  ]),
                ),
              ),
              // Question
              Expanded(child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_current + 1}-savol', style: const TextStyle(color: AppColors.ink2, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Text(_q.prompt, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
                      if (_q.image != null && _q.image!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            _q.image!.startsWith('http') ? _q.image! : 'https://api.alochi.org${_q.image}',
                            height: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            loadingBuilder: (_, child, prog) => prog == null ? child
                              : SizedBox(height: 220, child: Center(
                                  child: CircularProgressIndicator(
                                    value: prog.expectedTotalBytes != null
                                        ? prog.cumulativeBytesLoaded / prog.expectedTotalBytes!
                                        : null,
                                    color: AppColors.brand,
                                  ))),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      ...List.generate(4, (i) {
                        final char = ['a','b','c','d'][i];
                        final sel  = _answers[_current] == char;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: sel ? AppColors.brand : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => _answer(char),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border.all(color: sel ? AppColors.brand : AppColors.border, width: sel ? 2 : 1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 30, height: 30,
                                    decoration: BoxDecoration(
                                      color: sel ? Colors.white.withValues(alpha: .2) : AppColors.brandLight,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(child: Text(char.toUpperCase(),
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                                            color: sel ? Colors.white : AppColors.brand))),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(child: Text(_q.options[i],
                                      style: TextStyle(fontSize: 15, color: sel ? Colors.white : AppColors.ink1))),
                                ]),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        TextButton.icon(
                          onPressed: _current > 0 ? () => setState(() => _current--) : null,
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Oldingi'),
                          style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
                        ),
                        TextButton.icon(
                          onPressed: !_isLast ? () => setState(() => _current++) : null,
                          icon: const Text('Keyingi'),
                          label: const Icon(Icons.arrow_forward, size: 18),
                          style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
                        ),
                      ]),
                    ]),
                  ),
                ),
              )),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _section(String label, Color color, int from, int to) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 8),
      Wrap(spacing: 4, runSpacing: 4, children: [
        for (int i = from; i < to; i++)
          GestureDetector(
            onTap: () => setState(() => _current = i),
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: i == _current ? AppColors.brand
                     : _answers.containsKey(i) ? AppColors.ok.withValues(alpha: .15) : AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: i == _current ? AppColors.brand
                       : _answers.containsKey(i) ? AppColors.ok : AppColors.border,
                ),
              ),
              child: Center(child: Text('${i + 1}',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                      color: i == _current ? Colors.white
                           : _answers.containsKey(i) ? AppColors.ok : AppColors.ink3))),
            ),
          ),
      ]),
    ],
  );
}
