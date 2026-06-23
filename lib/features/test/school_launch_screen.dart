// lib/features/test/school_launch_screen.dart
import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import 'engine_host_screen.dart';

const Color _kBrand = AppColors.brand;

class SchoolLaunchScreen extends StatefulWidget {
  final Map<String, dynamic> testData;
  final String schoolCode;
  final String schoolLabel;
  final int variantCount;
  // null = show variant picker; non-null = skip to form directly (random mode)
  final int? preselectedVariant;
  // non-null = PIN required before launching
  final String? pin;

  const SchoolLaunchScreen({
    super.key,
    required this.testData,
    required this.schoolCode,
    required this.schoolLabel,
    required this.variantCount,
    this.preselectedVariant,
    this.pin,
  });

  @override
  State<SchoolLaunchScreen> createState() => _SchoolLaunchScreenState();
}

class _SchoolLaunchScreenState extends State<SchoolLaunchScreen> {
  late int _step; // 0 = variant picker, 1 = student form
  late int? _variant;

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  late final TextEditingController _schoolCtrl;

  String? _err;

  @override
  void initState() {
    super.initState();
    _schoolCtrl = TextEditingController(text: widget.schoolLabel);
    if (widget.preselectedVariant != null) {
      _variant = widget.preselectedVariant;
      _step = 1;
    } else {
      _variant = null;
      _step = 0;
    }
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _pinCtrl.dispose();
    _schoolCtrl.dispose();
    super.dispose();
  }

  void _start() {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _err = 'Ism va familiyani kiriting');
      return;
    }
    final enteredPin = _pinCtrl.text.trim();
    final requiredPin = widget.pin?.trim();
    if (requiredPin != null && requiredPin.isNotEmpty) {
      if (enteredPin.isEmpty) {
        setState(() => _err = 'PIN kodni kiriting');
        return;
      }
      if (enteredPin != requiredPin) {
        setState(() => _err = 'PIN noto\'g\'ri');
        return;
      }
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => EngineHostScreen(
          testData: widget.testData,
          variant: _variant!,
          firstName: first,
          lastName: last,
          school: widget.schoolCode,
          group: enteredPin.isEmpty ? null : enteredPin,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _step == 1 && widget.preselectedVariant == null
                ? Icons.arrow_back_rounded
                : Icons.arrow_back_rounded,
            color: AppColors.ink1,
          ),
          onPressed: () {
            if (_step == 1 && widget.preselectedVariant == null) {
              setState(() {
                _step = 0;
                _err = null;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _step == 0 ? 'Variantni tanlang' : "O'quvchi ma'lumotlari",
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink1),
        ),
        actions: [
          if (_variant != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'V$_variant',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kBrand),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _step == 0 ? _buildVariantPicker() : _buildStudentForm(),
    );
  }

  Widget _buildVariantPicker() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _kBrand.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBrand.withValues(alpha: .25)),
                ),
                child: Row(children: [
                  const Icon(Icons.school_rounded, color: _kBrand, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.schoolLabel,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: _kBrand),
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
                children: List.generate(widget.variantCount, (i) {
                  final v = i + 1;
                  final sel = _variant == v;
                  return GestureDetector(
                    onTap: () => setState(() => _variant = v),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: sel ? _kBrand : AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sel ? _kBrand : AppColors.border,
                            width: sel ? 2 : 1.5),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                    color: _kBrand.withValues(alpha: .25),
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
                  onPressed: _variant == null
                      ? null
                      : () => setState(() {
                            _step = 1;
                            _err = null;
                          }),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Davom etish',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.border,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentForm() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Variant $_variant',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kBrand),
                  ),
                ),
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
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("O'quvchi ma'lumotlari",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink1)),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                          child: _SField(
                              label: 'Ism', ctrl: _firstCtrl, hint: 'Alisher')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _SField(
                              label: 'Familiya',
                              ctrl: _lastCtrl,
                              hint: 'Karimov')),
                    ]),
                    _SField(
                        label: 'Maktab',
                        ctrl: _schoolCtrl,
                        hint: widget.schoolLabel,
                        required: false,
                        readOnly: true),
                    _SField(
                        label: 'Parol (PIN kod)',
                        ctrl: _pinCtrl,
                        hint: '****',
                        obscure: true,
                        required: widget.pin != null && widget.pin!.isNotEmpty),
                    if (_err != null) ...[
                      const SizedBox(height: 4),
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
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Testni boshlash',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBrand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SField extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final bool obscure;
  final bool required;
  final bool readOnly;

  const _SField({
    required this.label,
    required this.ctrl,
    required this.hint,
    this.obscure = false,
    this.required = true,
    this.readOnly = false,
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
        if (readOnly)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.lock_outline_rounded,
                size: 11, color: AppColors.ink3),
          ),
      ]),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        readOnly: readOnly,
        obscureText: obscure,
        style: TextStyle(
            fontSize: 14,
            color: readOnly ? AppColors.ink2 : AppColors.ink1),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.ink3.withValues(alpha: .6)),
          filled: true,
          fillColor: readOnly
              ? AppColors.muted.withValues(alpha: .5)
              : AppColors.bg,
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
              borderSide: readOnly
                  ? const BorderSide(color: AppColors.border)
                  : const BorderSide(color: AppColors.brand, width: 1.5)),
        ),
      ),
      const SizedBox(height: 14),
    ]);
  }
}
