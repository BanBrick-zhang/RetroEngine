import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/library.dart';
import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/toml_service.dart';
import '../theme.dart';
import '../widgets/permission_dialog.dart';
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

  /// 是否因缺少权限而等待用户从系统设置返回后自动继续选择目录。
  bool _pendingChoose = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _checkExternalChanges() async {
    var modified = false;
    for (final platform in _platforms) {
      if (!platform.hasToml) continue;
      if (await TomlService.isExternallyModified(platform)) {
        modified = true;
        break;
      }
    }
    await _load();
    if (mounted && !modified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('游戏库已刷新')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('游戏库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新（识别外部修改）',
            onPressed: _checkExternalChanges,
          ),
          IconButton(
            icon: const Icon(Icons.add_outlined),
            tooltip: '新建平台',
            onPressed: _platforms.isEmpty ? null : _createPlatform,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: _platforms.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addRom,
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('添加 ROM'),
            ),
      body: AppTheme.backdrop(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? _errorView()
                : _platforms.isEmpty
                    ? _emptyView()
                    : _libraryView(),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(onLibraryChanged: (_) {}),
      ),
    );
    if (mounted) await _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _emptyView() {
    final bound = _boundPath != null && _boundPath!.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                bound ? Icons.search_off_outlined : Icons.folder_off_outlined,
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
                  style: const TextStyle(color: AppTheme.accent, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  '扫描到 $_scannedDirs 个子目录，未发现可识别的 ROM。\n'
                  '请确认选择的是游戏库总目录（其下应包含 FC、GBA 等平台文件夹）。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12, height: 1.6),
                ),
              ] else
                const Text(
                  '在「设置」中绑定 SaveDeck 游戏库总目录，\n即可自动识别各平台 ROM 与 savedeck.toml。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
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
      MaterialPageRoute(
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
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _platforms.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = _platforms[index];
              return GlassChip(
                label: '${item.platform} (${item.games.length})',
                icon: item.hasToml ? null : Icons.auto_awesome_outlined,
                selected: index == _selected,
                onTap: () => setState(() => _selected = index),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                platform.platform,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: '修改平台名称与排序',
                visualDensity: VisualDensity.compact,
                onPressed: () => _editPlatform(platform),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  platform.loadError != null
                      ? '配置读取失败（点诊断查看）'
                      : (platform.hasToml
                          ? '${platform.games.length} 款游戏'
                          : '识别到 ${platform.games.length} 个 ROM'),
                  style: TextStyle(
                    color: platform.loadError != null
                        ? AppTheme.danger
                        : (platform.hasToml
                            ? AppTheme.textSecondary
                            : AppTheme.warning),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Text(
                platform.directory,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (!platform.hasToml)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              radius: 12,
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 16, color: AppTheme.accent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('尚未建立 savedeck.toml，点击游戏搜刮后自动生成',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
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
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      16, 4, 16, AppTheme.bottomNavClearance + 100),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        MediaQuery.of(context).orientation == Orientation.landscape
                            ? 4
                            : 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: platform.games.length,
                  itemBuilder: (context, index) =>
                      _gameCard(platform, platform.games[index]),
                ),
        ),
      ],
    );
  }

  Widget _gameCard(PlatformLibrary platform, GameEntry game) {
    final coverPath = game.cover == null || game.cover!.isEmpty
        ? null
        : p.join(platform.directory, game.cover!);
    final hasCover = coverPath != null && File(coverPath).existsSync();
    final romExists = File(p.join(platform.directory, game.file)).existsSync();

    return GlassCard(
      padding: const EdgeInsets.all(8),
      radius: 14,
      onTap: () => _openGame(platform, game),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: hasCover
                      ? Image.file(
                          File(coverPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _coverPlaceholder(),
                        )
                      : _coverPlaceholder(),
                ),
                if (!hasCover)
                  const Positioned(
                    left: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text('待搜刮',
                            style: TextStyle(color: Colors.white, fontSize: 9)),
                      ),
                    ),
                  ),
                if (game.video != null && game.video!.isNotEmpty)
                  const Positioned(
                    right: 6,
                    top: 6,
                    child: Icon(Icons.movie_outlined, size: 15, color: Colors.white),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            game.name.isEmpty ? p.basename(game.file) : game.name,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              if (!romExists)
                const Icon(Icons.warning_amber_rounded, size: 12, color: AppTheme.warning),
              if (game.video != null) ...[
                const Icon(Icons.movie_outlined, size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  game.file,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
        color: AppTheme.subtleFill,
        child: const Center(
          child: Icon(Icons.gamepad_outlined, size: 36, color: AppTheme.textSecondary),
        ),
      );

  Future<void> _openGame(PlatformLibrary platform, GameEntry game) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GameDetailScreen(platform: platform, game: game)),
    );
    if (result == true) await _load();
  }

  Future<void> _createPlatform() async {
    final root = widget.libraryPath ?? await PreferencesService.libraryPath;
    if (root == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('新建平台', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: '例如：GBA、FC、PSX'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await LibraryService.createPlatform(root, name);
    widget.onReload();
    await _load();
  }

  /// 修改当前平台的名称与排序，写回 savedeck.toml。
  Future<void> _editPlatform(PlatformLibrary platform) async {
    final nameController = TextEditingController(text: platform.platform);
    final sortController = TextEditingController(text: platform.sort ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('修改平台',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '平台名称',
                hintText: '例如：GBA、PS2',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sortController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '排序',
                hintText: '例如：001，留空则不设置',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('平台名称不能为空');
      return;
    }
    platform.platform = name;
    final sort = sortController.text.trim();
    platform.sort = sort.isEmpty ? null : sort;
    platform.hasToml = true;
    try {
      await TomlService.save(platform);
      await _load();
      if (mounted) _showMessage('平台信息已保存');
    } catch (e) {
      if (mounted) _showMessage('保存失败：$e');
    }
  }

  Future<void> _addRom() async {
    if (_platforms.isEmpty) return;
    final root = await LibraryService.defaultRoot();
    if (!mounted) return;
    final romPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
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
        MaterialPageRoute(
          builder: (_) => GameDetailScreen(platform: targetPlatform, game: entry),
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
