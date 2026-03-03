import 'package:flutter/material.dart';

/// Shows a loading dialog with optional message.
class LoadingDialog {
  static Future<void> show(BuildContext context, {String? message}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void hide(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Shows a confirmation dialog with custom title and message.
class ConfirmDialog {
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
    Color? confirmColor,
    IconData? icon,
    Widget? content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: confirmColor ?? cs.primary, size: 24),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(title)),
            ],
          ),
          content: content ?? Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancelText ?? '取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: confirmColor != null
                  ? FilledButton.styleFrom(backgroundColor: confirmColor)
                  : null,
              child: Text(confirmText ?? '确定'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}
