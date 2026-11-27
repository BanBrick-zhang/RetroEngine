import 'package:flutter/material.dart';

import '../theme.dart';

/// 统一的轻量提示弹窗：图标 + 标题 + 说明 + 可选操作。
Future<void> showInfoDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppTheme.accent.withOpacity(0.1),
                ),
                child: Icon(icon, size: 22, color: AppTheme.accent),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onAction?.call();
                      },
                      child: Text(actionLabel),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}