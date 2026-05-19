// lib/features/home/update_banner.dart
import 'package:flutter/material.dart';
import '../../core/services/update_service.dart';

class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});
  @override State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  ReleaseInfo? _info;
  bool _dismissed = false;

  @override void initState() { super.initState(); _check(); }

  Future<void> _check() async {
    final info = await UpdateService.instance.checkForUpdate();
    if (mounted && info != null) setState(() => _info = info);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null || _dismissed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1d4ed8), Color(0xFF2563eb)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.system_update_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
            Text('Yangi versiya: v\${info.version}', style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            Text(info.publishedAt, style: const TextStyle(
                color: Color(0xFFbfdbfe), fontSize: 11)),
          ])),
        TextButton(
          onPressed: () async {
            if (info.downloadUrl.isNotEmpty)
              await UpdateService.instance.downloadAndInstall(info.downloadUrl);
            else
              await UpdateService.instance.openReleasePage(info.releaseUrl);
          },
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Text('Yangilash', style: TextStyle(
              color: Color(0xFF1d4ed8), fontWeight: FontWeight.w800, fontSize: 12)),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () async {
            await UpdateService.instance.dismiss(info.version);
            setState(() => _dismissed = true);
          },
          child: const Icon(Icons.close_rounded, color: Color(0xFF93c5fd), size: 18)),
      ]),
    );
  }
}
