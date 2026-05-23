import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/cache/image_cache_manager.dart';
import '../../shared/theme/app_theme.dart';

class SyncImagesButton extends StatefulWidget {
  const SyncImagesButton({super.key});
  @override
  State<SyncImagesButton> createState() => _SyncImagesButtonState();
}

class _SyncImagesButtonState extends State<SyncImagesButton> {
  bool _syncing = false;
  double _progress = 0;
  int _total = 0;
  int _done = 0;

  Future<void> _startSync() async {
    setState(() {
      _syncing = true;
      _progress = 0;
      _total = 0;
      _done = 0;
    });

    try {
      final dataStr = await rootBundle.loadString('assets/questions.json');
      final data = jsonDecode(dataStr) as Map;

      final Set<String> urls = {};

      for (final grade in data.keys) {
        final variants = data[grade] as Map;
        for (final v in variants.keys) {
          final qList = variants[v] as List;
          for (final q in qList) {
            if (q['i'] != null && q['i'].toString().isNotEmpty) {
              final u = MonitoringApi.fixImageUrl(q['i'].toString());
              if (u.isNotEmpty) urls.add(u);
            }
            if (q['oi'] != null) {
              for (final oi in (q['oi'] as List)) {
                if (oi != null && oi.toString().isNotEmpty) {
                  final u = MonitoringApi.fixImageUrl(oi.toString());
                  if (u.isNotEmpty) urls.add(u);
                }
              }
            }
          }
        }
      }

      setState(() => _total = urls.length);
      final cacheMgr = AlochiImageCacheManager();

      for (final url in urls) {
        if (!mounted) return;
        try {
          // Bu buyruq rasmni serverdan olib doimiy xotiraga yozadi
          await cacheMgr.downloadFile(url);
        } catch (_) {}
        setState(() {
          _done++;
          _progress = _done / _total;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sinxronizatsiya yakunlandi! $_done ta rasm oflayn saqlandi.'), 
            backgroundColor: AppColors.ok
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato yuz berdi: $e'), backgroundColor: AppColors.err),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_syncing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text("Oflayn rasmlar yuklanmoqda...", 
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink2, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.brand),
            ),
          ),
          const SizedBox(height: 6),
          Text('$_done / $_total ta saqlandi', 
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ink3, fontSize: 11)),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: TextButton.icon(
        onPressed: _startSync,
        icon: const Icon(Icons.cloud_download_rounded, size: 16),
        label: const Text('Oflayn rasmlarni tayyorlash (Sync)'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
