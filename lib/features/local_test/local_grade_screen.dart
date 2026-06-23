// lib/features/local_test/local_grade_screen.dart
// Interhouse Grade 2 → Variant → Student Info → Test
import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import '../interhouse/interhouse_data.dart';
import '../interhouse/interhouse_runner.dart';

class LocalGradeScreen extends StatefulWidget {
  const LocalGradeScreen({super.key});
  @override
  State<LocalGradeScreen> createState() => _LocalGradeScreenState();
}

class _LocalGradeScreenState extends State<LocalGradeScreen>
    with SingleTickerProviderStateMixin {
  // Interhouse Grade 2 — grade fixed at 2
  int? _variant;
  int _step = 0; // 0=variant, 1=student info
  // Legacy: kept so LocalQuestionsLoader path compiles
  // ignore: prefer_final_fields
  int _grade = 2;

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _groupCtrl = TextEditingController();
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
    _groupCtrl.dispose();
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
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _err = 'Ism va familiyani kiriting');
      return;
    }
    if (_passCtrl.text.trim() != '1234') {
      setState(() => _err = "Maxfiy parol noto'g'ri (Maslahat: 1234)");
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      // Interhouse Grade 2 path
      final testData = await IhLoader.load();
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InterhouseRunner(
              isOnline: false,
              firstName: first,
              lastName: last,
              school: _schoolCtrl.text.trim(),
              variant: _variant!,
              testData: testData,
            ),
          ));
    } catch (e) {
      setState(() {
        _err = 'Xato: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: _step > 0
            ? IconButton(
                icon:
                    const Icon(Icons.arrow_back_rounded, color: AppColors.ink1),
                onPressed: () => _goStep(_step - 1))
            : IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.ink2),
                onPressed: () => Navigator.pop(context)),
        title: Text(
            _step == 0 ? 'Variantni tanlang' : "O'quvchi ma'lumotlari",
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink1)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _StepIndicator(current: _step, total: 2),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fade,
        child: _step == 0 ? _buildVariant() : _buildStudent(),
      ),
    );
  }

  // ── Step 0: Variant ────────────────────────────────────────────────
  Widget _buildVariant() {
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: .3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded,
                  color: Color(0xFF10B981), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '2-sinf Ingliz tili — Interhouse testi\n10 variant · 30 savol · Offline rejim',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF10B981),
                      height: 1.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('Variantni tanlang',
              style: TextStyle(
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
            children: List.generate(10, (i) {
              final v = i + 1;
              final sel = _variant == v;
              return GestureDetector(
                onTap: () => setState(() => _variant = v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.brand : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: sel ? AppColors.brand : AppColors.border,
                        width: sel ? 2 : 1.5),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: AppColors.brand.withValues(alpha: .25),
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
                              color: sel ? Colors.white : AppColors.ink2))),
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
              label: const Text('Davom etish',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.border,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    ));
  }

  // ── Step 1: Student Info ───────────────────────────────────────────
  Widget _buildStudent() {
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Row(children: [
            _GradeBadge(grade: _grade),
            const SizedBox(width: 8),
            _VariantBadge(variant: _variant!),
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("O'quvchi ma'lumotlari",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink1)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: _Field(
                        label: 'Ism', ctrl: _firstCtrl, hint: 'Alisher')),
                const SizedBox(width: 12),
                Expanded(
                    child: _Field(
                        label: 'Familiya', ctrl: _lastCtrl, hint: 'Karimov')),
              ]),
              Row(children: [
                Expanded(
                    child: _Field(
                        label: 'Guruh / Sinf',
                        ctrl: _groupCtrl,
                        hint: '3-A',
                        required: false)),
                const SizedBox(width: 12),
                Expanded(
                    child: _Field(
                        label: 'Maktab nomi',
                        ctrl: _schoolCtrl,
                        hint: '12-maktab',
                        required: false)),
              ]),
              const SizedBox(height: 14),
              _Field(
                  label: 'Parol (PIN kod)',
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
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(_loading ? 'Yuklanmoqda...' : 'Testni boshlash',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ok,
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
    ));
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _GradeBadge extends StatelessWidget {
  final int grade;
  const _GradeBadge({required this.grade});
  @override
  Widget build(BuildContext context) {
    final colors = {
      1: AppColors.brand,
      2: const Color(0xFF10B981),
      3: const Color(0xFF6366F1),
      4: const Color(0xFFEC4899),
    };
    final c = colors[grade] ?? AppColors.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: c.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: .3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.school_rounded, size: 14, color: c),
        const SizedBox(width: 6),
        Text('$grade-sinf',
            style:
                TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}

class _VariantBadge extends StatelessWidget {
  final int variant;
  const _VariantBadge({required this.variant});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: AppColors.brandLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.brand.withValues(alpha: .3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.tag_rounded, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('Variant $variant',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand)),
        ]),
      );
}

class _Field extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final bool required;
  final bool obscure;
  const _Field(
      {required this.label,
      required this.ctrl,
      required this.hint,
      this.obscure = false,
      this.required = true});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(
            text: TextSpan(
          text: label,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.ink2,
              letterSpacing: .3),
          children: required
              ? [
                  const TextSpan(
                      text: ' *', style: TextStyle(color: AppColors.err))
                ]
              : [],
        )),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.brand, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
        ),
      ]);
}

class _StepIndicator extends StatelessWidget {
  final int current, total;
  const _StepIndicator({required this.current, required this.total});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
            total,
            (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == current ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: i == current
                          ? AppColors.brand
                          : i < current
                              ? AppColors.ok.withValues(alpha: .4)
                              : AppColors.border,
                      borderRadius: BorderRadius.circular(4)),
                )),
      );
}
