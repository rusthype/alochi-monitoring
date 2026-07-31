// lib/features/downloads/downloads_sheet.dart
import 'dart:io';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';

class DownloadsSheet extends StatefulWidget {
  final String schoolCode;
  const DownloadsSheet({super.key, required this.schoolCode});

  @override
  State<DownloadsSheet> createState() => _DownloadsSheetState();
}

class _DownloadsSheetState extends State<DownloadsSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final Map<int, bool> _downloading = {};
  final Map<int, String> _saved = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await api.fetchDownloads(widget.schoolCode);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _download(Map<String, dynamic> item) async {
    final id = item['id'] as int;
    setState(() => _downloading[id] = true);
    try {
      final url = item['file_url'] as String;
      final filename = url.split('/').last.split('?').first;
      final resp = await http.get(Uri.parse(url));
      Directory? dir;
      try {
        if (!Platform.isIOS && !Platform.isAndroid) {
          if (Platform.isMacOS) {
            final home = Platform.environment['HOME'];
            if (home != null) {
              final parts = home.split('/');
              if (parts.length >= 3 && parts[1] == 'Users') {
                dir = Directory('/Users/${parts[2]}/Downloads');
              }
            }
          }
          dir ??= await getDownloadsDirectory();
        }
      } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(resp.bodyBytes);
      if (mounted) {
        setState(() => _saved[id] = file.path);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.savedFileMsg(file.path)),
            backgroundColor: AppColors.mint,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.errorPrefix(e.toString())),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0f172a),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.slateDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.download_rounded, color: AppColors.mint, size: 20),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)!.hujjatlarLabel,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.mint),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  AppLocalizations.of(context)!.noDocumentsMsg,
                  style: const TextStyle(color: Color(0xFF64748b)),
                ),
              ),
            )
          else
            ..._items.map((item) {
              final id = item['id'] as int;
              final saved = _saved[id];
              final loading = _downloading[id] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1e293b),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slateDark),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.table_chart,
                      color: AppColors.mint, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] as String,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (saved != null)
                          Text(
                            saved,
                            style: const TextStyle(
                              color: AppColors.mint,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.mint,
                          ),
                        )
                      : ElevatedButton(
                          onPressed: () => _download(item),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.mint,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          child:
                              Text(AppLocalizations.of(context)!.downloadBtn),
                        ),
                ]),
              );
            }),
        ],
      ),
    );
  }
}
