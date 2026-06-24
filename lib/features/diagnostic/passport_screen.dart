// lib/features/diagnostic/passport_screen.dart
// Diagnostik pasport natijasi: umumiy%, fan doiralari, bo'lim diagrammalari,
// ota-ona/o'qituvchi tavsiyalari, PDF tugmasi.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../core/engine/test_scorer.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/pdf_tips.dart';
import '../../shared/theme/app_theme.dart';

const Color _kTeal = Color(0xFF1F6F65);

class PassportScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String school;
  final String? group;
  final int grade;
  final int variant;
  final ScoredResult mathResult;
  final ScoredResult engResult;
  // 'sent' | 'queued' | 'error'
  final String submitStatus;

  const PassportScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.school,
    this.group,
    required this.grade,
    required this.variant,
    required this.mathResult,
    required this.engResult,
    this.submitStatus = 'queued',
  });

  @override
  State<PassportScreen> createState() => _PassportScreenState();
}

class _PassportScreenState extends State<PassportScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  bool _pdfGenerating = false;
  String? _pdfPath;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  int get _mathCor => widget.mathResult.totalCorrect;
  int get _mathTot => widget.mathResult.totalQuestions;
  int get _engCor => widget.engResult.totalCorrect;
  int get _engTot => widget.engResult.totalQuestions;
  int get _totalCor => _mathCor + _engCor;
  int get _totalTot => _mathTot + _engTot;
  double get _totalPct => _totalTot > 0 ? _totalCor * 100.0 / _totalTot : 0.0;
  double get _mathPct => _mathTot > 0 ? _mathCor * 100.0 / _mathTot : 0.0;
  double get _engPct => _engTot > 0 ? _engCor * 100.0 / _engTot : 0.0;

  Color _scoreColor(double pct) {
    if (pct >= 80) return AppColors.ok;
    if (pct >= 55) return const Color(0xFFD97706);
    return AppColors.err;
  }

  String _scoreLabel(double pct) {
    if (pct >= 80) return 'A\'lo';
    if (pct >= 60) return 'Yaxshi';
    if (pct >= 40) return "Qoniqarli";
    return "Qoniqarsiz";
  }

  Future<void> _generatePdf() async {
    if (_pdfGenerating) return;
    setState(() => _pdfGenerating = true);
    try {
      final mathTopics = widget.mathResult.sectionScores
          .map((s) => MapEntry(s.name, (ok: s.correct, tot: s.total)))
          .toList();
      final engTopics = widget.engResult.sectionScores
          .map((s) => MapEntry(s.name, (ok: s.correct, tot: s.total)))
          .toList();

      final bytes = await PdfService.generatePassportPdf(
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: widget.school,
        group: widget.group ?? '',
        grade: widget.grade,
        variant: widget.variant,
        mathOk: _mathCor,
        mathTotal: _mathTot,
        engOk: _engCor,
        engTotal: _engTot,
        totalPct: _totalPct.round(),
        mathTopics: mathTopics,
        engTopics: engTopics,
      );

      if (kIsWeb) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'passport_${widget.lastName}_${widget.firstName}.pdf',
        );
      } else {
        final dir = await getApplicationSupportDirectory();
        final path =
            '${dir.path}/passport_${widget.firstName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await File(path).writeAsBytes(bytes);
        if (mounted) setState(() => _pdfPath = path);
        await OpenFilex.open(path);
      }
    } catch (e) {
      debugPrint('PassportScreen._generatePdf error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF yaratishda xato'),
            backgroundColor: AppColors.err,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pdfGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: _kTeal,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Diagnostik Pasport',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
      body: FadeTransition(
        opacity: _fade,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StudentCard(
                firstName: widget.firstName,
                lastName: widget.lastName,
                school: widget.school,
                grade: widget.grade,
                variant: widget.variant,
                scoreLabel: _scoreLabel(_totalPct),
                scoreColor: _scoreColor(_totalPct),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _SubmitStatusChip(status: widget.submitStatus),
              ),
              const SizedBox(height: 12),
              _ScoreRingsCard(
                totalPct: _totalPct,
                mathPct: _mathPct,
                engPct: _engPct,
                mathCor: _mathCor,
                mathTot: _mathTot,
                engCor: _engCor,
                engTot: _engTot,
              ),
              const SizedBox(height: 16),
              _SectionBarsCard(
                title: 'Matematika bo\'limlari',
                color: AppColors.math,
                icon: Icons.calculate_rounded,
                sections: widget.mathResult.sectionScores,
              ),
              const SizedBox(height: 12),
              _SectionBarsCard(
                title: 'Ingliz tili bo\'limlari',
                color: AppColors.eng,
                icon: Icons.translate_rounded,
                sections: widget.engResult.sectionScores,
              ),
              const SizedBox(height: 16),
              _RecommendationsCard(
                mathPct: _mathPct / 100,
                engPct: _engPct / 100,
                totalPct: _totalPct.round(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pdfGenerating ? null : _generatePdf,
                      icon: _pdfGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded, size: 20),
                      label: Text(_pdfPath != null ? 'PDF qayta' : 'PDF saqlash'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kTeal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
                      icon: const Icon(Icons.home_rounded, size: 20),
                      label: const Text('Bosh sahifa'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTeal,
                        side: const BorderSide(color: _kTeal, width: 1.5),
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Student header card ───────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final String firstName;
  final String lastName;
  final String school;
  final int grade;
  final int variant;
  final String scoreLabel;
  final Color scoreColor;

  const _StudentCard({
    required this.firstName,
    required this.lastName,
    required this.school,
    required this.grade,
    required this.variant,
    required this.scoreLabel,
    required this.scoreColor,
  });

  @override
  Widget build(BuildContext context) {
    final initials =
        '${lastName.isNotEmpty ? lastName[0] : '?'}${firstName.isNotEmpty ? firstName[0] : ''}';
    final dateStr = _fmtDate(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F2937), Color(0xFF2D3748)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.brand,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: .25), width: 2.5),
              boxShadow: [
                BoxShadow(
                    color: AppColors.brand.withValues(alpha: .5),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Center(
              child: Text(
                initials.toUpperCase(),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$lastName $firstName',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _MetaChip(icon: Icons.school_rounded, label: '$grade-sinf'),
                    _MetaChip(icon: Icons.pin_rounded, label: 'V$variant'),
                    _MetaChip(
                        icon: Icons.calendar_today_rounded, label: dateStr),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scoreColor.withValues(alpha: .5)),
            ),
            child: Text(
              scoreLabel,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scoreColor.withValues(alpha: .9)),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: Colors.white.withValues(alpha: .6)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: .65),
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ── Score rings card ──────────────────────────────────────────────────────────

class _ScoreRingsCard extends StatelessWidget {
  final double totalPct;
  final double mathPct;
  final double engPct;
  final int mathCor;
  final int mathTot;
  final int engCor;
  final int engTot;

  const _ScoreRingsCard({
    required this.totalPct,
    required this.mathPct,
    required this.engPct,
    required this.mathCor,
    required this.mathTot,
    required this.engCor,
    required this.engTot,
  });

  Color _color(double pct) {
    if (pct >= 80) return AppColors.ok;
    if (pct >= 55) return const Color(0xFFD97706);
    return AppColors.err;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Text(
            'Umumiy natija',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2,
                letterSpacing: .5),
          ),
          const SizedBox(height: 16),
          // Big ring
          _Ring(
            pct: totalPct,
            size: 140,
            strokeWidth: 12,
            color: _color(totalPct),
            label: '${totalPct.round()}%',
            sublabel: '${mathCor + engCor}/${mathTot + engTot}',
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _FanRing(
                label: 'Matematika',
                pct: mathPct,
                cor: mathCor,
                tot: mathTot,
                color: AppColors.math,
                icon: Icons.calculate_rounded,
              ),
              Container(width: 1, height: 60, color: AppColors.border),
              _FanRing(
                label: 'Ingliz tili',
                pct: engPct,
                cor: engCor,
                tot: engTot,
                color: AppColors.eng,
                icon: Icons.translate_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double pct;
  final double size;
  final double strokeWidth;
  final Color color;
  final String label;
  final String sublabel;

  const _Ring({
    required this.pct,
    required this.size,
    required this.strokeWidth,
    required this.color,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: pct / 100),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: strokeWidth,
                backgroundColor: AppColors.gray100,
                color: color,
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      fontSize: size * 0.18,
                      fontWeight: FontWeight.w900,
                      color: color),
                ),
                Text(sublabel,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.ink2)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FanRing extends StatelessWidget {
  final String label;
  final double pct;
  final int cor;
  final int tot;
  final Color color;
  final IconData icon;

  const _FanRing({
    required this.label,
    required this.pct,
    required this.cor,
    required this.tot,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Ring(
          pct: pct,
          size: 80,
          strokeWidth: 7,
          color: color,
          label: '${pct.round()}%',
          sublabel: '$cor/$tot',
        ),
        const SizedBox(height: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      ],
    );
  }
}

// ── Section bars card ─────────────────────────────────────────────────────────

class _SectionBarsCard extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<SectionScore> sections;

  const _SectionBarsCard({
    required this.title,
    required this.color,
    required this.icon,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ]),
          if (sections.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...sections.map((s) => _SectionBar(section: s, color: color)),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Ma\'lumot yo\'q',
                  style: TextStyle(color: AppColors.ink3, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class _SectionBar extends StatelessWidget {
  final SectionScore section;
  final Color color;

  const _SectionBar({required this.section, required this.color});

  Color _barColor(double pct) {
    if (pct >= 75) return AppColors.ok;
    if (pct >= 50) return const Color(0xFFD97706);
    return AppColors.err;
  }

  @override
  Widget build(BuildContext context) {
    final pct = section.pct;
    final barColor = _barColor(pct);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  section.name,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink1),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${section.correct}/${section.total}',
                style: const TextStyle(fontSize: 11, color: AppColors.ink2),
              ),
              const SizedBox(width: 6),
              Text(
                '${pct.round()}%',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: barColor),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 7,
              backgroundColor: AppColors.gray100,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recommendations card ──────────────────────────────────────────────────────

class _RecommendationsCard extends StatelessWidget {
  final double mathPct;
  final double engPct;
  final int totalPct;

  const _RecommendationsCard({
    required this.mathPct,
    required this.engPct,
    required this.totalPct,
  });

  @override
  Widget build(BuildContext context) {
    final mathTips = PdfTips.mathTips(mathPct);
    final engTips = PdfTips.englishTips(engPct);
    final overallMsg = PdfTips.overallStatus(totalPct);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lightbulb_outline_rounded,
                size: 16, color: AppColors.brand),
            SizedBox(width: 8),
            Text('Tavsiyalar',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink1)),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TipsColumn(
                  label: 'Matematika',
                  color: AppColors.math,
                  tips: mathTips,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TipsColumn(
                  label: 'Ingliz tili',
                  color: AppColors.eng,
                  tips: engTips,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  totalPct >= 75 ? AppColors.successMuted : AppColors.warnMuted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: totalPct >= 75
                      ? AppColors.ok.withValues(alpha: .4)
                      : const Color(0xFFD97706).withValues(alpha: .4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  totalPct >= 75
                      ? Icons.check_circle_outline_rounded
                      : Icons.trending_up_rounded,
                  size: 18,
                  color:
                      totalPct >= 75 ? AppColors.ok : const Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    overallMsg,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Submit status chip ────────────────────────────────────────────────────────

class _SubmitStatusChip extends StatelessWidget {
  final String status;
  const _SubmitStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;
    if (status == 'sent') {
      bg = AppColors.successMuted;
      fg = AppColors.ok;
      icon = Icons.check_circle_outline_rounded;
      label = 'Natija serverga yuborildi';
    } else if (status == 'error') {
      bg = AppColors.errMuted;
      fg = AppColors.err;
      icon = Icons.error_outline_rounded;
      label = 'Natija yuborilmadi';
    } else {
      bg = const Color(0xFFFFFBEB);
      fg = const Color(0xFFD97706);
      icon = Icons.cloud_upload_outlined;
      label = 'Internet ulanganda yuboriladi';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

class _TipsColumn extends StatelessWidget {
  final String label;
  final Color color;
  final List<String> tips;

  const _TipsColumn({
    required this.label,
    required this.color,
    required this.tips,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 8),
        ...tips.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.arrow_right_rounded,
                    size: 16, color: color.withValues(alpha: .6)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    t,
                    style: const TextStyle(fontSize: 11, color: AppColors.ink2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
