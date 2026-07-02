// lib/features/combined/combined_screen.dart
// Combined Monitoring Test — Math (30) + English Unit 1 (49) = 79 questions
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../bob14/bob14_data.dart';
import '../unit1/unit1_data.dart';
import 'combined_runner.dart';

// Purple accent for the combined test (distinct from blue/green)
const Color _kPurple = Color(0xFF7C3AED);
const Color _kPurpleDark = Color(0xFF5B21B6);
const Color _kPurpleBannerTitle = Color(0xFF3B0764);
const Color _kPurpleBannerSub = Color(0xFF6D28D9);

class CombinedScreen extends StatefulWidget {
  const CombinedScreen({super.key});

  @override
  State<CombinedScreen> createState() => _CombinedScreenState();
}

class _CombinedScreenState extends State<CombinedScreen>
    with SingleTickerProviderStateMixin {
  int? _variant;
  int _step = 0; // 0=variant grid, 1=student info

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _err;

  late final AnimationController _animCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _schoolCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _goStep(int s) {
    _animCtrl.forward(from: 0);
    setState(() {
      _step = s;
      _err = null;
    });
  }

  Future<void> _startTest() async {
    final l10n = AppLocalizations.of(context)!;
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _err = l10n.enterFirstAndLastName);
      return;
    }
    if (_passCtrl.text.trim() != '1234') {
      setState(() => _err = l10n.incorrectPassword);
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      // Load both data sources in parallel
      final results = await Future.wait([
        Bob14Loader.getResolved(_variant!),
        Unit1Loader.loadResolved(),
      ]);
      if (!mounted) return;
      final mathQuestions = results[0] as List;
      final testData = results[1] as Unit1TestData;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CombinedRunner(
              firstName: first,
              lastName: last,
              school: _schoolCtrl.text.trim(),
              variant: _variant!,
              mathQuestions: mathQuestions.cast(),
              testData: testData,
            ),
          ));
    } catch (e) {
      if (!mounted) return;
      final l10nFallback = AppLocalizations.of(context)!;
      setState(() {
        _err = l10nFallback.errorPrefix(e.toString());
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.ink1),
                onPressed: () => _goStep(0))
            : IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.ink2),
                onPressed: () => Navigator.pop(context)),
        title: Text(
            _step == 0 ? l10n.selectVariant : l10n.studentInfoTitle,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink1)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _CombinedHeader(variant: _variant),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fade,
        child: _step == 0 ? _buildVariant(l10n) : _buildStudent(l10n),
      ),
    );
  }

  // ── Step 0: Variant 1-15 ──────────────────────────────────────────────────
  Widget _buildVariant(AppLocalizations l10n) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Info banner
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kPurple.withValues(alpha: .25)),
              ),
              child: Row(children: [
                const Icon(Icons.menu_book_rounded, color: _kPurple, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(l10n.monitoringTestUnit1,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: _kPurpleBannerTitle)),
                      const SizedBox(height: 2),
                      Text(l10n.combinedTestInfo,
                          style: const TextStyle(
                              fontSize: 11, color: _kPurpleBannerSub)),
                      const SizedBox(height: 2),
                      Text(l10n.combinedTestSubjects,
                          style: const TextStyle(
                              fontSize: 10,
                              color: _kPurpleBannerSub)),
                    ])),
              ]),
            ),
            const SizedBox(height: 20),
            Text(l10n.selectVariant,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink2)),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
              children: List.generate(15, (i) {
                final v = i + 1;
                final sel = _variant == v;
                return GestureDetector(
                  onTap: () => setState(() => _variant = v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: sel ? _kPurple : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel ? _kPurple : AppColors.border,
                          width: sel ? 2 : 1.5),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                  color: _kPurple.withValues(alpha: .25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3))
                            ]
                          : null,
                    ),
                    child: Center(
                        child: Text('$v',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color:
                                    sel ? Colors.white : AppColors.ink2))),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _variant == null ? null : () => _goStep(1),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(l10n.continueButton,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPurple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.border,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Step 1: Student Info ──────────────────────────────────────────────────
  Widget _buildStudent(AppLocalizations l10n) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Row(children: [
              _CombinedVariantBadge(variant: _variant!),
            ]),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .04),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.studentInfoTitle,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink1)),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                          child: _CField(
                              label: l10n.firstNameLabel,
                              ctrl: _firstCtrl,
                              hint: l10n.firstNameHint)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _CField(
                              label: l10n.lastNameLabel,
                              ctrl: _lastCtrl,
                              hint: l10n.lastNameHint)),
                    ]),
                    const SizedBox(height: 14),
                    _CField(
                        label: l10n.schoolNameLabel,
                        ctrl: _schoolCtrl,
                        hint: l10n.schoolNameHint,
                        required: false),
                    const SizedBox(height: 14),
                    _CField(
                        label: l10n.pinCodeLabel,
                        ctrl: _passCtrl,
                        hint: '****',
                        obscure: true,
                        required: true),
                    if (_err != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.err.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          const Icon(Icons.warning_rounded,
                              color: AppColors.err, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_err!,
                                  style: const TextStyle(
                                      color: AppColors.err, fontSize: 13))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _startTest,
                        icon: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(
                            _loading ? l10n.serverChecking : l10n.startTest,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPurple,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _CombinedHeader extends StatelessWidget {
  final int? variant;
  const _CombinedHeader({this.variant});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: _kPurple.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8)),
      child: Text(
          variant != null ? 'V$variant' : 'Unit 1',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kPurpleDark)),
    );
  }
}

class _CombinedVariantBadge extends StatelessWidget {
  final int variant;
  const _CombinedVariantBadge({required this.variant});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: _kPurple.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8)),
      child: Text('Variant $variant',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kPurpleDark)));
  }
}

class _CField extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final bool obscure;
  final bool required;

  const _CField({
    required this.label,
    required this.ctrl,
    required this.hint,
    this.obscure = false,
    this.required = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2)),
        if (required)
          const Text(' *',
              style: TextStyle(fontSize: 12, color: AppColors.err)),
      ]),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(fontSize: 14, color: AppColors.ink1),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: AppColors.ink3.withValues(alpha: .6)),
          filled: true,
          fillColor: AppColors.bg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: _kPurple, width: 1.5)),
        ),
      ),
      const SizedBox(height: 14),
    ]);
  }
}
