import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
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
    }
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
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
        title: const Text('Sessiya sozlamalari', style: AppTextStyles.titleMedium),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.entry.title,
                  style: AppTextStyles.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  'Maktabni tanlang',
                  style: AppTextStyles.labelLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.entry.schoolButtons.map((sb) {
                    final isSelected = _selected?.schoolCode == sb.schoolCode;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selected = sb;
                        _pinCtrl.clear();
                        _err = null;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryMuted
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          sb.label,
                          style: AppTextStyles.labelLarge.copyWith(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.ink1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (_selected != null) ...[
                  const SizedBox(height: 20),
                  Text('PIN kod', style: AppTextStyles.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: '****',
                    ),
                  ),
                ],
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.err.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_rounded,
                            color: AppColors.err, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _err!,
                            style: const TextStyle(
                                color: AppColors.err, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Tasdiqlash'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
