import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/login_screen.dart';
import '../widgets/error_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
          path: '/package', builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/test', builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/result', builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/history', builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/local_grade',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/combined',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/session_setup',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/local_test',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/engine_host',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/unit1', builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/unit1_result',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/interhouse',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/combined_runner',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/combined_result',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/student_entry',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/group_select',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/confirm', builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/local_result',
          builder: (context, state) => state.extra as Widget),
      GoRoute(
          path: '/widget_route',
          builder: (context, state) => state.extra as Widget),
    ],
  );
});
