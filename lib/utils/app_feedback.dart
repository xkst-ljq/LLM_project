import 'package:flutter/material.dart';

class AppFeedback {
  static void showSnack(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 2),
      }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
      ),
    );
  }

  static void showSuccessSnack(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 2),
      }) {
    showSnack(context, message, duration: duration);
  }

  static Future<void> showErrorDialog(
      BuildContext context, {
        required String title,
        required Object error,
        String? message,
        String? suggestion,
      }) {
    final errorText = error.toString();

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message != null && message.trim().isNotEmpty) ...[
                Text(message),
                const SizedBox(height: 12),
              ],
              const Text(
                '错误详情：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SelectableText(
                errorText,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.redAccent,
                ),
              ),
              if (suggestion != null && suggestion.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '建议：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  suggestion,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}