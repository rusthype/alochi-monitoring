// lib/core/security/incident_log.dart
//
// In-memory proctoring metadata for the CURRENT test attempt (decision 12 of
// the offline plan: focus-loss / tab-switch times, multi-monitor — metadata
// only, never screenshots). HeartbeatService writes here; the offline pack
// session drains it into the result row (`incidents`) when a test finishes.
// Cheap and bounded, so it is always on; online mode simply never reads it.
import 'monitored_clock.dart';

class IncidentLog {
  IncidentLog._();
  static final IncidentLog instance = IncidentLog._();

  static const int _cap = 200;
  final List<Map<String, dynamic>> _items = [];

  /// Incidents that did not fit under [_cap], counted per type. They are not
  /// silently lost: [drain] appends one `incident_overflow` entry carrying
  /// these counts, so the teacher sees that (and what kind of) activity was
  /// squeezed out.
  final Map<String, int> _dropped = {};

  /// Timestamps use the monitored (tamper-resistant) clock.
  void add(String type, [Map<String, dynamic> extra = const {}]) {
    if (_items.length >= _cap) {
      _dropped[type] = (_dropped[type] ?? 0) + 1;
      return;
    }
    _items.add({
      'type': type,
      'at': MonitoredClock.instance.nowUtc.toIso8601String(),
      'monotonic_ms': MonitoredClock.instance.ticksMs,
      ...extra,
    });
  }

  /// Returns what was recorded since the last call and clears it.
  List<Map<String, dynamic>> drain() {
    final out = List<Map<String, dynamic>>.from(_items);
    if (_dropped.isNotEmpty) {
      out.add({
        'type': 'incident_overflow',
        'at': MonitoredClock.instance.nowUtc.toIso8601String(),
        'dropped': Map<String, int>.from(_dropped),
      });
    }
    _items.clear();
    _dropped.clear();
    return out;
  }

  List<Map<String, dynamic>> get snapshot => List.unmodifiable(_items);
}
