import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/models.dart';
import '../../core/services/test_catalog_service.dart';
import 'test_session.dart';

/// The catalog entry selected from the login screen
final selectedCatalogEntryProvider = StateProvider<CatalogEntry?>((ref) => null);

/// The specific school code tapped on the login screen's school card, if any.
/// [selectedCatalogEntryProvider]'s entry can list schoolButtons for several
/// schools (one shared test), so SessionSetupScreen needs this to pick the
/// right one instead of defaulting to the first. Null when the entry point
/// has no specific school (e.g. the "Umumiy testlar" list).
final selectedSchoolCodeProvider = StateProvider<String?>((ref) => null);

/// The current test session
final currentSessionProvider = StateProvider<TestSession?>((ref) => null);

/// The logged-in student's [StudentSession], written by login_screen.dart
/// right before navigating to `/my_tests`. Centralized source of truth for
/// the student-cabinet shell/sidebar (and, later, Home/Messages screens) —
/// StatefulShellRoute branches don't reliably carry GoRouter's `extra` past
/// their first navigation, so screens that can't rely on `extra` fall back
/// to reading this provider instead.
final currentStudentSessionProvider = StateProvider<StudentSession?>((ref) => null);

/// The selected group
final selectedGroupProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

/// The selected student
final selectedStudentProvider = StateProvider<Map<String, dynamic>?>((ref) => null);
