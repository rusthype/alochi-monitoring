// lib/features/bob14/bob14_screen.dart
// 2-sinf Bob 1-4 monitoring testi — variant (1-15) + o'quvchi ma'lumotlari
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

import '../../shared/theme/app_theme.dart';
import '../local_test/local_test_screen.dart';
import 'bob14_data.dart';

class Bob14Screen extends StatefulWidget {
  const Bob14Screen({super.key});
  @override
  State<Bob14Screen> createState() => _Bob14ScreenState();
}

class _Bob14ScreenState extends State<Bob14Screen>
    with SingleTickerProviderStateMixin {
  int? _variant;
  int _step = 0; // 0=variant, 1=student info

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
      setState(() => _err = "Maxfiy parol noto'g'ri");
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final qs = await Bob14Loader.getResolved(_variant!);
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LocalTestScreen(
              firstName: first,
              lastName: last,
              group: _groupCtrl.text.trim(),
              school: _schoolCtrl.text.trim(),
              grade: 2,
              variant: _variant!,
              questions: qs,
            ),
          ));
    } catch (e) {
      setState(() {
        _err = "Xato: $e";
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
                onPressed: () => _goStep(0))
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
            child: _Bob14Header(variant: _variant),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fade,
        child: _step == 0 ? _buildVariant() : _buildStudent(),
      ),
    );
  }

  // ── Step 0: Variant 1-15 ──────────────────────────────────────────
  Widget _buildVariant() {
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Info banner
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.emerald.withValues(alpha: .25)),
            ),
            child: const Row(children: [
              Icon(Icons.menu_book_rounded,
                  color: AppColors.emerald, size: 20),
              SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('2-sinf — Bob 1-4 Monitoringi',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: AppColors.emeraldInk)),
                    SizedBox(height: 2),
                    Text('30 savol · 45 daqiqa · Offline rejim',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFF047857))),
                  ])),
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
            children: List.generate(15, (i) {
              final v = i + 1;
              final sel = _variant == v;
              return GestureDetector(
                onTap: () => setState(() => _variant = v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppColors.emerald
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: sel
                            ? AppColors.emerald
                            : AppColors.border,
                        width: sel ? 2 : 1.5),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: AppColors.emerald
                                    .withValues(alpha: .25),
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
                backgroundColor: AppColors.emerald,
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
                        label: AppLocalizations.of(context)!.firstNameLabel, ctrl: _firstCtrl, hint: AppLocalizations.of(context)!.alisherHint)),
                const SizedBox(width: 12),
                Expanded(
                    child: _Field(
                        label: AppLocalizations.of(context)!.lastNameLabel,
                        ctrl: _lastCtrl,
                        hint: 'Karimov')),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: _Field(
                        label: 'Guruh / Sinf',
                        ctrl: _groupCtrl,
                        hint: '2-A',
                        required: false)),
                const SizedBox(width: 12),
                Expanded(
                    child: _Field(
                        label: AppLocalizations.of(context)!.schoolLabel,
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
                    backgroundColor: AppColors.emerald,
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

class _Bob14Header extends StatelessWidget {
  final int? variant;
  const _Bob14Header({this.variant});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: AppColors.emerald.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8)),
      child: Text(
          variant != null ? 'V$variant' : 'Bob 1-4',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.emeraldInk)),
    );
  }
}

class _VariantBadge extends StatelessWidget {
  final int variant;
  const _VariantBadge({required this.variant});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: AppColors.emerald.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8)),
      child: Text('Variant $variant',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.emeraldInk)));
  }
}

class _Field extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final bool obscure;
  final bool required;
  const _Field(
      {required this.label,
      required this.ctrl,
      required this.hint,
      this.obscure = false,
      this.required = true});

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
          hintStyle: TextStyle(color: AppColors.ink3.withValues(alpha: .6)),
          filled: true,
          fillColor: AppColors.bg,
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
              borderSide: const BorderSide(
                  color: AppColors.emerald, width: 1.5)),
        ),
      ),
      const SizedBox(height: 14),
    ]);
  }
}
