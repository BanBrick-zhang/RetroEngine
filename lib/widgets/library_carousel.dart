import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/pinyin_initials.dart';
import '../models/library.dart';
import '../theme.dart';

/// 游戏库轮播视图：正方形封面卡片，信息直接叠加在封面上。
///
/// 采用“书柜”式布局：居中卡片完整显示，左右相邻卡片略微缩小并下沉露出两侧；
/// 切换时卡片一升一降，形成上浮/下沉的过渡。卡片不使用投影，
/// 也不渲染高斯模糊铺底，避免切换时模糊层反复重建造成的闪烁。
class LibraryCarousel extends StatefulWidget {
  final PlatformLibrary platform;
  final ValueChanged<GameEntry> onOpen;

  const LibraryCarousel({
    super.key,
    required this.platform,
    required this.onOpen,
  });

  @override
  State<LibraryCarousel> createState() => _LibraryCarouselState();
}

class _LibraryCarouselState extends State<LibraryCarousel> {
  /// 视口比例同时决定中间卡片宽度与两侧露出比例。
  ///
  /// 竖屏保持一枚卡片居中、两侧露出窄边；横屏可用高度变小，若继续沿用
  /// 0.74 会让相邻卡片被缩放后完全滑出视口，因此按宽高比动态缩小视口，
  /// 让横屏也能同时看到左右两张卡片。
  PageController _controller = PageController(viewportFraction: 0.74);
  double _fraction = 0.74;
  int _index = 0;

  /// 首字母指示条内容层，用于把拖动坐标换算成字母下标。
  final GlobalKey _letterStripKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 首帧后预解码相邻封面，减少左右切换时图片从占位符跳出的闪烁。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheAround(0);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    final landscape = size.width > size.height;
    // 横屏时卡片受高度限制，视口要比竖屏更窄，相邻卡片缩放后才不会整体
    // 滑出可视区域；两种方向都尽量放大视口，让相邻卡片贴得更紧。
    final fraction = landscape ? 0.52 : 0.74;
    if ((fraction - _fraction).abs() < 0.02) return;
    final previous = _controller;
    _fraction = fraction;
    _controller = PageController(
      viewportFraction: fraction,
      initialPage: _index,
    );
    // 旧控制器可能仍被当前帧的 PageView 引用，下一帧再释放。
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _precacheAround(int index) {
    final games = widget.platform.games;
    for (final offset in const <int>[1, -1]) {
      final target = index + offset;
      if (target < 0 || target >= games.length) continue;
      final relative = games[target].cover;
      if (relative == null || relative.isEmpty) continue;
      final file = File(p.join(widget.platform.directory, relative));
      if (!file.existsSync()) continue;
      precacheImage(FileImage(file), context);
    }
  }

