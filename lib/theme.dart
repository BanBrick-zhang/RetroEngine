import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// 统一的灰白色毛玻璃视觉风格。
class AppTheme {
  static const Color background = Color(0xFFF3F5F7);
  static const Color backgroundLight = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF616975);
  static const Color textPrimary = Color(0xFF272B32);
  static const Color textSecondary = Color(0xFF737B87);
  static const Color subtleFill = Color(0xFFEFF1F4);
  static const Color border = Color(0xFFE0E4E9);
  static const Color success = Color(0xFF4B9768);
  static const Color warning = Color(0xFFB1833B);
  static const Color danger = Color(0xFFC45C5C);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.light(
          primary: accent,
          onPrimary: Colors.white,
          secondary: accent,
          onSecondary: Colors.white,
          surface: surface,
          onSurface: textPrimary,
          error: danger,
          onError: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: textPrimary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.78),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          hintStyle: const TextStyle(color: textSecondary, fontSize: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accent, width: 1.2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            primary: accent,
            onPrimary: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: accent.withOpacity(0.14),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(primary: accent),
        ),
        iconTheme: const IconThemeData(color: textPrimary),
        dividerTheme: const DividerThemeData(color: border),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surface,
          contentTextStyle: const TextStyle(color: textPrimary),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  /// 带缓慢浮动光斑的浅灰渐变背景，作为毛玻璃的衬底。
  static Widget backdrop({required Widget child}) => GlassBackdrop(child: child);

  /// 页面内容需要避开底部导航栏时的额外间距。
  static const double bottomNavClearance = 92;

  static Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

/// 动态毛玻璃背景：光斑与渐变方向缓慢流动，为所有页面提供统一衬底。
class GlassBackdrop extends StatefulWidget {
  final Widget child;

  const GlassBackdrop({super.key, required this.child});

  @override
  State<GlassBackdrop> createState() => _GlassBackdropState();
}

class _GlassBackdropState extends State<GlassBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final angle = _controller.value * math.pi * 2;
        final dx = math.sin(angle) * 22;
        final dy = math.cos(angle * 0.8) * 18;
        final dx2 = math.cos(angle * 0.6) * 26;
        final dy2 = math.sin(angle * 0.7) * 20;

        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1 + dx / 320, -1 + dy / 320),
                    end: Alignment(1 + dx2 / 320, 1 + dy2 / 320),
                    colors: const <Color>[
                      Color(0xFFFAFBFC),
                      Color(0xFFEDEFF3),
                      Color(0xFFF7F8FA),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -130 + dy,
              left: -90 + dx,
              child: AppTheme._blob(320, Colors.white.withOpacity(0.85)),
            ),
            Positioned(
              top: 100 + dy2,
              right: -120 + dx2,
              child: AppTheme._blob(280,
                  const Color(0xFFE6ECF5).withOpacity(0.55)),
            ),
            Positioned(
              bottom: -170 + dy2,
              right: -70 + dx2,
              child: AppTheme._blob(360, Colors.black.withOpacity(0.025)),
            ),
            Positioned.fill(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
    );
  }
}

/// 可点击的毛玻璃卡片。
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final VoidCallback? onTap;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.blur = 14,
    this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.92),
              width: 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return Material(color: Colors.transparent, child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: card,
    ));
  }
}

/// Flutter 3.0 兼容的 FilledButton（3.3+ 才内置）。
class FilledButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;

  const FilledButton({
    Key? key,
    required this.onPressed,
    this.style,
    required this.child,
  }) : super(key: key);

  factory FilledButton.icon({
    Key? key,
    required VoidCallback? onPressed,
    ButtonStyle? style,
    required Widget icon,
    required Widget label,
  }) {
    return FilledButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[icon, const SizedBox(width: 8), label],
      ),
    );
  }

  factory FilledButton.tonal({
    Key? key,
    required VoidCallback? onPressed,
    ButtonStyle? style,
    required Widget child,
  }) {
    return FilledButton(key: key, onPressed: onPressed, style: style, child: child);
  }

  factory FilledButton.tonalIcon({
    Key? key,
    required VoidCallback? onPressed,
    ButtonStyle? style,
    required Widget icon,
    required Widget label,
  }) {
    return FilledButton.icon(
      key: key,
      onPressed: onPressed,
      style: style,
      icon: icon,
      label: label,
    );
  }

  static ButtonStyle styleFrom({
    Color? backgroundColor,
    Color? foregroundColor,
    double? elevation,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    OutlinedBorder? shape,
  }) {
    return ElevatedButton.styleFrom(
      primary: backgroundColor,
      onPrimary: foregroundColor,
      elevation: elevation,
      textStyle: textStyle,
      padding: padding,
      minimumSize: minimumSize,
      shape: shape,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(onPressed: onPressed, style: style, child: child);
  }
}

/// 小号标签胶囊。
class GlassChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  const GlassChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: selected ? AppTheme.accent : Colors.white.withOpacity(0.72),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? Colors.white : AppTheme.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : AppTheme.textSecondary,
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 统一的分段标题。
class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final IconData? icon;

  const SectionTitle(this.title, {super.key, this.trailing, this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 17, color: AppTheme.accent),
          const SizedBox(width: 8),
        ],
        Text(title, style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        )),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 可折叠的毛玻璃设置卡片，标题栏始终可见，内容区带展开动画。
class GlassExpansionCard extends StatefulWidget {
  final String title;
  final IconData? icon;
  final bool initiallyExpanded;
  final List<Widget> children;
  final EdgeInsetsGeometry contentPadding;

  const GlassExpansionCard({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.initiallyExpanded = false,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  @override
  State<GlassExpansionCard> createState() => _GlassExpansionCardState();
}

class _GlassExpansionCardState extends State<GlassExpansionCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(18),
              bottom: _expanded ? Radius.zero : const Radius.circular(18),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  if (widget.icon != null) ...<Widget>[
                    Icon(widget.icon, size: 17, color: AppTheme.accent),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: widget.contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
