// lib/features/test/package_screen.dart
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import 'confirm_screen.dart';

class PackageScreen extends StatefulWidget {
  final StudentSession session;
  const PackageScreen({super.key, required this.session});
  @override
  State<PackageScreen> createState() => _PackageScreenState();
}

class _PackageScreenState extends State<PackageScreen> {
  List<TestPackage> _packages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final pkgs = await api.getPackages(widget.session.grade);
      setState(() { _packages = pkgs; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.brandLight,
                    child: Text(s.studentName.isNotEmpty ? s.studentName[0] : 'T',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.brand)),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.studentName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${s.grade}-sinf · Variant ${s.variant}${s.groupName != null ? " · ${s.groupName}" : ""}',
                        style: const TextStyle(color: AppColors.ink2, fontSize: 13)),
                  ]),
                ]),
                const SizedBox(height: 32),
                Text('Test tanlang', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Mavjud monitoring testlari', style: TextStyle(color: AppColors.ink2)),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(child: CircularProgressIndicator(color: AppColors.brand))
                else if (_error != null)
                  Column(children: [
                    Text(_error!, style: const TextStyle(color: AppColors.err)),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: const Text('Qayta urinish')),
                  ])
                else if (_packages.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Hozircha test mavjud emas', style: TextStyle(color: AppColors.ink2)),
                  ))
                else
                  ..._packages.map((pkg) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ConfirmScreen(session: widget.session, package: pkg))),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(children: [
                            Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.quiz_outlined, color: AppColors.brand),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(pkg.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              const SizedBox(height: 6),
                              Row(children: [
                                _chip('Math: ${pkg.mathCount}', AppColors.math),
                                const SizedBox(width: 8),
                                _chip('Ingliz: ${pkg.engCount}', AppColors.eng),
                              ]),
                            ])),
                            const Icon(Icons.chevron_right, color: AppColors.ink3),
                          ]),
                        ),
                      ),
                    ),
                  )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  );
}
