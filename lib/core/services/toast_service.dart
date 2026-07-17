import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class ToastService {
  static void showSuccess(BuildContext context, String message) {
    _showToast(context, message, AppColors.ok, Icons.check_circle_outline);
  }

  static void showError(BuildContext context, String message) {
    _showToast(context, message, AppColors.err, Icons.error_outline);
  }

  static void showInfo(BuildContext context, String message) {
    _showToast(context, message, AppColors.primary, Icons.info_outline);
  }

  static void _showToast(BuildContext context, String message, Color color, IconData icon) {
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 40.0,
        right: 20.0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Text(message, style: AppTextStyles.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }
}
