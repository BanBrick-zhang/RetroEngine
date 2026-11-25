import 'package:flutter/material.dart';

import '../theme.dart';

/// 翻译结果确认弹窗。
///
/// 展示原文与可直接编辑的译文，用户可选择「应用翻译」写回内容，
/// 或点「取消」放弃本次翻译。返回最终译文（已去除首尾空白），取消返回 null。
Future<String?> showTranslationResultDialog(
  BuildContext context, {
  required String original,
  required String translated,
  String title = '翻译结果',
  String? directionLabel,
  int maxLines = 6,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TranslationResultDialog(
      original: original,
      translated: translated,
      title: title,
      directionLabel: directionLabel,
      maxLines: maxLines,
    ),
  );
}

class _TranslationResultDialog extends StatefulWidget {
  final String original;
  final String translated;
  final String title;
  final String? directionLabel;
  final int maxLines;

  const _TranslationResultDialog({
    required this.original,
    required this.translated,
    required this.title,
    this.directionLabel,
    this.maxLines = 6,
  });

  @override
  State<_TranslationResultDialog> createState() =>
      _TranslationResultDialogState();
}

class _TranslationResultDialogState extends State<_TranslationResultDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.translated);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Row(
        children: [
          const Icon(Icons.translate, color: AppTheme.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.title,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 17)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('原文',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                if (widget.directionLabel != null) ...[
                  const Spacer(),
                  Text(widget.directionLabel!,
                      style: const TextStyle(
                          color: AppTheme.accent, fontSize: 11)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                widget.original,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 14),
            const Text('译文（可直接修改）',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: widget.maxLines,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: '翻译结果',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _apply,
          child: const Text('应用翻译'),
        ),
      ],
    );
  }
}