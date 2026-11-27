import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 全局底部浮层提示。
///
/// 通过根 Overlay 展示，因此始终位于所有页面与弹窗之上；
/// 展示 1 秒后自动淡出，也可以向上滑动提前关闭。
class AppToast {
  static VoidCallback? _dismissCurrent;

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? color,
  }) {
    OverlayState? overlay;
    try {
      overlay = Overlay.of(context, rootOverlay: true);
    } catch (_) {
      // 上下文已失效（页面销毁）时静默忽略。
      return;
    }
    if (overlay == null) return;
    // 同一时间只保留一条提示，新的提示替换旧的。
    dismiss();

    late final OverlayEntry entry;
    var removed = false;
    void remove() {
      if (removed) return;
      removed = true;
      entry.remove();
      if (identical(_dismissCurrent, remove)) _dismissCurrent = null;
    }

    entry = OverlayEntry(
      builder: (_) => _ToastLayer(
        message: message,
        icon: icon ?? Icons.info_outline_rounded,
        color: color ?? AppTheme.accent,
        onClosed: remove,
      ),
    );
    _dismissCurrent = remove;
    overlay.insert(entry);
  }

  static void dismiss() {
    final current = _dismissCurrent;
    _dismissCurrent = null;
    current?.call();
  }
}

class _ToastLayer extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback onClosed;

  const _ToastLayer({
    required this.message,
    required this.icon,
    required this.color,
    required this.onClosed,
  });

  @override
  State<_ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends State<_ToastLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _controller.forward().whenComplete(() {
      if (!mounted || _closing) return;
      _timer = Timer(const Duration(seconds: 1), _close);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onClosed();
  }

  void _dismissBySwipe() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 18 + bottomInset,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.6),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Dismissible(
                  key: const ValueKey<String>('app-toast'),
                  direction: DismissDirection.up,
                  onDismissed: (_) => _dismissBySwipe(),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(widget.icon, size: 18, color: widget.color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}