  void _jump(int delta) {
    final count = widget.platform.games.length;
    if (count <= 1) return;
    final target = (_index + delta).clamp(0, count - 1);
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final games = widget.platform.games;
    if (games.isEmpty) return const SizedBox.shrink();

    // 条目被外部删除后页码可能越界，取当前有效页。
    final index = _index.clamp(0, games.length - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          6, 4, 6, AppTheme.bottomNavClearance + 8),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: games.length,
                  allowImplicitScrolling: true,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    _precacheAround(i);
                  },
                  itemBuilder: (context, i) => _pageItem(games[i], i),
                ),
              ],
            ),
          ),
          if (games.length > 1) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _arrow(Icons.chevron_left, -1, enabled: index > 0),
                Expanded(child: _letterStrip(games, index)),
                _arrow(Icons.chevron_right, 1,
                    enabled: index < games.length - 1),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 单页：在可用区域内保持 1:1 的方形卡片并居中。
  ///
  /// 卡片本身只构建一次，滚动时仅由 [_BookshelfPage] 调整位移与缩放。
  /// 页内留白只保留很小的一圈，避免相邻卡片之间出现过大的空隙。
  Widget _pageItem(GameEntry game, int index) {
    return RepaintBoundary(
      child: _BookshelfPage(
        controller: _controller,
        index: index,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: AspectRatio(
              aspectRatio: 1,
              child: _gameCard(game, index),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gameCard(GameEntry game, int index) {
    final total = widget.platform.games.length;
    final name = game.name.isEmpty ? p.basename(game.file) : game.name;
    final developer = game.developer;
    final releaseDate = game.releaseDate;
    final meta = [
      if (developer != null && developer.isNotEmpty) developer,
      if (releaseDate != null && releaseDate.isNotEmpty) releaseDate,
    ].join(' · ');
    final hasCover = game.cover != null && game.cover!.isNotEmpty;
    final hasVideo = game.video != null && game.video!.isNotEmpty;
    final romExists =
        File(p.join(widget.platform.directory, game.file)).existsSync();

    return GlassCard(
      padding: const EdgeInsets.all(8),
      radius: 22,
      blur: 0,
      onTap: () {
        // 点击两侧露出的卡片时先聚焦，再点一次才打开，避免误触。
        if (index != _index) {
          _controller.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        } else {
          widget.onOpen(game);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _cover(game),
            // 顶部轻渐变保证页码与状态图标在亮色封面上可读。
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.34),
                      Colors.black.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
            // 底部信息层：名称、厂商与发行日期，不展示简介。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 46, 14, 13),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0),
                      Colors.black.withOpacity(0.78),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.86),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!hasCover)
              const Positioned(
                left: 12,
                top: 12,
                child: _Badge(text: '待搜刮'),
              ),
            Positioned(
              right: 12,
              top: 12,
              child: Row(
                children: [
                  if (hasVideo)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.movie_outlined,
                          size: 16, color: Colors.white),
                    ),
                  if (!romExists)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.warning_amber_rounded,
                          size: 16, color: Colors.white),
                    ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.38),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${index + 1}/$total',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部首字母指示条：按库内顺序取出首字母（重复的只保留第一次出现），
  /// 点按或横向拖动字母即可跳到该首字母的第一个游戏。
  Widget _letterStrip(List<GameEntry> games, int index) {
    final markers = _buildMarkers(games);
    if (markers.isEmpty) return const SizedBox(height: 28);
    final current = PinyinInitials.of(_nameOf(games[index]));

    return SizedBox(
      height: 30,
      child: Listener(
        onPointerMove: (event) => _hitLetterStrip(event.position, markers),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            key: _letterStripKey,
            children: [
              for (final marker in markers)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _animateTo(marker.index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: marker.letter == current
                          ? AppTheme.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      marker.letter,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: marker.letter == current
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: marker.letter == current
                            ? Colors.white
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<_InitialMarker> _buildMarkers(List<GameEntry> games) {
    final markers = <_InitialMarker>[];
    final seen = <String>{};
    for (var i = 0; i < games.length; i++) {
      final letter = PinyinInitials.of(_nameOf(games[i]));
      if (!seen.add(letter)) continue;
      markers.add(_InitialMarker(letter: letter, index: i));
    }
    return markers;
  }

  String _nameOf(GameEntry game) =>
      game.name.isEmpty ? p.basename(game.file) : game.name;

  /// 把拖动坐标映射到字母，触发对应页的跳转。
  void _hitLetterStrip(Offset globalPosition, List<_InitialMarker> markers) {
    final box =
        _letterStripKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(globalPosition);
    // 每个字母占 26 宽 + 左右各 2 的间距。
    var target = ((local.dx - 2) / 30).floor();
    if (target < 0 || target >= markers.length) return;
    _animateTo(markers[target].index);
  }

  void _animateTo(int target) {
    if (target == _index) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// 正方形卡片直接铺满封面，无需模糊铺底，避免切换时闪烁。
  Widget _cover(GameEntry game) {
    final relative = game.cover;
    if (relative == null || relative.isEmpty) return _coverPlaceholder();
    final file = File(p.join(widget.platform.directory, relative));
    if (!file.existsSync()) return _coverPlaceholder();

    return Image.file(
      file,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => _coverPlaceholder(),
    );
  }

  Widget _coverPlaceholder() => Container(
        color: AppTheme.subtleFill,
        child: const Center(
          child: Icon(Icons.gamepad_outlined,
              size: 44, color: AppTheme.textSecondary),
        ),
      );

  Widget _arrow(IconData icon, int delta, {required bool enabled}) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.35,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.88),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.border),
        ),
        child: IconButton(
          iconSize: 18,
          color: AppTheme.textPrimary,
          tooltip: delta < 0 ? '上一款' : '下一款',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          icon: Icon(icon),
          onPressed: enabled ? () => _jump(delta) : null,
        ),
      ),
    );
  }
}

/// 书柜式单页：随滚动位置在“上浮聚焦”和“下沉”之间过渡。
///
/// [child] 在外部构建并缓存，这里只调整位移与缩放，避免滚动时重建封面图片。
class _BookshelfPage extends StatelessWidget {
  final PageController controller;
  final int index;
  final Widget child;

  const _BookshelfPage({
    required this.controller,
    required this.index,
    required this.child,
  });

  double get _page {
    if (controller.hasClients && controller.position.haveDimensions) {
      return controller.page ?? controller.initialPage.toDouble();
    }
    return controller.initialPage.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final distance = (_page - index).abs().clamp(0.0, 1.0);
        final focus = 1.0 - distance;
        // 两侧卡片只做很小的缩放与下沉：缩得越少、下沉越浅，相邻卡片看起来
        // 就越紧凑。不使用投影，卡面本身也不降低透明度，避免出现暗色边界
        // 或背景透出造成的割裂感。
        final scale = 0.97 + 0.03 * focus;
        final dy = 3.0 * distance;

        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

/// 底部字母条上的一个首字母及其对应页。
class _InitialMarker {
  final String letter;
  final int index;

  const _InitialMarker({required this.letter, required this.index});
}

/// 封面左上角的角标。
class _Badge extends StatelessWidget {
  final String text;

  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 10)),
      ),
    );
  }
}