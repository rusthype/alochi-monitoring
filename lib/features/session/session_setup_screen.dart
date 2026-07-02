import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/test_catalog_service.dart';
import '../../shared/theme/app_theme.dart';
import 'student_entry_screen.dart';
import 'test_session.dart';

class SessionSetupScreen extends StatefulWidget {
  final CatalogEntry entry;
  const SessionSetupScreen({super.key, required this.entry});

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  SchoolButton? _selected;
  final _pinCtrl = TextEditingController();
  String? _err;
  bool _obscure = true;
  final FocusNode _pinFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _pinFocus.addListener(() => setState(() {}));
    if (widget.entry.schoolButtons.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: 'student_entry'),
            builder: (_) => StudentEntryScreen(
              session: TestSession.fromEntry(
                widget.entry,
                schoolCode: '',
                schoolLabel: 'Umumiy',
              ),
            ),
          ),
        );
      });
    } else if (widget.entry.schoolButtons.length == 1) {
      _selected = widget.entry.schoolButtons.first;
    }
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  String _expectedPin(SchoolButton sb) {
    if (sb.pin.isNotEmpty) return sb.pin;
    final digits = sb.schoolCode.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? '' : '$digits$digits';
  }

  void _confirm() {
    if (_selected == null) {
      setState(() => _err = 'Maktabni tanlang');
      return;
    }
    final expected = _expectedPin(_selected!);
    if (expected.isNotEmpty && _pinCtrl.text.trim() != expected) {
      setState(() => _err = "PIN noto'g'ri");
      return;
    }
    setState(() => _err = null);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'student_entry'),
        builder: (_) => StudentEntryScreen(
          session: TestSession.fromEntry(
            widget.entry,
            schoolCode: _selected!.schoolCode,
            schoolLabel: _selected!.label,
          ),
        ),
      ),
    );
  }

  Widget _step(int n, String label, bool active) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$n',
              style: TextStyle(
                color: active ? AppColors.secondary : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _schoolCard(SchoolButton sb) {
    final sel = _selected?.schoolCode == sb.schoolCode;
    return GestureDetector(
      onTap: () => setState(() {
        _selected = sb;
        _pinCtrl.clear();
        _err = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? AppColors.secondaryMuted : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? AppColors.secondary : AppColors.border,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: sel ? AppColors.surface : AppColors.muted,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.school_outlined,
                      color: AppColors.secondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    sb.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: AppColors.ink1,
                    ),
                  ),
                ],
              ),
            ),
            if (sel)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinInput() {
    final len = _expectedPin(_selected!).length.clamp(4, 8);
    const double boxW = 52;
    const double gap = 10;
    final double boxesW = len * boxW + (len - 1) * gap;
    return Semantics(
      textField: true,
      label: 'PIN kod',
      hint: "To'rt xonali PIN kodni kiriting",
      child: Row(
      children: [
        SizedBox(
          width: boxesW,
          height: 56,
          child: Stack(
            children: [
              IgnorePointer(
                child: Row(
                  children: List.generate(len, (i) {
                    final filled = i < _pinCtrl.text.length;
                    final active = _pinFocus.hasFocus && i == _pinCtrl.text.length;
                    final ch = filled ? _pinCtrl.text[i] : '';
                    return Container(
                      margin: EdgeInsets.only(right: i == len - 1 ? 0 : gap),
                      width: boxW,
                      height: 56,
                      decoration: BoxDecoration(
                        color: (active || filled)
                            ? AppColors.secondaryMuted
                            : AppColors.muted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (active || filled)
                              ? AppColors.secondary
                              : AppColors.border,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: filled
                            ? (_obscure
                                ? Container(
                                    width: 11,
                                    height: 11,
                                    decoration: const BoxDecoration(
                                      color: AppColors.ink1,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : Text(
                                    ch,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 22,
                                      color: AppColors.ink1,
                                    ),
                                  ))
                            : const SizedBox(),
                      ),
                    );
                  }),
                ),
              ),
              Positioned.fill(
                child: TextField(
                  controller: _pinCtrl,
                  focusNode: _pinFocus,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: len,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.transparent,
                  ),
                  cursorColor: Colors.transparent,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(len),
                  ],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _confirm(),
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: _obscure ? "Ko'rsatish" : 'Yashirish',
          child: InkWell(
            onTap: () => setState(() => _obscure = !_obscure),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.ink2,
                size: 20,
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Maktabni tanlang',
          style: TextStyle(
            color: AppColors.ink2,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: widget.entry.schoolButtons.map(_schoolCard).toList(),
        ),
        if (_selected != null && _expectedPin(_selected!).isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'PIN kod',
            style: TextStyle(
              color: AppColors.ink2,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 12),
          _buildPinInput(),
        ],
        if (_err != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.err.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_rounded, color: AppColors.err, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _err!,
                    style: const TextStyle(color: AppColors.err, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Tasdiqlash'),
          ),
        ),
        const SizedBox(height: 14),
        const Center(
          child: Text(
            "Keyingi qadam: o'quvchi ismini kiritish",
            style: TextStyle(color: AppColors.ink3, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF2A968),
            AppColors.secondary,
            Color(0xFFCF7A34),
          ],
        ),
      ),
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: const Center(
              child: Text(
                'A',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.menu_book_outlined, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Sinov sessiyasi',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            widget.entry.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 26,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Sinov sessiyasini boshlash uchun maktabni tanlang va PIN kodni kiriting.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _step(1, 'Sessiya sozlamalari', true),
              const SizedBox(height: 10),
              _step(2, "O'quvchi ismi", false),
              const SizedBox(height: 10),
              _step(3, 'Testni boshlash', false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowHeader() {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF2A968),
            AppColors.secondary,
            Color(0xFFCF7A34),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: const Center(
              child: Text(
                'A',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book_outlined, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Sinov sessiyasi',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.entry.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entry.schoolButtons.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 40,
                  child: _buildLeftPanel(),
                ),
                Expanded(
                  flex: 60,
                  child: Container(
                    color: AppColors.surface,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 52,
                            vertical: 40,
                          ),
                          child: _buildForm(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildNarrowHeader(),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: _buildForm(),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}
