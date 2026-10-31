// lib/core/diagnostics/device_info_collector.dart
//
// Best-effort hardware/OS facts for the kiosk device report. Every probe is
// individually guarded: a failing probe yields an empty/zero value, never an
// exception. No device_info_plus dependency — sysctl (macOS) and native Win32
// calls (Windows) cover the CPU/RAM fields; PowerShell CIM is a last resort.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
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

  /// False when a hardware probe came back empty; the sender then retries
  /// instead of treating the report as final.
  bool get isComplete => cpu.isNotEmpty && ramMb > 0;
}

Future<String> _run(String exe, List<String> args,
    {Duration timeout = const Duration(seconds: 8)}) async {
  try {
    final r = await Process.run(exe, args).timeout(timeout);
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

  /// "version+build", '' if unavailable. Cheap: no hardware probing.
  static Future<String> appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
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
        // Native first: PowerShell/WMI cold start can exceed 8 s on slow
        // school PCs (first launch after boot/update) and used to leave
        // cpu='' / ram=0.
        cpu = _winCpuName();
        ramMb = _winTotalRamMb();
        if (cpu.isEmpty) {
          cpu = parseRegQueryCpu(await _run('reg', [
            'query',
            'HKLM\\$_cpuRegPath',
            '/v',
            'ProcessorNameString',
          ]));
        }
        if (cpu.isEmpty || ramMb == 0) {
          final hw = parsePowershellHw(await _run(
            'powershell',
            [
              '-NoProfile',
              '-Command',
              '(Get-CimInstance Win32_Processor | Select-Object -First 1).Name;'
                  '[math]::Round((Get-CimInstance Win32_ComputerSystem)'
                  '.TotalPhysicalMemory/1MB)',
            ],
            timeout: const Duration(seconds: 30),
          ));
          if (cpu.isEmpty) cpu = hw.cpu;
          if (ramMb == 0) ramMb = hw.ramMb;
        }
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

    final version = await appVersion();

    return DeviceInfo(
      os: Platform.operatingSystem,
      osVersion: normalizeOsVersion(Platform.operatingSystemVersion),
      cpu: cpu,
      ramMb: ramMb,
      screenW: w,
      screenH: h,
      appVersion: version,
    );
  }
}

/// "Version 26.5.2 (Build 25F84)" -> "26.5.2";
/// '"Windows 10 Pro" 10.0 (Build 19045)' -> "10.0.19045".
String normalizeOsVersion(String raw) {
  final v = RegExp(r'\d+(\.\d+)+').firstMatch(raw)?.group(0);
  if (v == null) {
    final t = raw.trim();
    return t.length > 40 ? t.substring(0, 40) : t;
  }
  final build = RegExp(r'\(Build (\d+)\)').firstMatch(raw)?.group(1);
  return build == null ? v : '$v.$build';
}

const _cpuRegPath = r'HARDWARE\DESCRIPTION\System\CentralProcessor\0';

/// Trims and collapses whitespace (CPU names are space-padded) and drops NULs.
String cleanCpuName(String raw) =>
    raw.replaceAll('\u0000', '').replaceAll(RegExp(r'\s+'), ' ').trim();

int bytesToMb(int bytes) => bytes ~/ (1024 * 1024);

/// `reg query ... /v ProcessorNameString` -> CPU name ('' when unparseable).
String parseRegQueryCpu(String out) {
  final m = RegExp(r'ProcessorNameString\s+REG_SZ\s+(.+)').firstMatch(out);
  return m == null ? '' : cleanCpuName(m.group(1)!);
}

/// PowerShell output: line 1 = CPU name, line 2 = RAM in MB.
({String cpu, int ramMb}) parsePowershellHw(String out) {
  final lines = out.split(RegExp(r'\r?\n'));
  return (
    cpu: cleanCpuName(lines.first),
    ramMb: lines.length > 1 ? int.tryParse(lines[1].trim()) ?? 0 : 0,
  );
}

int _winTotalRamMb() {
  if (!Platform.isWindows) return 0;
  final p = calloc<MEMORYSTATUSEX>();
  try {
    p.ref.dwLength = sizeOf<MEMORYSTATUSEX>();
    return GlobalMemoryStatusEx(p) != 0 ? bytesToMb(p.ref.ullTotalPhys) : 0;
  } catch (_) {
    return 0;
  } finally {
    calloc.free(p);
  }
}

String _winCpuName() {
  if (!Platform.isWindows) return '';
  final path = _cpuRegPath.toNativeUtf16();
  final name = 'ProcessorNameString'.toNativeUtf16();
  final hKey = calloc<IntPtr>();
  final size = calloc<Uint32>();
  Pointer<Uint8>? data;
  try {
    if (RegOpenKeyEx(HKEY_LOCAL_MACHINE, path, 0, KEY_READ, hKey) !=
        ERROR_SUCCESS) {
      return '';
    }
    try {
      // First call returns the byte length, second fills the buffer.
      if (RegQueryValueEx(hKey.value, name, nullptr, nullptr, nullptr, size) !=
              ERROR_SUCCESS ||
          size.value == 0) {
        return '';
      }
      data = calloc<Uint8>(size.value);
      if (RegQueryValueEx(hKey.value, name, nullptr, nullptr, data, size) !=
          ERROR_SUCCESS) {
        return '';
      }
      return cleanCpuName(String.fromCharCodes(
          data.cast<Uint16>().asTypedList(size.value ~/ 2)));
    } finally {
      RegCloseKey(hKey.value);
    }
  } catch (_) {
    return '';
  } finally {
    if (data != null) calloc.free(data);
    calloc.free(path);
    calloc.free(name);
    calloc.free(hKey);
    calloc.free(size);
  }
}
