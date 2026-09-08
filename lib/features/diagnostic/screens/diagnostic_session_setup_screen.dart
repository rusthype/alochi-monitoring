// lib/features/diagnostic/screens/diagnostic_session_setup_screen.dart
//
// Full-screen PIN confirmation for the diagnostic kiosk flow — copied
// (never imported) from lib/features/session/session_setup_screen.dart's
// floating navbar / header / school+PIN card / bottom action pill.
// Replaces the old popup PIN dialog (_showPinDialog) that used to live in
// diagnostic_school_select_screen.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/hover_region.dart';

class DiagnosticSessionSetupScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;
  final String schoolCode;
  final String expectedPin;

  const DiagnosticSessionSetupScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
    required this.schoolCode,
    required this.expectedPin,
  });

  @override
  State<DiagnosticSessionSetupScreen> createState() =>
      _DiagnosticSessionSetupScreenState();
}

class _DiagnosticSessionSetupScreenState
    extends State<DiagnosticSessionSetupScreen> {
  final _pinCtrl = TextEditingController();
  final FocusNode _pinFocus = FocusNode();
  String? _err;
  bool _obscure = true;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _pinCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/diagnostic_school_select');
    }
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context)!;

    if (widget.expectedPin.isNotEmpty &&
        _pinCtrl.text.trim() != widget.expectedPin) {
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

    context.push('/diagnostic_class_select', extra: {
      'schoolId': widget.schoolId,
      'schoolName': widget.schoolName,
      'schoolCode': widget.schoolCode,
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _pinCtrl.text.trim().isNotEmpty;
    final isSmall = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
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
                padding: EdgeInsets.symmetric(
                        horizontal: isSmall ? 16 : 24, vertical: 24)
                    .copyWith(bottom: 140),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(isSmall),
                        SizedBox(height: isSmall ? 16 : 24),
                        _buildSchoolCore(),
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
                label: AppLocalizations.of(context)!.backBtn,
                child: InkWell(
                  onTap: _goBack,
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.pageBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.accent, size: 20),
                  ),
                ),
              ),
              Text(
                AppLocalizations.of(context)!.diagnosticTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: AppColors.charcoal,
                ),
              ),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    '1/3',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: AppColors.stone,
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
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 12, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.diagnosticHeaderTag,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 2.0,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context)!.confirmSessionTitle,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: isSmall ? 32 : 40,
            height: 1.1,
            letterSpacing: -1.0,
            color: AppColors.charcoal,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          AppLocalizations.of(context)!.testSessionInstruction,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
            height: 1.5,
            color: AppColors.stone,
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolCore() {
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
                color: AppColors.accent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.school_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.schoolName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: AppColors.charcoal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.schoolCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 1.0,
                            color: AppColors.stone,
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
                    child: const Icon(Icons.check_rounded,
                        color: AppColors.accent, size: 18),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Divider(color: Color(0x0D000000), height: 1),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!.pinCodeRequired,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 1.5,
                color: AppColors.stone,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.pageBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _pinFocus.hasFocus
                      ? AppColors.accent.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: TextField(
                controller: _pinCtrl,
                focusNode: _pinFocus,
                autofocus: true,
                obscureText: _obscure,
                keyboardType: TextInputType.number,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: _obscure ? 4.0 : 2.0,
                  color: AppColors.charcoal,
                ),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.enterPinCode,
                  hintStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0,
                    color: AppColors.stone.withValues(alpha: 0.4),
                  ),
                  prefixIcon: Icon(
                    Icons.lock_outline_rounded,
                    color: _pinFocus.hasFocus
                        ? AppColors.accent
                        : AppColors.stone.withValues(alpha: 0.6),
                    size: 20,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      color: AppColors.stone.withValues(alpha: 0.6),
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
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.err, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _err!,
                      style: const TextStyle(
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
                    Icon(Icons.info_rounded,
                        color: AppColors.accent.withValues(alpha: 0.7),
                        size: 16),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.of(context)!.enterTeacherCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: AppColors.stone,
                      ),
                    ),
                  ],
                ),
                Semantics(
                  button: true,
                  label: AppLocalizations.of(context)!.otherSchoolBtn,
                  child: GestureDetector(
                    onTap: _goBack,
                    child: Text(
                      AppLocalizations.of(context)!.otherSchoolBtn,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.charcoal,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
            AppColors.pageBg.withValues(alpha: 0.0),
            AppColors.pageBg.withValues(alpha: 0.8),
            AppColors.pageBg,
          ],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Semantics(
            button: true,
            label: AppLocalizations.of(context)!.confirmBtn,
            child: HoverRegion(
              builder: (context, isHovered) => GestureDetector(
                onTap: canSubmit && !_isChecking ? _confirm : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: canSubmit
                        ? (isHovered && !_isChecking
                            ? const Color(0xFF333333)
                            : AppColors.charcoal)
                        : AppColors.charcoal.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: canSubmit
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 32,
                              offset: const Offset(0, 16),
                            )
                          ]
                        : [],
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
                              AppLocalizations.of(context)!.confirmBtn,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppLocalizations.of(context)!
                                  .diagnosticNextStepClasses,
                              style: TextStyle(
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
                          color: AppColors.accent,
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
                            : const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
