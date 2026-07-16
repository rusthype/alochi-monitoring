import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/test_catalog_service.dart';
import '../../shared/theme/app_theme.dart';
import 'group_select_screen.dart';
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
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _pinCtrl.addListener(() => setState(() {}));
    if (widget.entry.schoolButtons.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pushReplacement('/student_entry',
            extra: StudentEntryScreen(
              session: TestSession.fromEntry(
                widget.entry,
                schoolCode: '',
                schoolLabel: 'Umumiy',
              ),
            ));
      });
    } else {
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

  void _confirm() async {
    if (_selected == null) return;
    
    final l10n = AppLocalizations.of(context)!;
    final expected = _expectedPin(_selected!);
    
    if (expected.isNotEmpty && _pinCtrl.text.trim() != expected) {
      setState(() => _err = l10n.incorrectPin);
      return;
    }
    
    setState(() {
      _err = null;
      _isChecking = true;
    });
    
    // Simulate slight delay for premium feel
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    context.pushReplacement('/group_select',
        extra: GroupSelectScreen(
          schoolCode: _selected!.schoolCode,
          schoolLabel: _selected!.label,
          fallbackEntry: widget.entry,
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_selected == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFFAFAFA),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFDE8E52))),
      );
    }

    final hasPin = _expectedPin(_selected!).isNotEmpty;
    final canSubmit = !hasPin || _pinCtrl.text.length >= 4;
    final isSmall = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Stack(
          children: [
            // Floating Navbar
            Positioned(
              top: isSmall ? 16 : 24,
              left: 16,
              right: 16,
              child: _buildFloatingNavbar(isSmall),
            ),

            // Main Content
            Positioned.fill(
              top: isSmall ? 80 : 100,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: isSmall ? 16 : 24, vertical: 24).copyWith(bottom: 140),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(isSmall),
                        SizedBox(height: isSmall ? 16 : 24),
                        _buildSchoolCore(hasPin),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Action Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomAction(canSubmit),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingNavbar(bool isSmall) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Semantics(
                button: true,
                label: 'Ortga',
                child: InkWell(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/');
                    }
                  },
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: Color(0xFFDE8E52), size: 20),
                  ),
                ),
              ),
              Text(
                'MONITORING TEST',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: const Color(0xFF111111),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '1/3',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: const Color(0xFF737373),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFDE8E52).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFFDE8E52).withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_rounded, size: 12, color: Color(0xFFDE8E52)),
              const SizedBox(width: 6),
              Text(
                'MONITORING TEST',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 2.0,
                  color: const Color(0xFFDE8E52),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Sessiyani\ntasdiqlang',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: isSmall ? 32 : 40,
            height: 1.1,
            letterSpacing: -1.0,
            color: const Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Monitoring testida qatnashish uchun maktabni tasdiqlang va PIN kodni kiriting.',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w500,
            fontSize: 15,
            height: 1.5,
            color: const Color(0xFF737373),
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolCore(bool hasPin) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Selected School Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFDE8E52).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDE8E52).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDE8E52),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.school_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selected!.label,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: const Color(0xFF111111),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.entry.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 1.0,
                            color: const Color(0xFF737373),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Color(0xFFDE8E52), size: 18),
                  ),
                ],
              ),
            ),

            if (hasPin) ...[
              const SizedBox(height: 24),
              const Divider(color: Color(0x0D000000), height: 1),
              const SizedBox(height: 20),
              Text(
                'PIN KOD (MAJBURIY)',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: const Color(0xFF737373),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _pinFocus.hasFocus 
                        ? const Color(0xFFDE8E52).withValues(alpha: 0.5) 
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: TextField(
                  controller: _pinCtrl,
                  focusNode: _pinFocus,
                  obscureText: _obscure,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: _obscure ? 4.0 : 2.0,
                    color: const Color(0xFF111111),
                  ),
                  decoration: InputDecoration(
                    hintText: 'PIN kodni kiriting',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0,
                      color: const Color(0xFF737373).withValues(alpha: 0.4),
                    ),
                    prefixIcon: Icon(
                      Icons.lock_outline_rounded,
                      color: _pinFocus.hasFocus ? const Color(0xFFDE8E52) : const Color(0xFF737373).withValues(alpha: 0.6),
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        color: const Color(0xFF737373).withValues(alpha: 0.6),
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onSubmitted: (_) => _confirm(),
                ),
              ),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.err, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _err!,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: AppColors.err,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_rounded, color: const Color(0xFFDE8E52).withValues(alpha: 0.7), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        "O'qituvchi bergan kodni kiriting",
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: const Color(0xFF737373),
                        ),
                      ),
                    ],
                  ),
                  Semantics(
                    button: true,
                    label: 'Boshqa maktabni tanlash',
                    child: GestureDetector(
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/');
                        }
                      },
                      child: Text(
                        'Boshqa maktab',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: const Color(0xFF111111),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction(bool canSubmit) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFAFAFA).withValues(alpha: 0.0),
            const Color(0xFFFAFAFA).withValues(alpha: 0.8),
            const Color(0xFFFAFAFA),
          ],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Semantics(
            button: true,
            label: 'Sessiyani tasdiqlash',
            child: GestureDetector(
              onTap: canSubmit && !_isChecking ? _confirm : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: canSubmit ? const Color(0xFF111111) : const Color(0xFF111111).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: canSubmit ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    )
                  ] : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Tasdiqlash',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Keyingi: O'quvchi ismi",
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: 1.0,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDE8E52),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _isChecking
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
