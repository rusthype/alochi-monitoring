// lib/shared/widgets/subject_badge.dart
//
// Generalized (public) versions of my_tests_screen.dart's private
// `_SubjectBox` and `_StudentTestCard._subjectBadge()` instance method.
// [subjectBadge] takes the raw subject string directly (was previously an
// instance method reading `test.subject`) — same math/english/other switch,
// same visuals.
import 'package:flutter/material.dart';

/// 40x40 rounded-square leading icon box for a subject badge.
class SubjectBox extends StatelessWidget {
  final Color bg;
  final Widget child;
  const SubjectBox({super.key, required this.bg, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: child,
      );
}

/// Subject icon badge: math/english/other, matched case-insensitively.
Widget subjectBadge(String subject) {
  final s = subject.toLowerCase();
  if (s == 'math') {
    return const SubjectBox(
      bg: Color(0xFFEDE7F6),
      child: Icon(Icons.calculate_rounded, color: Color(0xFF673AB7), size: 22),
    );
  }
  if (s == 'english') {
    return const SubjectBox(
      bg: Color(0xFFE8F5E9),
      child: Text('EN',
          style: TextStyle(
              color: Color(0xFF2E7D32),
              fontWeight: FontWeight.w800,
              fontSize: 13)),
    );
  }
  return const SubjectBox(
    bg: Color(0xFFE3F2FD),
    child: Icon(Icons.description_rounded, color: Color(0xFF1976D2), size: 22),
  );
}
