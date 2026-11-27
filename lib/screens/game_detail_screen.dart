import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/emulator.dart';
import '../models/library.dart';
import '../models/resource_fields.dart';
import '../services/background_scrape_service.dart';
import '../services/emulator_service.dart';
import '../services/preferences_service.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/emulator_picker.dart';
import '../widgets/game_edit_dialog.dart';
import '../widgets/video_preview.dart';

/// 游戏详情页：只负责展示，所有修改都通过右上角「编辑」弹窗完成。
///
/// 采用轮播视图：左侧展示 box2D 封面、开发商、发行日期与简介，
/// 右侧依次轮播 wheel / box-texture / support-2D / fanart / mixrbv / 视频。
class GameDetailScreen extends StatefulWidget {
  final PlatformLibrary platform;
  final GameEntry game;

  /// 添加 ROM 后立即弹出编辑弹窗（用于新增条目后的搜刮/补全）。
  final bool editOnOpen;

  const GameDetailScreen({
    super.key,
    required this.platform,
    required this.game,
    this.editOnOpen = false,
  });

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen>
    with WidgetsBindingObserver {
  late GameEntry _game = widget.game;

  /// 详情页需要展示的字段（来自设置页「游戏详情页设置」）。
  Set<String> _detailFields = <String>{...ResourceFields.defaults};

  /// 库中数据是否发生变化，退出时回传给游戏库以触发刷新。
  bool _changed = false;
  bool _deleted = false;

  /// 当前平台的默认模拟器（未配置时为 null）。
  EmulatorConfig? _emulator;
  bool _launching = false;

  /// 已发起启动，等待从模拟器返回时给出提示。
  bool _awaitingReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _loadEmulator();
    BackgroundScrapeService.instance.addListener(_onBackgroundScrape);
    if (widget.editOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEditor());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BackgroundScrapeService.instance.removeListener(_onBackgroundScrape);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从模拟器回到应用时详情页仍在栈顶，顺带提示已经返回。
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      if (mounted) {
        AppToast.show(context, '已返回游戏详情',
            icon: Icons.arrow_back_rounded);
      }
    }
  }

  Future<void> _loadEmulator() async {
    final config = await EmulatorService.instance.configFor(
      widget.platform.platform,
    );
    if (!mounted) return;
    setState(() => _emulator = config);
  }

  Future<void> _loadSettings() async {
    final fields = await PreferencesService.detailFields;
    if (!mounted) return;
    setState(() => _detailFields = fields);
  }

  /// 后台搜刮会直接改写 platform.games，这里同步最新的条目内容。
  void _syncFromLibrary() {
    final games = widget.platform.games;
    var index = -1;
    final id = _game.id;
    // 改名会同时改变 ROM 文件名，因此优先用稳定的 UUID 定位。
    if (id != null && id.isNotEmpty) {
      index = games.indexWhere((g) => g.id == id);
    }
    if (index < 0) index = games.indexWhere((g) => g.file == _game.file);
    if (index < 0) {
      _deleted = true;
      return;
    }
    _game = games[index];
  }

  void _onBackgroundScrape() {
    if (!mounted) return;
    final previous = _game;
    setState(() {
      _syncFromLibrary();
      if (_game.name != previous.name ||
          _game.file != previous.file ||
          _game.cover != previous.cover) {
        _changed = true;
      }
    });
  }

  /// 启动游戏：未配置模拟器时先弹出选择框，配置完成后再启动。
  Future<void> _launchGame() async {
    if (_launching || _deleted) return;
    setState(() => _launching = true);
    try {
      while (true) {
        try {
          final outcome = await EmulatorService.instance.launchGame(
            platform: widget.platform,
            game: _game,
          );
          if (!mounted) return;
          final config = outcome.config;
          setState(() => _emulator = config);
          _awaitingReturn = true;
          final appOnly = config.mode == LaunchMode.app;
          AppToast.show(
            context,
            appOnly
                ? '已打开 ${config.label}'
                : outcome.direct
                    ? '正在通过 ${config.label} 启动…'
                    : '${config.label} 无法直接加载 ROM，已打开主界面',
            icon: outcome.direct && !appOnly
                ? Icons.play_arrow_rounded
                : Icons.info_outline_rounded,
          );
          return;
        } on EmulatorNotConfiguredException {
          final result = await showEmulatorPicker(
            context,
            platformName: widget.platform.platform,
            initial: _emulator,
          );
          if (result == null || result.config == null) return;
          await EmulatorService.instance.saveConfig(
            widget.platform.platform,
            result.config,
          );
          if (!mounted) return;
          setState(() => _emulator = result.config);
          // 让用户看到已保存的配置，再重试启动。
        }
      }
    } on EmulatorException catch (e) {
      if (mounted) {
        AppToast.show(context, e.message, icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  /// 信息栏中的启动按钮，下方附带当前默认模拟器名称。
  Widget _launchButton() {
    final emulator = _emulator;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _launching ? null : _launchGame,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: _launching
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.play_arrow_rounded, size: 19),
          label: Text(_launching ? '正在启动…' : '启动游戏',
              style: const TextStyle(fontSize: 13.5)),
        ),
        const SizedBox(height: 5),
        Text(
          emulator == null
              ? '尚未设置默认模拟器，启动时会提示选择'
              : '默认模拟器：${emulator.label}${emulator.core == null ? '' : ' · ${emulator.core}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
        ),
      ],
    );
  }

  Future<void> _openEditor() async {
    if (_deleted) return;
    final outcome = await GameEditDialog.show(
      context,
      platform: widget.platform,
      game: _game,
    );
    if (!mounted) return;
    if (outcome == GameEditOutcome.deleted) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _syncFromLibrary();
      if (outcome == GameEditOutcome.saved) _changed = true;
    });
  }

  String? get _coverFile {
    final relative = _game.cover;
    if (relative == null || relative.isEmpty) return null;
    final path = p.join(widget.platform.directory, relative);
    return File(path).existsSync() ? path : null;
  }

  String? get _videoPath {
    final relative = _game.video;
    if (relative == null || relative.isEmpty) return null;
    return p.join(widget.platform.directory, relative);
  }

  String? _resourcePathOf(String tag) {
    switch (tag) {
      case 'wheel':
        return _game.wheel;
      case 'box-texture':
        return _game.boxTexture;
      case 'box-3D':
        return _game.box3D;
      case 'support-2D':
        return _game.support2D;
      case 'fanart':
        return _game.fanart;
      case 'mixrbv':
        return _game.mixrbv;
    }
    return null;
  }

  String? _existingMediaPath(String tag) {
    final relative = _resourcePathOf(tag);
    if (relative == null || relative.isEmpty) return null;
    final path = p.join(widget.platform.directory, relative);
    return File(path).existsSync() ? path : null;
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_changed);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: landscape ? 46 : kToolbarHeight,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
          title: Text(
            _game.name.isEmpty ? _game.file : _game.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: '启动游戏',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: _launching ? null : _launchGame,
            ),
            IconButton(
              tooltip: '编辑游戏',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _openEditor,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _carouselBody(),
      ),
    );
  }

  Widget _tagChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.subtleFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _placeholderBox() => Container(
        color: AppTheme.subtleFill,
        child: const Center(
          child: Icon(Icons.image_outlined,
              size: 24, color: AppTheme.textSecondary),
        ),
      );

  // ---------------------------------------------------------------------------
  // 轮播视图
  // ---------------------------------------------------------------------------

  Widget _carouselBody() {
    final items = _carouselItems();
    final size = MediaQuery.of(context).size;
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    // 横屏为主：左右分栏，信息栏宽度随屏幕伸缩，封面高度按可用高度取比例。
    final wide = landscape && size.width >= 600;
    final infoWidth = (size.width * 0.3).clamp(240.0, 400.0);
    final coverHeight =
        wide ? ((size.height - 110) * 0.42).clamp(90.0, 200.0) : 120.0;
    final info = _carouselInfoPanel(coverHeight: coverHeight);

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: Column(
          children: [
            _progressBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: infoWidth, child: info),
                  const SizedBox(width: 16),
                  Expanded(child: _MediaCarousel(items: items)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 竖屏（次要场景）：信息在上，轮播在下，避免左右分栏过窄。
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          _progressBar(),
          SizedBox(height: 240, child: info),
          const SizedBox(height: 10),
          Expanded(child: _MediaCarousel(items: items)),
        ],
      ),
    );
  }

  Widget _carouselInfoPanel({required double coverHeight}) {
    final description = (_game.description ?? '').trim();
    final developer = _game.developer;
    final releaseDate = _game.releaseDate;
    final cover = _coverFile;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_detailFields.contains(ResourceFields.cover)) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: coverHeight,
                  width: double.infinity,
                  child: cover != null
                      ? Image.file(
                          File(cover),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _placeholderBox(),
                        )
                      : _placeholderBox(),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              _game.name,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.3),
            ),
            const SizedBox(height: 10),
            _launchButton(),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_detailFields.contains(ResourceFields.developer) &&
                    developer != null &&
                    developer.isNotEmpty)
                  _tagChip(Icons.business_outlined, developer),
                if (_detailFields.contains(ResourceFields.releaseDate) &&
                    releaseDate != null &&
                    releaseDate.isNotEmpty)
                  _tagChip(Icons.event_outlined, releaseDate),
              ],
            ),
            if (_detailFields.contains(ResourceFields.description) &&
                description.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('游戏简介',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SelectableText(
                description,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12.5, height: 1.7),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '${widget.platform.platform} · ${_game.file}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// 轮播内容：已下载的媒体资源，顺序固定为
  /// wheel → box-texture → support-2D → fanart → mixrbv → 视频。
  ///
  /// 这里不按「详情页设置」过滤：轮播用于浏览库中已有的全部媒体，
  /// 而左侧信息栏仍按设置勾选展示。
  List<_MediaItem> _carouselItems() {
    const order = <String>[
      'wheel',
      'box-texture',
      'support-2D',
      'fanart',
      'mixrbv',
    ];
    final items = <_MediaItem>[];
    for (final tag in order) {
      final path = _existingMediaPath(tag);
      if (path == null) continue;
      items.add(_MediaItem(label: ResourceFields.labelOf(tag), path: path));
    }
    final video = _videoPath;
    if (video != null && File(video).existsSync()) {
      items.add(_MediaItem(label: '游戏视频', path: video, isVideo: true));
    }
    return items;
  }

  // ---------------------------------------------------------------------------
  // 后台搜刮进度
  // ---------------------------------------------------------------------------

  Widget _progressBar() {
    final service = BackgroundScrapeService.instance;
    if (!service.isRunning) return const SizedBox.shrink();
    final key = '${widget.platform.directory}/${_game.file}';
    final snapshot = service.status;
    final state = snapshot.statuses[key];
    if (state == null) return const SizedBox.shrink();
    final progress = snapshot.progresses[key] ?? 0;
    final failed = state.startsWith('失败');
    final done = state == '已完成';
    if (done) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.subtleFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(failed ? Icons.error_outline : Icons.download,
                    size: 15,
                    color: failed ? AppTheme.danger : AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: failed ? AppTheme.danger : AppTheme.textPrimary,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
            if (!failed) ...[
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 3,
                backgroundColor: AppTheme.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 轮播中的一项媒体资源。
class _MediaItem {
  final String label;
  final String path;
  final bool isVideo;

  const _MediaItem({
    required this.label,
    required this.path,
    this.isVideo = false,
  });
}

/// 媒体轮播：一次展示一项，带左右箭头与页码指示。
class _MediaCarousel extends StatefulWidget {
  final List<_MediaItem> items;

  const _MediaCarousel({required this.items});

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MediaCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length &&
        _index >= widget.items.length) {
      _index = widget.items.isEmpty ? 0 : widget.items.length - 1;
    }
  }

  void _jump(int delta) {
    if (widget.items.length <= 1) return;
    final next = (_index + delta) % widget.items.length;
    final target = next < 0 ? next + widget.items.length : next;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return GlassCard(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.photo_library_outlined,
                  size: 42, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              const Text('暂无媒体资源',
                  style:
                      TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
              const SizedBox(height: 6),
              Text(
                '点击右上角编辑按钮可搜刮轮播图、包装、卡带等资源。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textSecondary.withOpacity(0.9),
                    fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.items.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _MediaPage(
                    item: widget.items[i],
                    index: i,
                    total: widget.items.length,
                  ),
                ),
              ),
              if (widget.items.length > 1) ...[
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(child: _arrow(Icons.chevron_left, -1)),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(child: _arrow(Icons.chevron_right, 1)),
                ),
              ],
            ],
          ),
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.items.length; i++)
                GestureDetector(
                  onTap: () => _controller.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index ? AppTheme.accent : AppTheme.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _arrow(IconData icon, int delta) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.86),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.border),
      ),
      child: IconButton(
        iconSize: 20,
        color: AppTheme.textPrimary,
        icon: Icon(icon),
        onPressed: () => _jump(delta),
      ),
    );
  }
}

class _MediaPage extends StatelessWidget {
  final _MediaItem item;
  final int index;
  final int total;

  const _MediaPage({
    required this.item,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.subtleFill,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: item.isVideo
                  ? Center(
                      child: VideoPreview(
                        path: item.path,
                        placeholderHeight: 160,
                      ),
                    )
                  : Image.file(
                      File(item.path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 32, color: AppTheme.textSecondary),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(item.label,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 12)),
              const SizedBox(width: 8),
              Text('${index + 1} / $total',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}