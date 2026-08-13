// lib/features/session/results_screen.dart
//
// Thin compatibility shim: `core/router/app_router.dart` still imports this
// file and references `ResultsScreen(session: ...)` directly (router
// wiring is intentionally left untouched here — see
// student_results_screen.dart's file header). All actual UI/logic now
// lives in `StudentResultsScreen`; this class just forwards to it so the
// route keeps working without touching app_router.dart.
import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import 'student_results_screen.dart';

class ResultsScreen extends StatelessWidget {
  final StudentSession session;

  const ResultsScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) => StudentResultsScreen(session: session);
}
