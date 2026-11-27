import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/library.dart';
import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/toml_service.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/info_dialog.dart';
import '../widgets/library_carousel.dart';
import '../widgets/permission_dialog.dart';
import '../widgets/side_menu.dart';
import 'cloud_save_screen.dart';
import 'file_browser_screen.dart';
import 'game_detail_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  final String? libraryPath;
  final VoidCallback onReload;
  final ValueChanged<String>? onLibraryChanged;

  const LibraryScreen({
    super.key,
    required this.libraryPath,
    required this.onReload,
    this.onLibraryChanged,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  List<PlatformLibrary> _platforms = <PlatformLibrary>[];
  int _selected = 0;
  bool _loading = true;
  String? _error;
  String? _boundPath;
  int _scannedDirs = 0;

  /// 游戏列表展示模式：`list` / `grid` / `carousel`。
  String _viewMode = 'grid';

  /// 是否因缺少权限而等待用户从系统设置返回后自动继续选择目录。
  bool _pendingChoose = false;

  /// 平台标签的定位键，用于切换平台后把选中标签滚动到可视区域中央。
  List<GlobalKey> _tabKeys = <GlobalKey>[];

  late final FocusNode _gamepadFocus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gamepadFocus = FocusNode(debugLabel: 'gamepad');
    _loadViewMode();
    _load();
  }

  Future<void> _loadViewMode() async {
    final mode = await PreferencesService.libraryViewMode;
    if (!mounted) return;
    setState(() => _viewMode = mode);
  }

  Future<void> _setViewMode(String mode) async {
    setState(() => _viewMode = mode);
    await PreferencesService.setLibraryViewMode(mode);
  }

  IconData get _viewModeIcon {
    switch (_viewMode) {
      case 'list':
        return Icons.view_list_outlined;
      case 'carousel':
        return Icons.view_carousel_outlined;
      default:
        return Icons.grid_view_outlined;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gamepadFocus.dispose();
    super.dispose();
  }

  /// 手柄按键：A 打开游戏、X 添加 ROM、L/R 切换平台、START 次级菜单。
  void _handleGamepadKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.enter) {
      if (_platforms.isNotEmpty && !_loading) {
        final platform = _platforms[_selected];
        if (platform.games.isNotEmpty) {
          _openGame(platform, platform.games.first);
        }
      }
    } else if (key == LogicalKeyboardKey.gameButtonX ||
        key == LogicalKeyboardKey.keyX) {
      if (_platforms.isNotEmpty) _addRom();
    } else if (key == LogicalKeyboardKey.gameButtonLeft1 ||
        key == LogicalKeyboardKey.gameButtonLeft2 ||
        key == LogicalKeyboardKey.keyQ) {
      _switchPlatform(-1);
    } else if (key == LogicalKeyboardKey.gameButtonRight1 ||
        key == LogicalKeyboardKey.gameButtonRight2 ||
        key == LogicalKeyboardKey.keyE) {
      _switchPlatform(1);
    } else if (key == LogicalKeyboardKey.gameButtonStart ||
        key == LogicalKeyboardKey.escape) {
      _openSideMenu();
    }
  }

  void _switchPlatform(int delta) {
    if (_platforms.isEmpty || _loading) return;
    setState(() {
      _selected = (_selected + delta) % _platforms.length;
      if (_selected < 0) _selected += _platforms.length;
    });
    _centerSelectedTab();
  }

  /// 把当前选中的平台标签滚动到可视区域中央，避免长标签条下看不到选中项。
  void _centerSelectedTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selected < 0 || _selected >= _tabKeys.length) return;
      final target = _tabKeys[_selected].currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_pendingChoose) {
      _pendingChoose = false;
      _resumeChooseLibrary();
    } else {
      _refreshIfAccessible();
    }
  }

  /// 授权返回后：已授权则自动继续打开目录选择器，否则提示一次。
  Future<void> _resumeChooseLibrary() async {
    if (!mounted) return;
    if (!await LibraryService.hasStorageAccess()) {
      if (mounted) _showMessage('尚未开启“所有文件访问权限”，请重试');
      return;
    }
    if (mounted) await _chooseLibrary();
  }

  /// 从系统设置返回或切回前台时，若已可访问则静默刷新列表。
  Future<void> _refreshIfAccessible() async {
    if (!await LibraryService.hasStorageAccess()) return;
    if (!mounted) return;
    await _load(silent: true);
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryPath != widget.libraryPath) _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    // 以本地持久化为准，避免主页面状态尚未同步时误判为未绑定。
    final stored = await PreferencesService.libraryPath;
    final path = (stored != null && stored.isNotEmpty) ? stored : widget.libraryPath;
    if (mounted) setState(() => _boundPath = path);

    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _scannedDirs = 0;
          _platforms = <PlatformLibrary>[];
        });
      }
      return;
    }
    try {
      final platforms = await LibraryService.loadLibrary(path);
      final dir = Directory(path);
      final dirs = await dir.exists()
          ? (await dir.list().toList()).whereType<Directory>().length
          : 0;
      if (mounted) {
        setState(() {
          _platforms = platforms;
          _scannedDirs = dirs;
          if (_selected >= platforms.length) _selected = 0;
          _tabKeys = List<GlobalKey>.generate(
            platforms.length,
            (_) => GlobalKey(debugLabel: 'platform-tab'),
          );
          _loading = false;
        });
        _centerSelectedTab();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: landscape ? 48 : kToolbarHeight,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: '次级菜单',
          onPressed: _openSideMenu,
        ),
        // 顶部栏由平台标签条独占，当前平台与其后所有平台横向排列。
        title: _platformStrip(),
        actions: [
          PopupMenuButton<String>(
            tooltip: '切换视图',
            icon: Icon(_viewModeIcon),
            onSelected: _setViewMode,
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              _viewMenuItem('list', Icons.view_list_outlined, '列表视图'),
              _viewMenuItem('grid', Icons.grid_view_outlined, '网格视图'),
              _viewMenuItem('carousel', Icons.view_carousel_outlined, '轮播图视图'),
            ],
          ),
        ],
      ),
      // 按键提示占用独立底栏，浮动按钮会自动排在其上方，避免互相遮挡。
      bottomNavigationBar: _buildGamepadHint(),
      body: RawKeyboardListener(
        focusNode: _gamepadFocus,
        autofocus: true,
        onKey: _handleGamepadKey,
        child: AppTheme.backdrop(
          child: _loading
              ? const Center(child: GlassLoader(message: '正在扫描游戏库…'))
              : _error != null
                  ? _errorView()
                  : _platforms.isEmpty
                      ? _emptyView()
                      : GestureDetector(
                          // 左右滑动切换平台；页面内容横向自滑动由轮播自身处理。
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragEnd: (details) {
                            final velocity = details.primaryVelocity ?? 0;
                            if (velocity.abs() < 140) return;
                            _switchPlatform(velocity < 0 ? 1 : -1);
                          },
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (current, previous) => Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                ...previous,
                                if (current != null) current,
                              ],
                            ),
                            transitionBuilder: (child, animation) {
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                                reverseCurve: Curves.easeInCubic,
                              );
                              return FadeTransition(
                                opacity: curved,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                          begin: 0.985, end: 1.0)
                                      .animate(curved),
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey<String>(
                                  'platform-view-${_platforms[_selected].directory}'),
                              child: _libraryView(),
                            ),
                          ),
                        ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _viewMenuItem(
      String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accent),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }

  /// AppBar 内的平台标签条：当前平台与其余已扫描平台横向排列，可滚动或点按切换。
  Widget _platformStrip() {
    if (_platforms.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '未绑定游戏库',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          for (var index = 0; index < _platforms.length; index++)
            Padding(
              padding: EdgeInsets.only(left: index == 0 ? 4 : 6),
              child: Center(
                child: KeyedSubtree(
                  key: index < _tabKeys.length ? _tabKeys[index] : null,
                  child: GlassChip(
                    label:
                        '${_platforms[index].platform} (${_platforms[index].games.length})',
                    icon: _platforms[index].hasToml
                        ? null
                        : Icons.auto_awesome_outlined,
                    selected: index == _selected,
                    onTap: () {
                      if (index == _selected) return;
                      setState(() => _selected = index);
                      _centerSelectedTab();
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 底部手柄按键指示：左侧 A/X，右侧 L/R 与 START。
  Widget _buildGamepadHint() {
    Widget chip(String key, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(key,
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 10)),
            ],
          ),
        );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: IgnorePointer(
        child: Row(
          children: [
            chip('A', '打开'),
            const SizedBox(width: 6),
            chip('X', '添加'),
            const Spacer(),
            chip('L', '切换平台'),
            const SizedBox(width: 6),
            chip('R', '切换平台'),
            const SizedBox(width: 6),
            chip('START', '菜单'),
          ],
        ),
      ),
    );
  }

  /// 左上角次级菜单：账号、游戏生涯、云存档、设置选项。
  Future<void> _openSideMenu() async {
    final selected = await showSideMenu(
      context,
      actions: const <SideMenuAction>[
        SideMenuAction(
          id: 'account',
          label: '账号',
          subtitle: 'ScreenScraper 账号与配额',
          icon: Icons.person_outline,
        ),
        SideMenuAction(
          id: 'career',
          label: '游戏生涯',
          subtitle: '游玩时长与通关统计',
          icon: Icons.emoji_events_outlined,
        ),
        SideMenuAction(
          id: 'cloud',
          label: '云存档',
          subtitle: '跨设备同步存档',
          icon: Icons.cloud_outlined,
        ),
        SideMenuAction(
          id: 'settings',
          label: '设置选项',
          subtitle: '目录、搜刮与界面偏好',
          icon: Icons.settings_outlined,
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'account':
        await _showAccountInfo();
        break;
      case 'career':
        await _showPlannedFeature(
          title: '游戏生涯',
          icon: Icons.emoji_events_outlined,
          message: '游玩时长、最近游玩与通关进度统计正在开发中，'
              '后续版本将结合存档与启动记录自动生成。',
        );
        break;
      case 'cloud':
        await Navigator.of(context).push<void>(
          AppPageRoute<void>(
            settings: const RouteSettings(name: 'cloud-save'),
            builder: (_) => const CloudSaveScreen(),
          ),
        );
        break;
      case 'settings':
        await _openSettings();
        break;
    }
  }

  /// 账号入口：展示 ScreenScraper 账号状态，可直接跳转设置。
  Future<void> _showAccountInfo() async {
    final username = await PreferencesService.ssUsername;
    final configured = username != null && username.isNotEmpty;
    if (!mounted) return;
    await showInfoDialog(
      context,
      icon: Icons.person_outline,
      title: '账号',
      message: configured
          ? '当前已配置 ScreenScraper 账号：$username。\n'
              '账号用于提升搜刮配额，可在设置中修改或清除。'
          : '尚未配置 ScreenScraper 个人账号。\n'
              '开发者凭据已内置，可直接搜刮；填写个人账号可提升每日配额。',
      actionLabel: '打开设置',
      onAction: _openSettings,
    );
  }

  Future<void> _showPlannedFeature({
    required String title,
    required String message,
    required IconData icon,
  }) {
    return showInfoDialog(context, icon: icon, title: title, message: message);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      AppPageRoute<void>(
        settings: const RouteSettings(name: 'settings'),
        builder: (_) => SettingsScreen(onLibraryChanged: (_) {}),
      ),
    );
    if (mounted) await _load();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    AppToast.show(context, message);
  }

  Widget _emptyView() {
    final bound = _boundPath != null && _boundPath!.isNotEmpty;
    // 横屏高度有限，内容可滚动以防卡片被裁切。
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity),
          ),
          child: Center(
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
              radius: 18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    bound
                        ? Icons.search_off_outlined
                        : Icons.folder_off_outlined,
                    size: 48,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    bound ? '未识别到游戏 ROM' : '还没有绑定游戏库',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (bound) ...[
                    Text(
                      '当前目录：$_boundPath',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.accent, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '扫描到 $_scannedDirs 个子目录，未发现可识别的 ROM。\n'
                      '请确认选择的是游戏库总目录（其下应包含 FC、GBA 等平台文件夹）。',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ] else
                    const Text(
                      '在「设置」中绑定 SaveDeck 游戏库总目录，\n即可自动识别各平台 ROM 与 savedeck.toml。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.6),
                    ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _chooseLibrary,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(bound ? '重新选择目录' : '选择游戏库目录'),
                  ),
                  if (bound) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重新扫描'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseLibrary() async {
    // Android 11+ 无“所有文件访问权限”时文件浏览器读不到共享存储，先引导授权；
    // 用户从系统设置返回后自动继续选择目录。
    final access = await ensureStorageAccessPrompt(
      context,
      isMounted: () => mounted,
    );
    if (!mounted) return;
    if (access == StorageAccessPrompt.openedSettings) {
      _pendingChoose = true;
      return;
    }
    if (access != StorageAccessPrompt.granted) return;

    final root = _boundPath ?? await LibraryService.defaultRoot();
    if (!mounted) return;
    final path = await Navigator.of(context).push<String>(
      AppPageRoute(
        builder: (_) => FileBrowserScreen(initialPath: root, title: '选择游戏库总目录'),
      ),
    );
    if (path == null || !mounted) return;

    // 1. 先持久化路径：用户去系统设置授权后返回，无需再次选择目录。
    await PreferencesService.setLibraryPath(path);
    if (!mounted) return;
    setState(() => _boundPath = path);

    // 2. 在页面仍然挂载时完成权限校验与授权引导。
    //    必须在通知父级之前完成——通知父级会让本页面按新 key 重建、旧 State
    //    被销毁，导致授权对话框丢失（Android 13 上选完目录不弹引导的根因）。
    final outcome = await ensureDirectoryAccess(
      context,
      path,
      isMounted: () => mounted,
    );
    if (!mounted) return;

    if (outcome == DirectoryAccessOutcome.awaitingSettings) {
      _showMessage('目录已保存，开启“所有文件访问权限”后返回应用会自动读取');
    }

    // 3. 再通知父级刷新；父级重建后会以新目录重新扫描。
    if (widget.onLibraryChanged != null) {
      widget.onLibraryChanged!(path);
    } else {
      widget.onReload();
      await _load();
    }
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );

  Widget _libraryView() {
    final platform = _platforms[_selected];
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Column(
      children: [
        SizedBox(height: landscape ? 2 : 6),
        // 平台名称与排序统一在设置的「游戏库管理」中维护，这里只保留状态提示。
        if (platform.loadError != null)
          _statusBanner(
            icon: Icons.error_outline,
            color: AppTheme.danger,
            text: '配置读取失败：${platform.loadError}',
            landscape: landscape,
          ),
        if (!platform.hasToml)
          _statusBanner(
            icon: Icons.info_outline,
            color: AppTheme.accent,
            text: '尚未建立 savedeck.toml，点击游戏搜刮后自动生成',
            landscape: landscape,
          ),
        SizedBox(height: landscape ? 2 : 6),
        Expanded(
          // 切换平台时重置滚动位置，避免沿用上一个平台的偏移。
          child: KeyedSubtree(
            key: ValueKey('platform-body-${platform.directory}'),
            child: platform.games.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videogame_asset_off_outlined,
                            size: 44, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          platform.hasToml ? '该平台还没有游戏' : '未识别到 ROM 文件',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _addRom,
                          style: FilledButton.styleFrom(
                              foregroundColor: AppTheme.textPrimary,
                              backgroundColor: AppTheme.subtleFill),
                          child: const Text('添加 ROM'),
                        ),
                      ],
                    ),
                  )
                : _gamesView(platform),
          ),
        ),
      ],
    );
  }

  /// 内容区顶部的单行状态提示。
  Widget _statusBanner({
    required IconData icon,
    required Color color,
    required String text,
    required bool landscape,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, landscape ? 2 : 4, 16, 0),
      child: GlassCard(
        padding:
            EdgeInsets.symmetric(horizontal: 12, vertical: landscape ? 5 : 8),
        radius: 12,
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 按当前视图模式渲染游戏列表。
  Widget _gamesView(PlatformLibrary platform) {
    switch (_viewMode) {
      case 'list':
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              12, 0, 12, AppTheme.bottomNavClearance + 12),
          itemCount: platform.games.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final game = platform.games[index];
            return _gameRow(platform, game,
                onTap: () => _openGame(platform, game));
          },
        );
      case 'carousel':
        return LibraryCarousel(
          platform: platform,
          onOpen: (game) => _openGame(platform, game),
        );
      default:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
              12, 0, 12, AppTheme.bottomNavClearance + 12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisExtent: 238,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: platform.games.length,
          itemBuilder: (context, index) {
            final game = platform.games[index];
            return _gameCard(platform, game,
                onTap: () => _openGame(platform, game));
          },
        );
    }
  }

  Widget _gameRow(PlatformLibrary platform, GameEntry game,
      {required VoidCallback onTap}) {
    final name = game.name.isEmpty ? game.file : game.name;
    final developer = game.developer;
    final releaseDate = game.releaseDate;
    final cover = _coverPathOf(platform, game);

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 46,
              height: 60,
              child: cover != null
                  ? Image.file(
                      File(cover),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _coverPlaceholder(),
                    )
                  : _coverPlaceholder(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (developer != null && developer.isNotEmpty) developer,
                    if (releaseDate != null && releaseDate.isNotEmpty)
                      releaseDate,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Text(
                  game.file,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 18, color: AppTheme.textSecondary),
        ],
      ),
    );
  }

  /// 解析封面文件路径，缺失时返回 null。
  String? _coverPathOf(PlatformLibrary platform, GameEntry game) {
    final relative = game.cover;
    if (relative == null || relative.isEmpty) return null;
    final path = p.join(platform.directory, relative);
    return File(path).existsSync() ? path : null;
  }

  Widget _gameCard(PlatformLibrary platform, GameEntry game,
      {required VoidCallback onTap}) {
    final name = game.name.isEmpty ? game.file : game.name;
    final developer = game.developer;
    final releaseDate = game.releaseDate;
    final cover = _coverPathOf(platform, game);

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    cover != null
                        ? Image.file(
                            File(cover),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => _coverPlaceholder(),
                          )
                        : _coverPlaceholder(),
                    if (cover == null)
                      const Positioned(
                        left: 8,
                        top: 8,
                        child: _Badge(text: '待搜刮'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            [
              if (developer != null && developer.isNotEmpty) developer,
              if (releaseDate != null && releaseDate.isNotEmpty) releaseDate,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
        color: AppTheme.subtleFill,
        child: const Center(
          child: Icon(Icons.gamepad_outlined,
              size: 32, color: AppTheme.textSecondary),
        ),
      );

  Future<void> _openGame(PlatformLibrary platform, GameEntry game) async {
    final result = await Navigator.of(context).push<bool>(
      AppPageRoute(builder: (_) => GameDetailScreen(platform: platform, game: game)),
    );
    if (result == true) await _load();
  }

  Future<void> _addRom() async {
    if (_platforms.isEmpty) return;
    final root = await LibraryService.defaultRoot();
    if (!mounted) return;
    final romPath = await Navigator.of(context).push<String>(
      AppPageRoute(
        builder: (_) => FileBrowserScreen(
          initialPath: root,
          mode: FileBrowserMode.file,
          title: '选择 ROM 文件',
          extensions: const <String>[
            'nes', 'fc', 'sfc', 'snes', 'gb', 'gbc', 'gba', 'n64', 'nds', '3ds',
            'zip', '7z', 'iso', 'bin', 'cue', 'chd', 'pbp', 'cso', 'md', 'gen',
            'sms', 'gg', 'pce', 'gcm', 'rvz', 'a26', 'vpk', 'wbfs', 'gdi', 'fds',
          ],
        ),
      ),
    );
    if (romPath == null) return;

    final targetPlatform = await _selectPlatform(romPath);
    if (targetPlatform == null) return;

    final relative = await LibraryService.copyRomToPlatform(romPath, targetPlatform);
    final generateId = await PreferencesService.autoId;
    final entry = GameEntry(
      name: LibraryService.gameNameFromRom(romPath),
      file: relative,
      id: generateId ? LibraryService.newId() : null,
    );
    targetPlatform.games.add(entry);
    await TomlService.save(targetPlatform);
    await _load();

    if (mounted) {
      final result = await Navigator.of(context).push<bool>(
        AppPageRoute(
          builder: (_) => GameDetailScreen(
            platform: targetPlatform,
            game: entry,
            editOnOpen: true,
          ),
        ),
      );
      if (result == true) await _load();
    }
  }

  Future<PlatformLibrary?> _selectPlatform(String romPath) async {
    final guessed = PlatformCatalog.byExtension(romPath)?.name;
    return showModalBottomSheet<PlatformLibrary>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择目标平台',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _platforms.length,
                itemBuilder: (context, index) {
                  final platform = _platforms[index];
                  final recommend = platform.platform.toUpperCase() == guessed?.toUpperCase();
                  return ListTile(
                    leading: const Icon(Icons.folder_outlined, color: AppTheme.accent),
                    title: Text(platform.platform,
                        style: const TextStyle(color: AppTheme.textPrimary)),
                    subtitle: recommend
                        ? const Text('根据扩展名推荐',
                            style: TextStyle(color: AppTheme.success, fontSize: 11))
                        : Text('${platform.games.length} 款游戏',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    onTap: () => Navigator.pop(context, platform),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
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
