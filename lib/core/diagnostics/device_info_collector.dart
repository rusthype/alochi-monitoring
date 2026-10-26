// lib/core/diagnostics/device_info_collector.dart
//
// Best-effort hardware/OS facts for the kiosk device report. Every probe is
// individually guarded: a failing probe yields an empty/zero value, never an
// exception. No device_info_plus dependency — sysctl (macOS) and PowerShell
// CIM (Windows) cover the CPU/RAM fields.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceInfo {
  final String os;
  final String osVersion;
  final String cpu;
  final int ramMb;
  final int screenW;
  final int screenH;
  final String appVersion;
  const DeviceInfo({
    required this.os,
    required this.osVersion,
    required this.cpu,
    required this.ramMb,
    required this.screenW,
    required this.screenH,
    required this.appVersion,
  });
}

Future<String> _run(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args).timeout(const Duration(seconds: 8));
    return r.exitCode == 0 ? r.stdout.toString().trim() : '';
  } catch (_) {
    return '';
  }
}

class DeviceInfoCollector {
  static const _idKey = 'device_report_device_id';

  /// Persisted random id (no app-wide device id exists; heartbeat uses a
  /// per-platform constant).
  static Future<String> deviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_idKey);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await prefs.setString(_idKey, id);
      }
      return id;
    } catch (_) {
      return '';
    }
  }

  static Future<DeviceInfo> collect() async {
    var cpu = '';
    var ramMb = 0;
    try {
      if (Platform.isMacOS) {
        cpu = await _run('sysctl', ['-n', 'machdep.cpu.brand_string']);
        final mem = int.tryParse(await _run('sysctl', ['-n', 'hw.memsize']));
        ramMb = mem == null ? 0 : mem ~/ (1024 * 1024);
      } else if (Platform.isWindows) {
        final out = await _run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-CimInstance Win32_Processor | Select-Object -First 1).Name;'
              '[math]::Round((Get-CimInstance Win32_ComputerSystem)'
              '.TotalPhysicalMemory/1MB)',
        ]);
        final lines = out.split(RegExp(r'\r?\n'));
        cpu = lines.first.trim();
        ramMb = lines.length > 1 ? int.tryParse(lines[1].trim()) ?? 0 : 0;
      }
    } catch (_) {}

    var w = 0, h = 0;
    try {
      final views = PlatformDispatcher.instance.views;
      if (views.isNotEmpty) {
        w = views.first.physicalSize.width.round();
        h = views.first.physicalSize.height.round();
      }
    } catch (_) {}

    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    return DeviceInfo(
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      cpu: cpu,
      ramMb: ramMb,
      screenW: w,
      screenH: h,
      appVersion: version,
    );
  }
}
